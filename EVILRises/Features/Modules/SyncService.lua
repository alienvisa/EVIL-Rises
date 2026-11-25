----------------------------------------------------------------------
-- EVIL Rises - Sync Service (protocol v2)
--
-- A thin, versioned publish/subscribe layer that sits ON TOP of
-- CommSystem's transport (serialize -> compress -> chunk). New
-- shared-state features (points/DKP, calendar events, guild bank,
-- polls, ...) publish through here instead of inventing ad-hoc message
-- strings, so they automatically get:
--   * a versioned envelope (protocol version + addon version)
--   * messageId dedup (drops echoes and re-deliveries)
--   * per-entity revision checks (highest revision wins)
--   * officer-domain write-permission enforcement
--   * optional ACK for critical messages (award/delete) with one retry
--
-- Backward compatible: this is carried as a single new CommSystem wire
-- type ("SV"). Every legacy message type keeps working untouched.
--
-- Addresses ADR-0010 (central type inventory) and ADR-0012 (protocol
-- versioning) for all *new* domains.
----------------------------------------------------------------------
local SyncService = {}
EVRFeatures.SyncService = SyncService

local LibSerialize = LibStub("EVRFeatures-LibSerialize")

SyncService.PROTOCOL_VERSION = 2
SyncService.ENVELOPE_MSGTYPE = "SV"   -- CommSystem wire tag carrying a v2 envelope

