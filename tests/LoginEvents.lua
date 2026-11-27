-- Run with Lua 5.1 from the repository root.
-- The client rejects events it does not have, as WoW: Forever rejects CLUBS_LOADED: crafting and
-- gear sync still start at login, before the Crafting Orders tab is ever opened.
strmatch = string.match
local function noop() end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local UNKNOWN = { CLUBS_LOADED = true }
local now, pending, frames = 2000000, {}, {}
local function frame()
    local f = { events = {}, scripts = {} }
    function f.RegisterEvent(self, event)
        if UNKNOWN[event] then error('Frame:RegisterEvent(): Attempt to register unknown event "' .. event .. '"') end
        self.events[event] = true
    end
    function f.SetScript(self, name, fn) self.scripts[name] = fn end
    for _, m in ipairs({ "SetSize", "SetPoint", "SetAlpha", "SetUnit", "Hide", "Show" }) do f[m] = noop end
    f.GetDisplayInfo = function() return 0 end
    frames[#frames + 1] = f
    return f
end
local comm = {}
function comm.RegisterComm() end
function comm.SendCommMessage() end
local c = { name = "First Lemon" }
local env = setmetatable({
    LibStub = function(name) if name == "AceComm-3.0" then return comm end return LibStub(name) end,
    CreateFrame = frame,
    GetServerTime = function() return now end, UnitFullName = function() return "First", "Lemon" end,
    IsInGuild = function() return true end, GetGuildInfo = function() return "EVIL" end,
    GetRealmName = function() return "Forever" end, C_Club = { GetGuildClubId = function() return 7 end },
    C_AddOns = { GetAddOnMetadata = function() return "0.9.0" end },
    GetProfessions = function() return 1 end,
    GetProfessionInfo = function() return "Alchemy", nil, 150, 150, nil, nil, 171 end,
    IsPlayerSpell = function(id) return id == 2329 end,
    GetNumGuildMembers = function() return 0 end,
    GetInventoryItemLink = function(_, slot) if slot == 16 then return "|cff00ff00|Hitem:123:0|h[Sword]|h|r" end end,
    GetInventoryItemID = function() return nil end,
    UnitRace = function() return "Human", "Human", 1 end, UnitSex = function() return 2 end,
    GetMoney = function() return 100 end,
    securecallfunction = function(fn, ...) return fn(...) end,
    GetTime = function() return now end, date = os.date, print = noop,
    C_Timer = { NewTicker = noop, After = function(delay, fn) pending[#pending + 1] = { at = now + delay, fn = fn } end },
}, { __index = _G })
-- The files up to gear sync, in TOC order; the message format files when this branch has them.
for _, file in ipairs({ "Debug", "Version", "Comm", "Repair", "Bounty", "Sync", "Crafting/Client",
    "Crafting/ProfCatalogForever", "Crafting/Professions", "Crafting/ProfDirectory", "Crafting/ProfSync",
    "Crafting/CraftOrders", "Crafting/Sync", "Crafting/Page", "MemberGear" }) do
    local path = "EVILRises/" .. file .. ".lua"
    local exists = io.open(path)
    if exists then
        exists:close()
        setfenv(assert(loadfile(path)), env)("EVILRises", c)
    end
end
assert(not c.Crafting.guild, "nothing binds before login")
-- Logging in, then the first minute.
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
    end
end
while #pending > 0 do
    table.sort(pending, function(x, y) return x.at < y.at end)
    if pending[1].at > now + 60 then break end
    local t = table.remove(pending, 1)
    now = math.max(now, t.at)
    t.fn()
end
local function logged(pattern)
    for _, line in ipairs(c.DebugLog.Lines()) do if line:find(pattern) then return true end end
    return false
end
assert(c.Crafting.guild == "7", "crafting sync bound at login")
assert(logged("%[Guild%]  Crafting and gear sync bound to guild 7"))
assert(logged("%[Craft Out%]  Professions sum"), "professions summary sent")
assert(logged("%[Craft Out%]  Orders ask"), "orders asked for")
assert(logged("%[Gear%]  Sharing own snapshot"), "own gear shared")
print("Login events: crafting and gear sync start at login on a client without CLUBS_LOADED.")
