local _, addon = ...
local craft = addon.Crafting
local D, O = craft.ProfDirectory, craft.CraftOrders
----------------------------------------------------------------------
-- EVIL Rises - Crafting Orders page
--
-- Three tabs over one inset: Recipes (the guild's recipe book), Crafters (who has which
-- profession) and Orders (mine, assigned to me, open to me). A row opens its detail in the
-- same inset; Back or any tab returns to the list. Built from the client's own templates
-- (top tabs, inset, search box, money input) so it matches the native windows.
----------------------------------------------------------------------
local ROW = 24
local GRAY, GREEN, RED, GOLD = "ff9d9d9d", "ff40c040", "ffff5050", "ffffd100"
local STATES = {
    open = { "Open", "ffffffff" },
    accepted = { "Accepted", GOLD },
    mats = { "Materials sent", "ffff9933" },
    done = { "Completed", GREEN },
    cancelled = { "Cancelled", GRAY },
    expired = { "Expired", GRAY },
}
local function color(hex, s) return "|c" .. hex .. tostring(s) .. "|r" end

-- A frame from a native template, or a plain one when the client lacks the template.
local function make(kind, parent, template, fallback, name)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame, true end
    return CreateFrame(kind, nil, parent, fallback), false
end
local function text(parent, caption, font)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    f:SetJustifyH("LEFT")
    f:SetText(caption or "")
    return f
