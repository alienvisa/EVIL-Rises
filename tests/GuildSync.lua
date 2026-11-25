-- Run from the repository root with Lua 5.1. Each client has its own globals,
-- SavedVariables, libraries, event receiver and clock-driven callbacks.
local now, timers, clients, packets = 100, {}, {}, {}
local function noop() end
local function after(delay, fn)
    timers[#timers + 1] = { at = now + delay, run = fn }
end
local function advance(seconds)
    local stop = now + seconds
    while true do
        local nextIndex
        for i, t in ipairs(timers) do
            if t.at <= stop and (not nextIndex or t.at < timers[nextIndex].at) then nextIndex = i end
        end
        if not nextIndex then break end
        local t = table.remove(timers, nextIndex)
        now = t.at
        t.run()
    end
    now = stop
end
local function deliver(peer, p)
    peer.receiver(nil, "CHAT_MSG_ADDON", p.prefix, p.msg, p.channel, p.sender)
end
local function client(name)
    local c = { online = true, guild = "EVIL", name = name }
    clients[#clients + 1] = c
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.strmatch = string.match
    env.GetTime = function() return now end
    env.time = function() return math.floor(now) end
    env.GetServerTime = env.time
    env.C_Timer = { After = after, NewTicker = function(period, fn)
        assert(period == 60)
        local function tick()
            if c.online then fn() end
            after(period, tick)
        end
        after(period, tick)
    end }
    env.IsInGuild = function() return c.guild ~= nil end
    env.GetNumGuildMembers = function() return 0 end
    env.CreateFrame = function()
        return { SetScript = function(_, _, fn) c.receiver = fn end }
    end
    local e = {
        PREFIX = "EVRF", VERSION = "1.40.0", db = { members = {} }, State = { comm = {} },
        Perf = { Start = noop, Stop = noop, Count = noop }, Print = function(_, message) error(message) end,
        L = setmetatable({}, { __index = function(_, k) return k end }),
        Compat = { After = after, RegisterEvent = noop, PlayerName = function() return name end },
        GetClientRealm = function() return "Forever" end,
        GetPlayerKey = function(_, n) return n .. "-Forever" end,
        KeyOfRosterName = function(_, n) return n:match("^[^-]+") .. "-Forever" end,
        IsOnGuildDB = function() return c.guild == "EVIL" end,
        IsFeatureEnabled = function() return true end, IsOfficer = function() return c.officer == true end,
        IsOfficerByName = function(_, sender)
            for _, peer in ipairs(clients) do
                if peer.guild == c.guild and peer.name == sender then return peer.officer == true end
            end
            return false
        end,
        RefreshRosterUI = noop, SanitizeUserText = function(_, s, max) return s:sub(1, max) end,
        SafeCall = function(_, f, ...) return f(...) end
    }
    e.Compat.OfficerAddonChannel = function() return c.officer and "OFFICER" or nil end
    c.engine, env.EVRFeatures = e, e
    e.Compat.SendAddonMessage = function(prefix, msg, channel, target)
        if not c.online then return end
        assert(#msg <= 255)
        local p = { prefix = prefix, msg = msg, channel = channel, sender = name }
        packets[#packets + 1] = p
        for _, peer in ipairs(clients) do
            if peer.online and peer.guild == c.guild and (channel ~= "OFFICER" or peer.officer) and (not target or target == peer.name) then deliver(peer, p) end
        end
    end
    for _, path in ipairs({ "Features/Libs/LibStub", "Features/Libs/LibSerialize",
        "Features/Libs/LibDeflate", "Features/Modules/SyncService", "Features/Modules/CommSystem",
        "Features/Modules/DataCollector", "Bounty" }) do
        setfenv(assert(loadfile("EVILRises/" .. path .. ".lua")), env)("EVILRises", {})
    end
    e.DataCollector.CollectMyData = noop
    e.DataCollector.GetBroadcastData = function()
        return { name = name, class = "Mage", lastUpdate = env.time(),
            professions = { { name = "Tailoring", rank = 225, isPrimary = true } } }
    end
    e.SyncService:Initialize()
    e.Bounty:Initialize()
    e.CommSystem:Initialize()
    return c
end

local alice, bob = client("Alice"), client("Bob")
local a, b = alice.engine, bob.engine
advance(12)
assert(b.db.members["Alice-Forever"].professions[1].rank == 225)
assert(a.db.members["Bob-Forever"].class == "Mage")
local function post(i)
    local reason = {}
    for j = 1, 175 do reason[j] = string.char(math.random(65, 122)) end
    assert(not a.Bounty:Post("Enemy" .. i, i, table.concat(reason), "kos", "Horde", "Warrior"))
end
for i = 1, 5 do post(i) end
advance(2)
local function sheet(e) return e.db.bounties["Alice-Forever"] end
assert(#sheet(b).posts == 5 and sheet(b).rev == sheet(a).rev)

bob.online = false
while #sheet(a).posts > 0 do a.Bounty:Withdraw(sheet(a).posts[1]) end
advance(2)
assert(#sheet(b).posts == 5)
bob.online = true
b.CommSystem:QueueSync(true)
advance(2)
assert(#sheet(b).posts == 0 and sheet(b).rev == sheet(a).rev)

-- Receive a large board out of order with duplicate fragments and then
-- replay an older board. The newer withdrawal and each author's ownership hold.
local stale, fragment = {}, false
for _, p in ipairs(packets) do
    if p.sender == "Alice" and p.msg:sub(1, 2) == "M:" then
        stale[#stale + 1] = p
        fragment = true
    end
end
assert(fragment)
for i = #stale, 1, -1 do deliver(bob, stale[i]); deliver(bob, stale[i]) end
assert(#sheet(b).posts == 0)

bob.online = false
local first = #packets + 1
for i = 1, 4 do post(i) end
advance(2)
local last = #packets
bob.online = true
for i = last, first, -1 do deliver(bob, packets[i]); deliver(bob, packets[i]) end
assert(#sheet(b).posts == 4 and sheet(b).rev == sheet(a).rev)

-- A fresh peer receives both member data and the author's sheet even if the
-- owner broadcast its roster immediately before answering a request.
local chris = client("Chris")
a.CommSystem:BroadcastMyData(true)
chris.engine.CommSystem:QueueSync(true)
advance(22)
assert(chris.engine.db.members["Alice-Forever"])
assert(sheet(chris.engine).rev == sheet(a).rev)
bob.guild = "Different guild"
local revision = sheet(b).rev
post(5)
advance(2)
for i = last + 1, #packets do deliver(bob, packets[i]) end
assert(sheet(b).rev == revision)
-- Stay offline for a withdrawal, then let the real 60-second ticker heal it
-- with every window closed. Subsequent idle minutes only announce digests.
bob.guild = "EVIL"
bob.online = false
a.Bounty:Withdraw(sheet(a).posts[1])
advance(2)
bob.online = true
advance(64)
assert(sheet(b).rev == sheet(a).rev)
local rounds = {}
for _, peer in ipairs(clients) do
    local comm = peer.engine.CommSystem
    local send = comm.SendMessage
    function comm:SendMessage(kind, ...)
        rounds[kind] = (rounds[kind] or 0) + 1
        return send(self, kind, ...)
    end
end
advance(60)
assert(rounds.HD == 3 and not rounds.BC and not rounds.SV and not rounds.RQ and not rounds.HN)
rounds = {}
for i = 1, 10 do b.CommSystem:QueueSync(true) end
advance(2)
assert(rounds.HD <= 3 and not rounds.BC and not rounds.SV and not rounds.RQ)
local dc = a.DataCollector
local envTime = math.floor(now)
local function store(sequence, level)
    return dc:StoreReceivedData("Bob-Forever", { name = "Bob", class = "Mage", level = level,
        lastUpdate = envTime, updateSequence = sequence })
end
assert(store(2, 60))
assert(not store(1, 59))
assert(a.db.members["Bob-Forever"].level == 60)
-- Older installs still broadcast a timestamp without a sequence.
envTime = envTime + 1
assert(store(nil, 61))
local sync = a.SyncService
for i = 1, 501 do assert(not sync:IsDuplicate("Bob:" .. i)) end
assert(sync:IsDuplicate("Bob:500") and not sync:IsDuplicate("Alice:500"))
local rules
chris.engine.SyncService:On("guildcfg", function(env) rules = env.data end)
a.SyncService:Publish("guildcfg", "rules", "First charter")
assert(rules == nil)
alice.officer = true
a.SyncService:Publish("guildcfg", "rules", "Updated charter", { rev = 1 })
assert(rules == "Updated charter")
chris.online = false
a.SyncService:Publish("guildcfg", "rules", "Missed charter", { rev = 2 })
assert(rules == "Updated charter")
chris.online = true
advance(61)
assert(rules == "Missed charter")
-- A missed officer sheet is requested and replayed only over OFFICER.
chris.officer = true
local officerSheet
chris.engine.SyncService:On("osheet", function(env) officerSheet = env.data end)
b.SyncService:On("osheet", function() error("officer sheet reached a member") end)
chris.online = false
a.SyncService:Publish("osheet", "sheet", "Private sheet", { rev = 1 })
chris.online = true
advance(62)
assert(officerSheet == "Private sheet")
-- The archive of completed raids stays local until another officer needs it.
local raid, sentRaids = nil, 0
a.RaidTracker = { BroadcastRaidData = function()
    sentRaids = sentRaids + 1
    a.CommSystem:SendMessage("RD", "Completed raid")
end }
chris.engine.RaidTracker = { HandleIncoming = function(_, data) raid = data end }
chris.online = false
a.RaidTracker:BroadcastRaidData()
chris.online = true
advance(61)
assert(raid == "Completed raid" and sentRaids == 2)
advance(60)
assert(sentRaids == 2)
print("Silent window and minute checks, idle traffic, revisioned guild data and guild sync passed: startup, postings, missed withdrawal, catch-up, reordered and duplicate chunks, guild switch.")
