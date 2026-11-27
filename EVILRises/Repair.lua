local _, addon = ...
----------------------------------------------------------------------
-- EVIL Rises - the shared repair loop
--
-- Every sync area heals the same way: a member's summary says what it holds, a guildmate whose
-- copy differs asks for those entries, and the holder answers. A lost summary, request or
-- answer is not retried on its own; the next summary shows the gap and the loop runs again.
-- These two pieces are the loop's bookkeeping, so every area asks and answers by one rule:
--
--   Repair.Asker(reaskAfter, times, rest)
--       Whether to ask a guildmate for an entry now: once per version of the entry, again when
--       no answer came within `reaskAfter` seconds, and `times` times in a row at most (no limit
--       when nil). Then the entry rests for `rest` seconds (REST by default) before the count
--       starts over: a difference that an answer cannot settle costs a few messages an hour, and
--       one whose answers were all lost is still repaired.
--   Repair.Gather(seconds, flush)
--       Requests gathered for `seconds`, then one answer per group: flush(items, target, group),
--       where target is the one member who asked, or nil when several did and the answer goes
--       to the whole guild.
----------------------------------------------------------------------
local Repair = { REST = 1800 }
addon.Repair = Repair

local function owner(name) return addon.Owner and addon.Owner(name) or name end

local Asker = {}
Asker.__index = Asker

function Repair.Asker(reaskAfter, times, rest)
    return setmetatable({ reaskAfter = reaskAfter, times = times, rest = rest or Repair.REST, entries = {} }, Asker)
end

-- Whether to ask `from` for `entry` at version `stamp` now. Records the ask when it is due.
function Asker:Want(from, entry, stamp)
    local tag = tostring(owner(from)) .. ":" .. tostring(entry)
    local now = GetServerTime()
    local e = self.entries[tag]
    if e and e.stamp ~= stamp then e = nil end
    if e and self.times and e.n >= self.times and now - e.t >= self.rest then e = nil end
    if e and (now - e.t < self.reaskAfter or (self.times and e.n >= self.times)) then return false end
    self.entries[tag] = { stamp = stamp, t = now, n = (e and e.n or 0) + 1 }
    return true
end

-- The version last asked of `from` for `entry`, or nil.
function Asker:Asked(from, entry)
    local e = self.entries[tostring(owner(from)) .. ":" .. tostring(entry)]
    return e and e.stamp
end

function Asker:Reset() self.entries = {} end

local Gather = {}
Gather.__index = Gather

function Repair.Gather(seconds, flush)
    return setmetatable({ seconds = seconds, flush = flush, groups = {} }, Gather)
end

-- `sender` asked for `item` (optional) in `group` (optional, one answer per group).
function Gather:Add(sender, item, group)
    group = group == nil and "" or group
    local g = self.groups[group]
    if not g then
        g = { items = {}, to = {} }
        self.groups[group] = g
        C_Timer.After(self.seconds, function()
            if self.groups[group] ~= g then return end
            self.groups[group] = nil
            local only, n = nil, 0
            for key in pairs(g.to) do only, n = key, n + 1 end
            self.flush(g.items, n == 1 and only or nil, group)
        end)
    end
    if item ~= nil then g.items[item] = true end
    g.to[owner(sender)] = true
end

-- Drops what is waiting, as when the guild changes.
function Gather:Reset() self.groups = {} end