end
local function button(parent, caption, width, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(caption)
    b:SetScript("OnClick", fn)
    return b
end
local function input(parent, width, max, numeric)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(max)
    box:SetNumeric(numeric or false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end
local function menu(parent, width, choices, selected, choose)
    local b = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    b:SetWidth(width)
    b:SetupMenu(function(_, root)
        for _, entry in ipairs(choices()) do
            root:CreateRadio(entry[2], function() return selected() == entry[1] end, function() choose(entry[1]) end)
        end
    end)
    return b
end
local function itemName(id)
    return craft.Compat.GetItemInfo(id) or ("Item #" .. id)
end
local function itemIcon(id)
    return id and id > 0 and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400
end
local function recipeIcon(r)
    if r.out and r.out > 0 then return itemIcon(r.out) end
    return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(r.id) or 134400
end
local function qualityName(id, fallback)
    local name, _, quality = craft.Compat.GetItemInfo(id)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    name = name or fallback or ("Item #" .. id)
    return c and c.hex and (c.hex .. name .. "|r") or name
end
local function inline(icon) return "|T" .. tostring(icon) .. ":16:16:0:0|t " end
local function memberName(key, who)
    local w = who and who[key]
    local name = w and w.name or key
    if key == O:MyKey() then return color(GREEN, name .. " (you)") end
    if w and not w.online then return color(GRAY, name) end
    local c = w and w.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[w.class]
    return c and c.colorStr and color(c.colorStr, name) or name
end
local function stateText(o)
    local s = STATES[O.StateOf(o)] or { O.StateOf(o), "ffffffff" }
    return color(s[2], s[1])
end

-- A virtual list: a row per visible line, each with an icon, a name on the left and details on
-- the right, alternating stripes, a highlight and a tooltip.
local function buildListing(parent)
    local rows, data, describe, click, enter = {}, nil, nil, nil, nil
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local empty = text(parent, "", "GameFontDisable")
    empty:SetPoint("TOP", scroll, "TOP", 0, -24)
    empty:SetJustifyH("CENTER")
    local function draw()
        local start = math.floor(scroll:GetVerticalScroll() / ROW)
        local visible = math.ceil(scroll:GetHeight() / ROW) + 1
        for i = 1, visible do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, child)
                row:SetHeight(ROW)
                row.stripe = row:CreateTexture(nil, "BACKGROUND")
                row.stripe:SetAllPoints()
                row.stripe:SetColorTexture(1, 1, 1, 0.04)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", 4, 0)
                row.left = text(row, "", "GameFontHighlight")
                row.left:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.left:SetWordWrap(false)
                row.right = text(row, "", "GameFontHighlightSmall")
                row.right:SetPoint("RIGHT", -6, 0)
                row.right:SetJustifyH("RIGHT")
                row.right:SetWordWrap(false)
                row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
                row:SetScript("OnClick", function(self) if self.value and click then click(self.value) end end)
                row:SetScript("OnEnter", function(self)
                    if not (self.value and enter) then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    enter(self.value)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                rows[i] = row
            end
            local index = start + i
            row.value = data and data[index]
            row:SetShown(row.value ~= nil)
            if row.value then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
                row:SetWidth(child:GetWidth())
                row.stripe:SetShown(index % 2 == 0)
                local icon, left, right = describe(row.value)
                row.icon:SetShown(icon ~= nil)
                row.icon:SetTexture(icon)
                row.left:ClearAllPoints()
                row.left:SetPoint("LEFT", icon and row.icon or row, icon and "RIGHT" or "LEFT", 6, 0)
                row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
                row.left:SetText(left)
                row.right:SetText(right or "")
            end
        end
        for i = visible + 1, #rows do rows[i]:Hide() end
    end
    scroll:HookScript("OnVerticalScroll", draw)
    scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(math.max(1, w)); draw() end)
    local list = {}
    function list.Set(values, describer, clicker, tooltip, reset, emptyText)
        data, describe, click, enter = values, describer, clicker, tooltip
        child:SetHeight(math.max(1, #values * ROW))
        if reset then scroll:SetVerticalScroll(0) end
        empty:SetText(#values == 0 and emptyText or "")
        draw()
    end
    list.Redraw = draw
    list.frame = scroll
    return list
end

function craft.Build(page)
    local title = text(page, "Crafting Orders", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)

    local inset = make("Frame", page, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 6, -62)
    inset:SetPoint("BOTTOMRIGHT", -6, 6)
    local browse = CreateFrame("Frame", nil, inset)
    browse:SetAllPoints()
    local detail = CreateFrame("Frame", nil, inset)
    detail:SetAllPoints()
    detail:Hide()

    local TABS = { "Recipes", "Crafters", "Orders" }
    local mode, line, coverage, queue = 1, 0, "all", "mine"
    local selectedRecipe, selectedOrder, recipient, material, forCrafter
    local render, showRecipe, showOrder, list

    -- Tabs: the native top tabs, chained on one baseline above the inset.
    local tabs = {}
    page.Tabs = tabs
    local nativeTabs = true
    local function resizeTab(t)
        if nativeTabs and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, t, 0) end
    end
    local function highlightTab(i)
        if not (nativeTabs and PanelTemplates_SetTab and pcall(PanelTemplates_SetTab, page, i)) then
            for j, t in ipairs(tabs) do t:SetEnabled(j ~= i) end
        end
    end
    local function selectTab(i)
        mode = i
        highlightTab(i)
        list()
    end
    for i, name in ipairs(TABS) do
        local t, native = make("Button", page, "PanelTopTabButtonTemplate", "UIPanelButtonTemplate")
        t:SetID(i)
        t:SetText(name)
        if not native then nativeTabs = false; t:SetSize(96, 22) end
        if i == 1 then
            t:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 6, -2)
        else
            t:SetPoint("BOTTOMLEFT", tabs[i - 1], "BOTTOMRIGHT", 2, 0)
        end
        t:SetScript("OnClick", function() selectTab(i) end)
        tabs[i] = t
        resizeTab(t)
    end
    if nativeTabs and PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, page, #tabs) end

    -- Toolbar: search on the left, filters beside it, the result count on the right.
    local search, nativeSearch = make("EditBox", browse, "SearchBoxTemplate", "InputBoxTemplate")
    search:SetSize(170, 20)
    search:SetPoint("TOPLEFT", 14, -10)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    if not nativeSearch then search:SetScript("OnEscapePressed", search.ClearFocus) end
    local lines = { { 0, "All professions" } }
    for _, id in ipairs(D.Lines()) do lines[#lines + 1] = { id, D.DisplayName(id) } end
    local profMenu = menu(browse, 150, function() return lines end, function() return line end,
        function(v) line = v; render(true) end)
    profMenu:SetPoint("LEFT", search, "RIGHT", 10, 0)
    local filters = { { "all", "All recipes" }, { "guild", "Known by the guild" }, { "gaps", "Nobody knows yet" } }
    local views = { { "mine", "My requests" }, { "forme", "For me to craft" }, { "open", "Open to me" } }
    local filter = menu(browse, 150, function() return mode == 3 and views or filters end,
        function() return mode == 3 and queue or coverage end,
        function(v) if mode == 3 then queue = v else coverage = v end; render(true) end)
    local count = text(browse, "", "GameFontDisableSmall")
    count:SetPoint("TOPRIGHT", -14, -14)
    count:SetJustifyH("RIGHT")
    local rule = browse:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.18)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 8, -36)
    rule:SetPoint("TOPRIGHT", -8, -36)

    -- While one crafter's recipes are listed, a Back button replaces the search and filters.
    local crafterBack = button(browse, "Back", 70, function() forCrafter = nil; render(true) end)
    crafterBack:SetPoint("TOPLEFT", 10, -9)
    crafterBack:Hide()
    local crafterTitle = text(browse, "", "GameFontNormal")
    crafterTitle:SetPoint("LEFT", crafterBack, "RIGHT", 10, 0)
    local listing = buildListing(browse)
    listing.frame:SetPoint("TOPLEFT", 8, -40)
    listing.frame:SetPoint("BOTTOMRIGHT", -28, 6)

    -- Orders waiting on me: assigned to me and not finished, or open and mine to take.
    local function waiting()
        local n = 0
        for _, o in ipairs(O:Rows("forme")) do if O.IsActive(o) then n = n + 1 end end
        return n + #O:Rows("open")
    end
    local function updateBadge()
        local n = waiting()
        local label = n > 0 and ("Orders (" .. n .. ")") or "Orders"
        if tabs[3]:GetText() ~= label then
            tabs[3]:SetText(label)
            resizeTab(tabs[3])
        end
    end

    list = function()
        selectedRecipe, selectedOrder, forCrafter = nil, nil, nil
        detail:Hide()
        browse:Show()
        render(true)
    end

    local function toolbar(crafterView)
        crafterBack:SetShown(crafterView)
        crafterTitle:SetShown(crafterView)
        search:SetShown(not crafterView)
        profMenu:SetShown(not crafterView and mode ~= 3)
        filter:SetShown(not crafterView and mode ~= 2)
    end
    render = function(reset)
        updateBadge()
        toolbar(false)
        filter:ClearAllPoints()
        filter:SetPoint("LEFT", mode == 3 and search or profMenu, "RIGHT", 10, 0)
        filter:GenerateMenu()
        profMenu:GenerateMenu()
        local q = (search:GetText() or ""):lower()
        local values, describe, click, tooltip, emptyText = {}, nil, nil, nil, nil
        if mode == 1 then
            values = D.RecipeRows(line ~= 0 and line or nil, coverage, q)
            describe = function(r)
                local n = #r.crafters
                local who = n > 0 and color(GREEN, n == 1 and "1 crafter" or (n .. " crafters")) or color(GRAY, "No crafters")
                local name = r.out and r.out > 0 and qualityName(r.out, r.name) or r.name
                return recipeIcon(r), name, color(GRAY, D.DisplayName(r.line) .. "  ·  " .. (r.reqSkill or 0) .. "   ") .. who
            end
            click = function(r) showRecipe(r) end
            tooltip = function(r)
                if r.out and r.out > 0 then GameTooltip:SetItemByID(r.out) else GameTooltip:SetSpellByID(r.id) end
                GameTooltip:AddLine("Click to see the reagents and place an order.", 0.5, 0.8, 1)
            end
            emptyText = q ~= "" and "No recipes match your search." or "No recipes for this filter."
        elseif mode == 2 then
            for _, entry in ipairs(lines) do
                if entry[1] ~= 0 and (line == 0 or line == entry[1]) then
                    for _, r in ipairs(D.MemberRows(entry[1])) do
                        if r.name:lower():find(q, 1, true) then
                            r.line = entry[1]
                            values[#values + 1] = r
                        end
                    end
                end
            end
            local roster = D.Roster()
            describe = function(r)
                local rank = r.native and color(GRAY, "level not shared") or ((r.rank or "?") .. "/" .. (r.max or "?"))
                local known = r.native and "" or ("  ·  " .. r.count .. " recipes")
                return nil, memberName(r.key, roster), D.DisplayName(r.line) .. "  " .. rank .. color(GRAY, known)
            end
            click = function(r)
                if not r.native then forCrafter = r; render(true) end
            end
            tooltip = function(r)
                GameTooltip:SetText(r.name)
                GameTooltip:AddLine(D.DisplayName(r.line) .. (r.native and "" or ("  " .. (r.rank or "?") .. "/" .. (r.max or "?"))), 1, 1, 1)
                GameTooltip:AddLine(r.native and "This member does not run EVIL Rises, so their recipes are not shared."
                    or "Click to see their recipes.", 0.5, 0.8, 1, true)
            end
            emptyText = q ~= "" and "Nobody matches your search." or "Nobody has shared this profession yet."
            if forCrafter then
                -- One crafter's recipes on that profession.
                local r = forCrafter
                toolbar(true)
                crafterTitle:SetText(memberName(r.key, roster) .. color(GRAY, "  ·  " .. D.DisplayName(r.line)))
                values = {}
                for _, e in ipairs(D.RecipeRows(r.line, "guild")) do
                    if craft.Professions:KnowsRecipe(r.key, e.id) then values[#values + 1] = e end
                end
                describe = function(e)
                    return recipeIcon(e), e.out and e.out > 0 and qualityName(e.out, e.name) or e.name,
                        color(GRAY, "Skill " .. (e.reqSkill or 0))
                end
                click = function(e) showRecipe(e, r.key) end
                tooltip = function(e)
                    if e.out and e.out > 0 then GameTooltip:SetItemByID(e.out) else GameTooltip:SetSpellByID(e.id) end
                    GameTooltip:AddLine("Click to order it from " .. r.name .. ".", 0.5, 0.8, 1)
                end
                emptyText = "No recipes shared yet."
            end
        else
            local roster = D.Roster()
            for _, o in ipairs(O:Rows(queue)) do
                local hay = (itemName(o.item) .. " " .. o.who .. " " .. (o.cr or "")):lower()
                if hay:find(q, 1, true) then values[#values + 1] = o end
            end
            describe = function(o)
                local other
                if queue == "mine" then
                    other = o.cr and memberName(o.cr, roster) or o.to and (memberName(o.to, roster) .. color(GRAY, " (asked)"))
                        or color(GRAY, "any crafter")
                else
                    other = color(GRAY, "from ") .. memberName(o.who, roster)
                end
                return itemIcon(o.item), qualityName(o.item) .. color(GRAY, "  ×" .. o.n), stateText(o) .. color(GRAY, "  ·  ") .. other
            end
            click = function(o) showOrder(o) end
            tooltip = function(o)
                GameTooltip:SetItemByID(o.item)
                GameTooltip:AddLine("Click to see the order.", 0.5, 0.8, 1)
            end
            emptyText = queue == "mine" and "You have no requests. Open a recipe to place an order."
                or queue == "forme" and "Nothing is waiting for you to craft."
                or "No open orders for recipes you know."
        end
        count:SetText(#values == 0 and "" or (#values == 1 and "1 result" or (#values .. " results")))
        listing.Set(values, describe, click, tooltip, reset, emptyText)
    end
    if search.HookScript then search:HookScript("OnTextChanged", function() render(true) end) end

    -------------------------------------------------------------------
    -- Detail: a header, a scrolling description, and a form or actions along the bottom.
    -------------------------------------------------------------------
    local back = button(detail, "Back", 70, function()
        if forCrafter then
            -- Back to the crafter's recipes this one was opened from.
            selectedRecipe, selectedOrder = nil, nil
            detail:Hide(); browse:Show()
            render(false)
            return
        end
        list()
    end)
    back:SetPoint("TOPLEFT", 10, -8)
    local icon = detail:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 12, -38)
    local heading = text(detail, "", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    heading:SetPoint("RIGHT", -12, 0)
    heading:SetWordWrap(false)
    local subline = text(detail, "", "GameFontHighlightSmall")
    subline:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
    subline:SetPoint("RIGHT", -12, 0)
    local hover = CreateFrame("Frame", nil, detail)
    hover:SetAllPoints(icon)
    hover:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.item)
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local body = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
    body:SetPoint("TOPLEFT", 14, -84)
    local content = CreateFrame("Frame", nil, body)
    content:SetSize(1, 1)
    body:SetScrollChild(content)
    local info = text(content, "")
    info:SetPoint("TOPLEFT")
    info:SetSpacing(3)
    local function sizeBody()
        local width = math.max(1, body:GetWidth())
        info:SetWidth(width)
        content:SetSize(width, math.max(1, info:GetStringHeight() + 4))
    end
    body:SetScript("OnSizeChanged", sizeBody)
    local function describeDetail(value, bottom)
        body:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -32, bottom)
        info:SetText(value)
        sizeBody()
        body:SetVerticalScroll(0)
    end
    local function section(name) return color(GOLD, name) end

    -- The order form for a recipe that makes an item.
    local form = CreateFrame("Frame", nil, detail)
    form:SetPoint("BOTTOMLEFT", 14, 10)
    form:SetPoint("BOTTOMRIGHT", -14, 10)
    form:SetHeight(120)
    local formRule = form:CreateTexture(nil, "ARTWORK")
    formRule:SetColorTexture(1, 0.82, 0, 0.18)
    formRule:SetHeight(1)
    formRule:SetPoint("TOPLEFT", 0, 6)
    formRule:SetPoint("TOPRIGHT", 0, 6)
    local function caption(s, x, y)
        local f = text(form, s, "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", x, y)
        return f
    end
    caption("Quantity", 0, 0)
    local qty = input(form, 40, 2, true)
    qty:SetPoint("TOPLEFT", 6, -14)
    caption("Crafter", 64, 0)
    local who = menu(form, 180, function()
        local options = { { false, "Any guild crafter" } }
        local roster = D.Roster()
        for _, key in ipairs(selectedRecipe and selectedRecipe.crafters or {}) do
            if key ~= O:MyKey() then
                local w = roster[key]
                options[#options + 1] = { key, (w and w.name or key) .. (w and not w.online and " (offline)" or "") }
            end
        end
        return options
    end, function() return recipient end, function(v) recipient = v end)
    who:SetPoint("TOPLEFT", 60, -12)
    caption("Materials", 256, 0)
    local materials = menu(form, 170, function()
        return { { "mats", "I bring the materials" }, { "own", "Crafter uses their own" } }
    end, function() return material end, function(v) material = v end)
    materials:SetPoint("TOPLEFT", 252, -12)
    caption("Tip", 0, -44)
    -- Named, because the template names its gold, silver and copper boxes after the frame.
    local tipFrame, nativeMoney = make("Frame", form, "MoneyInputFrameTemplate", nil, "EVILRisesCraftTip")
    local tipBox
    if nativeMoney then
        tipFrame:SetPoint("TOPLEFT", 4, -60)
    else
        tipBox = input(form, 90, 10, true)
        tipBox:SetPoint("TOPLEFT", 6, -58)
        caption("copper", 100, -62)
    end
    local function tipCopper()
        if nativeMoney and MoneyInputFrame_GetCopper then return MoneyInputFrame_GetCopper(tipFrame) or 0 end
        return tipBox and tipBox:GetNumber() or 0
    end
    local function resetTip()
        if nativeMoney and MoneyInputFrame_ResetMoney then MoneyInputFrame_ResetMoney(tipFrame)
        elseif tipBox then tipBox:SetText("") end
    end
    caption("Note", 200, -44)
    local note = input(form, 220, 80)
    note:SetPoint("TOPLEFT", 206, -58)
    local place
    local status = text(form, "", "GameFontHighlightSmall")
    place = button(form, "Place order", 120, function()
        if not selectedRecipe then return end
        local n = qty:GetNumber()
        if n < 1 or n > O.MAX_N then status:SetText(color(RED, "Enter a quantity from 1 to " .. O.MAX_N .. ".")); return end
        local o, err = O:Place(selectedRecipe.out, { recipe = selectedRecipe.id, n = n, tip = tipCopper(),
            note = note:GetText(), to = recipient or nil, mode = material })
        if o then
            queue = "mine"
            mode = 3
            highlightTab(3)
            search:SetText("")
            showOrder(o)
        else
            status:SetText(color(RED, err))
        end
    end)
    place:SetPoint("BOTTOMLEFT", 0, 0)
    status:SetPoint("LEFT", place, "RIGHT", 10, 0)
    status:SetPoint("RIGHT", 0, 0)

    -- The order's buttons, along the bottom.
    local actions = {}
    local function clearActions() for _, b in ipairs(actions) do b:Hide() end end
    local function action(label, fn)
        local i = 1
        while actions[i] and actions[i]:IsShown() do i = i + 1 end
        local b = actions[i] or button(detail, "", 110, fn)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 14 + (i - 1) * 116, 10)
        actions[i] = b
        b:SetText(label)
        b:SetScript("OnClick", fn)
        b:Show()
    end

    -- Reagent lines: what one order of `quantity` takes, and how many I carry.
    local function reagentLines(needs)
        local out = {}
        for _, r in ipairs(needs) do
            local have = r.have or (craft.Compat.GetItemCount(r.itemID) or 0)
            local enough = have >= r.need
            out[#out + 1] = inline(itemIcon(r.itemID)) .. qualityName(r.itemID) .. "   "
                .. color(enough and GREEN or RED, have .. "/" .. r.need)
        end
        return #out > 0 and table.concat(out, "\n") or color(GRAY, "None listed")
    end

    local function recipeDetail()
        local r = selectedRecipe
        local n = math.max(1, qty:GetNumber())
        local yield = r.out and r.out > 0 and O:KnownYield(r.out, r.id) or 1
        local crafts = math.ceil(n / yield)
        local needs = {}
        for _, v in ipairs(D.Reagents(r.id)) do needs[#needs + 1] = { itemID = v.itemID, need = v.count * crafts } end
        local roster = D.Roster()
        local names = {}
        for _, key in ipairs(r.crafters) do names[#names + 1] = memberName(key, roster) end
        local source = r.src == 3 and "Learned automatically"
            or (r.src == 2 and ((r.recipeItem or 0) > 0 and ("From " .. itemName(r.recipeItem)) or "From a recipe item")
            or "From a trainer")
        local makes = yield > 1 and ("   " .. color(GRAY, "Each craft makes " .. yield)) or ""
        describeDetail(table.concat({
            section("Reagents") .. "  " .. color(GRAY, "for " .. n .. (crafts ~= n and (" (" .. crafts .. " crafts)") or "")) .. makes,
            reagentLines(needs),
            "",
            section("Crafters"),
            #names > 0 and table.concat(names, ",  ") or color(GRAY, "Nobody in the guild knows this recipe yet."),
            "",
            color(GRAY, source),
        }, "\n"), r.out and r.out > 0 and 136 or 10)
    end
    qty:SetScript("OnTextChanged", function() if selectedRecipe then recipeDetail() end end)

    showRecipe = function(r, to)
        selectedRecipe, selectedOrder, recipient, material = r, nil, to or false, "mats"
        if recipient == O:MyKey() then recipient = false end
        browse:Hide(); detail:Show(); clearActions()
        icon:SetTexture(recipeIcon(r))
        hover.item = r.out and r.out > 0 and r.out or nil
        heading:SetText(r.out and r.out > 0 and qualityName(r.out, r.name) or r.name)
        subline:SetText(D.DisplayName(r.line) .. "  ·  Skill " .. (r.reqSkill or 0))
        local makesItem = r.out and r.out > 0
        form:SetShown(makesItem)
        qty:SetText("1"); note:SetText(""); status:SetText(""); resetTip()
        who:GenerateMenu(); materials:GenerateMenu()
        if not makesItem then status:SetText("") end
        recipeDetail()
        if not makesItem then
            info:SetText(info:GetText() .. "\n\n" .. color(GRAY, "This recipe does not make an item, so it cannot be ordered."))
            sizeBody()
        end
    end

    local STEPS = { { "open", "Placed" }, { "accepted", "Accepted" }, { "mats", "Materials sent" }, { "done", "Completed" } }
    local RANK = { open = 1, accepted = 2, mats = 3, done = 4 }
    local function progress(o)
        local state, out = O.StateOf(o), {}
        local at = RANK[state]
        for i, s in ipairs(STEPS) do
            if not (s[1] == "mats" and o.mode == "own") then
                local hex = not at and GRAY or (i < at and GREEN) or (i == at and GOLD) or GRAY
                out[#out + 1] = color(hex, s[2])
            end
        end
        local line = table.concat(out, color(GRAY, "  ›  "))
        if not at then line = line .. "   " .. stateText(o) end
        return line
    end

    showOrder = function(o)
        selectedRecipe, selectedOrder = nil, o
        browse:Hide(); detail:Show(); form:Hide(); clearActions()
        icon:SetTexture(itemIcon(o.item))
        hover.item = o.item
        heading:SetText(qualityName(o.item) .. color(GRAY, "  ×" .. o.n))
        subline:SetText(stateText(o))
        local me = O:MyKey()
        local roster = D.Roster()
        local crafter = o.cr and memberName(o.cr, roster)
            or (o.to and (memberName(o.to, roster) .. color(GRAY, " (asked)")) or color(GRAY, "Any guild crafter"))
        local lines = {
            progress(o),
            "",
            section("Requested by") .. "   " .. memberName(o.who, roster),
            section("Crafter") .. "   " .. crafter,
            section("Materials") .. "   " .. (o.mode == "own" and "The crafter uses their own" or "The requester brings them"),
            section("Tip") .. "   " .. ((o.tip or 0) > 0 and GetCoinTextureString(o.tip) or color(GRAY, "None")),
        }
        if o.note then lines[#lines + 1] = section("Note") .. "   " .. o.note end
        if o.mode ~= "own" then
            lines[#lines + 1] = ""
            lines[#lines + 1] = section("Reagents")
            lines[#lines + 1] = reagentLines(O:Needs(o))
        end
        if o.cr or o.who ~= me then
            lines[#lines + 1] = ""
            lines[#lines + 1] = color(GRAY, "Trade or mail each other to deliver: the bar on the trade and mail windows fills them in.")
        end
        describeDetail(table.concat(lines, "\n"), 42)
        local state = O.StateOf(o)
        local function act(label, verb) action(label, function() O:Act(o.id, verb); showOrder(o) end) end
        if state == "open" and o.who ~= me and (o.to == me or not o.to) and O:CanCraft(o.item) then act("Accept", "accept") end
        if state == "open" and o.to == me then act("Decline", "decline") end
        if (state == "accepted" or state == "mats") and (o.who == me or o.cr == me) then
            if state == "accepted" and o.mode == "mats" then act("Materials sent", "mats") end
            act("Complete", "done")
            if o.cr == me then act("Release", "release") end
        end
        if o.who == me and O.IsActive(o) then act("Cancel order", "cancel") end
    end

    -- Item names and qualities arrive after the first draw: redraw what is on screen, once.
    local pendingNames
    local names = CreateFrame("Frame", nil, page)
    names:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    names:SetScript("OnEvent", function()
        if pendingNames or not page:IsVisible() then return end
        pendingNames = true
        C_Timer.After(0.2, function()
            pendingNames = false
            if browse:IsShown() then listing.Redraw()
            elseif selectedOrder then showOrder(selectedOrder)
            elseif selectedRecipe then recipeDetail() end
        end)
    end)

    function page:List() selectTab(mode) end
    craft.ResetPage = function() if page:IsVisible() then page:List() end end
    O.uiRefresh = function()
        if not page:IsVisible() then return end
        if selectedOrder then showOrder(selectedOrder)
        elseif selectedRecipe then recipeDetail()
        elseif browse:IsShown() then render(false)
        else updateBadge() end
    end
    selectTab(1)
end
