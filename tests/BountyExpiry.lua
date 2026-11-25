-- Run from the repository root with Lua 5.1. Advance server time without waiting seven days.
local week = 7 * 86400
local now = 2 * week
local wakeAt, wake, receive, broadcasts = nil, nil, nil, 0
local mine = { rev = now - 1, posts = {} }
local theirs = { rev = now - 2, posts = {} }
local function post(at)
    return { time = at, target = "Enemy", reward = "1g", mode = "kos", faction = "Horde" }
end
for i = 1, 20 do mine.posts[i] = post(now - week - i) end
theirs.posts[1] = post(now - week + 1)
EVRFeatures = {
    db = { bounties = { Me = mine, Other = theirs } },
    IsOnGuildDB = function() return true end,
    KeyOfRosterName = function(_, name) return name end,
    SanitizeUserText = function(_, value) return value end,
    Compat = { PlayerName = function() return "Me" end },
    SyncService = {
        On = function(_, _, fn) receive = fn end,
        Publish = function(_, _, _, sheet)
            assert(sheet == mine)
            broadcasts = broadcasts + 1
        end,
    },
}
GetServerTime = function() return now end
C_Timer = { After = function(delay, fn) wakeAt, wake = now + delay, fn end }
assert(loadfile("EVILRises/Bounty.lua"))("EVILRises", {})
local board = EVRFeatures.Bounty
board:Initialize()
assert(#mine.posts == 0 and mine.rev == now and broadcasts == 1)
assert(#theirs.posts == 1 and wakeAt == now + 1)
assert(not board:Post("New target", 1, "", "kos", "Horde"))
local posted = now
local peerRevision = theirs.rev
now = wakeAt
wake()
assert(#theirs.posts == 0 and theirs.rev == peerRevision and broadcasts == 2)
assert(#mine.posts == 1 and wakeAt == posted + week)
-- A newer sync from an old client still carries the original posting time.
receive({ act = "board", data = { rev = now, posts = { post(now - week) } } }, "Other")
assert(#EVRFeatures.db.bounties.Other.posts == 0 and broadcasts == 2)
now = wakeAt
wake()
assert(#mine.posts == 0 and mine.rev == now and broadcasts == 3)
print("Seven-day boundary, offline poster, expiry on login, post capacity and stale sync passed.")