-- Domains whose WRITES require the sender to be a verified guild officer.
-- Reads (snapshots applied locally) are still gated by these because the
-- sender is the writer. Member-level actions inside an officer domain are
-- whitelisted per domain in MEMBER_ACTIONS below.
SyncService.OFFICER_DOMAINS = {
    points   = true,   -- DKP / EPGP / loot council economy
    event    = true,   -- calendar event create/update/delete (rsvp is member-level)
    poll     = true,   -- poll create/close (vote is member-level)
    bulletin = true,   -- officer announcements
    cta      = true,   -- an officer's call to arms (answering it is a member action, issue #108)
    ban      = true,   -- blacklist add/remove (officer-authoritative)
    alt      = true,   -- alt links, one entry per alt with a tombstone on unlink (issue #424)
    osheet   = true,   -- a member's officer sheet, the long text (issue #427): officers write, and only officers keep it
    discipline = true, -- the disciplinary record (issue #402): officers write, and only officers keep it
    reminder  = true,  -- when an officer reminded a member to install EVRFeatures (issue #422)
    modalert  = true,  -- an officer claiming a flagged chat line, so the others do not alert (issue #404)
    audit    = true,   -- guild audit trail (officer-authoritative, id-deduped)
    allyboard = true,  -- alliance bulletin posts this guild authored (ambassadors)
    allyhide  = true,  -- chat lines an ambassador pulled from the alliance feed
    guildcfg  = true,  -- the guild's officer threshold (issue #81), on retail its loot system (#185), its trials (#249)
    founding  = true,  -- WoW: Forever's founding and an officer's suggested date (issue #208)
    allylink  = true,  -- the alliance code an officer saved (issue #348); ask/have are member relays
    gbankneed = true,  -- how much of each item the guild bank should hold (issue #380)
    gbankclean = true, -- what officers marked to take out of the guild bank and sell (issue #380)
    marks     = true,  -- the officers' safe list and nicknames (issue #429)
}

-- Domains outside OFFICER_DOMAINS whose handlers trust IsOfficerByName(sender) themselves.
-- Handlers never see the channel, so the GUILD rule is held here (issue #81).
SyncService.GUILD_ONLY_DOMAINS = {
    bounty = true,
    alliance       = true,   -- AllianceSync's trusted fan-out
    ["core.roster"] = true,  -- CoreManager's officer roster updates
    journal        = true,   -- each member's own journal (#205): from the guild, never a whisper
    foundingSelf   = true,   -- each member's own join date (#208), filed under its sender
    birthday       = true,   -- a member's birthday, for their own characters; officers correct it (#428)
    gbank          = true,   -- the guild bank's picture, its ledger and asks for them (#380)
    gbankreq       = true,   -- a member's request for an item; officers close it (#380)
    craftorder     = true,   -- a member's craft order and its crafter's answers (#389)
}

-- Officer domains that travel only over the game's OFFICER addon channel (issue #427): free text about a person,
-- whose bytes a member's client must never get. Published there, accepted only from there; never over GUILD or a
-- whisper. On a client without that channel (Compat.OfficerAddonChannel) they are not sent at all.
SyncService.OFFICER_CHANNEL_DOMAINS = {
    osheet = true,
    marks  = true,   -- the safe list and nicknames (#429): what officers call a member
}

-- Actions any guild member may perform inside an officer domain, over GUILD. Keyed by domain:
-- an action word that opened every domain let a member send the guild's officer threshold
-- dressed as an RSVP, and so become an officer everywhere (issue #108).
SyncService.MEMBER_ACTIONS = {
    event = { rsvp = true },    -- event signup
    allylink = { ask = true, have = true },   -- asking for the alliance code, and relaying an officer's
    poll  = { vote = true },    -- poll vote
    cta   = { going = true },   -- "On my way" to an officer's call to arms (issue #108)
}

-- Actions inside an officer domain that whoever the guild lets do them may send over GUILD (issue #283).
-- The domain's handler holds the rest of the rule: a creator who is not an officer writes only their own events.
SyncService.RANKED_ACTIONS = {
    event = { create = true, update = true, cancel = true, delete = true },
}

SyncService.handlers    = {}   -- [domain] = function(env, sender)
SyncService.seenIds     = {}   -- messageId dedup set
SyncService.seenOrder   = {}
SyncService.seenSlot    = 1
SyncService.pendingAcks = {}   -- [id] = { tries, payload, target, priority, dom, act }

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function SyncService:Initialize()
    -- Persistent revision store: db.sync.rev[domain][entityKey] = number
    EVRFeatures.db.sync = EVRFeatures.db.sync or {}
    EVRFeatures.db.sync.rev = EVRFeatures.db.sync.rev or {}
    self.seenIds = {}
    self.seenOrder = {}
    self.seenSlot = 1
    self.pendingAcks = {}
    -- The guild's settings an officer decides: the officer threshold (issue #81) and, on retail, the
    -- loot system (issue #185). A client before #185 reads a loot system as a threshold with no `max`.
    self:On("guildcfg", function(env)
        if env.act == "lootsys" then return EVRFeatures:OnLootSystemSync(env) end
        -- The guild's own loot rule (issue #333); a client before it reads a threshold with no `max`.
        if env.act == "lootrule" then
            if EVRFeatures.LootRule then EVRFeatures.LootRule:OnSync(env) end
            return
        end
        -- WoW: Forever's minimum item level for a 60 (issue #206); a client before it reads a
        -- threshold with no `max`, which it ignores.
        if env.act == "readymin" then
            if EVRFeatures.Readiness then EVRFeatures.Readiness:OnMinIlvlSync(env) end
            return
        end
        -- The guild's trial length and its switch for new members (issue #249); neither carries `max`.
        if env.act == "trialdays" or env.act == "trialauto" then
            if EVRFeatures.TrialTracker then EVRFeatures.TrialTracker:OnConfigSync(env) end
            return
        end
        -- The disciplinary record's term and ladder (issue #402); neither carries `max`.
        if env.act == "discterm" or env.act == "discladder" or env.act == "disctpl" or env.act == "discrank" then
            if EVRFeatures.Discipline then EVRFeatures.Discipline:OnConfigSync(env) end
            return
        end
        -- The officers' list of chat alerts (issue #404); it carries no `max`.
        if env.act == "modrules" then
            if EVRFeatures.ModAlerts then EVRFeatures.ModAlerts:OnConfigSync(env) end
            return
        end
        -- And the anti-flood's limits (issue #405); it carries no `max`.
        if env.act == "modflood" then
            if EVRFeatures.ModFlood then EVRFeatures.ModFlood:OnConfigSync(env) end
            return
        end
        -- And the newcomer's quarantine (issue #406); it carries no `max`.
        if env.act == "newcomer" then
            if EVRFeatures.Newcomer then EVRFeatures.Newcomer:OnConfigSync(env) end
            return
        end
        -- The guild's rules (issue #407), kept on every client; it carries no `max`.
        if env.act == "rules" then
            if EVRFeatures.GuildRules then EVRFeatures.GuildRules:OnConfigSync(env) end
            return
        end
        -- Who creates calendar events (issue #283).
        if env.act == "events" then
            EVRFeatures:OnEventMaxRankSync(env)
            return
        end
        -- And which kinds of event the ranks below the officers create (issue #308); it carries no `max`.
        if env.act == "eventkinds" then
            if EVRFeatures.Calendar then EVRFeatures.Calendar:OnMemberKindsSync(env) end
            return
        end
        EVRFeatures:OnOfficerMaxRankSync(env)
    end)
end

local function newId()
    return string.format("%04X%04X", math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

----------------------------------------------------------------------
-- Register a domain handler. fn(env, sender) is called for each valid,
-- non-duplicate envelope addressed to `domain`.
----------------------------------------------------------------------
function SyncService:On(domain, fn)
    self.handlers[domain] = fn
end

-- Keep recent revisioned writes briefly for peers that missed one. An officer's
-- records have their own history and are advertised and replayed on OFFICER only.
local MAX_RECENT, MAX_ENTRY_BYTES, RECENT_SECONDS = 12, 16384, 180
local recent = { GUILD = {}, OFFICER = {} }

local function remember(env, payload, channel)
    if not env.rev or #payload > MAX_ENTRY_BYTES then return end
    local entries = recent[channel]
    if #entries == MAX_RECENT then table.remove(entries, 1) end
    entries[#entries + 1] = { id = env.id, payload = payload, expires = GetTime() + RECENT_SECONDS }
end

function SyncService:RecentIds(channel)
    local ids, now = {}, GetTime()
    for _, entry in ipairs(recent[channel]) do
        if entry.expires > now then ids[#ids + 1] = entry.id end
    end
    return table.concat(ids)
end

function SyncService:CheckRecent(sender, ids, channel)
    if #ids == 0 or #ids > MAX_RECENT * 8 or #ids % 8 ~= 0 or ids:find("[^%x]") then return end
    local missing = {}
    for i = 1, #ids, 8 do
        local id = ids:sub(i, i + 7)
        if not self.seenIds[sender .. ":" .. id] then missing[#missing + 1] = id end
    end
    if #missing > 0 and (channel ~= "OFFICER" or EVRFeatures.Compat.OfficerAddonChannel()) then
        EVRFeatures.CommSystem:SendMessage("HM", sender .. ":" .. table.concat(missing), nil, nil, nil, channel)
    end
end

function SyncService:ReplayRecent(data, channel)
    local target, ids = data:match("^([^:]+):(%x+)$")
    if not target or #ids > MAX_RECENT * 8 or #ids % 8 ~= 0
        or EVRFeatures:KeyOfRosterName(target) ~= EVRFeatures:KeyOfRosterName(EVRFeatures.Compat.PlayerName()) then return end
    local wanted = {}
    for i = 1, #ids, 8 do wanted[ids:sub(i, i + 7)] = true end
    for _, entry in ipairs(recent[channel]) do
        if wanted[entry.id] and entry.expires > GetTime() and not entry.pending then
            entry.pending = true
            C_Timer.After(0.25, function()
                entry.pending = nil
                if not EVRFeatures:IsOnGuildDB() then return end
                if channel == "OFFICER" and not EVRFeatures.Compat.OfficerAddonChannel() then return end
                EVRFeatures.CommSystem:SendMessage("SV", entry.payload, nil, nil, nil, channel)
            end)
        end
    end
end

----------------------------------------------------------------------
-- Publish an envelope to the guild (or a single target).
-- opts (all optional):
--   target     send to a single player (WHISPER) instead of GUILD
--   priority   ChatThrottleLib priority ("BULK"|"NORMAL"|"ALERT")
--   rev        entity revision (receiver applies only if newer)
--   pv         payload schema version (default 1)
--   src        origin tag ("local"|"sync"|"migration"|"import")
--   requireAck request an ACK from `target` (target required); 1 retry
-- Returns the messageId, or nil if it could not be sent.
----------------------------------------------------------------------
function SyncService:Publish(domain, action, data, opts)
    if not EVRFeatures:IsOnGuildDB() then return nil end
    opts = opts or {}

    local env = {
        v   = self.PROTOCOL_VERSION,
        id  = newId(),
        av  = EVRFeatures.VERSION,
        dom = domain,
        act = action,
        ts  = (GetTime and GetTime()) or 0,
        rev = opts.rev,
        pv  = opts.pv or 1,
        src = opts.src or "local",
        data = data,
    }
    if opts.requireAck and opts.target then
        env.ack = true
    end

    local officersOnly = self.OFFICER_CHANNEL_DOMAINS[domain]
    if officersOnly then
        -- No channel, or a rank that may not speak there (told once a session, shared with the notes, #430).
        local chan = EVRFeatures.CommSystem and EVRFeatures.CommSystem:OfficerChannel()
        if opts.target or not chan then return nil end
    end

    local ok, serialized = pcall(function() return LibSerialize:Serialize(env) end)
    if not ok or type(serialized) ~= "string" then return nil end
    if not EVRFeatures.CommSystem then return nil end

    if not opts.target then remember(env, serialized, officersOnly and "OFFICER" or "GUILD") end
    if officersOnly then
        EVRFeatures.CommSystem:SendToOfficers(self.ENVELOPE_MSGTYPE, serialized, opts.priority,
            self.ENVELOPE_MSGTYPE .. " " .. tostring(domain))
        return env.id
    end

    EVRFeatures.CommSystem:SendMessage(self.ENVELOPE_MSGTYPE, serialized, opts.target, opts.priority,
        self.ENVELOPE_MSGTYPE .. " " .. tostring(domain))   -- /eviltools perf counts it by domain (issue #324)

    if env.ack then
        self.pendingAcks[env.id] = {
            tries = 1, payload = serialized, target = opts.target,
            priority = opts.priority, dom = domain, act = action,
        }
        local id = env.id
        EVRFeatures.Compat.After(10, function() self:RetryAck(id) end)
    end
    return env.id
end

----------------------------------------------------------------------
-- ACK retry: resend the IDENTICAL envelope (same id) so a receiver that
-- already applied it dedups it (no double-apply) but one that missed it
-- gets a second chance. Gives up after one retry.
----------------------------------------------------------------------
function SyncService:RetryAck(id)
    local p = self.pendingAcks[id]
    if not p then return end   -- already acked
    if p.tries >= 2 then
        self.pendingAcks[id] = nil
        EVRFeatures.Logger.Warn(string.format("Sync: no ACK for %s/%s", tostring(p.dom), tostring(p.act)))
        return
    end
    p.tries = p.tries + 1
    EVRFeatures.CommSystem:SendMessage(self.ENVELOPE_MSGTYPE, p.payload, p.target, p.priority)
    EVRFeatures.Compat.After(10, function() self:RetryAck(id) end)
end

local function sendAck(refId, target)
    SyncService:Publish("ack", "ok", { ref = refId }, { target = target })
end

----------------------------------------------------------------------
-- Entry point called by CommSystem when an "SV" wire message arrives.
-- `raw` is the serialized v2 envelope (already de-chunked/decompressed).
----------------------------------------------------------------------
function SyncService:OnEnvelope(sender, raw, channel)
    local ok, env = LibSerialize:Deserialize(raw)
    if not ok or type(env) ~= "table" then return end
    if EVRFeatures.State.comm then EVRFeatures.State.comm.recvKind = self.ENVELOPE_MSGTYPE .. " " .. tostring(env.dom) end

    -- ACK frames clear a pending entry and never dispatch.
    if not self:Validate(env, sender, channel) then return end
    if env.dom == "ack" then
        local ref = type(env.data) == "table" and env.data.ref
        local pending = self.pendingAcks[ref]
        if pending and channel == "WHISPER" and env.act == "ok"
            and EVRFeatures:KeyOfRosterName(pending.target) == EVRFeatures:KeyOfRosterName(sender) then
            self.pendingAcks[ref] = nil
        end
        return
    end

    -- Duplicate: drop, but honour a re-ack request so a lost ACK recovers.
    if self:IsDuplicate(sender .. ":" .. env.id) then
        if env.ack then sendAck(env.id, sender) end
        return
    end

    local handler = self.handlers[env.dom]
    if handler then
        local log = EVRFeatures.DebugWindow
        if log and log.capturing then log:Record("Sync", "Dispatch " .. env.dom .. " / " .. env.act .. " from " .. sender) end
        EVRFeatures:SafeCall(handler, env, sender)
    end

    if env.ack then sendAck(env.id, sender) end
end

----------------------------------------------------------------------
-- Validation: structure, protocol ceiling, and officer-domain writes.
----------------------------------------------------------------------
-- An officer write counts only over GUILD: IsOfficerByName drops the realm, so a namesake on
-- another realm could otherwise whisper as the officer (issue #81, as #78 for the rest).
function SyncService:Validate(env, sender, channel)
    if type(env) ~= "table" then return false end
    if type(env.v) ~= "number" or type(env.id) ~= "string" or type(env.dom) ~= "string"
        or type(env.act) ~= "string" then return false end
    if env.v > self.PROTOCOL_VERSION then return false end   -- newer protocol than we speak
    if self.GUILD_ONLY_DOMAINS[env.dom] and channel ~= "GUILD" then return false end
    if self.OFFICER_DOMAINS[env.dom] then
        if channel ~= (self.OFFICER_CHANNEL_DOMAINS[env.dom] and "OFFICER" or "GUILD") then return false end
        local member = self.MEMBER_ACTIONS[env.dom]
        local ranked = self.RANKED_ACTIONS[env.dom]
        if not (member and member[env.act]) and not EVRFeatures:IsOfficerByName(sender)
            and not (ranked and ranked[env.act] and EVRFeatures:MayCreateEventsByName(sender)) then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------
-- Dedup: circular set of the last ~500 messageIds.
----------------------------------------------------------------------
function SyncService:IsDuplicate(id)
    if self.seenIds[id] then return true end
    local slot = self.seenSlot
    local oldest = self.seenOrder[slot]
    if oldest then self.seenIds[oldest] = nil end
    self.seenOrder[slot] = id
    self.seenSlot = slot % 500 + 1
    self.seenIds[id] = true
    return false
end

----------------------------------------------------------------------
-- Revision helpers (highest revision wins per entity, per domain).
----------------------------------------------------------------------
function SyncService:GetRevision(domain, key)
    local rev = EVRFeatures.db.sync and EVRFeatures.db.sync.rev and EVRFeatures.db.sync.rev[domain]
    return (rev and rev[key]) or 0
end

-- True if an incoming revision should be applied. Unversioned (nil) always applies.
function SyncService:ShouldApply(domain, key, rev)
    if not rev then return true end
    return rev > self:GetRevision(domain, key)
end

-- Record a revision we have applied (only ever increases).
function SyncService:SetRevision(domain, key, rev)
    if not rev then return end
    EVRFeatures.db.sync = EVRFeatures.db.sync or {}
    EVRFeatures.db.sync.rev = EVRFeatures.db.sync.rev or {}
    EVRFeatures.db.sync.rev[domain] = EVRFeatures.db.sync.rev[domain] or {}
    local cur = EVRFeatures.db.sync.rev[domain][key] or 0
    if rev > cur then EVRFeatures.db.sync.rev[domain][key] = rev end
end

-- Allocate the next revision for an entity we are about to write+publish.
function SyncService:NextRevision(domain, key)
    EVRFeatures.db.sync = EVRFeatures.db.sync or {}
    EVRFeatures.db.sync.rev = EVRFeatures.db.sync.rev or {}
    EVRFeatures.db.sync.rev[domain] = EVRFeatures.db.sync.rev[domain] or {}
    local nxt = (EVRFeatures.db.sync.rev[domain][key] or 0) + 1
    EVRFeatures.db.sync.rev[domain][key] = nxt
    return nxt
end
