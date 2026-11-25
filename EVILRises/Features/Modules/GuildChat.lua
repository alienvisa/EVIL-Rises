----------------------------------------------------------------------
-- EVIL Rises - Guild and officer chat
--
-- Every line of /g, the player's own included, goes into the guild's own
-- log, so the Chat sub-tab can show what was said before the window opened
-- and before the last reload. Sending is the player pressing Enter in that
-- tab, which is a hardware event, so it is allowed on WoW: Forever too.
--
-- Where the server keeps the guild's chat (WoW: Forever, issue #126), the tab
-- shows that instead: it also holds what was said while the player was away,
-- with separate feeds for guild and officer chat. Only /g is written to disk.
--
-- A channel is { id, name, kind } from Compat.GuildChatStreams; nil means /g.
--
-- Unlike the alliance channel, the line is kept as the game sent it: item
-- and player links stay clickable. It is what the default chat frame shows
-- for the same line, and only the guild can say it. Line breaks go: one
-- line of chat is one line of the feed.
----------------------------------------------------------------------
local GuildChat = {}
EVRFeatures.GuildChat = GuildChat

-- Capped on purpose: plain text on the player's disk, and an unbounded log
-- would grow the SavedVariables file forever.
GuildChat.MAX_LOG = 200

GuildChat.listeners = {}

function GuildChat:Log()
    EVRFeatures.db.guildChatLog = EVRFeatures.db.guildChatLog or {}
    return EVRFeatures.db.guildChatLog
end

