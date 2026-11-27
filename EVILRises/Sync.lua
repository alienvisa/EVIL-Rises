local _, board = ...
local comm = LibStub("AceComm-3.0")
local codec = LibStub("EVRFeatures-LibSerialize")
local wire = LibStub("LibDeflate")
local prefix = "EVRBounty1"
local noop = function() end
local log, logSync = board.Log or noop, board.LogSync or noop
local version, noteVersion = board.Version or noop, board.NoteVersion or noop
-- A message as the debug log names it.
local function describe(kind, payload)
    if kind == "hello" then return "hello (asks for revisions)" end
    if kind == "revision" then return "revision " .. tostring(payload) end
    if kind == "get" then return "get sheet of " .. tostring(payload) end
    if kind == "sheet" and type(payload) == "table" then
        return string.format("sheet rev %s, %d posts", tostring(payload.rev),
            type(payload.posts) == "table" and #payload.posts or 0)
    end
    return tostring(kind)
end
local function send(kind, payload)
    local guild = board.GuildID()
    if not guild then return end
    -- The trailing version is read by newer clients and ignored by older ones.
    local encoded = wire:EncodeForWoWAddonChannel(codec:Serialize(guild, kind, payload, version()))
    comm:SendCommMessage(prefix, encoded, "GUILD", nil, "NORMAL")
    logSync("out", "Bounty", "%s  ·  %d bytes", describe(kind, payload), #encoded)
end
local function ownSheet()
    local data = board.Records()
    return data and data[board.Owner()]
end
function board.SendSheet(sheet)
    send("sheet", sheet)
end
local function announce()
    local sheet = ownSheet()
    if sheet then send("revision", sheet.rev) end
end
local scheduled = {}
local function once(kind, fn)
    local guild = board.GuildID()
    if not guild or scheduled[kind] == guild then return end
    scheduled[kind] = guild
    C_Timer.After(0.5 + math.random(), function()
        if scheduled[kind] ~= guild then return end
        scheduled[kind] = nil
        if board.GuildID() == guild then fn() end
    end)
end
function board.Request()
    once("hello", function() send("hello", false) end)
end
comm.RegisterComm(board, prefix, function(_, message, channel, sender)
    local author = board.Owner(sender)
    -- The guild channel echoes our own messages back: those are not logged twice.
    if author and author == board.Owner() then return end
    if channel ~= "GUILD" or #message > 32000 then
        logSync("drop", "Bounty", "from %s on %s  ·  %d bytes  ·  not the guild channel or too large",
            sender, channel, #message)
        return
    end
    if not author then return end
    local raw = wire:DecodeForWoWAddonChannel(message)
    if not raw then
        logSync("drop", "Bounty", "from %s  ·  could not decode", sender)
        return
    end
    local ok, guild, kind, payload, theirs = codec:Deserialize(raw)
    if not ok or not guild or guild ~= board.GuildID() then
        logSync("drop", "Bounty", "from %s  ·  %s", sender, ok and "another guild" or "could not read")
        return
    end
    logSync("in", "Bounty", "%s from %s  ·  %d bytes", describe(kind, payload), sender, #message)
    noteVersion(sender, theirs)
    local data = board.Records()
    if kind == "hello" then
        once("revision", announce)
    elseif kind == "revision" and type(payload) == "number" and payload > (data[author] and data[author].rev or 0) then
        once("get:" .. author, function()
            if not data[author] or data[author].rev < payload then send("get", author) end
        end)
    elseif kind == "get" and payload == board.Owner() then
        once("sheet", function()
            local sheet = ownSheet()
            if sheet then board.SendSheet(sheet) end
        end)
    elseif kind == "sheet" then
        if board.Import({authors=data}, author, payload) then
            log("Bounty", "Stored %s's sheet", author)
            board.Update()
        else
            log("Bounty", "Ignored %s's sheet: older than the one held, or invalid", author)
        end
    end
end)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:SetScript("OnEvent", function()
    board.Update()
    board.Request()
end)
C_Timer.NewTicker(60, function() board.Update(); announce() end)
