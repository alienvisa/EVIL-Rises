local _, addon = ...
local craft = addon.Crafting
----------------------------------------------------------------------
-- EVIL Rises - Profession sync (WoW: Forever, issue #31)
--
-- The "prof" SyncService domain. A member announces a summary: rank, max, specialization
-- and a hash of the recipe list, per profession. A guildmate whose stored hash differs asks
-- for that one list; the crafter answers once, addressed to the one who asked, or to everyone
-- when several asked within a few seconds. Lists travel once per change, never on a timer.
-- The asking and the gathered answers are the shared repair loop (Repair.lua). An addressed
-- message goes by whisper to a member on the current format, or on the guild channel, where
-- everyone else drops it.
--
--   sum   everyone          { p = { [line] = { r, m, s, h, n } } }
--   ask   everyone          {}                        everyone answers with its own sum
--   req   the crafter       { l = { line, ... } }
--   list  one or everyone   { l = line, h = hash, r = { ids }, x = { extra ids } }
----------------------------------------------------------------------

local ProfSync = {}
craft.ProfSync = ProfSync

local Compat = craft.Compat
local DOMAIN = "prof"
local log = addon.Log or function() end
ProfSync.SUMMARY_EVERY = 600   -- heartbeat summary
ProfSync.CHANGE_DELAY = 10     -- one summary for a burst of changes
ProfSync.AGGREGATE = 3         -- requests for a line gathered before answering
ProfSync.REASK_AFTER = 120     -- a list that never came is asked for again

local serializer = LibStub("EVRFeatures-LibSerialize")
local deflate = LibStub("LibDeflate")
local function digest(summary)
    return string.format("%08X", deflate:Adler32(serializer:SerializeEx({stable = true}, summary)))
end

function ProfSync:Initialize()
    self.receivedDigests = {}
    self.asker = addon.Repair.Asker(self.REASK_AFTER)
    self.lists = addon.Repair.Gather(self.AGGREGATE, function(_, target, line) ProfSync:FlushLine(line, target) end)
    craft.SyncService:On(DOMAIN, function(env, sender) ProfSync:OnEnvelope(env, sender) end)
    Compat.After(math.random(5, 15), function()
        ProfSync:PublishSummary()
        craft.SyncService:Publish(DOMAIN, "ask", {})
    end)
    Compat.NewTicker(self.SUMMARY_EVERY, function() ProfSync:PublishSummary() end)
end

function ProfSync:PublishSummary()
    local summary = craft.Professions:OwnSummary()
    self.ownDigest = digest(summary)
    craft.SyncService:Publish(DOMAIN, "sum", { p = summary })
end

-- Publish once things have been quiet for `delay` seconds (CHANGE_DELAY by default): a later
-- call pushes the summary back, so levelling a profession sends one summary, not one per craft.
function ProfSync:ScheduleSummary(delay)
    delay = delay or self.CHANGE_DELAY
    local due = GetServerTime() + delay
    if not self.summaryDue or due > self.summaryDue then self.summaryDue = due end
    if self.summaryPending then return end
    self.summaryPending = true
    local function fire()
        local wait = (self.summaryDue or 0) - GetServerTime()
        if wait > 0 then
            Compat.After(wait, fire)
            return
        end
        self.summaryPending, self.summaryDue = false, nil
        self:PublishSummary()
    end
    Compat.After(delay, fire)
end

-- The member key of a guildmate sender, or nil when the sender is not in the guild roster.
-- The key comes from who sent the message, never from what it says.
function ProfSync:SenderKey(sender)
    if type(sender) ~= "string" then return nil end
    return craft.Professions.KeyFor(sender)
end

function ProfSync:OnEnvelope(env, sender)
    local key = self:SenderKey(sender)
    local data = env and env.data
    if not key or type(data) ~= "table" then return end
    if env.act == "sum" then
        self:OnSummary(key, sender, data.p)
    elseif env.act == "ask" then
        -- On its own short timer: a member busy levelling (the change debounce keeps moving) still
        -- answers a guildmate who just logged in.
        if not self.askPending then
            self.askPending = true
            Compat.After(math.random(1, 8), function()
                self.askPending = false
                self:PublishSummary()
            end)
        end
    elseif env.act == "req" then
        self:OnRequest(sender, data.l)
    elseif env.act == "list" then
        local stored = craft.Professions:ApplyList(key, data.l, data.h, data.r, data.x)
        log("Professions", "%s %s's recipe list for line %s", stored and "Stored" or "Ignored (already held or not matching)",
            key, data.l)
    end
end

function ProfSync:OnSummary(key, sender, p)
    local need = craft.Professions:ApplySummary(key, p)
    if not need then
        log("Professions", "Ignored %s's summary: invalid", key)
        return
    end
    self.receivedDigests[key] = #need == 0 and digest(p) or nil
    if #need == 0 then return end
    local rec = craft.Professions:Get(key)
    local ask = {}
    for _, line in ipairs(need) do
        if self.asker:Want(sender, line, rec.profs[line].h) then ask[#ask + 1] = line end
    end
    if #ask == 0 then return end
    log("Professions", "%s's recipes changed on %d lines: asking for them", key, #ask)
    Compat.After(math.random(2, 6), function()
        -- A guild-wide answer to someone else may have brought the list meanwhile.
        local still, current = {}, craft.Professions:Get(key)
        for _, line in ipairs(ask) do
            local e = current and current.profs[line]
            if e and not e.recipes and e.h == self.asker:Asked(sender, line) then still[#still + 1] = line end
        end
        if #still > 0 then craft.SyncService:Publish(DOMAIN, "req", { l = still }, { target = sender }) end
    end)
end

function ProfSync:OnRequest(sender, lines)
    if type(lines) ~= "table" or #lines > craft.Professions.MAX_LINES then return end
    for _, line in ipairs(lines) do
        if type(line) == "number" and craft.Professions:OwnLine(line) then self.lists:Add(sender, nil, line) end
    end
end

-- Answer everyone who asked for a line: addressed to one, or to the whole guild for several.
function ProfSync:FlushLine(line, target)
    local e = craft.Professions:OwnLine(line)
    if not (e and e.recipes) then return end
    craft.SyncService:Publish(DOMAIN, "list", { l = line, h = e.h, r = e.recipes, x = e.extra or {} },
        { target = target })
end