function GuildChat:OnRefresh(fn)
    if type(fn) == "function" then
        self.listeners[#self.listeners + 1] = fn
    end
end

function GuildChat:_Notify()
    for _, fn in ipairs(self.listeners) do
        pcall(fn)
    end
end

-- Prefer the officer stream for its history. A rank with listen permission can
-- also follow live /o events on clients that expose no officer stream.
local guildStream = { kind = "guild" }
local liveOfficer = { kind = "officer" }
function GuildChat:OfficerStream()
    if not EVRFeatures:IsOnGuildDB() then return end
    local rank = select(3, GetGuildInfo("player"))
    local flags = EVRFeatures.Compat.GuildRankFlags(rank)
    if rank ~= 0 and flags and flags[3] == false then return end
    for _, stream in ipairs(EVRFeatures.Compat.GuildChatStreams() or {}) do
        if stream.kind == "officer" then return stream end
    end
    if rank == 0 or (flags and flags[3] == true) then return liveOfficer end
end

function GuildChat:Streams()
    return { guildStream, self:OfficerStream() }
end

-- In a chat lockdown nothing of the server's can be read: a feed keeps what it shows.
function GuildChat:Locked()
    return EVRFeatures.Compat.InChatLockdown()
end

local function isGuild(stream)
    return not stream or stream.kind == "guild"
end

-- What a channel's tab shows, and whether it came from the server. For /g, the
-- server's history where it has one, and the addon's log elsewhere or while the
-- server has nothing loaded yet: never both, so no line shows twice. Any other
-- channel only ever has the server's.
function GuildChat:Entries(stream)
    local live = self.officerGuild == EVRFeatures.guildKey and self.officerLog
    if not isGuild(stream) then
        local allowed = self:OfficerStream()
        if not allowed or allowed.id ~= stream.id then return {} end
        if not stream.id then return live or {} end
    end
    local server, locked = EVRFeatures.Compat.GuildChatHistory(self.MAX_LOG, stream and stream.id)
    if locked then return nil end
    if not isGuild(stream) then
        return server and #server > 0 and server or live or {}, true
    end
    if server and #server > 0 then
        return GuildChat.Merge(server, self:AlliedLog(), self.MAX_LOG), true
    end
    return GuildChat.Merge(self:Log(), self:AlliedLog(), self.MAX_LOG), false
end

----------------------------------------------------------------------
-- The allied guilds' /g (issue #344), kept apart from ours: the server's
-- history replaces our log where it has one, and it never holds these.
-- Each entry carries `g`, the guild it came from, which the feed shows as a
-- tag and which keeps two namesakes of two guilds in separate blocks.
----------------------------------------------------------------------
function GuildChat:AlliedLog()
    EVRFeatures.db.guildChatAllyLog = EVRFeatures.db.guildChatAllyLog or {}
    return EVRFeatures.db.guildChatAllyLog
end

function GuildChat:AddAllied(guild, line)
    if type(guild) ~= "string" or type(line) ~= "table" then return end
    local log = self:AlliedLog()
    log[#log + 1] = {
        t = GetServerTime(),
        n = (Ambiguate and Ambiguate(line.n or "", "short")) or line.n,
        c = line.c,
        g = guild,
        m = line.m,
    }
    while #log > self.MAX_LOG do
        table.remove(log, 1)
    end
    self:_Notify()
end

-- Pure. Two time-ordered logs as one, oldest first, the newest `cap` kept. An
-- empty allied log hands back ours untouched, which is every guild outside an
-- alliance.
function GuildChat.Merge(own, allied, cap)
    if type(allied) ~= "table" or #allied == 0 then
        return own
    end
    local out, i, j = {}, 1, 1
    while i <= #own or j <= #allied do
        local a, b = own[i], allied[j]
        if b and (not a or (tonumber(b.t) or 0) < (tonumber(a.t) or 0)) then
            out[#out + 1] = b
            j = j + 1
        else
            out[#out + 1] = a
            i = i + 1
        end
    end
    cap = cap or #out
    if #out > cap then
        local trimmed = {}
        for k = #out - cap + 1, #out do trimmed[#trimmed + 1] = out[k] end
        out = trimmed
    end
    return out
end

-- A channel's tab opened (true) or closed. Two feeds can show one channel (the
-- Now card and Guild > Chat), so the server hears the first open and the last
-- close. Opened, it is asked for older lines while it holds fewer than the cap;
-- they redraw the tab when they arrive.
GuildChat.watching = {}

function GuildChat:Watch(on, stream)
    if not isGuild(stream) and not stream.id then return end
    if on and not isGuild(stream) then
        local allowed = self:OfficerStream()
        if not allowed or allowed.id ~= stream.id then return end
    end
    local id = (not isGuild(stream)) and stream.id or nil
    local key = id or "guild"
    local was = self.watching[key] or 0
    if not on and was == 0 then return end
    self.watching[key] = was + (on and 1 or -1)
    if not on then
        if was == 1 then EVRFeatures.Compat.WatchGuildChat(false, id) end
        return
    end
    if was > 0 then return end
    EVRFeatures.Compat.WatchGuildChat(true, id)
    local server = EVRFeatures.Compat.GuildChatHistory(self.MAX_LOG, id)
    if server and #server < self.MAX_LOG then
        EVRFeatures.Compat.RequestOlderGuildChat(self.MAX_LOG - #server, id)
    end
end

-- The class is read now, while the speaker is a GUID the game knows: the
-- history is drawn in class colours long after they logged off.
local function classOf(guid)
    if not guid or EVRFeatures.Compat.IsSecret(guid) or not GetPlayerInfoByGUID then return nil end
    local _, class = GetPlayerInfoByGUID(guid)
    if EVRFeatures.Compat.IsSecret(class) then return nil end
    return class
end

function GuildChat:_OnMessage(msg, author, guid, officer)
    -- Chat in lockdown on Forever: neither the line nor its speaker is readable.
    if EVRFeatures.Compat.IsSecret(msg, author) or not msg or not author then return end
    -- The data resolved at login for a guildless character is shared by every guildless
    -- character on the realm: a guild joined since then is not written into it.
    if not EVRFeatures:IsOnGuildDB() then return end
    local log
    if officer then
        if not self:OfficerStream() then return end
        if self.officerGuild ~= EVRFeatures.guildKey then self.officerLog = {} end
        self.officerGuild = EVRFeatures.guildKey
        self.officerLog = self.officerLog or {}
        log = self.officerLog
    else
        log = self:Log()
    end
    log[#log + 1] = {
        t = GetServerTime(),
        n = (Ambiguate and Ambiguate(author, "guild")) or author,
        c = classOf(guid),
        m = (tostring(msg):gsub("%c", " ")),
    }
    while #log > self.MAX_LOG do
        table.remove(log, 1)
    end
    self:_Notify()
end

-- Only ever called from a tab's Enter or Send click. The line is not logged
-- here: it shows when the game echoes it back.
function GuildChat:Send(text, stream)
    local clean = EVRFeatures:SanitizeUserText(text, 240)
    if clean == "" then
        return false
    end
    -- Forever drops a line sent in an encounter's chat lockdown without an error, so it is
    -- asked first and the text stays with the player (as Modules/CallToArms.lua does).
    if EVRFeatures.Compat.InChatLockdown() then
        return false, "locked"
    end
    if isGuild(stream) then
        SendChatMessage(clean, "GUILD")
        -- The same click carries it to the allied guilds (issue #348): the tab's
        -- box is not one of the chat frame's, so the hook there never sees it.
        if EVRFeatures.AllianceLink then EVRFeatures.AllianceLink:OnPlayerChat("GUILD", clean) end
    elseif stream.kind == "officer" then
        if not self:OfficerStream() or EVRFeatures.Compat.CanSpeakOfficerChat() == false then return false end
        SendChatMessage(clean, "OFFICER")
    else
        return EVRFeatures.Compat.SendGuildStream(stream.id, clean)
    end
    return true
end

function GuildChat:Initialize()
    local f = CreateFrame("Frame")
    EVRFeatures.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    EVRFeatures.Compat.RegisterEvent(f, "CHAT_MSG_OFFICER")
    for _, event in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_RANKS_UPDATE" }) do
        EVRFeatures.Compat.RegisterEvent(f, event, true)
    end
    -- The server's channels: a new line, older ones arriving, a channel made or
    -- removed, the list arriving. Absent where there are none.
    EVRFeatures.Compat.RegisterEvent(f, "CLUB_MESSAGE_ADDED", true)
    EVRFeatures.Compat.RegisterEvent(f, "CLUB_MESSAGE_HISTORY_RECEIVED", true)
    EVRFeatures.Compat.RegisterEvent(f, "CLUB_STREAM_ADDED", true)
    EVRFeatures.Compat.RegisterEvent(f, "CLUB_STREAM_REMOVED", true)
    EVRFeatures.Compat.RegisterEvent(f, "CLUB_STREAMS_LOADED", true)
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event == "GUILD_RANKS_UPDATE" then
            if GuildChat.officerGuild ~= EVRFeatures.guildKey or not GuildChat:OfficerStream() then
                GuildChat.officerLog, GuildChat.officerGuild = nil, nil
            end
            GuildChat:_Notify()
            return
        end
        if event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
            local msg, author = ...
            local guid = select(12, ...)
            EVRFeatures:SafeCall(function() GuildChat:_OnMessage(msg, author, guid, event == "CHAT_MSG_OFFICER") end)
            return
        end
        local clubId = ...
        EVRFeatures:SafeCall(function()
            if EVRFeatures.Compat.IsGuildClub(clubId) then GuildChat:_Notify() end
        end)
    end)
end
