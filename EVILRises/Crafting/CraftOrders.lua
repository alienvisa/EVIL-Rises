local _, addon = ...
local craft = addon.Crafting
----------------------------------------------------------------------
-- EVIL Rises - Craft orders (issue #389)
--
-- A member asks the guild's crafters to make an item. The order is open to everyone who knows the
-- recipe until one accepts, or sent to one crafter (who may decline it back to everyone). The author
-- brings the materials or the crafter uses their own, with an optional tip on trust. Delivery is by
-- trade or by mail; a finished trade or a sent mail moves the order on by itself.
--
-- Every change goes through one rule (apply), the same for my own clicks and for what guildmates
-- send: the author is always the sender, never what a message says.
--
--   domain "craftorder" (GUILD only)
--   new  { order }        acc { id, at, rg }   dec { id }   rel { id }
--   mats { id }           done { id }          can { id }
--   ask  {}               have { l = { orders } }
--
-- Repair (new clients only): every SUMMARY_EVERY seconds a member lists the orders it speaks for
-- (placed, taken, released or declined), and a guildmate whose copy differs asks for those orders
-- and replays what changed through the same rule.
--   sum  { l = { { id, at, st, cr, to } } }     get { l = { id } }     fix { l = { orders } }
----------------------------------------------------------------------
local CraftOrders = {}
craft.CraftOrders = CraftOrders

local L = craft.L
local Compat = craft.Compat
local DOMAIN = "craftorder"
local log = addon.Log or function() end

CraftOrders.OPEN_PER  = 5                  -- open orders one member may have
CraftOrders.MAX_N     = 20                 -- items in one order
CraftOrders.NOTE_MAX  = 80                 -- bytes of a note
CraftOrders.TIP_MAX   = 100000 * 10000     -- copper: 100,000 gold
CraftOrders.OPEN_DAYS = 7                  -- an open order nobody took expires
CraftOrders.KEEP_DAYS = 14                 -- a closed order is kept this long
CraftOrders.MAX       = 200                -- orders kept at most
CraftOrders.HAVE_MAX  = 60                 -- orders in one answer to a login
CraftOrders.MAX_RG    = 8                  -- reagents of one recipe
CraftOrders.FUTURE    = 300                -- seconds a peer's clock may run ahead
CraftOrders.ANSWER_EVERY = 120             -- at most one answer to logins every two minutes
CraftOrders.TAKEOVER  = 60                 -- seconds two acceptances count as "at once"
CraftOrders.SUMMARY_EVERY = 180            -- seconds between summaries of the orders I speak for
CraftOrders.SUM_MAX   = 100                -- orders in one summary or request
CraftOrders.RECENT    = 86400              -- a closed order stays in summaries this long
CraftOrders.GATHER    = 3                  -- requests gathered before one repair answer
CraftOrders.REASK_AFTER = 120              -- an answer that never came is asked for again
CraftOrders.ASK_TIMES = 3                  -- times one difference is asked about at most
-- The shared repair bookkeeping (Repair.lua): which differences were asked about, and the
-- requests waiting for one answer.
CraftOrders.asker = addon.Repair.Asker(CraftOrders.REASK_AFTER, CraftOrders.ASK_TIMES)
CraftOrders.fixes = addon.Repair.Gather(CraftOrders.GATHER, function(ids, target)
    CraftOrders:FlushFix(ids, target)
end)
local MAX_ITEM_ID = 10000000

local STATES = { open = true, accepted = true, mats = true, done = true, cancelled = true }
local ACTIVE = { open = true, accepted = true, mats = true }
CraftOrders.ACTIVE = ACTIVE

local function now() return (GetServerTime and GetServerTime()) or time() end

local function store()
    local db = craft.db
    db.craftOrders = db.craftOrders or {}
    return db.craftOrders
end

-- A member key from a name as a message or the roster says it ("Bob", "Bob-Realm").
function CraftOrders.KeyOf(name)
    if type(name) ~= "string" or name == "" then return nil end
    return addon.Owner(name)
end
local keyOf = CraftOrders.KeyOf

function CraftOrders:MyKey()
    return addon.Owner()
end

-- The name to whisper, mail or trade: the realm only when it is not mine.
function CraftOrders.NameOf(key)
    if type(key) ~= "string" then return "?" end
    local name, realm = key:match("^([^-]+)-(.+)$")
    if not name then return key end
    local mine = craft:RealmName()
    if mine and (realm == mine or realm == mine:gsub("[%s%-]", "")) then return name end
    return key
end

local function cleanText(v, max)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[%c|]", "")
    v = v:match("^%s*(.-)%s*$")
    v = v:sub(1, max)
    if v == "" then return nil end
    return v
end

local function int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v % 1 ~= 0 or v < lo or v > hi then return nil end
    return v
end

-- A reagent list: { itemID, count, itemID, count, … }, or nil.
local function cleanRg(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for i = 1, math.min(#t, CraftOrders.MAX_RG * 2) - 1, 2 do
        local id, n = int(t[i], 1, MAX_ITEM_ID - 1), int(t[i + 1], 1, 1000)
        if not (id and n) then return nil end
        out[#out + 1] = id
        out[#out + 1] = n
    end
    return #out > 0 and out or nil
end

-- An order as it may be kept, or nil. `who`, when given, is its author (the sender), whatever the
-- message says.
local function clean(v, who)
    if type(v) ~= "table" then return nil end
    local id = cleanText(v.id, 20)
    local item = int(v.item, 1, MAX_ITEM_ID - 1)
    local n = int(v.n, 1, CraftOrders.MAX_N)
    who = who or keyOf(cleanText(v.who, 60))
    if not (id and item and n and who) then return nil end
    local tip = int(v.tip or 0, 0, CraftOrders.TIP_MAX)
    if not tip then return nil end   -- a negative or impossible tip: the order is malformed
    local t = now()
    local o = {
        id = id, who = who, item = item, n = n,
        mode = (v.mode == "own") and "own" or "mats",
        tip = tip,
        note = cleanText(v.note, CraftOrders.NOTE_MAX),
        to = keyOf(cleanText(v.to, 60)),
        rg = cleanRg(v.rg),
        y = int(v.y, 1, 1000),
        st = STATES[v.st] and v.st or "open",
        cr = keyOf(cleanText(v.cr, 60)),
        ts = math.min(craft.Finite(v.ts) or t, t + CraftOrders.FUTURE),
        at = math.min(craft.Finite(v.at) or t, t + CraftOrders.FUTURE),
        acc = craft.Finite(v.acc),
    }
    if o.to == who then o.to = nil end
    if o.st == "open" then o.cr, o.acc = nil, nil end
    if (o.st == "accepted" or o.st == "mats") and not o.cr then o.st = "open" end
    if o.st == "mats" and o.mode ~= "mats" then o.st = "accepted" end
    return o
end

-- An order's state as it reads: an open order nobody took in OPEN_DAYS has expired.
function CraftOrders.StateOf(o, t)
    if o.st == "open" and (t or now()) - (o.ts or 0) > CraftOrders.OPEN_DAYS * 86400 then return "expired" end
    return o.st
end

function CraftOrders.IsActive(o, t)
    return ACTIVE[CraftOrders.StateOf(o, t)] == true
end

local function openCount(who)
    local n, t = 0, now()
    for _, o in pairs(store()) do
        if o.who == who and CraftOrders.IsActive(o, t) then n = n + 1 end
    end
    return n
end

-- The acceptance that holds when two crafters accept at once: the earlier, then the lower name.
-- Every client applies the same rule, so they all agree on one crafter.
function CraftOrders.Wins(at1, cr1, at2, cr2)
    at1, at2 = at1 or math.huge, at2 or math.huge
    if at1 ~= at2 then return at1 < at2 end
    return (cr1 or "") < (cr2 or "")
end

----------------------------------------------------------------------
-- The rule: one change, by `by` (a member key). Returns the order changed, or nil when `by` may
-- not make it. Used for my own clicks and for every message alike.
----------------------------------------------------------------------
function CraftOrders:Apply(act, data, by)
    if type(data) ~= "table" or not by then return nil end
    local orders = store()
    local t = now()
    local at = math.min(craft.Finite(data.at) or t, t + self.FUTURE)

    if act == "new" then
        local o = clean(data, by)
        if not o or orders[o.id] or openCount(by) >= self.OPEN_PER then return nil end
        o.st, o.cr, o.acc, o.ts, o.at = "open", nil, nil, math.min(o.ts, t + self.FUTURE), o.ts
        orders[o.id] = o
        self:Prune()
        return o
    end

    local o = orders[cleanText(data.id, 20) or ""]
    if not o then return nil end
    local st = CraftOrders.StateOf(o, t)

    if act == "acc" then
        if by == o.who or (o.to and o.to ~= by) then return nil end
        if at < (o.ts or 0) then return nil end
        -- "At once" means within TAKEOVER of each other AND heard within TAKEOVER of being sent: a
        -- message dated a second before an acceptance but arriving hours later is a takeover.
        local atOnce = function(other) return other and math.abs(at - other) <= self.TAKEOVER and t - at <= self.TAKEOVER end
        if at < (o.rel or 0) then
            -- From before the last release. It counts only when it beat the acceptance that was
            -- released (a crafter who took the order and gave it back before hearing an earlier
            -- one): then every client ends with the earlier crafter, whatever order they heard in.
            if not (st == "open" and o.relBy and by ~= o.relBy and atOnce(o.relAcc)
                    and CraftOrders.Wins(at, by, o.relAcc, o.relBy)) then
                return nil
            end
            o.st, o.cr, o.acc = "accepted", by, at
        elseif st == "open" then
            o.st, o.cr, o.acc = "accepted", by, at
        elseif st == "accepted" and o.cr ~= by and atOnce(o.acc) and CraftOrders.Wins(at, by, o.acc, o.cr) then
            -- Two crafters took it at once: every client keeps the earlier. Never once the materials
            -- went to one of them, and never later: that is not "at once" but a takeover.
            o.cr, o.acc = by, at
        else
            return nil
        end
        o.rg = cleanRg(data.rg) or o.rg
        o.y = int(data.y, 1, 1000) or o.y   -- the crafter knows how many one craft makes
    elseif act == "dec" then
        if st ~= "open" or o.to ~= by then return nil end
        o.to, o.decBy = nil, by
    elseif act == "rel" then
        if o.cr ~= by or not (st == "accepted" or st == "mats") then return nil end
        o.st, o.rel, o.relBy, o.relAcc = "open", math.max(at, o.acc or 0), o.cr, o.acc
        o.cr, o.acc = nil, nil
        if o.to == by then o.to = nil end
    elseif act == "mats" then
        if st ~= "accepted" or o.mode ~= "mats" or not (by == o.who or by == o.cr) then return nil end
        o.st = "mats"
    elseif act == "done" then
        if not (st == "accepted" or st == "mats") or not (by == o.cr or by == o.who) then return nil end
        o.st = "done"
    elseif act == "can" then
        if by ~= o.who or not ACTIVE[st] then return nil end
        o.st = "cancelled"
    else
        return nil
    end
    o.at = math.max(o.at or 0, at)
    return o
end

-- Closed and expired orders go after KEEP_DAYS; past MAX the closed ones go first, then the oldest.
function CraftOrders:Prune()
    local orders = store()
    local t = now()
    local cutoff = t - self.KEEP_DAYS * 86400
    local list = {}
    for id, o in pairs(orders) do
        if not CraftOrders.IsActive(o, t) and (o.at or 0) < cutoff then
            orders[id] = nil
        else
            list[#list + 1] = o
        end
    end
    if #list > self.MAX then
        table.sort(list, function(a, b)
            local aa, ba = CraftOrders.IsActive(a, t), CraftOrders.IsActive(b, t)
            if aa ~= ba then return not aa end
            return (a.at or 0) < (b.at or 0)
        end)
        for i = 1, #list - self.MAX do orders[list[i].id] = nil end
    end
end

----------------------------------------------------------------------
-- Who can craft what, and what it takes
----------------------------------------------------------------------
local canCache, canCacheAt = {}, 0
local CAN_TTL = 60

-- The guild's crafters of an item: { { playerKey, playerName, class, profName } }, or an empty list.
function CraftOrders:CraftersOf(item)
    return craft.ProfDirectory.CraftersForItem(item) or {}
end

-- Whether `key` (me by default) knows a recipe that makes `item`. Cached for a minute: the Orders
-- tab asks for every open order on every draw.
function CraftOrders:CanCraft(item, key)
    local me = self:MyKey()
    key = key or me
    local t = GetTime and GetTime() or 0
    if t - canCacheAt > CAN_TTL then canCache, canCacheAt = {}, t end
    local tag = tostring(item) .. "|" .. tostring(key)
    if canCache[tag] ~= nil then return canCache[tag] end
    local yes = false
    for _, c in ipairs(self:CraftersOf(item)) do
        if c.playerKey == key then yes = true break end
    end
    canCache[tag] = yes
    return yes
end

function CraftOrders:ForgetCrafters() canCache, canCacheAt = {}, 0 end

-- The catalog recipe that makes `item` for `key` (a member key): the one they know, else the one
-- most of the guild knows, else the lowest id. Seven Forever items have two recipes (a bar smelted
-- or transmuted, Tailoring's or Leatherworking's), each with its own reagents (issue #396): taking
-- the first gave Gold Ore for a transmute. Nil when no catalog recipe makes the item.
function CraftOrders:RecipeFor(item, key)
    local D, P = craft.ProfDirectory, craft.Professions
    local ids = D and D.ItemRecipes and D.ItemRecipes(item) or {}
    if #ids <= 1 then return ids[1] end
    local best, bestN
    for _, id in ipairs(ids) do
        local who = (P and P.CraftersOf and P:CraftersOf(id)) or {}
        if key then
            for _, k in ipairs(who) do if k == key then return id end end
        end
        if not bestN or #who > bestN then best, bestN = id, #who end
    end
    return best
end

-- The catalog row of a recipe, or nil.
local function catalogRecipe(id)
    local cat = craft.ProfCatalog
    return id and cat and cat.recipes and cat.recipes[id], cat
end

-- What one craft of `item` needs: { { itemID, count } }. The order's own list (the crafter's, sent
-- with the acceptance) first, then the catalog's for `recipeId` (the row clicked) or for the recipe
-- the order's crafter, else `key`, would use.
function CraftOrders:Reagents(item, o, recipeId, key)
    local flat = o and o.rg
    if not flat then
        local id = recipeId or self:RecipeFor(item, (o and (o.cr or o.to)) or key)
        return id and craft.ProfDirectory.Reagents(id) or {}
    end
    local out = {}
    for i = 1, #flat - 1, 2 do out[#out + 1] = { itemID = flat[i], count = flat[i + 1] } end
    return out
end

-- How many items one craft makes, from the catalog's recipe; nil when it does not say.
function CraftOrders:KnownYield(item, recipeId, key)
    local r, cat = catalogRecipe(recipeId or self:RecipeFor(item, key))
    local n = r and tonumber(r[cat.F.outCount])
    if n and n >= 1 then return math.floor(n) end
end

-- How many items one craft makes: the order's own (the crafter's), else what this client knows for
-- that recipe; 1 when nobody knows.
function CraftOrders:Yield(item, o, recipeId, key)
    if o and o.y then return o.y end
    return self:KnownYield(item, recipeId, (o and (o.cr or o.to)) or key) or 1
end

-- How many crafts make the order's items.
function CraftOrders:Crafts(o)
    return math.ceil(o.n / self:Yield(o.item, o))
end

-- The same as a flat list, to send. `key`: whose recipe (an acceptance sends the crafter's own).
function CraftOrders:ReagentsFlat(item, key, recipeId)
    local flat = {}
    for _, r in ipairs(self:Reagents(item, nil, recipeId, key)) do
        flat[#flat + 1] = r.itemID
        flat[#flat + 1] = r.count
    end
    return #flat > 0 and flat or nil
end

-- What an order needs in all, with how many I carry: { { itemID, need, have } }.
function CraftOrders:Needs(o)
    local out = {}
    local crafts = self:Crafts(o)
    for _, r in ipairs(self:Reagents(o.item, o)) do
        local need = r.count * crafts
        out[#out + 1] = { itemID = r.itemID, need = need, have = Compat.GetItemCount(r.itemID) or 0 }
    end
    return out
end

----------------------------------------------------------------------
-- Lists
----------------------------------------------------------------------
local function sortRows(rows, t)
    table.sort(rows, function(a, b)
        local aa, ba = CraftOrders.IsActive(a, t), CraftOrders.IsActive(b, t)
        if aa ~= ba then return aa end
        return (a.ts or 0) > (b.ts or 0)
    end)
    return rows
end

-- view: "mine" (orders I placed), "forme" (sent to me, or accepted by me), "open" (open to everyone,
-- for a recipe I know, not mine).
function CraftOrders:Rows(view)
    local me, t, rows = self:MyKey(), now(), {}
    for _, o in pairs(store()) do
        local st = CraftOrders.StateOf(o, t)
        local take
        if view == "mine" then
            take = o.who == me
        elseif view == "forme" then
            take = o.cr == me or (o.to == me and st == "open")
        elseif view == "open" then
            take = st == "open" and not o.to and o.who ~= me and self:CanCraft(o.item)
        end
        if take then rows[#rows + 1] = o end
    end
    return sortRows(rows, t)
end

function CraftOrders:Get(id) return store()[id] end

----------------------------------------------------------------------
-- My own actions
----------------------------------------------------------------------
local counter = 0
local function newId()
    counter = counter + 1
    return string.format("%X%03X%02X", now(), math.random(0, 0xFFF), counter % 256)
end

local function itemText(item)
    local _, link = Compat.GetItemInfo(item)
    return link or ("item:" .. tostring(item))
end

-- Redraw the open page once on the next frame. A sync burst (a login's answers, a roster read)
-- changes many records in a row, and each redraw rebuilds the recipe list.
local refreshQueued
function CraftOrders:Refresh()
    if not self.uiRefresh or refreshQueued then return end
    refreshQueued = true
    Compat.After(0, function()
        refreshQueued = false
        if self.uiRefresh then craft:SafeCall(self.uiRefresh) end
    end)
end

local function publish(act, data, options)
    if craft.SyncService then craft.SyncService:Publish(DOMAIN, act, data, options) end
end

-- Place an order. opts = { n, mode ("mats"/"own"), tip (copper), note, to (a member key), recipe (the
-- catalog recipe opened, whose reagents and yield the order carries until a crafter answers) }.
-- Returns the order, or nil and why.
function CraftOrders:Place(item, opts)
    opts = opts or {}
    item = int(item, 1, MAX_ITEM_ID - 1)
    if not item then return nil, L["That names no item."] end
    local me = self:MyKey()
    if openCount(me) >= self.OPEN_PER then
        return nil, string.format(L["You already have %d open craft orders."], openCount(me))
    end
    local t = now()
    local data = {
        id = newId(), item = item,
        n = math.max(1, math.min(self.MAX_N, math.floor(tonumber(opts.n) or 1))),
        mode = opts.mode == "own" and "own" or "mats",
        tip = math.max(0, math.min(self.TIP_MAX, math.floor(tonumber(opts.tip) or 0))),
        note = cleanText(opts.note, self.NOTE_MAX),
        to = opts.to ~= me and opts.to or nil,
        rg = self:ReagentsFlat(item, opts.to, opts.recipe), y = self:KnownYield(item, opts.recipe, opts.to), ts = t, at = t,
    }
    local o = self:Apply("new", data, me)
    if not o then
        log("Orders", "Could not place an order for item %d", item)
        return nil, L["The order could not be placed."]
    end
    log("Orders", "Placed order %s: %d x item %d", o.id, o.n, item)
    publish("new", data)
    self:Refresh()
    return o
end

-- accept · decline · release · mats · done · cancel, on order `id`, by me.
local ACTS = { accept = "acc", decline = "dec", release = "rel", mats = "mats", done = "done", cancel = "can" }
local ACT_LOG = { accept = "Accepted", decline = "Declined", release = "Released", mats = "Marked materials sent for",
    done = "Completed", cancel = "Cancelled" }
function CraftOrders:Act(id, what)
    local act = ACTS[what] or what
    local data = { id = id, at = now() }
    local o = self:Get(id)
    -- The crafter tells the order what their own recipe takes and makes (issue #396).
    if act == "acc" and o then
        local me = self:MyKey()
        data.rg, data.y = self:ReagentsFlat(o.item, me), self:KnownYield(o.item, nil, me)
    end
    if not self:Apply(act, data, self:MyKey()) then
        log("Orders", "Could not %s order %s", what, tostring(id))
        return false
    end
    log("Orders", "%s order %s", ACT_LOG[what] or tostring(what), tostring(id))
    publish(act, data)
    self:Refresh()
    return true
end

----------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------
local function sound()
    if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
end

-- What a change from a guildmate means to me, said once in the chat.
function CraftOrders:Notify(act, o, by)
    local me = self:MyKey()
    if by == me then return end
    local who, what = CraftOrders.NameOf(by), itemText(o.item) .. (o.n > 1 and (" x" .. o.n) or "")
    local msg
    if act == "new" then
        if o.to == me then
            msg = string.format(L["%s asks you to craft %s. See the Orders tab."], who, what)
        elseif not o.to and self:CanCraft(o.item) then
            msg = string.format(L["%s asks the guild's crafters for %s. See the Orders tab."], who, what)
        end
    elseif o.who == me then
        if act == "acc" and o.cr == by then msg = string.format(L["%s accepted your order for %s."], who, what)
        elseif act == "dec" then msg = string.format(L["%s declined your order for %s: it is open to every crafter now."], who, what)
        elseif act == "rel" then msg = string.format(L["%s gave your order for %s back: it is open again."], who, what)
        elseif act == "done" then msg = string.format(L["%s finished your order for %s."], who, what)
        elseif act == "mats" then msg = string.format(L["%s got your materials for %s."], who, what) end
    elseif o.cr == me then
        if act == "mats" then msg = string.format(L["%s's materials for %s arrived."], who, what)
        elseif act == "can" then msg = string.format(L["%s cancelled the order for %s."], who, what)
        elseif act == "done" then msg = string.format(L["%s got the %s you crafted."], who, what) end
    end
    if msg then
        craft:Print(msg)
        if act == "new" then sound() end
    end
end

function CraftOrders:OnEnvelope(env, sender)
    local by = keyOf(sender)
    local data = env and env.data
    if not by or by == self:MyKey() or type(data) ~= "table" then return end
    if env.act == "ask" then
        self:OnAsk()
    elseif env.act == "have" then
        self:Merge(data.l, by)
    elseif env.act == "sum" then
        self:OnSummary(data.l, by, sender)
    elseif env.act == "get" then
        self:OnGet(data.l, sender)
    elseif env.act == "fix" then
        self:Repair(data.l, by)
    else
        local known = self:Get(type(data.id) == "string" and data.id or "")
        local before = known and known.cr
        local o = self:Apply(env.act, data, by)
        log("Orders", "%s %s from %s on order %s", o and "Applied" or "Ignored", tostring(env.act), by, tostring(data.id))
        if o then
            if env.act == "acc" and before == self:MyKey() and o.cr ~= before then
                craft:Print(string.format(L["%s accepted the order for %s at the same moment, and keeps it."],
                    CraftOrders.NameOf(by), itemText(o.item)))
            end
            self:Notify(env.act, o, by)
            self:Refresh()
        end
    end
end

-- My orders still running, newest first, for an answer: the ones I placed or took, which only I
-- speak for.
function CraftOrders:ActiveList()
    local t, me, list = now(), self:MyKey(), {}
    for _, o in pairs(store()) do
        if CraftOrders.IsActive(o, t) and (o.who == me or o.cr == me) then list[#list + 1] = o end
    end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    for i = #list, self.HAVE_MAX + 1, -1 do list[i] = nil end
    return list
end

-- Orders from an answer by `by` (a member key). Each counts only where `by` speaks for it: its
-- author, or the crafter this client already knows took it. A forged answer can then say nothing
-- about anyone else's order.
--   * unknown: only from its author, kept while running, within the author's cap, never naming me;
--   * known: the newer state, forward only (open, accepted, materials, done) with the same author
--     and target; the author may also have cancelled it; a crafter speaks only as the crafter.
-- Orders I placed or took are never touched: they come to me live. Returns whether it changed.
local RANK = { open = 1, accepted = 2, mats = 3, done = 4 }
function CraftOrders:Merge(list, by)
    if type(list) ~= "table" or not by then return false end
    local orders, t, changed, me = store(), now(), false, self:MyKey()
    for i = 1, math.min(#list, self.HAVE_MAX) do
        local o = clean(list[i])
        if o then
            local mine = orders[o.id]
            if not mine then
                -- Only its author brings an order I never heard of.
                if by == o.who and CraftOrders.IsActive(o, t) and o.who ~= me and o.cr ~= me
                    and openCount(o.who) < self.OPEN_PER then
                    orders[o.id] = o
                    changed = true
                end
            elseif mine.who == o.who and mine.who ~= me and mine.cr ~= me and o.to == mine.to
                and (o.at or 0) > (mine.at or 0) then
                -- The author speaks for their order; a crafter only for an acceptance this client
                -- already holds (never by naming themselves in the answer).
                local speaks = by == mine.who or (mine.cr ~= nil and by == mine.cr and o.cr == mine.cr)
                local forward = speaks and RANK[o.st] and RANK[mine.st] and RANK[o.st] > RANK[mine.st]
                    and o.cr ~= nil and (mine.cr == nil or mine.cr == o.cr)
                local cancel = o.st == "cancelled" and by == mine.who and ACTIVE[mine.st]
                if forward or cancel then
                    mine.st, mine.at = o.st, o.at
                    if forward then mine.cr, mine.acc = o.cr, mine.acc or o.acc end
                    mine.rg, mine.y = mine.rg or o.rg, mine.y or o.y
                    changed = true
                end
            end
        end
    end
    log("Orders", "%s's running orders: %s", by, changed and "updated this client" or "nothing new")
    if changed then
        self:Prune()
        self:Refresh()
    end
    return changed
end

-- A guildmate logged in and asked: I answer for my own orders (placed or taken), after a random
-- wait, at most once every ANSWER_EVERY.
function CraftOrders:OnAsk()
    if self.answerPending then return end
    if now() - (self.answeredAt or 0) < self.ANSWER_EVERY then return end
    if #self:ActiveList() == 0 then return end
    self.answerPending = true
    Compat.After(math.random(2, 10), function()
        self.answerPending = false
        local list = self:ActiveList()
        if #list == 0 then return end
        self.answeredAt = now()
        publish("have", { l = list })
    end)
end

----------------------------------------------------------------------
-- Repair: summaries of the orders each member speaks for, and the orders that differ
----------------------------------------------------------------------
-- Whether `key` speaks for `o`: it placed it, took it, or gave it back or declined it last.
function CraftOrders.SpeaksFor(o, key)
    return key ~= nil and (o.who == key or o.cr == key or o.relBy == key or o.decBy == key)
end

-- { { id, at, st, cr, to } } for the orders I speak for that are running or closed within RECENT,
-- newest first.
function CraftOrders:SummaryList()
    local t, me, list = now(), self:MyKey(), {}
    for _, o in pairs(store()) do
        if CraftOrders.SpeaksFor(o, me) and (CraftOrders.IsActive(o, t) or t - (o.at or 0) <= self.RECENT) then
            list[#list + 1] = o
        end
    end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    local out = {}
    for i = 1, math.min(#list, self.SUM_MAX) do
        local o = list[i]
        out[i] = { o.id, o.at or 0, o.st, o.cr or false, o.to or false }
    end
    return out
end

function CraftOrders:PublishSummary()
    local list = self:SummaryList()
    if #list > 0 then publish("sum", { l = list }, { newOnly = true }) end
end

-- A guildmate's summary: ask it for each order my copy lacks or holds in another state. A
-- difference that replaying cannot settle is asked about ASK_TIMES times at most.
function CraftOrders:OnSummary(list, by, sender)
    if type(list) ~= "table" then return end
    local orders, need = store(), {}
    for i = 1, math.min(#list, self.SUM_MAX) do
        local e = list[i]
        if type(e) == "table" then
            local id, at, st, cr, to = cleanText(e[1], 20), craft.Finite(e[2]), e[3], keyOf(e[4]), keyOf(e[5])
            if id and at and STATES[st] then
                local mine = orders[id]
                local differs
                if mine then
                    -- As new or newer and different, or both accepted by different crafters: the loser of
                    -- two acceptances at once holds the newer copy, and must still ask.
                    differs = (at >= (mine.at or 0) and (mine.st ~= st or mine.cr ~= cr or mine.to ~= to))
                        or (st == "accepted" and mine.st == "accepted" and cr ~= nil and mine.cr ~= cr)
                else
                    differs = ACTIVE[st] == true
                end
                if differs and self.asker:Want(by, id, at) then need[#need + 1] = id end
            end
        end
    end
    if #need == 0 then return end
    log("Orders", "%s's summary: %d orders differ here, asking for them", by, #need)
    publish("get", { l = need }, { target = sender, newOnly = true })
end

-- A guildmate asked for orders I speak for: answer every asker at once after GATHER seconds,
-- addressed to one, or to the whole guild for several.
function CraftOrders:OnGet(ids, sender)
    if type(ids) ~= "table" then return end
    local orders, me = store(), self:MyKey()
    for i = 1, math.min(#ids, self.SUM_MAX) do
        local id = cleanText(ids[i], 20)
        local o = id and orders[id]
        if o and CraftOrders.SpeaksFor(o, me) then self.fixes:Add(sender, id) end
    end
end

function CraftOrders:FlushFix(ids, target)
    local orders, list = store(), {}
    for id in pairs(ids) do
        if orders[id] then list[#list + 1] = orders[id] end
    end
    if #list == 0 then return end
    table.sort(list, function(a, b) return a.id < b.id end)
    publish("fix", { l = list }, { target = target, newOnly = true })
end

-- Replays on my copy what `by` did to an order that I missed, through Apply, so the same rules
-- decide: an acceptance, a release, a decline, the materials, completion or a cancellation.
-- Two acceptances at once that this copy heard only one of are settled as Apply settles them
-- live, the earlier one keeping the order, without Apply's "heard just now" condition: a repair
-- is by definition heard late.
function CraftOrders:Replay(mine, o, by)
    local acts = {}
    if o.cr == by and mine.st == "accepted" and mine.cr and mine.cr ~= by and o.acc and mine.acc
        and math.abs(o.acc - mine.acc) <= self.TAKEOVER and CraftOrders.Wins(o.acc, by, mine.acc, mine.cr) then
        local before = mine.cr
        mine.cr, mine.acc, mine.at = by, o.acc, math.max(mine.at or 0, o.at or 0)
        log("Orders", "Repaired acc from %s on order %s: accepted at the same moment as %s, and keeps it", by, o.id, before)
        if before == self:MyKey() then
            craft:Print(string.format(L["%s accepted the order for %s at the same moment, and keeps it."],
                CraftOrders.NameOf(by), itemText(mine.item)))
        end
        return true
    end
    if o.st == "open" then
        if mine.to == by and o.to == nil then acts[#acts + 1] = "dec" end
        if mine.cr == by and o.cr == nil then acts[#acts + 1] = "rel" end
    elseif o.st == "cancelled" then
        acts[#acts + 1] = "can"
    else
        if o.cr == by and mine.cr ~= by then acts[#acts + 1] = "acc" end
        if (o.st == "mats" or o.st == "done") and o.mode == "mats" then acts[#acts + 1] = "mats" end
        if o.st == "done" then acts[#acts + 1] = "done" end
    end
    local changed = false
    for _, act in ipairs(acts) do
        local data = { id = o.id, at = act == "acc" and o.acc or o.at, rg = o.rg, y = o.y }
        local r = self:Apply(act, data, by)
        if r then
            changed = true
            log("Orders", "Repaired %s from %s on order %s", act, by, o.id)
            self:Notify(act, r, by)
        end
    end
    return changed
end

-- Orders sent in answer to my request: new ones as a login answer would bring them, known ones by
-- replaying what changed.
function CraftOrders:Repair(list, by)
    if type(list) ~= "table" or not by then return end
    local orders, changed = store(), false
    for i = 1, math.min(#list, self.SUM_MAX) do
        local o = clean(list[i])
        if o then
            local mine = orders[o.id]
            if mine then
                changed = self:Replay(mine, o, by) or changed
            else
                changed = self:Merge({ list[i] }, by) or changed
            end
        end
    end
    if changed then
        self:Prune()
        self:Refresh()
    end
end

----------------------------------------------------------------------
-- Delivery: the trade and the mail
----------------------------------------------------------------------
-- My running orders with `partner` (a member key), oldest first: { { o, role } }, role "author"
-- or "crafter".
function CraftOrders:OrdersWith(partner)
    local out = {}
    if not partner then return out end
    local me, t = self:MyKey(), now()
    for _, o in pairs(store()) do
        local st = CraftOrders.StateOf(o, t)
        if st == "accepted" or st == "mats" then
            local r = (o.who == me and o.cr == partner and "author") or (o.cr == me and o.who == partner and "crafter")
            if r then out[#out + 1] = { o = o, role = r } end
        end
    end
    -- Oldest first; two placed in the same second by their id, so every run and client agrees.
    table.sort(out, function(a, b)
        if (a.o.ts or 0) ~= (b.o.ts or 0) then return (a.o.ts or 0) < (b.o.ts or 0) end
        return a.o.id < b.o.id
    end)
    return out
end

-- What I should hand over in an order: the materials (author, when they bring them and have not
-- yet) or the crafted item (crafter). { { itemID, need } }, and the tip in copper.
function CraftOrders:ToHand(o, role)
    if role == "author" then
        local tip = (o.tip or 0) > 0 and not o.paid and o.tip or 0
        if o.mode == "mats" and o.st == "accepted" then
            local out = {}
            local crafts = self:Crafts(o)
            for _, r in ipairs(self:Reagents(o.item, o)) do out[#out + 1] = { itemID = r.itemID, need = r.count * crafts } end
            return out, tip
        end
        return {}, tip
    end
    return { { itemID = o.item, need = o.n } }, 0
end

local function idOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Put `wants` ({ { itemID, need } }) from my bags into the free `slots`, through `drop(slot)`.
-- Whole stacks first, a split for the last of each. Returns what is still missing, by item id,
-- and whether it ran out of slots.
function CraftOrders:PutItems(wants, slots, drop)
    if Compat.CursorHasItem() then Compat.ClearCursor() end
    local missing, next, full = {}, 1, false
    for _, w in ipairs(wants) do
        local left = w.need
        for _, bag in ipairs(Compat.BagIDs()) do
            for slot = 1, Compat.GetContainerNumSlots(bag) do
                if left <= 0 then break end
                local info = Compat.GetContainerItemInfo(bag, slot)
                if info and info.itemID == w.itemID and not info.isLocked then
                    local target = slots[next]
                    if not target then full = true break end
                    local count = tonumber(info.stackCount) or 1
                    if count <= left then
                        Compat.PickupContainerItem(bag, slot)
                        left = left - count
                    else
                        Compat.SplitContainerItem(bag, slot, left)
                        left = 0
                    end
                    drop(target)
                    if Compat.CursorHasItem() then Compat.ClearCursor() end
                    next = next + 1
                end
            end
            if left <= 0 or full then break end
        end
        if left > 0 then missing[w.itemID] = left end
    end
    return missing, full
end

-- The trade window: who it is with, and what each side put in, kept until it ends.
function CraftOrders:OnTradeShow()
    local name, realm = Compat.TradePartner()
    self.trade = { partner = name and addon.Owner(name), mine = {}, theirs = {} }
    if self.uiTrade then craft:SafeCall(self.uiTrade, true) end
end

function CraftOrders:SnapshotTrade()
    local t = self.trade
    if not t then return end
    t.mine, t.theirs = Compat.TradeItemLinks(), Compat.TradeTargetItemLinks()
end

function CraftOrders:OnTradeClosed()
    if self.uiTrade then craft:SafeCall(self.uiTrade, false) end
end

-- A trade went through: what it means for the order with that partner.
function CraftOrders:OnTradeDone(partner, mine, theirs, tipPut, pick)
    -- One trade moves one order: the one picked on the bar when what changed hands fits it, else the
    -- oldest it fits. Item ids carry no counts, so two orders for the same item, or with a reagent in
    -- common, never both move on one trade.
    local list = self:OrdersWith(partner)
    if #list == 0 then return end
    local function effect(o, role)
        local reagent = {}
        for _, r in ipairs(self:Reagents(o.item, o)) do reagent[r.itemID] = true end
        local gaveRg, gotRg, gaveItem, gotItem = false, false, false, false
        for _, l in ipairs(mine or {}) do
            local id = idOf(l)
            if id and reagent[id] then gaveRg = true end
            if id == o.item then gaveItem = true end
        end
        for _, l in ipairs(theirs or {}) do
            local id = idOf(l)
            if id and reagent[id] then gotRg = true end
            if id == o.item then gotItem = true end
        end
        local matsStep = o.st == "accepted" and o.mode == "mats"
        if role == "author" then
            if gotItem then return "done" end
            if gaveRg and matsStep then return "mats" end
        else
            if gaveItem then return "done" end
            if gotRg and matsStep then return "mats" end
        end
        return nil
    end
    local chosen, act
    for _, x in ipairs(list) do
        if x.o.id == pick then chosen, act = x, effect(x.o, x.role) end
    end
    if not act then
        chosen = nil
        for _, x in ipairs(list) do
            local a = effect(x.o, x.role)
            if a then chosen, act = x, a break end
        end
    end
    -- The tip went with this trade: it belongs to the picked order, or the only one.
    local tipFor = pick or (#list == 1 and list[1].o.id) or (chosen and chosen.o.id)
    for _, x in ipairs(list) do
        if x.role == "author" and tipPut and x.o.id == tipFor then x.o.paid = true end
    end
    log("Orders", "Trade with %s finished: %s", partner, chosen and act and (act .. " on order " .. chosen.o.id) or "no order moved")
    if chosen and act then self:Act(chosen.o.id, act) end
    self:Refresh()
end

-- Orders I can send by mail now: { { o, role, act } }. The author mails the materials of an order
-- they bring them for (or the tip once it is done); the crafter mails the item.
function CraftOrders:MailRows()
    local me, t, rows = self:MyKey(), now(), {}
    for _, o in pairs(store()) do
        local st = CraftOrders.StateOf(o, t)
        if o.who == me and st == "accepted" and o.mode == "mats" then
            rows[#rows + 1] = { o = o, role = "author", act = "mats" }
        elseif o.who == me and st == "done" and (o.tip or 0) > 0 and not o.paid and o.cr then
            rows[#rows + 1] = { o = o, role = "author", act = "tip" }
        elseif o.cr == me and (st == "mats" or (st == "accepted" and o.mode == "own")) then
            rows[#rows + 1] = { o = o, role = "crafter", act = "done" }
        end
    end
    table.sort(rows, function(a, b) return (a.o.ts or 0) < (b.o.ts or 0) end)
    return rows
end

-- Write the mail for a MailRows row: the recipient, a subject, the items and the money. The order
-- moves on once the game says the mail went (MAIL_SEND_SUCCESS).
function CraftOrders:FillMail(row)
    local o = row.o
    Compat.ShowSendMail()
    local to = CraftOrders.NameOf(row.role == "author" and o.cr or o.who)
    local subject = string.format(L["Craft order: %s"], (Compat.GetItemInfo(o.item)) or ("item:" .. o.item))
    local wants, tip = {}, 0
    if row.act == "mats" then
        wants, tip = self:ToHand(o, "author")
    elseif row.act == "tip" then
        tip = o.tip or 0
    else
        wants = self:ToHand(o, "crafter")
    end
    Compat.FillSendMail(to, subject, tip)
    local missing, full = self:PutItems(wants, Compat.MailFreeSlots(), Compat.ClickSendMailItemButton)
    self.mailPending = { id = o.id, act = row.act, tip = tip > 0, to = to, subject = subject }
    self.lastSend = nil
    return missing, full
end

-- The game is sending a mail (hooked SendMail): to whom and under what subject.
function CraftOrders:OnSendMail(to, subject)
    self.lastSend = { to = type(to) == "string" and to or "", subject = type(subject) == "string" and subject or "" }
end

-- Only the mail the bar wrote moves the order on: the same recipient and subject. Another mail
-- sent with the mailbox still open leaves the order where it was.
function CraftOrders:OnMailSent()
    local p, sent = self.mailPending, self.lastSend
    self.lastSend = nil
    if not p then return end
    local subj = sent and sent.subject or ""
    local sameSubject = subj ~= "" and (p.subject:sub(1, #subj) == subj or subj:sub(1, #p.subject) == p.subject)
    if not sent or sent.to:lower() ~= p.to:lower() or not sameSubject then
        log("Orders", "Mail sent, but not the one prepared for order %s", p.id)
        return
    end
    log("Orders", "Mail for order %s sent to %s", p.id, p.to)
    self.mailPending = nil
    local o = self:Get(p.id)
    if not o then return end
    if p.tip then o.paid = true end
    if p.act == "mats" or p.act == "done" then self:Act(p.id, p.act) end
    self:Refresh()
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function CraftOrders:Initialize()
    store()
    self:Prune()
    if craft.SyncService then
        craft.SyncService:On(DOMAIN, function(env, sender) CraftOrders:OnEnvelope(env, sender) end)
    end
    local f = CreateFrame("Frame")
    self.frame = f
    for _, ev in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
                          "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "MAIL_SHOW", "MAIL_CLOSED",
                          "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do
        Compat.RegisterEvent(f, ev, true)
    end
    f:SetScript("OnEvent", function(_, event, a, b)
        if event == "TRADE_SHOW" then
            CraftOrders:OnTradeShow()
        elseif event == "TRADE_CLOSED" then
            CraftOrders:OnTradeClosed()
        elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
            CraftOrders:SnapshotTrade()
        elseif event == "UI_INFO_MESSAGE" then
            if Compat.IsTradeComplete(a, b) then
                local t = CraftOrders.trade
                CraftOrders.trade = nil
                if t and t.partner then
                    craft:SafeCall(function() CraftOrders:OnTradeDone(t.partner, t.mine, t.theirs, t.tipPut, t.pick) end)
                end
            end
        elseif event == "MAIL_SHOW" then
            if CraftOrders.uiMail then craft:SafeCall(CraftOrders.uiMail, true) end
        elseif event == "MAIL_CLOSED" then
            CraftOrders.mailPending = nil
            if CraftOrders.uiMail then craft:SafeCall(CraftOrders.uiMail, false) end
        elseif event == "MAIL_SEND_SUCCESS" then
            craft:SafeCall(function() CraftOrders:OnMailSent() end)
            if CraftOrders.uiMail then craft:SafeCall(CraftOrders.uiMail, true) end
        elseif event == "MAIL_FAILED" then
            CraftOrders.mailPending = nil
        end
    end)
    Compat.HookSendMail(function(to, subject) CraftOrders:OnSendMail(to, subject) end)
    -- A login asks once what is running; the reply comes from one member. The window's tab and the
    -- bars are painted once the answers had time to come in.
    Compat.After(math.random(8, 20), function() publish("ask", {}) end)
    Compat.NewTicker(self.SUMMARY_EVERY, function() CraftOrders:PublishSummary() end)
    Compat.After(30, function() CraftOrders:Refresh() end)
end
