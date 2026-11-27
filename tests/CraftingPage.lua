-- Run with Lua 5.1 from the repository root. Builds the Crafting Orders page against a mock UI
-- on top of the real two-client crafting sync, and walks its main flows.
strmatch = string.match
local function noop() end

-- Mock widgets: every method exists. Scripts, text, visibility and checked state are kept so the
-- test can click buttons and read what the page shows.
local widgets = {}
local methods = {}
local function widget(kind, template)
    local w = setmetatable({ kind = kind, template = template, scripts = {}, shown = true, text = "" },
        -- Methods are capitalized; a missing field reads as nil, as on a real frame.
        { __index = function(_, k) return methods[k] or (type(k) == "string" and k:match("^%u") and noop) or nil end })
    widgets[#widgets + 1] = w
    return w
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function methods:GetScript(name) return self.scripts[name] end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(v) self.shown = v and true or false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetText(t)
    self.text = t or ""
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.text end
function methods:GetNumber() return tonumber(self.text) or 0 end
function methods:GetHeight() return 300 end
function methods:GetWidth() return 500 end
function methods:GetStringHeight() return 40 end
function methods:GetVerticalScroll() return 0 end
function methods:SetEnabled(v) self.enabled = v end
function methods:CreateFontString() return widget("FontString") end
function methods:CreateTexture() return widget("Texture") end
function methods:SetupMenu(fn) self.menu = fn end

local now, packets, pending = 2000000, {}, {}
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local function client(first, surname, ui)
    local c = { guild = 7, name = first .. " " .. surname }
    local comm = {}
    local handlers = {}
    function comm.RegisterComm(_, prefix, callback) handlers[prefix] = callback end
    c.receive = function(prefix, ...) if handlers[prefix] then handlers[prefix](prefix, ...) end end
    function comm:SendCommMessage(prefix, message, channel)
        packets[#packets + 1] = { prefix, message, channel, c.name }
    end
    local env = setmetatable({
        LibStub = function(name) if name == "AceComm-3.0" then return comm end return LibStub(name) end,
        GetServerTime = function() return now end, UnitFullName = function() return first, surname end,
        IsInGuild = function() return c.guild ~= nil end, GetGuildInfo = function() return "EVIL" end,
        GetRealmName = function() return "Forever" end, C_Club = { GetGuildClubId = function() return c.guild end },
        GetProfessions = function() if first == "Second" then return 1 end end,
        GetProfessionInfo = function() return "Alchemy", nil, 150, 150, nil, nil, 171 end,
        IsPlayerSpell = function(id) return id == 2329 end,
        GetNumGuildMembers = function() return 2 end,
        GetGuildRosterInfo = function(i)
            local names = { "First Lemon", "Second Lemon" }
            return names[i], nil, nil, nil, nil, nil, nil, nil, i == 2, nil, "PALADIN"
        end,
        securecallfunction = function(fn, ...) return fn(...) end,
        GetTime = function() return now end, date = os.date,
        GetCoinTextureString = function(c) return c .. "c" end,
        C_Item = { GetItemIconByID = function() return 1 end, GetItemCount = function() return 2 end },
        C_Timer = { NewTicker = noop, After = function(delay, fn) pending[#pending + 1] = { at = now + delay, fn = fn } end },
        CreateFrame = ui and function(kind, _, _, template) return widget(kind, template) end
            or function() return { SetScript = noop, RegisterEvent = noop } end,
        GameTooltip = widget("GameTooltip"),
        MoneyInputFrame_GetCopper = function() return 50 end,
    }, { __index = _G })
    c.env = env
    for _, file in ipairs({ "Debug", "Comm", "Bounty", "Crafting/Client", "Crafting/ProfCatalogForever", "Crafting/Professions",
        "Crafting/ProfDirectory", "Crafting/ProfSync", "Crafting/CraftOrders", "Crafting/Sync", "Crafting/Page" }) do
        local chunk = assert(loadfile("EVILRises/" .. file .. ".lua"))
        setfenv(chunk, env)("EVILRises", c)
    end
    c.Crafting.BindGuild()
    return c
end
local a, b = client("First", "Lemon", true), client("Second", "Lemon")
local function deliver()
    while #pending > 0 or #packets > 0 do
        if #pending > 0 then
            table.sort(pending, function(x, y) return x.at < y.at end)
            local timer = table.remove(pending, 1)
            now = timer.at
            timer.fn()
        end
        while #packets > 0 do
            local packet = table.remove(packets, 1)
            for _, c in ipairs({ a, b }) do c.receive(unpack(packet)) end
        end
    end
end
deliver()

-- Build the page for the first client.
local page = widget("Frame")
a.Crafting.Build(page)
local function find(pred)
    for _, w in ipairs(widgets) do if pred(w) then return w end end
end
local function buttonText(t) return find(function(w) return w.kind == "Button" and w.text == t and w.shown end) end
local function visibleRows()
    local out = {}
    for _, w in ipairs(widgets) do
        if w.kind == "Button" and w.value ~= nil and w.shown then out[#out + 1] = w end
    end
    return out
end
local function shownText(pattern)
    return find(function(w) return w.kind == "FontString" and w.shown and tostring(w.text):find(pattern) end)
end
local tabs = page.Tabs
assert(#tabs == 3 and tabs[1].text == "Recipes" and tabs[1].template == "PanelTopTabButtonTemplate")

-- Recipes: the guild's recipe book, filtered to what the guild knows.
local radios = {}
local root = { CreateRadio = function(_, label, _, choose) radios[label] = choose end }
for _, w in ipairs(widgets) do if w.kind == "DropdownButton" and w.menu then w.menu(nil, root) end end
assert(radios["Known by the guild"] and radios["All professions"])
radios["Known by the guild"]()
local rows = visibleRows()
assert(#rows == 1, "one recipe the guild knows, got " .. #rows)
assert(rows[1].left.text:find("1 crafter") == nil and rows[1].right.text:find("1 crafter"))

-- Open it, then place an order with a quantity, a tip and a note.
rows[1].scripts.OnClick(rows[1])
assert(shownText("Reagents") and shownText("Second Lemon"))
local qty = find(function(w) return w.kind == "EditBox" and w.template == "InputBoxTemplate" and w.text == "1" end)
qty:SetText("3")
assert(shownText("for 3"))
buttonText("Place order").scripts.OnClick()
assert(page.Tabs and shownText("Placed"), "the new order opens on the Orders tab")
local placed = a.Crafting.CraftOrders:Rows("mine")[1]
assert(placed and placed.n == 3 and placed.tip == 50)
deliver()

-- The crafter accepts and completes it; the requester's open detail follows along.
assert(b.Crafting.CraftOrders:Act(placed.id, "accept"))
deliver()
assert(shownText("Accepted"))
assert(buttonText("Materials sent"))
buttonText("Materials sent").scripts.OnClick()
deliver()
assert(b.Crafting.CraftOrders:Act(placed.id, "done"))
deliver()
assert(shownText("Completed"))

-- Back to the list: the order shows there with its state.
buttonText("Back").scripts.OnClick()
rows = visibleRows()
assert(#rows == 1 and rows[1].right.text:find("Completed"))

-- Crafters: one crafter's recipes, with a way back to everyone.
tabs[2].scripts.OnClick()
rows = visibleRows()
assert(#rows == 1 and rows[1].left.text:find("Second Lemon"))
rows[1].scripts.OnClick(rows[1])
assert(shownText("Alchemy"))
rows = visibleRows()
assert(#rows == 1)
rows[1].scripts.OnClick(rows[1])
assert(shownText("Reagents"))
buttonText("Back").scripts.OnClick()
assert(#visibleRows() == 1 and buttonText("Back"), "back to the crafter's recipes")
buttonText("Back").scripts.OnClick()
rows = visibleRows()
assert(#rows == 1 and rows[1].left.text:find("Second Lemon"), "back to all crafters")
print("Crafting page: tabs, recipe filter, ordering with quantity and tip, live order progress, crafter recipes and back navigation passed.")
