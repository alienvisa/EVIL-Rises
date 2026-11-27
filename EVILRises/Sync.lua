local _, board = ...
local noop = function() end
local log, logSync = board.Log or noop, board.LogSync or noop
local AREA = "bounty"
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
    local bytes = board.Comm:Send(AREA, kind, payload)
    if bytes then logSync("out", "Bounty", "%s  ·  %d bytes", describe(kind, payload), bytes) end
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
-- Comm has checked the channel, the guild and the size, and that the sender is a guildmate.
local function receive(kind, payload, sender, info)
    local author = board.Owner(sender)
    logSync("in", "Bounty", "%s from %s  ·  %d bytes", describe(kind, payload), sender, info.bytes)
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
end
board.Comm:Register(AREA, { label = "Bounty", priority = "NORMAL", maxBytes = 32000, legacy = "bounty", handle = receive })
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:SetScript("OnEvent", function()
    board.Update()
    board.Request()
end)
C_Timer.NewTicker(60, function() board.Update(); announce() end)
