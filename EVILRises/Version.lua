local _, addon = ...
----------------------------------------------------------------------
-- EVIL Rises update reminder
--
-- Every sync message carries the sender's addon version. When a guildmate runs a newer
-- version than this copy, the player sees a reminder in their chat frame FIRST_DELAY seconds
-- later, then every REMIND_EVERY seconds while this copy stays out of date. The short wait lets
-- a login hear everyone, so the first reminder names the newest version. Only this player sees
-- it; nothing is sent to anyone.
----------------------------------------------------------------------
local FIRST_DELAY, REMIND_EVERY = 10, 30 * 60
local log = addon.Log or function() end

-- { major, minor, patch } for a version such as "0.8.1", or nil. Each part is at most three
-- digits, so a guildmate cannot claim a version that keeps everyone else out of date for good.
local function parse(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

local function newer(x, y)
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

local own
-- This copy's version from the TOC, or nil when the client does not say.
function addon.Version()
    if own == nil then
        own = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("EVILRises", "Version") or false
    end
    return own or nil
end

local latest, started
local function remind()
    local mine, seen = parse(addon.Version()), parse(latest)
    if not (mine and seen and newer(seen, mine)) then return end
    print(string.format("|cffffd100EVIL Rises:|r version %s is out, and you have %s. Update to get the latest features and fixes.",
        latest, addon.Version()))
    log("Version", "Reminded the player: %s is out, this copy is %s", latest, addon.Version())
end

-- A guildmate's message said which version they run.
function addon.NoteVersion(sender, version)
    local seen, mine = parse(version), parse(addon.Version())
    if not (seen and mine and newer(seen, mine)) then return end
    if latest and not newer(seen, parse(latest)) then return end
    latest = version
    log("Version", "%s runs EVIL Rises %s, newer than this copy (%s)", tostring(sender), version, addon.Version())
    if not started then
        started = true
        C_Timer.After(FIRST_DELAY, function()
            remind()
            C_Timer.NewTicker(REMIND_EVERY, remind)
        end)
    end
end
