local _, addon = ...
local engine = EVRFeatures
local board = {}
engine.Bounty = board
local limit = 20
local modes = { kos = "Kill on sight", camp = "Camp", both = "Kill on sight + camp" }

local function owner(name)
    return engine:KeyOfRosterName(name or engine.Compat.PlayerName())
end

local function records()
    if not engine.db or not engine:IsOnGuildDB() then return end
    engine.db.bounties = engine.db.bounties or {}
    return engine.db.bounties
end

local function clean(s, size)
    if type(s) ~= "string" then return "" end
    return engine:SanitizeUserText(s, size)
end

local function refresh()
    if board.page and board.page:IsVisible() then board.page:Refresh() end
end

function board:Broadcast()
    local data = records()
    local sheet = data and data[owner()]
    if sheet then engine.SyncService:Publish("bounty", "board", sheet) end
end

local function save(key, sheet)
    sheet.rev = math.max(GetServerTime(), sheet.rev + 1)
    records()[key] = sheet
    board:Broadcast()
    refresh()
end

local function validCopper(amount)
    return type(amount) == "number" and amount >= 1 and amount <= 999999999999
        and amount == math.floor(amount)
end

local function money(amount)
    return string.format("%dg %ds %dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

local function readUnit(unit)
    if not unit or not UnitIsPlayer(unit) then return end
    local name = GetUnitName(unit, true)
    if not name or name == "" then return end
    return { name = name, class = UnitClass(unit), faction = UnitFactionGroup(unit) }
end

local function matchName(text)
    local wanted = clean(text, 72):lower()
    if wanted == "" then return end
    local function matches(name)
        if not name then return false end
        local full = name:lower()
        return wanted == full or wanted == full:match("^([^-]+)")
    end
    local function matchUnit(unit)
        if UnitExists(unit) and UnitIsPlayer(unit) and UnitIsConnected(unit)
            and matches(GetUnitName(unit, true)) then return readUnit(unit) end
    end
    for _, unit in ipairs({"target", "mouseover", "focus"}) do
        local info = matchUnit(unit)
        if info then return info end
    end
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local info = matchUnit((raid and "raid" or "party") .. i)
        if info then return info end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            if plate.namePlateUnitToken then
                local info = matchUnit(plate.namePlateUnitToken)
                if info then return info end
            end
        end
    end
    if C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo then
        for i = 1, C_FriendList.GetNumWhoResults() or 0 do
            local who = C_FriendList.GetWhoInfo(i)
            if who and matches(who.fullName) then
                return { name = who.fullName, class = who.classStr or who.filename }
            end
        end
    end
end

function board:Post(target, copper, reason, mode, faction, class)
    local data = records()
    if not data then return "Join a guild and reload to post a bounty." end
    target, reason = clean(target, 72), clean(reason, 180)
    if target == "" then return "Enter a bounty target name." end
    if not modes[mode] then return "Select Kill on sight, Camp, or both." end
    if not validCopper(copper) then return "Enter a reward of at least one copper." end
    if faction ~= "Alliance" and faction ~= "Horde" then return "Choose a faction." end
    local key = owner()
    local sheet = data[key] or { rev = 0, posts = {} }
    if #sheet.posts >= limit then return "Withdraw an open bounty before posting another." end
    table.insert(sheet.posts, 1, { target = target, reward = money(copper), copper = copper, class = clean(class, 40), reason = reason, mode = mode,
        faction = faction, time = GetServerTime() })
    save(key, sheet)
end

function board:Withdraw(post)
    local data = records()
    local key = owner()
    local sheet = data and data[key]
    if not sheet then return end
    for i, entry in ipairs(sheet.posts) do
        if entry == post then table.remove(sheet.posts, i); save(key, sheet); return end
    end
end

function board:Initialize()
    engine.SyncService:On("bounty", function(env, sender)
        local data, sheet = records(), env.data
        if not data or env.act ~= "board" or type(sheet) ~= "table" or type(sender) ~= "string" then return end
        local key = owner(sender)
        local rev = sheet.rev
        if not key or key == owner() or type(rev) ~= "number" or rev ~= math.floor(rev)
            or rev <= 0 or rev > GetServerTime() + 86400 or type(sheet.posts) ~= "table"
            or #sheet.posts > limit or (data[key] and data[key].rev >= rev) then return end
        local posts = {}
        for _, p in ipairs(sheet.posts) do
            if type(p) ~= "table" or not modes[p.mode] or (p.faction ~= "Horde" and p.faction ~= "Alliance")
                or type(p.time) ~= "number" or not (p.time > 0 and p.time <= rev) then return end
            local target, reward = clean(p.target, 72), clean(p.reward, 64)
            local copper = validCopper(p.copper) and p.copper or nil
            if copper then reward = money(copper) end
            if target == "" or reward == "" then return end
            posts[#posts + 1] = { target = target, reward = reward, reason = clean(p.reason, 180),
                faction = p.faction, mode = p.mode, time = p.time, copper = copper, class = clean(p.class, 40) }
        end
        data[key] = { rev = rev, posts = posts }
        refresh()
    end)
end

function board:BuildPage(page)
    self.page = page
    local function label(parent, text, x, y, font)
        local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end
    local function field(caption, x, y, width, max)
        label(page, caption, x, y)
        local input = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", x + 4, y - 18)
        input:SetSize(width, 22)
        input:SetMaxBytes(max)
        input:SetAutoFocus(false)
        input:SetScript("OnEscapePressed", input.ClearFocus)
        return input
    end
    local name = field("Bounty Target Name", 10, -8, 195, 72)
    local gold = field("Gold", 235, -8, 80, 8)
    local silver = field("Silver", 333, -8, 42, 2)
    local copper = field("Copper", 394, -8, 42, 2)
    for _, box in ipairs({gold, silver, copper}) do box:SetNumeric(true) end
    local reason = field("Reason (optional)", 10, -58, 428, 180)
    local function check(text, x)
        local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", x, -24)
        box:SetSize(24, 24)
        label(box, text, 26, -5)
        return box
    end
    local kos, camp = check(modes.kos, 475), check(modes.camp, 610)
    kos:SetChecked(true)
    local status = label(page, "", 10, -110, "GameFontHighlightSmall")
    local function button(text, x, y, width, onClick)
        local b = addon.CreateThemeButton(page, text)
        b:SetPoint("TOPLEFT", x, y)
        b:SetSize(width, 23)
        b:SetScript("OnClick", onClick)
    end
    local faction, class
    local classLabel = label(page, "", 695, -88, "GameFontHighlightSmall")
    label(page, "Faction", 700, -8)
    local factionButton = addon.CreateThemeButton(page, "")
    factionButton:SetPoint("TOPLEFT", 700, -26)
    factionButton:SetSize(100, 22)
    local function setFaction(value)
        faction = value
        factionButton:SetText(faction or "Choose faction")
    end
    local function defaultFaction()
        return UnitFactionGroup("player") == "Alliance" and "Horde" or "Alliance"
    end
    setFaction(defaultFaction())
    local resolvedName
    function page:FillTarget(info)
        name:SetText(info.name)
        resolvedName = info.name
        class = clean(info.class, 40)
        classLabel:SetText(class)
        if info.faction == "Alliance" or info.faction == "Horde" then setFaction(info.faction) end
        status:SetText("")
    end
    name:SetScript("OnTextChanged", function()
        resolvedName, class = nil, nil
        classLabel:SetText("")
    end)
    local function resolve()
        if name:GetText() ~= resolvedName then
            local info = matchName(name:GetText())
            if info then page:FillTarget(info); status:SetText("Matched player: " .. info.name) end
        end
    end
    factionButton:SetScript("OnClick", function()
        resolve()
        setFaction(faction == "Alliance" and "Horde" or "Alliance")
    end)
    name:SetScript("OnEditFocusLost", resolve)
    name:SetScript("OnEnterPressed", name.ClearFocus)
    button("Use target", 470, -75, 102, function()
        local info = readUnit("target")
        if info then page:FillTarget(info) else status:SetText("Select a player first.") end
    end)
    button("Post bounty", 580, -75, 104, function()
        resolve()
        local mode = kos:GetChecked() and (camp:GetChecked() and "both" or "kos") or (camp:GetChecked() and "camp")
        local amount = gold:GetNumber()*10000 + silver:GetNumber()*100 + copper:GetNumber()
        local err = board:Post(name:GetText(), amount, reason:GetText(), mode, faction, class)
        status:SetText(err or "Bounty posted.")
        if not err then
            for _, box in ipairs({name, gold, silver, copper, reason}) do box:SetText(""); box:ClearFocus() end
            setFaction(defaultFaction())
        end
    end)
    local scroll, child = engine.UI:CreateScrollFrame(page, "EVILRisesBountyScroll")
    scroll:SetPoint("TOPLEFT", 7, -133)
    scroll:SetPoint("BOTTOMRIGHT", -27, 7)
    local empty = label(child, "No open bounties.", 6, -4, "GameFontDisable")
    local rows = {}
    local function createRow(i)
        local row = CreateFrame("Frame", nil, child)
        row:SetPoint("TOPLEFT", 0, -(i-1)*58)
        row:SetPoint("TOPRIGHT", 0, -(i-1)*58)
        row:SetHeight(58)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(unpack(i%2==1 and addon.colors.row or addon.colors.alternateRow))
        local function line(y, font)
            local fs = label(row, "", 6, y, font)
            fs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -90, y)
            fs:SetJustifyH("LEFT")
            return fs
        end
        row.title = line(-3, "GameFontNormal")
        row.meta = line(-20, "GameFontHighlightSmall")
        row.reason = line(-34, "GameFontHighlightSmall")
        row.withdraw = addon.CreateThemeButton(row, "Withdraw")
        row.withdraw:SetSize(76, 22)
        row.withdraw:SetPoint("RIGHT", -5, 0)
        row.withdraw:SetScript("OnClick", function() board:Withdraw(row.post) end)
        return row
    end
    function page:Refresh()
        local list = {}
        for author, sheet in pairs(records() or {}) do
            for index, post in ipairs(sheet.posts) do list[#list+1] = {author=author, post=post, index=index} end
        end
        table.sort(list, function(a,b)
            if a.post.time ~= b.post.time then return a.post.time > b.post.time end
            if a.author ~= b.author then return a.author < b.author end
            return a.index < b.index
        end)
        empty:SetShown(#list == 0)
        child:SetHeight(math.max(23, #list*58))
        for i, item in ipairs(list) do
            local row = rows[i] or createRow(i)
            local p = item.post
            rows[i], row.post = row, p
            row.title:SetText(p.target .. " (" .. p.faction .. (p.class and p.class ~= "" and ", " .. p.class or "") .. ")  -  " .. modes[p.mode])
            row.meta:SetText("Reward: " .. p.reward .. "     Posted by: " .. item.author)
            row.reason:SetText(p.reason)
            row.withdraw:SetShown(item.author == owner())
            row:Show()
        end
        for i=#list+1,#rows do rows[i]:Hide() end
    end
    scroll:SetScript("OnSizeChanged", function(_, width) child:SetWidth(math.max(1,width)) end)
    page:SetScript("OnShow", page.Refresh)
    page:Refresh()
end

-- Capture the selected unit while its menu is being built. The target may change before the click.
if Menu and Menu.ModifyMenu then
    local function addEntry(_, root, context)
        if not engine.db or not engine:IsOnGuildDB() or not engine:IsFeatureEnabled("bounty") then return end
        local info = readUnit(context and context.unit)
        if info then
            root:CreateButton("Create bounty", function()
                if engine.UI:OpenWindow("bounty") and board.page then board.page:FillTarget(info) end
            end)
        end
    end
    for _, tag in ipairs({"TARGET", "PLAYER", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "FOCUS"}) do
        Menu.ModifyMenu("MENU_UNIT_" .. tag, addEntry)
    end
end
