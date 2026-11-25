----------------------------------------------------------------------
-- EVIL Rises - Communication System
-- Handles addon-to-addon communication for syncing member data
----------------------------------------------------------------------
local CommSystem = {}
EVRFeatures.CommSystem = CommSystem
local L = EVRFeatures.L

local LibSerialize = LibStub("EVRFeatures-LibSerialize")
local LibDeflate = LibStub("LibDeflate")

-- Message types
CommSystem.MSG_TYPES = {
    BROADCAST = "BC",    -- Full data broadcast
    REQUEST   = "RQ",    -- Request data from someone
    RESPONSE  = "RS",    -- Response to a request
    PING      = "PI",    -- Presence ping
    PONG      = "PO",    -- Presence response
    VERSION   = "VR",    -- Version check
    ALT_LINK  = "AL",    -- Alt/main link table, for clients before #424; received only as a merge (AltSync)
    SELF_ALT  = "SA",    -- member self-claim of own alts (officers replay via LinkAlt)
    RAID_DATA = "RD",    -- Raid attendance + session sync (officer only)
    RAID_DELETE = "RX",  -- Delete a raid session (officer only; sender verified)
    NOTES_ALL = "OA",    -- Bulk officer notes sync (officer only)
    WELCOME_INTENT = "WI",-- Officer declares intent to welcome a member (race coordination)
    WELCOME_CLAIM = "WC",-- Welcome message sent (suppresses remaining timers)
    SYNC_V2   = "SV",    -- SyncService v2 versioned envelope (points/events/bank/polls)
    RECRUIT_INFO = "RI", -- Recruitment status broadcast (officer → all members)
    LFG       = "LG",    -- member self-declared LFG availability (sender bound)
    -- NOT "LP": that code is the wishlist's loot prio, matched by its literal further down.
    LFG_GROUP = "GF",    -- a group being formed (sender bound; GUILD only; issue #341)
    LFG_JOIN  = "GJ",    -- a request for a spot and its answer (WHISPER only; issue #341)
    RECRUIT_STATS = "RE",-- self-reported recruitment engagement (sender bound; officers aggregate).
                         -- NOT "RS": that code is already RESPONSE above; "RE" is the free code.
    MAP_POS   = "MP",    -- live guild-map position (sender bound; GUILD-only; clamped)
}

-- Throttle settings
CommSystem.THROTTLE_INTERVAL = 5  -- seconds between broadcasts
local function checksum(bytes)
    return string.format("%08X", LibDeflate:Adler32(bytes))
end

-- The raid and recruitment modules already publish full snapshots on changes.
-- Keep a short identifier so a missed snapshot can be requested individually.
local sharedSnapshot = { RD = "raid", RX = "raid", RI = "recruitment" }
local advertised, received = {}, {}


-- The alt links' old "AL" table (issue #424): sent only while a client before #424 was heard within
-- LEGACY_WINDOW (its broadcast's version at or below LEGACY_ALT_MAX, or an "AL" without the mark).
CommSystem.LEGACY_ALT_MAX = "1.38.0"   -- 1.38.0 shipped before #424
CommSystem.LEGACY_WINDOW = 1800
local ALT_LINK_MARK = { v = 2 }
-- The officers' safe list and nicknames (issue #429) on a sync request's answer at most once per 10 minutes.
CommSystem.MARKS_BACKFILL_GAP = 600

function CommSystem:Initialize()
    if self.listening then return end
    -- Addon messages on EVIL Rises's prefix.
    local frame = CreateFrame("Frame")
    EVRFeatures.Compat.RegisterEvent(frame, "CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        if prefix == EVRFeatures.PREFIX then
            -- Timed by the type it carried (issue #324); a chunk still waiting for the rest says "chunk".
            local st, t = EVRFeatures.State.comm, EVRFeatures.Perf:Start()
            st.recvKind = nil
            CommSystem:OnMessageReceived(msg, channel, sender)
            EVRFeatures.Perf:Stop("guild sync in " .. (st.recvKind or "chunk"), t, #msg)
        end
    end)
    self.listening = true

    C_Timer.After(3, function() self:QueueSync(true) end)
    C_Timer.NewTicker(60, function() self:QueueSync(false) end)
end

-- Chunking settings
CommSystem.CHUNK_SIZE = 230  -- Leave room for chunk header + "M:xxxx:nn:nn:"
local chunkSequence
CommSystem.pendingMessages = {}  -- [sender] = { chunks = {}, total = 0, received = 0, last = GetTime() }
-- Seconds a half-received message waits for its next chunk. A whisper's chunks come at the sender's
-- WhisperQueue pace (issue #393): one every 4 s, up to 64 s while the server throttles, and a "high"
-- whisper may pass between two of them; so two of its slowest steps.
CommSystem.CHUNK_SECONDS = 30
CommSystem.WHISPER_CHUNK_SECONDS = 128

----------------------------------------------------------------------
-- Member-data counters (issue #312). Every drop on the way from a guildmate's broadcast to
-- db.members was silent, so "sync does nothing" could not be told apart from "nobody sent".
-- Per sender, this session only: what arrived, what was stored, what was dropped and why.
-- A message lost before its type is known (it would not decode, decompress or reassemble)
-- counts as dropped too, whatever it carried, so the Audit line says "messages", not member data.
----------------------------------------------------------------------
CommSystem.MAX_STAT_SENDERS = 200   -- a busy guild's worth; past it only the totals grow
CommSystem.syncStats = { senders = {}, nSenders = 0, received = 0, stored = 0, dropped = 0, reasons = {} }

function CommSystem:_CountPayload(sender, outcome, reason)
    local log = EVRFeatures.DebugWindow
    if log and log.capturing then
        log:Record("Sync", outcome .. (reason and (" (" .. reason .. ")") or "") .. "  ·  " .. (sender or "?"))
    end
    local st = self.syncStats
    local s = st.senders[sender or "?"]
    if not s and st.nSenders < self.MAX_STAT_SENDERS then
        s = { received = 0, stored = 0, dropped = 0, reasons = {} }
        st.senders[sender or "?"] = s
        st.nSenders = st.nSenders + 1
    end
    st.received = st.received + 1
    if s then s.received = s.received + 1 end
    if outcome == "stored" then
        st.stored = st.stored + 1
        if s then s.stored = s.stored + 1 end

    else
        reason = reason or "rejected"
        st.dropped = st.dropped + 1
        st.reasons[reason] = (st.reasons[reason] or 0) + 1
        if s then
            s.dropped = s.dropped + 1
            s.reasons[reason] = (s.reasons[reason] or 0) + 1
        end
    end
end

-- The session's counters: totals, the reason most drops had (or nil), and the per-sender table.
function CommSystem:SyncCounters()
    local st = self.syncStats
    local top, topN = nil, 0
    for r, n in pairs(st.reasons) do
        if n > topN or (n == topN and top and r < top) then top, topN = r, n end
    end
    return { received = st.received, stored = st.stored, dropped = st.dropped,
             topReason = top, topCount = topN, senders = st.senders }
end

-- How a drop reason reads to the player (Audit > Sync).
CommSystem.DROP_REASON_TEXT = {
    decode = L["could not decode"], decompress = L["could not decompress"], chunks = L["chunks lost"],
    rejected = L["missing name or class"], stale = L["older than stored"],
}

----------------------------------------------------------------------
-- Send a message to guild (with chunking for large payloads)
----------------------------------------------------------------------
-- `kind`, optional, names it in /eviltools perf (SyncService passes its domain); else the type does.
-- `channel`, optional: "OFFICER" for what only officers may receive (SendToOfficers); GUILD otherwise.
function CommSystem:SendMessage(msgType, data, target, priority, kind, channel)
    if not EVRFeatures:IsOnGuildDB() then return end
    -- The officers' notes never leave by GUILD or a whisper, whoever calls (#430): SendToOfficers sends them.
    if self.OFFICER_TYPES[msgType] and (target or channel ~= "OFFICER") then return end
    local snapshot = sharedSnapshot[msgType]
    if snapshot and not target and (not channel or channel == "GUILD") and EVRFeatures:IsOfficer() then
        advertised[snapshot] = checksum(data)
    end
    local payload = msgType .. ":" .. (data or "")

    -- Compress
    local t = EVRFeatures.Perf:Start()
    local compressed = LibDeflate:CompressDeflate(payload)
    local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
    EVRFeatures.Perf:Stop("guild sync out " .. (kind or msgType), t, #encoded)

    local len = #encoded
    local log = EVRFeatures.DebugWindow
    if log and log.capturing then log:Packet("Queued", kind or msgType, target and "WHISPER" or channel or "GUILD", target, len) end
    if len <= 250 then
        -- Single message, no chunking needed (prefix with "S:").
        -- Cap at 250 so "S:" + payload stays safely under the 255-byte addon-message limit.
        local msg = "S:" .. encoded
        self:SendRaw(msg, target, priority, channel)
    else
        -- Multi-chunk: prefix each with "M:msgId:chunkIndex:totalChunks:"
        chunkSequence = ((chunkSequence or math.random(0, 0xFFFF) * 65536) + 1) % 4294967296
        local msgId = string.format("%08X", chunkSequence)
        local totalChunks = math.ceil(len / self.CHUNK_SIZE)
        local msgs = {}
        for i = 1, totalChunks do
            local startPos = (i - 1) * self.CHUNK_SIZE + 1
            local endPos = math.min(i * self.CHUNK_SIZE, len)
            local header = string.format("M:%s:%d:%d:", msgId, i, totalChunks)
            msgs[i] = header .. encoded:sub(startPos, endPos)
        end
        -- A whisper on WoW: Forever waits in the WhisperQueue, which paces it: the chunks go in as one
        -- message, all or none, since a message missing one is lost whole (issue #393).
        local queue = EVRFeatures.WhisperQueue
        if target and queue and queue.Active() then
            self:SendRawGroup(msgs, target, priority)
            return
        end
        for i, msg in ipairs(msgs) do
            C_Timer.After((i - 1) * 0.1, function()
                self:SendRaw(msg, target, priority, channel)
            end)
        end
    end
end

-- The chunks of one whisper, into the WhisperQueue together. Never "low", as SendRaw.
function CommSystem:SendRawGroup(msgs, target, priority)
    return EVRFeatures.WhisperQueue:PushAddonGroup(EVRFeatures.PREFIX, msgs, target,
        priority == "ALERT" and "high" or "normal", function(msg) self:_Whisper(msg, target) end)
end

-- One addon whisper on the sync prefix.
function CommSystem:_Whisper(msg, target)
    if not EVRFeatures:IsOnGuildDB() then return end
    EVRFeatures:NoteWhisper(target) -- a guildmate gone since they asked answers "No player named" (issue #326)
    EVRFeatures.Compat.SendAddonMessage(EVRFeatures.PREFIX, msg, "WHISPER", target, "NORMAL")
end

function CommSystem:SendRaw(msg, target, priority, channel)
    if not EVRFeatures:IsOnGuildDB() then return end
    if target then
        local function send() self:_Whisper(msg, target) end
        -- WoW: Forever throttles a client that whispers too fast (issue #393): every whisper waits its turn.
        -- Never "low": a chunk the queue let go stale would cost the whole message.
        local queue = EVRFeatures.WhisperQueue
        if queue then
            queue:PushAddon(EVRFeatures.PREFIX, msg, target, priority == "ALERT" and "high" or "normal", send)
        else
            send()
        end
    else
        EVRFeatures.Compat.SendAddonMessage(EVRFeatures.PREFIX, msg, channel or "GUILD", nil, priority or "BULK")
    end
end

-- Message types that travel only over the OFFICER addon channel, as SyncService.OFFICER_CHANNEL_DOMAINS for
-- envelopes (issue #430): the officers' dated notes and tags. Sent there only; received over OFFICER, except "ON"
-- over GUILD from an officer for the clients before #430 (OFFICER_TYPES_LEGACY_GUILD), never over a whisper.
CommSystem.OFFICER_TYPES = { ON = true, OA = true }
-- Transition only (#430, ADR-0045): an officer on a client before #430 still sends "ON" over GUILD; a new client
-- reads it, so a note written there is not lost. Remove in the next version. "OA" over GUILD is not read.
CommSystem.OFFICER_TYPES_LEGACY_GUILD = { ON = true }

-- The OFFICER addon channel (Compat.OfficerAddonChannel), or nil when what goes to officers stays on this client.
function CommSystem:OfficerChannel()
    return EVRFeatures.Compat.OfficerAddonChannel()
end

-- Whether an OFFICER_TYPES message counts over `channel`: OFFICER; GUILD for the legacy "ON" only (#430). Pure.
function CommSystem:OfficerTypeChannelOk(msgType, channel)
    if channel == "OFFICER" then return true end
    return channel == "GUILD" and self.OFFICER_TYPES_LEGACY_GUILD[msgType] == true
end

-- To the officers only, over the game's OFFICER addon channel: a member's client never gets the bytes (issue #427).
-- False, and nothing sent, on a client without that channel (Compat.OfficerAddonChannel).
function CommSystem:SendToOfficers(msgType, data, priority, kind)
    local channel = self:OfficerChannel()
    if not channel then return false end
    self:SendMessage(msgType, data, nil, priority, kind, channel)
    return true
end

----------------------------------------------------------------------
-- Receive a message
----------------------------------------------------------------------
-- channel is the addon-message distribution ("GUILD", "WHISPER", "PARTY", ...)
-- from CHAT_MSG_ADDON. Threaded to the type dispatch so handlers can bind trust
-- to how a message arrived, not just to who claims to have authored the body.
-- For a reassembled multi-chunk message this is the channel of the arriving
-- chunk; every chunk of one message travels over the same distribution.
function CommSystem:OnMessageReceived(msg, channel, sender)
    if not EVRFeatures:IsOnGuildDB() then return end
    -- Don't process our own messages
    local myName = EVRFeatures.Compat.PlayerName()
    if sender == myName or sender == EVRFeatures:GetPlayerKey(myName) then
        return
    end

    local encoded
    local prefix = msg:sub(1, 2)

    if prefix == "S:" then
        -- Single (non-chunked) message
        encoded = msg:sub(3)
    elseif prefix == "M:" then
        -- Multi-chunk message: "M:msgId:chunkIndex:totalChunks:data"
        local msgId, idx, total, chunkData = msg:match("^M:(%x+):(%d+):(%d+):(.+)$")
        if not msgId then return end
        idx = tonumber(idx)
        total = tonumber(total)

        if idx < 1 or idx > total then return end
        local key = channel .. ":" .. sender .. ":" .. msgId
        if not self.pendingMessages[key] then
            local started = { chunks = {}, total = total, received = 0, last = GetTime() }
            self.pendingMessages[key] = started
            -- Timeout: given up once no chunk came for the window. Still waiting then, a chunk was
            -- lost: counted, not silent (issue #312). A finished message has left the table already.
            -- Each chunk renews it: a whisper's chunks leave the sender's WhisperQueue one every few
            -- seconds on WoW: Forever, more slowly when the server throttles (issue #393).
            local window = channel == "WHISPER" and self.WHISPER_CHUNK_SECONDS or self.CHUNK_SECONDS
            local function expire()
                if self.pendingMessages[key] ~= started then return end
                local left = started.last + window - GetTime()
                if left > 0 then C_Timer.After(left, expire); return end
                self.pendingMessages[key] = nil
                self:_CountPayload(sender, "dropped", "chunks")
            end
            C_Timer.After(window, expire)
        end

        local pending = self.pendingMessages[key]
        if total ~= pending.total then return end
        pending.last = GetTime()
        if not pending.chunks[idx] then
            pending.chunks[idx] = chunkData
            pending.received = pending.received + 1
        end

        if pending.received < pending.total then
            return  -- Still waiting for more chunks
        end

        -- All chunks received, reassemble
        encoded = table.concat(pending.chunks)
        self.pendingMessages[key] = nil
    else
        -- Legacy (untagged) message — treat as single
        encoded = msg
    end

    -- Decode and decompress
    -- A message that fails here is lost with its type unknown: counted (issue #312).
    local decoded = LibDeflate:DecodeForWoWAddonChannel(encoded)
    if not decoded then self:_CountPayload(sender, "dropped", "decode"); return end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then self:_CountPayload(sender, "dropped", "decompress"); return end

    -- Parse message type
    local msgType, data = decompressed:match("^(%w+):(.*)$")
    if not msgType then return end
    local log = EVRFeatures.DebugWindow
    if log and log.capturing then log:Packet("Received", msgType, channel, sender, #encoded) end
    EVRFeatures.State.comm.recvKind = msgType   -- for /eviltools perf; SyncService narrows SV to its domain

    local snapshot = sharedSnapshot[msgType]
    if snapshot and channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) then
        local key = EVRFeatures:KeyOfRosterName(sender)
        received[key] = received[key] or {}
        received[key][snapshot] = checksum(data)
    end
    if msgType == "HD" and channel == "GUILD" then
        self:OnDigest(sender, data)
    elseif msgType == "HV" and channel == "OFFICER" then
        EVRFeatures.SyncService:CheckRecent(sender, data, channel)
    elseif msgType == "HM" and (channel == "GUILD" or channel == "OFFICER") then
        EVRFeatures.SyncService:ReplayRecent(data, channel)
    elseif msgType == "HN" and channel == "GUILD" then
        self:OnNeed(sender, data)
    elseif msgType == CommSystem.MSG_TYPES.BROADCAST then
        if channel == "GUILD" then self:HandleBroadcast(sender, data, channel) end
    elseif msgType == CommSystem.MSG_TYPES.REQUEST then
        if channel == "GUILD" then self:HandleRequest(sender, data) end
    elseif msgType == CommSystem.MSG_TYPES.RESPONSE then
        if channel == "GUILD" then self:HandleResponse(sender, data) end
    elseif msgType == CommSystem.MSG_TYPES.PING then
        self:HandlePing(sender)
    elseif msgType == "WL" then
        if EVRFeatures.Wishlist then
            EVRFeatures.Wishlist:HandleWishlistBroadcast(sender, data, channel)
        end
    elseif msgType == "LP" then
        -- Officer-set priorities, stored by everyone: only an officer's, over GUILD, replace them.
        -- The channel matters as much as the name: IsOfficerByName drops the realm, so a
        -- namesake on another realm could whisper as the officer (issue #78).
        if EVRFeatures.Wishlist and channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) then
            EVRFeatures.Wishlist:HandleLootPriosBroadcast(sender, data)
        end
    elseif msgType == "ON" then
        -- Only an officer writes officer notes, and only an officer keeps them (issue #78). Over OFFICER, or over
        -- GUILD from a client before #430 (OFFICER_TYPES_LEGACY_GUILD); never a whisper.
        if EVRFeatures.OfficerNotes and EVRFeatures:IsOfficer() and self:OfficerTypeChannelOk(msgType, channel)
            and EVRFeatures:IsOfficerByName(sender) then
            EVRFeatures.OfficerNotes:HandleIncoming(data)
        end
    elseif msgType == "RC" then
        if EVRFeatures.RecipeTracker then
            EVRFeatures.RecipeTracker:HandleIncoming(sender, data)
        end
    elseif msgType == "TR" then
        if EVRFeatures.TrialTracker and EVRFeatures:IsOfficer() and channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) then
            EVRFeatures.TrialTracker:HandleIncoming(data)
        end
    elseif msgType == "RR" then
        -- Raider roster: everyone stores it (members view); HandleIncoming
        -- trusts it only when the sender is a verified officer, and only over GUILD (issue #81).
        if EVRFeatures.RaiderRoster and channel == "GUILD" then
            EVRFeatures.RaiderRoster:HandleIncoming(sender, data)
        end
    elseif msgType == CommSystem.MSG_TYPES.ALT_LINK then
        -- The whole table, from an officer on a client before #424 (or this one's copy for them). Over GUILD
        -- only (issue #81). It used to replace this client's table and wiped everybody's links; now it is
        -- only merged in, never removing or changing a link, and an empty one is nothing (AltSync).
        -- A client since #424 adds a second value an old one never reads (ALT_LINK_MARK): its "AL" is for the old
        -- clients only, and is ignored here, so new clients never merge each other's views.
        if channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) and EVRFeatures.AltSync then
            local ok, links, mark = LibSerialize:Deserialize(data)
            if ok and type(links) == "table" and not (type(mark) == "table" and mark.v == ALT_LINK_MARK.v) then
                self:_HeardLegacy()
                EVRFeatures.AltSync:OnLegacyList(links, sender)
            end
        end
    elseif msgType == CommSystem.MSG_TYPES.SELF_ALT then
        if EVRFeatures.AltAutoDetect then EVRFeatures.AltAutoDetect:HandleSelfClaim(sender, data) end
    elseif msgType == CommSystem.MSG_TYPES.LFG then
        if EVRFeatures.LFGBoard then EVRFeatures.LFGBoard:HandleEntry(sender, data, channel) end
    elseif msgType == CommSystem.MSG_TYPES.LFG_GROUP then
        if EVRFeatures.Groups then EVRFeatures.Groups:HandleGroup(sender, data, channel) end
    elseif msgType == CommSystem.MSG_TYPES.LFG_JOIN then
        if EVRFeatures.Groups then EVRFeatures.Groups:HandleJoin(sender, data, channel) end
    elseif msgType == CommSystem.MSG_TYPES.RAID_DATA then
        if EVRFeatures:IsOfficer() and channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) and EVRFeatures.RaidTracker then
            EVRFeatures.RaidTracker:HandleIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.RAID_DELETE then
        -- Only apply if the sender is a verified officer in the guild roster, over GUILD (issue #81)
        if channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) and EVRFeatures.RaidTracker then
            EVRFeatures.RaidTracker:HandleDeleteIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.NOTES_ALL then
        -- Over OFFICER only (#430).
        if EVRFeatures:IsOfficer() and self:OfficerTypeChannelOk(msgType, channel) and EVRFeatures:IsOfficerByName(sender)
            and EVRFeatures.OfficerNotes then
            EVRFeatures.OfficerNotes:HandleAllIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.SYNC_V2 then
        -- Versioned envelope (protocol v2): dedup/validation/dispatch is
        -- handled entirely by SyncService.
        if EVRFeatures.SyncService then
            EVRFeatures.SyncService:OnEnvelope(sender, data, channel)
        end
    elseif msgType == CommSystem.MSG_TYPES.WELCOME_INTENT then
        -- Another officer is also considering welcoming this member; record their intent. The
        -- welcome race is the officers', over GUILD: anybody else could win the tie-break with a
        -- low-sorting name, or suppress a welcome with a claim (issue #78).
        if EVRFeatures.Recruitment and data and data ~= "" and channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) then
            EVRFeatures.Recruitment._welcomeIntents = EVRFeatures.Recruitment._welcomeIntents or {}
            EVRFeatures.Recruitment._welcomeIntents[data] = EVRFeatures.Recruitment._welcomeIntents[data] or {}
            EVRFeatures.Recruitment._welcomeIntents[data][sender] = true
        end
    elseif msgType == CommSystem.MSG_TYPES.WELCOME_CLAIM then
        -- Another officer already sent the welcome — suppress ours. Every client gets this, and
        -- only an officer's Recruitment:Initialize creates the table (issue #77).
        if EVRFeatures.Recruitment and data and data ~= "" and channel == "GUILD" and EVRFeatures:IsOfficerByName(sender) then
            EVRFeatures.Recruitment._welcomedRecently = EVRFeatures.Recruitment._welcomedRecently or {}
            EVRFeatures.Recruitment._welcomedRecently[data] = true
            EVRFeatures.Recruitment._welcomedRecently[data .. "_sent"] = true
            EVRFeatures.Recruitment:OnWelcomeClaim(data, sender)
        end
    elseif msgType == CommSystem.MSG_TYPES.RECRUIT_INFO then
        -- Direct officer broadcast OR a member relay. Trust is bound to the
        -- envelope (sender + channel) in Recruitment:ApplyIncoming: it must
        -- arrive over GUILD, name a current officer as author, and be sent by a
        -- current guildmate. Passing channel is what kills the whisper-injection.
        local ok, info = LibSerialize:Deserialize(data)
        if ok and EVRFeatures.Recruitment then
            EVRFeatures.Recruitment:ApplyIncoming(info, sender, channel)
        end
    elseif msgType == CommSystem.MSG_TYPES.RECRUIT_STATS then
        -- Self-reported engagement stats. Identity is the envelope sender and it
        -- must arrive over GUILD; HandleStats keys the entry by that sender and
        -- clamps every number, so a member can only file under their own name and
        -- a hostile packet cannot break the officer UI.
        if EVRFeatures.RecruitEngagement then
            EVRFeatures.RecruitEngagement:HandleStats(sender, data, channel)
        end
    elseif msgType == CommSystem.MSG_TYPES.MAP_POS then
        -- Live guild-map position. Identity is the envelope sender and it must
        -- arrive over GUILD; HandlePosition keys the entry by that sender and
        -- clamps every number, so a peer can only ever place its OWN pin and a
        -- hostile packet cannot break the map UI. channel is threaded exactly
        -- like RECRUIT_STATS so the GUILD-only rule can be enforced.
        if EVRFeatures.GuildMap then
            EVRFeatures.GuildMap:HandlePosition(sender, data, channel)
        end
    end
end

----------------------------------------------------------------------
-- Broadcast own data
----------------------------------------------------------------------
-- force=true bypasses the throttle (used for corrective re-broadcasts once a
-- cold-cache snapshot finally resolves, which would otherwise be swallowed by
-- the 5s window right after the startup broadcast).
function CommSystem:BroadcastMyData(force)
    if not self.listening or not EVRFeatures:IsOnGuildDB() then return end
    if not force and self.checkedRoster and GetTime() - self.checkedRoster < self.THROTTLE_INTERVAL then return end
    if self:RefreshRosterSnapshot() then self:SendRosterSnapshot() end
end

-- Compare the actual member fields. Collection time changes even while standing still.
function CommSystem:RefreshRosterSnapshot()
    local collector = EVRFeatures.DataCollector
    collector:CollectMyData()
    if EVRFeatures.AttunementTracker then EVRFeatures.AttunementTracker:ScanAttunements() end
    local data = collector:GetBroadcastData()
    local timestamp, sequence = data.lastUpdate, data.updateSequence
    data.lastUpdate, data.updateSequence = nil, nil
    local stable = LibSerialize:SerializeEx({ stable = true }, data)
    self.checkedRoster = GetTime()
    if stable == self.rosterContents then return false end
    self.rosterContents = stable
    self.rosterDigest = checksum(stable) .. "-" .. #stable
    data.lastUpdate, data.updateSequence, data.evrDigest = timestamp, sequence, self.rosterDigest
    self.rosterPayload = LibSerialize:Serialize(data)
    return true
end

function CommSystem:SendRosterSnapshot()
    if not self.rosterPayload then self:RefreshRosterSnapshot() end
    self:SendMessage(self.MSG_TYPES.BROADCAST, self.rosterPayload)
end

local function bountyRevision(key)
    local boards = EVRFeatures.db.bounties
    return boards and boards[key] and boards[key].rev or 0
end

-- A normal minute sends one short announcement per install. Only a window open
-- solicits immediate announcements from peers. Replies never solicit replies.
function CommSystem:Announce(query)
    local now = GetTime()
    if not query and self.lastAnnouncement and now - self.lastAnnouncement < 2 then return end
    self.lastAnnouncement = now
    if not self.rosterPayload then self:RefreshRosterSnapshot() end
    local key = EVRFeatures:KeyOfRosterName(EVRFeatures.Compat.PlayerName())
    self:SendMessage("HD", self.rosterDigest .. ":" .. bountyRevision(key) .. ":" .. (query and "1" or "0")
        .. ":" .. (EVRFeatures.ProfSync and EVRFeatures.ProfSync.ownDigest or "")
        .. ":" .. (advertised.raid or "") .. ":" .. (advertised.recruitment or "")
        .. ":" .. EVRFeatures.SyncService:RecentIds("GUILD"))
    local private = EVRFeatures.SyncService:RecentIds("OFFICER")
    if private ~= "" and EVRFeatures.Compat.OfficerAddonChannel() then
        self:SendMessage("HV", private, nil, nil, nil, "OFFICER")
    end
end

function CommSystem:QueueSync(opened)
    if not self.listening or not EVRFeatures:IsOnGuildDB() or not EVRFeatures:IsFeatureEnabled("commSystem") then return end
    self.openRequested = self.openRequested or opened
    if self.checkPending then return end
    self.checkPending = true
    C_Timer.After(0.1, function()
        local query = self.openRequested
        self.checkPending, self.openRequested = nil, nil
        if not EVRFeatures:IsOnGuildDB() then return end
        local now = GetTime()
        local log = EVRFeatures.DebugWindow
        if log and log.capturing then
            local trigger = not self.bootstrapped and "Initial check" or (query and "Window check" or "60-second check")
            log:Record("Sync", trigger)
        end
        if query and self.lastQuery and now - self.lastQuery < 3 then query = false end
        if query then self.lastQuery = now end
        if not self.checkedRoster or now - self.checkedRoster >= 59 then
            if self:RefreshRosterSnapshot() then self:SendRosterSnapshot() end
        end
        self:Announce(query)
        -- Bootstrap the other feature modules and clients predating digests.
        -- One guild-wide request serves everybody already listening.
        if not self.bootstrapped or now - (self.lastBackfillRequest or 0) >= 600 then
            local request = self.bootstrapped and "ALL" or "INIT"
            self.bootstrapped, self.lastBackfillRequest = true, now
            self:SendMessage(self.MSG_TYPES.REQUEST, request)
            if request == "INIT" and EVRFeatures:IsOfficer() and not EVRFeatures.State.comm.answeredAt then
                self:HandleRequest(nil, request)
            end
        end
    end)
end

function CommSystem:OnDigest(sender, data)
    local digest, rev, query, prof, raid, recruitment, ids =
        data:match("^(%x%x%x%x%x%x%x%x%-%d+):(%d+):([01]):(%x*):(%x*):(%x*):(%x*)$")
    if not digest then return end
    EVRFeatures.SyncService:CheckRecent(sender, ids, "GUILD")
    local key = EVRFeatures:KeyOfRosterName(sender)
    local member = EVRFeatures.db.members[key]
    local roster = not member or member.evrDigest ~= digest
    local board = bountyRevision(key) < tonumber(rev)
    local seen = received[key]
    local professions = prof ~= "" and EVRFeatures.ProfSync and EVRFeatures.ProfSync.receivedDigests
        and EVRFeatures.ProfSync.receivedDigests[key] ~= prof
    local raids = raid ~= "" and EVRFeatures.RaidTracker and EVRFeatures:IsOfficer() and (not seen or seen.raid ~= raid)
    local ad = recruitment ~= "" and EVRFeatures.Recruitment and (not seen or seen.recruitment ~= recruitment)
    if roster or board or professions or raids or ad then
        self:SendMessage("HN", sender .. ":" .. (roster and "1" or "0") .. (board and "1" or "0")
            .. (professions and "1" or "0") .. (raids and "1" or "0") .. (ad and "1" or "0"))
    end
    if query == "1" and not self.replyPending then
        self.replyPending = true
        C_Timer.After(0.15 + math.random() * 0.45, function()
            self.replyPending = nil
            if EVRFeatures:IsOnGuildDB() then self:Announce(false) end
        end)
    end
end

function CommSystem:OnNeed(sender, data)
    local target, flags = data:match("^([^:]+):([01][01][01][01][01])$")
    if not target or EVRFeatures:KeyOfRosterName(target) ~= EVRFeatures:KeyOfRosterName(EVRFeatures.Compat.PlayerName()) then return end
    local pending = self.pendingSnapshotRequests or {}
    for i = 1, 5 do
        if flags:sub(i, i) == "1" and (i ~= 4 or EVRFeatures:IsOfficerByName(sender)) then pending[i] = true end
    end
    if self.pendingSnapshotRequests then return end
    self.pendingSnapshotRequests = pending
    C_Timer.After(0.25, function()
        self.pendingSnapshotRequests = nil
        if not EVRFeatures:IsOnGuildDB() then return end
        if pending[1] then self:SendRosterSnapshot() end
        if pending[2] and EVRFeatures.Bounty then EVRFeatures.Bounty:Broadcast() end
        if pending[3] and EVRFeatures.ProfSync and EVRFeatures.ProfSync.ownDigest then EVRFeatures.ProfSync:PublishSummary() end
        if pending[4] and advertised.raid and EVRFeatures:IsOfficer() then EVRFeatures.RaidTracker:BroadcastRaidData() end
        if pending[5] and advertised.recruitment and EVRFeatures:IsOfficer() then EVRFeatures.Recruitment:RespondToSync() end
    end)
end

----------------------------------------------------------------------
-- Handle incoming broadcast
----------------------------------------------------------------------
function CommSystem:HandleBroadcast(sender, data, channel)
    local ok, playerData = LibSerialize:Deserialize(data)
    if not ok or type(playerData) ~= "table" then self:_CountPayload(sender, "dropped", "decode"); return end

    -- Build player key: the payload's realm, else the client's, as in 0.53.0. Only a client with no
    -- realm at all takes the sender's own suffix, so it agrees with a roster that suffixes names (issue #8).
    -- On WoW: Forever GetPlayerKey takes this client's realm whatever is passed (issue #95).
    local realm = playerData.realm
    if (not realm or realm == "") and not EVRFeatures:GetClientRealm() then realm = sender:match("^[^-]+%-(.+)$") end
    -- The name is the sender's: a broadcast is always its own author's data, and on WoW: Forever
    -- 0.56.0 sends only the first name while the sender carries the surname (issue #26).
    local name = sender:match("^([^-]+)") or playerData.name
    playerData.name = name
    local key = EVRFeatures:GetPlayerKey(name, realm)

    -- Store the data, and count what became of it (issue #312).
    local stored, why = EVRFeatures.DataCollector:StoreReceivedData(key, playerData)
    self:_CountPayload(sender, stored and "stored" or "dropped", why)
    -- A guildmate's own version, over GUILD only: a whisper can come from anyone (#377).
    if channel == "GUILD" then self:HandleVersionCheck(sender, playerData.addonVersion) end
end

----------------------------------------------------------------------
-- Request data from all online guildies
----------------------------------------------------------------------
-- Older installations use ALL or NOW to ask for a complete backfill.
CommSystem.ANSWER_GAP = 120
CommSystem.NOW_GAP = 15

local function answer(self)
    local st = EVRFeatures.State.comm
    st.answeredAt, st.answerDue = GetTime(), nil
    EVRFeatures.Perf:Count("guild sync request answered")
    self:_Answer()
end

function CommSystem:HandleRequest(_sender, data)
    local st = EVRFeatures.State.comm
    self.lastBackfillRequest = GetTime()
    EVRFeatures.Perf:Count("guild sync request")
    local now = GetTime()
    local gap = (data == "INIT" or data == "NOW") and self.NOW_GAP or self.ANSWER_GAP
    if not st.answeredAt or now - st.answeredAt >= gap then return answer(self) end
    EVRFeatures.Perf:Count("guild sync request held")
    local at = st.answeredAt + gap
    if st.answerDue and st.answerDue <= at then return end   -- an answer comes by then already
    st.answerDue = at
    EVRFeatures.Compat.After(at - now, function()
        if st.answerDue == at then answer(self) end   -- else answered meanwhile, or brought forward
    end)
end

function CommSystem:_Answer()
    -- Respond with a broadcast to the GUILD channel instead of a direct
    -- WHISPER to the sender.  Using WHISPER caused "No player named X"
    -- spam whenever the requester logged off between their REQUEST and our
    -- staggered response — ChatThrottleLib would keep sending each queued
    -- chunk even after the player went offline.
    C_Timer.After(math.random() * 3, function()  -- Stagger responses
        if not EVRFeatures:IsOnGuildDB() then return end
        self:SendRosterSnapshot()

        if EVRFeatures.Bounty then EVRFeatures.Bounty:Broadcast() end

        -- Officers also send the alt/main link table, only while a client before #424 is around
        -- (BroadcastAltLinks). The new clients' links come from AltSync:Backfill below.
        if EVRFeatures:IsOfficer() then
            C_Timer.After(0.5, function()
                self:BroadcastAltLinks()
            end)
        end

        -- Officers also send trial data
        if EVRFeatures:IsOfficer() and EVRFeatures.TrialTracker then
            C_Timer.After(1, function()
                EVRFeatures.TrialTracker:BroadcastTrials()
            end)
        end

        -- Officers also send raid attendance data
        if EVRFeatures:IsOfficer() and EVRFeatures.RaidTracker then
            C_Timer.After(2, function()
                EVRFeatures.RaidTracker:BroadcastRaidData()
            end)
        end

        -- And the guild's officer threshold (issue #81), and on retail its loot system (issue #185)
        if EVRFeatures:IsOfficer() then
            C_Timer.After(3, function()
                EVRFeatures:PublishOfficerMaxRank()
                EVRFeatures:PublishEventMaxRank()   -- who creates events (issue #283)
                if EVRFeatures.Calendar then EVRFeatures.Calendar:PublishMemberKinds() end   -- and which kinds (issue #308)
                EVRFeatures:PublishLootSystem()
                if EVRFeatures.CoreManager then EVRFeatures.CoreManager:PublishAllLoot() end   -- each core's own (issue #338)
                if EVRFeatures.Readiness then EVRFeatures.Readiness:PublishMinIlvl() end  -- Forever (issue #206)
                if EVRFeatures.Founding and EVRFeatures:IsFeatureEnabled("founding") then EVRFeatures.Founding:Publish() end  -- Forever (issue #208)
                if EVRFeatures.TrialTracker then EVRFeatures.TrialTracker:PublishConfig() end  -- the trials' length and switch (#249)
                if EVRFeatures.Discipline then EVRFeatures.Discipline:PublishConfig() end  -- the record's term and ladder (#402)
                if EVRFeatures.ModAlerts then EVRFeatures.ModAlerts:PublishConfig() end  -- the chat alerts' list (#404)
                if EVRFeatures.GuildRules then EVRFeatures.GuildRules:PublishConfig() end  -- the guild's rules (#407)
            end)
        end

        -- Share the guild recruitment config so alts/late-loggers reliably get
        -- it: officers push their own, members relay the cached copy.
        if EVRFeatures.Recruitment then
            C_Timer.After(2.5, function()
                EVRFeatures.Recruitment:RespondToSync()
            end)
        end

        -- Officers answer with the curated raider roster (login backfill).
        if EVRFeatures:IsOfficer() and EVRFeatures.RaiderRoster then
            C_Timer.After(3, function()
                EVRFeatures.RaiderRoster:RespondToSync()
            end)
        end

        -- Every member answers with their own live LFG listing. Availability
        -- is otherwise only ever sent once, so a guildmate who logged in after
        -- the post would see an empty board until it was posted again.
        -- Rebroadcast carries the age of the entry, not a fresh timestamp, so
        -- answering requests can never extend a listing.
        if EVRFeatures.LFGBoard and EVRFeatures.LFGBoard:AmAvailable() then
            C_Timer.After(3.5, function()
                EVRFeatures.LFGBoard:Rebroadcast()
            end)
        end
        -- And a leader with the group they are forming (issue #341), for the same reason.
        if EVRFeatures.Groups and EVRFeatures.Groups:Mine() then
            C_Timer.After(4, function()
                EVRFeatures.Groups:Rebroadcast()
            end)
        end

        -- Every member answers with its own recruitment engagement self-report,
        -- so an officer logging in converges on a fresh picture of who is active.
        if EVRFeatures.RecruitEngagement then
            C_Timer.After(4, function()
                EVRFeatures.RecruitEngagement:BroadcastStats()
            end)
        end

        -- Every member answers with its own current map position (forced past
        -- the throttle), so a guildmate logging in converges on where everyone
        -- is instead of waiting for each peer's next zone change.
        if EVRFeatures.GuildMap then
            C_Timer.After(4.5, function()
                EVRFeatures.GuildMap:Broadcast(true)
            end)
        end

        -- Officers re-broadcast their authoritative shared state (blacklist,
        -- audit trail, bulletin board) so a peer who was offline when it last
        -- changed converges on login instead of waiting for the next mutation.
        -- Each backfill preserves its stored revision and never bumps it, so
        -- the SyncService revision check (or audit id-dedup) drops it for a
        -- peer already current and applies it only for one that missed the
        -- change. Members must never re-broadcast these, hence the gate.
        if EVRFeatures:IsOfficer() and EVRFeatures.BanList then
            C_Timer.After(5, function()
                EVRFeatures.BanList:Backfill()
            end)
        end

        if EVRFeatures:IsOfficer() and EVRFeatures.Discipline then
            C_Timer.After(5.25, function()
                EVRFeatures.Discipline:Backfill()
            end)
        end

        if EVRFeatures:IsOfficer() and EVRFeatures.RosterLog then
            C_Timer.After(5.5, function()
                EVRFeatures.RosterLog:Backfill()
            end)
        end

        if EVRFeatures:IsOfficer() and EVRFeatures.Bulletin then
            C_Timer.After(6, function()
                EVRFeatures.Bulletin:Backfill()
            end)
        end

        -- Every alt link, tombstones included, at its stored revision, in spaced batches, at most once per
        -- AltSync.BACKFILL_GAP (issue #424).
        if EVRFeatures:IsOfficer() and EVRFeatures.AltSync then
            C_Timer.After(6.5, function()
                EVRFeatures.AltSync:Backfill()
            end)
        end

        -- Every member's birthday, tombstones included, in spaced batches (issue #428).
        if EVRFeatures:IsOfficer() and EVRFeatures.Birthdays then
            C_Timer.After(7, function()
                EVRFeatures.Birthdays:Backfill()
            end)
        end

        -- Every member's officer sheet, a couple per envelope and spaced out, once per 10 minutes (issue #427).
        if EVRFeatures:IsOfficer() and EVRFeatures.OfficerNotes then
            C_Timer.After(7.5, function()
                local now = GetTime()
                if not self.lastBulkNotes or now - self.lastBulkNotes >= self.MARKS_BACKFILL_GAP then
                    self.lastBulkNotes = now
                    EVRFeatures.OfficerNotes:BroadcastAllNotes()
                end
                EVRFeatures.OfficerNotes:BackfillSheets()
            end)
        end

        -- The officers' safe list and nicknames (issue #429), the same way, at most once per MARKS_BACKFILL_GAP.
        if EVRFeatures:IsOfficer() and EVRFeatures.MemberMarks then
            C_Timer.After(7, function()
                self:_BackfillMarks()
            end)
        end
    end)
end

----------------------------------------------------------------------
-- Handle data response
----------------------------------------------------------------------
function CommSystem:HandleResponse(sender, data)
    -- Same as broadcast handling
    self:HandleBroadcast(sender, data)
end

----------------------------------------------------------------------
-- Handle ping (presence check)
----------------------------------------------------------------------
function CommSystem:HandlePing(sender)
    self:SendMessage(self.MSG_TYPES.PONG, EVRFeatures.VERSION, sender)
end

----------------------------------------------------------------------
-- A newer EVIL Rises in the guild (#377)
----------------------------------------------------------------------
-- Every member's broadcast carries its addon version, and the newest one above this client's is said in
-- chat: NOTICE_WAIT seconds after the first, so a login's wave of broadcasts says only its newest, and
-- again only if a newer one still comes. The addon cannot see CurseForge: the newest is the newest some
-- guildmate runs. Only a plain x.y.z on both sides counts, so a beta, a dev build or junk off the network
-- warns nobody.
-- At most NOTICE_MAX lines a session, and each part at most three digits: a guildmate stepping
-- 1.29.1, 1.29.2... earns a few lines, not one every 10s.
-- ponytail: one guildmate can still claim a version; ask for two senders if that is ever abused.
CommSystem.NOTICE_WAIT, CommSystem.NOTICE_MAX = 10, 3
local PLAIN = "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?$"
function CommSystem:HandleVersionCheck(_sender, ver)
    if type(ver) == "string" and ver:match(PLAIN) and not self:_AfterLegacyAlt(ver) then self:_HeardLegacy() end
    local cur, M = EVRFeatures.VERSION, EVRFeatures.Mesh
    if not (M and M.CompareVersions) then return end
    if type(ver) ~= "string" or not ver:match(PLAIN) or type(cur) ~= "string" or not cur:match(PLAIN) then return end
    if M.CompareVersions(ver, self.newestSeen or cur) <= 0 then return end
    self.newestSeen = ver
    if self.noticeDue or (self.noticesSaid or 0) >= self.NOTICE_MAX then return end
    self.noticeDue = true
    C_Timer.After(self.NOTICE_WAIT, function()
        self.noticeDue = nil
        self.noticesSaid = (self.noticesSaid or 0) + 1
        EVRFeatures:Print(string.format(L["EVIL Rises %s is out, you have %s. Update it on CurseForge."], self.newestSeen, cur))
    end)
end

----------------------------------------------------------------------
-- Broadcast alt link table to all officers in guild
----------------------------------------------------------------------
-- For the clients before #424, which replace their whole table with it (issue #424). Only while one was
-- heard within LEGACY_WINDOW: with only new clients listening it is noise, and an old officer's unlink is not
-- undone on the old clients by a new one's view. AltSync:LegacyView is the whole view without the unconfirmed
-- links an old officer's newest table lacks; an empty one goes too (the last unlink reaches the old clients),
-- but nothing goes from a client that knows no entry at all (a new install would wipe them).
function CommSystem:BroadcastAltLinks()
    if not EVRFeatures:IsOfficer() then return end
    if not IsInGuild() or not EVRFeatures.AltSync or not self:LegacyHeard() then return end
    local links = EVRFeatures.AltSync:LegacyView()
    if type(links) ~= "table" then return end
    local serialized = LibSerialize:Serialize(links, ALT_LINK_MARK)
    self:SendMessage(self.MSG_TYPES.ALT_LINK, serialized)
end

-- Whether `ver` (a plain x.y.z) is a version with AltSync, after LEGACY_ALT_MAX.
function CommSystem:_AfterLegacyAlt(ver)
    local function parts(v)
        local a, b, c = v:match("^(%d+)%.(%d+)%.(%d+)$")
        return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    end
    local a1, a2, a3 = parts(ver)
    local b1, b2, b3 = parts(self.LEGACY_ALT_MAX)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

function CommSystem:_HeardLegacy()
    self.legacyHeardAt = GetTime()
end

--- Whether a client before #424 was heard within LEGACY_WINDOW.
function CommSystem:LegacyHeard()
    return self.legacyHeardAt ~= nil and GetTime() - self.legacyHeardAt < self.LEGACY_WINDOW
end

-- MemberMarks:Backfill on a sync request's answer, at most once per MARKS_BACKFILL_GAP unless forced.
function CommSystem:_BackfillMarks(force)
    if not EVRFeatures.MemberMarks then return end
    local now = GetTime()
    if not force and self._marksBackfillAt and now - self._marksBackfillAt < self.MARKS_BACKFILL_GAP then return end
    self._marksBackfillAt = now
    EVRFeatures.MemberMarks:Backfill()
end

----------------------------------------------------------------------
-- Sync health: who is running EVIL Rises, who is on an outdated version,
-- and when each member last synced data. Drives the Audit > Sync view.
-- Returns (rows, withAddonCount, outdatedCount). Each row:
-- { name, key, class, online, hasAddon, version, outdated, lastUpdate }
----------------------------------------------------------------------
function CommSystem:GetSyncHealth()
    local rows, withAddon, outdated = {}, 0, 0
    local cur = EVRFeatures.VERSION
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = EVRFeatures:GetPlayerKey(short, realm)
            local d = EVRFeatures.db.members[key]
            local has = (d and d.lastUpdate and d.lastUpdate > 0) and true or false
            local ver = d and d.addonVersion or nil
            local isOld = (has and ver and EVRFeatures.Mesh.CompareVersions(ver, cur) < 0) and true or false
            if has then withAddon = withAddon + 1 end
            if isOld then outdated = outdated + 1 end
            rows[#rows + 1] = {
                name = short, key = key, class = classFile or "", online = isOnline,
                hasAddon = has, version = ver, outdated = isOld,
                lastUpdate = (d and d.lastUpdate) or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        -- Members WITHOUT the addon first (those are the actionable ones).
        if a.hasAddon ~= b.hasAddon then return not a.hasAddon end
        return a.name:lower() < b.name:lower()
    end)
    return rows, withAddon, outdated
end
