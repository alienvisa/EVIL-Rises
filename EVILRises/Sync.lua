local _, board = ...
local comm = LibStub("AceComm-3.0")
local codec = LibStub("EVRFeatures-LibSerialize")
local wire = LibStub("LibDeflate")
local prefix = "EVRBounty1"
local function send(kind, payload)
    local guild = board.GuildID()
    if not guild then return end
    local encoded = wire:EncodeForWoWAddonChannel(codec:Serialize(guild, kind, payload))
    comm:SendCommMessage(prefix, encoded, "GUILD", nil, "NORMAL")
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
    if channel ~= "GUILD" or #message > 32000 then return end
    local author = board.Owner(sender)
    if not author or author == board.Owner() then return end
    local raw = wire:DecodeForWoWAddonChannel(message)
    if not raw then return end
    local ok, guild, kind, payload = codec:Deserialize(raw)
    if not ok or not guild or guild ~= board.GuildID() then return end
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
    elseif kind == "sheet" and board.Import({authors=data}, author, payload) then
        board.Update()
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

