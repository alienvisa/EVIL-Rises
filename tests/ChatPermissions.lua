-- Run from the repository root with Lua 5.1.
local rank, clubStreams, historyCalls = 4, {}, 0
local permissions = { [3] = true, [4] = false }
EVRFeatures = {
    guildKey = "EVIL", db = {},
    IsOnGuildDB = function() return true end,
    SanitizeUserText = function(_, text) return text end,
}
function GetBuildInfo() return "1.60.1", "0", "", 16001 end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
function GetGuildInfo() return "EVIL", "Raid Lead", rank end
function IsInGuild() return true end
function GetServerTime() return 100 end
C_GuildInfo = { GuildControlGetRankFlags = function(order)
    assert(order == rank + 1)
    return permissions
end }
local sent
function SendChatMessage(_, channel) sent = channel end
dofile("EVILRises/Features/Core/Compat.lua")
dofile("EVILRises/Features/Modules/GuildChat.lua")
local compat, chat = EVRFeatures.Compat, EVRFeatures.GuildChat
compat.GuildChatStreams = function() return clubStreams end
compat.GuildChatHistory = function(_, id)
    historyCalls = historyCalls + 1
    if id == 42 then return { { m = "Server officer history" } } end
end

assert(compat.HasOfficerPermissions(permissions))
assert(compat.HasOfficerPermissions({ [12] = true }))
assert(not compat.HasOfficerPermissions({ [1] = true, [2] = true, [7] = true }))
local officer = assert(chat:Streams()[2])
chat:_OnMessage("Private", "Lead", nil, true)
assert(chat:Entries(officer)[1].m == "Private" and historyCalls == 0)
assert(#chat:Entries(nil) == 0 and #chat:Log() == 0)
assert(not chat:Send("Read only", officer) and not sent)
permissions[4] = true
assert(chat:Send("Reply", officer) and sent == "OFFICER")

clubStreams = { { kind = "other", id = 13 }, { kind = "officer", id = 42 } }
officer = assert(chat:Streams()[2])
assert(#chat:Streams() == 2 and chat:Entries(officer)[1].m == "Server officer history")
permissions[3] = false
assert(#chat:Streams() == 1 and #chat:Entries(officer) == 0)
assert(not chat:Send("Stale draft", officer))
assert(chat:Send("Guild", nil) and sent == "GUILD")
permissions, clubStreams = nil, {}
assert(not chat:OfficerStream())
rank, EVRFeatures.guildKey = 0, "Another Guild"
assert(#chat:Entries(assert(chat:OfficerStream())) == 0)
print("Officer permissions, live and server histories, channel isolation and guild changes passed.")
