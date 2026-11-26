local _, addon = ...
local craft = addon.Crafting
----------------------------------------------------------------------
-- EVIL Rises - Profession directory (WoW: Forever, issue #33)
--
-- What the Professions panel and the item tooltips read: the static catalog crossed with
-- every member's professions (craft.Professions). Reads only; nothing here writes the
-- database. Names are localized at run time: professions through the locale table, recipes
-- through the client's spell names.
----------------------------------------------------------------------

local ProfDirectory = {}
craft.ProfDirectory = ProfDirectory

local Compat = craft.Compat
local L = craft.L

local function catalog() return craft.ProfCatalog end

-- Recipe names the client has already resolved, by recipe ID.
local names = {}
function ProfDirectory.RecipeName(id)
    local name = names[id]
    if name then return name end
    name = Compat.GetSpellInfo(id)
    if name then names[id] = name end
    return name or ("#" .. id)
end

function ProfDirectory.DisplayName(line)
    local meta = catalog().professions[line]
    return meta and L[meta.en] or ("#" .. tostring(line))
end

-- Whether a recipe is shown. Forever's game data still holds Season of Discovery's recipes (285 of
-- 2490, under categories the catalog marks `seasonal`), many beside the Forever recipe of the same
-- name with other reagents and skill: two "Enchant Bracer - Agility" (issue #396). Such a recipe is
-- shown only while someone in the guild knows it, so a member who learned one still finds it.
function ProfDirectory.Shown(id)
    local cat = catalog()
    local r = cat.recipes[id]
    if not (r and cat.seasonal and cat.seasonal[r[cat.F.category]]) then return true end
    return #craft.Professions:CraftersOf(id) > 0
end
local shown = ProfDirectory.Shown

-- The catalog's profession lines: primaries, then secondaries, each by localized name.
function ProfDirectory.Lines()
    local cat = catalog()
    local out = {}
    for line in pairs(cat.professions) do out[#out + 1] = line end
    table.sort(out, function(a, b)
        local pa, pb = cat.professions[a].primary, cat.professions[b].primary
        if pa ~= pb then return pa end
        return ProfDirectory.DisplayName(a) < ProfDirectory.DisplayName(b)
    end)
    return out
end

-- The catalog's recipes on `line` (every line when nil), filtered by `mode` ("all", "guild":
-- someone knows it, "gaps": nobody does) and a plain-text, case-insensitive `query` on the
-- localized name; sorted by the yellow rank, then name.
function ProfDirectory.RecipeRows(line, mode, query)
    local cat, P = catalog(), craft.Professions
    local F = cat.F
    local q = (query and query ~= "") and query:lower() or nil
    local rows, seen = {}, {}
    for _, l in ipairs(line and { line } or ProfDirectory.Lines()) do
        for _, id in ipairs(cat.byLine[l] or {}) do
            if not seen[id] and shown(id) then
                seen[id] = true
                local crafters = P:CraftersOf(id)
                local known = #crafters > 0
                if (mode ~= "guild" or known) and (mode ~= "gaps" or not known) then
                    local name = ProfDirectory.RecipeName(id)
                    if not q or name:lower():find(q, 1, true) then
                        local r = cat.recipes[id]
                        rows[#rows + 1] = {
                            id = id, line = l, name = name, yellow = r[F.yellow], grey = r[F.grey],
                            out = r[F.out], spec = r[F.spec], focus = r[F.focus], src = r[F.src],
                            reqSkill = r[F.reqSkill], recipeItem = r[F.recipeItem], crafters = crafters,
                        }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.yellow ~= b.yellow then return a.yellow < b.yellow end
        return a.name < b.name
    end)
    return rows
end

-- key -> { name, class, online } for everyone on the guild roster, read once per call.
local function roster()
    local out = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local full, _, _, _, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
        local key = full and craft.Professions.KeyFor(full)
        if key then
            out[key] = { name = addon.Owner(full), class = class, online = online and true or false }
        end
    end
    return out
end

-- Members with the line: { key, name, class, online, rank, max, spec, count, native }, the
-- ranked ones first by rank, members known from the guild roster only (native) last.
function ProfDirectory.MemberRows(line)
    local P = craft.Professions
    local who = roster()
    local rows = {}
    for _, key in ipairs(P:Members(line)) do
        local rec = P:Get(key)
        local e = rec.profs[line]
        local w = who[key] or {}
        local recipes, extra = P.Lists(e)
        rows[#rows + 1] = {
            key = key, name = w.name or key, class = w.class, online = w.online or false,
            rank = e.rank, max = e.max, spec = e.spec, count = #recipes + #extra, native = rec.src == "native",
        }
    end
    table.sort(rows, function(a, b)
        if a.native ~= b.native then return not a.native end
        if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
        return a.name < b.name
    end)
    return rows
end

-- The catalog recipes that create an item (a map built once per catalog).
local byItem, byItemFor
function ProfDirectory.ItemRecipes(itemID)
    local cat = catalog()
    if byItemFor ~= cat then
        byItem, byItemFor = {}, cat
        for id, r in pairs(cat.recipes) do
            local out = r[cat.F.out]
            if out and out > 0 then
                byItem[out] = byItem[out] or {}
                table.insert(byItem[out], id)
            end
        end
        for _, ids in pairs(byItem) do table.sort(ids) end
    end
    local out = {}
    for _, id in ipairs(byItem[itemID] or {}) do
        if shown(id) then out[#out + 1] = id end
    end
    return out
end

-- The members who know any of `recipeIDs`: { { playerName, playerKey, class, profName } }, or nil.
-- profName is the English name; the screens show it through L (issue #114).
local function crafters(recipeIDs)
    local P, cat = craft.Professions, catalog()
    local who, out, seen = nil, {}, {}
    for _, id in ipairs(recipeIDs) do
        local r = cat.recipes[id]
        for _, key in ipairs(P:CraftersOf(id)) do
            if not seen[key] then
                seen[key] = true
                who = who or roster()
                local w = who[key] or {}
                -- A recipe two professions learn is recorded under one line: name the member's own.
                local line = r and r[cat.F.line]
                local rec = P:Get(key)
                if rec and line and not rec.profs[line] then
                    for l in pairs(rec.profs) do
                        for _, x in ipairs(cat.byLine[l] or {}) do
                            if x == id then line = l end
                        end
                    end
                end
                out[#out + 1] = { playerName = w.name or key, playerKey = key,
                                  class = w.class, profName = line and cat.professions[line] and cat.professions[line].en or "" }
            end
        end
    end
    return #out > 0 and out or nil
end

function ProfDirectory.CraftersForItem(itemID) return crafters(ProfDirectory.ItemRecipes(itemID)) end

-- { { itemID, count } } a recipe needs, from the catalog.
function ProfDirectory.Reagents(id)
    local cat = catalog()
    local r = cat.recipes[id]
    local flat, out = (r and r[cat.F.reagents]) or {}, {}
    for i = 1, #flat - 1, 2 do out[#out + 1] = { itemID = flat[i], count = flat[i + 1] } end
    return out
end
