local _, addon = ...

local tabNames = { "Roster", "Raids", "Loot", "Professions", "Guild", "Alliances", "Recruitment", "Leadership", "Settings" }
local tabWidths = { Roster = 69, Raids = 58, Loot = 49, Professions = 94, Guild = 55, Alliances = 76, Recruitment = 103, Leadership = 92, Settings = 72 }
local panel

local function loadTabOrder(saved)
    local order, seen = {}, {}
    if type(saved) == "table" then
        for _, name in ipairs(saved) do
            if tabWidths[name] and not seen[name] then
                order[#order + 1], seen[name] = name, true
            end
        end
    end
    for _, name in ipairs(tabNames) do
        if not seen[name] then
            order[#order + 1] = name
        end
    end
    return order
end

function addon.SetWindowBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    frame:SetBackdropColor(0.60, 0.72, 0.52, 1)
    frame:SetBackdropBorderColor(0.80, 0.76, 0.56, 1)
end

local function settingsCheck(page, label, key, top)
    local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 16, top)
    local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 3, 0)
    text:SetText(label)
    check:SetChecked(addon.settings[key])
    check:SetScript("OnClick", function(self)
        addon.settings[key] = not not self:GetChecked()
    end)
end

local function createPanel()
    local frame = CreateFrame("Frame", "EVILRisesPanel", UIParent, "BackdropTemplate")
    frame:SetSize(1070, 620)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    addon.SetWindowBackdrop(frame)
    tinsert(UISpecialFrames, frame:GetName())

    local function fitScreen()
        frame:SetScale(math.min(1, UIParent:GetWidth() / 1100, UIParent:GetHeight() / 650))
    end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 13, -9)
    titleBar:SetPoint("TOPRIGHT", -36, -9)
    titleBar:SetHeight(34)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 8, 0)
    title:SetTextColor(0.88, 0.94, 0.43)
    title:SetText(addon.title)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", 17, -47)
    tabBar:SetPoint("TOPRIGHT", -17, -47)
    tabBar:SetHeight(30)

    local guildTab = CreateFrame("Frame", nil, tabBar, "BackdropTemplate")
    guildTab:SetPoint("LEFT")
    guildTab:SetSize(184, 26)
    guildTab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    guildTab:SetBackdropColor(0.18, 0.23, 0.09, 0.85)
    local guildName = guildTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildName:SetPoint("LEFT", 8, 0)
    guildName:SetPoint("RIGHT", -8, 0)
    guildName:SetTextColor(0.88, 0.94, 0.43)
    guildName:SetWordWrap(false)

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 17, -88)
    body:SetPoint("BOTTOMRIGHT", -17, 17)

    local tabs, pages = {}, {}
    local activeTab
    local dragMarker = tabBar:CreateTexture(nil, "OVERLAY", nil, 7)
    dragMarker:SetSize(3, 27)
    dragMarker:SetColorTexture(0.80, 0.93, 0.25, 1)
    dragMarker:Hide()

    local order = loadTabOrder(addon.settings.tabOrder)
    addon.settings.tabOrder = order

    local function layoutTabs()
        local previous = guildTab
        for _, name in ipairs(order) do
            local button = tabs[name]
            button:ClearAllPoints()
            button:SetPoint("LEFT", previous, "RIGHT", 3, 0)
            previous = button
        end
    end

    local function selectTab(name)
        if activeTab then
            tabs[activeTab]:UnlockHighlight()
            pages[activeTab]:Hide()
        end
        activeTab = name
        if not pages[name] then
            local page = CreateFrame("Frame", nil, body)
            page:SetAllPoints()
            pages[name] = page
            if name == "Roster" then
                addon.CreateRoster(page)
            elseif name == "Settings" then
                settingsCheck(page, "Show a message on login", "showLoginMessage", -8)
                local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
                reset:SetSize(140, 24)
                reset:SetPoint("TOPLEFT", 19, -52)
                reset:SetText("Reset tab order")
                reset:SetScript("OnClick", function()
                    order = loadTabOrder()
                    addon.settings.tabOrder = order
                    layoutTabs()
                end)
            else
                local label = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                label:SetPoint("TOPLEFT", 18, -14)
                label:SetText(name .. " is planned for a later build.")
            end
        end
        tabs[name]:LockHighlight()
        pages[name]:Show()
    end

    local function dropIndex(dragged)
        local cursorX = GetCursorPosition() / frame:GetEffectiveScale()
        local count = 1
        for _, name in ipairs(order) do
            if name ~= dragged then
                if cursorX < tabs[name]:GetCenter() then
                    return count, tabs[name], "LEFT", -2
                end
                count = count + 1
            end
        end
        return count, tabs[order[#order]], "RIGHT", 2
    end

    for _, name in ipairs(tabNames) do
        local button = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
        button:SetSize(tabWidths[name], 25)
        button:SetText(name)
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnClick", function() if not button.dragging then selectTab(name) end end)
        button:SetScript("OnDragStart", function()
            button.dragging = true
            button:SetScript("OnUpdate", function()
                local _, neighbor, side, offset = dropIndex(name)
                dragMarker:ClearAllPoints()
                dragMarker:SetPoint("CENTER", neighbor, side, offset, 0)
                dragMarker:Show()
            end)
        end)
        button:SetScript("OnDragStop", function()
            local index = dropIndex(name)
            for current, tabName in ipairs(order) do
                if tabName == name then
                    table.remove(order, current)
                    break
                end
            end
            table.insert(order, index, name)
            button:SetScript("OnUpdate", nil)
            dragMarker:Hide()
            layoutTabs()
            C_Timer.After(0, function() button.dragging = nil end)
        end)
        button:SetScript("OnHide", function()
            if button.dragging then
                button.dragging = nil
                button:SetScript("OnUpdate", nil)
                dragMarker:Hide()
            end
        end)
        tabs[name] = button
    end

    local function updateTitle()
        guildName:SetText(GetGuildInfo("player") or addon.guildName)
    end

    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function(_, event)
        if event == "DISPLAY_SIZE_CHANGED" then fitScreen() else updateTitle() end
    end)
    frame:SetScript("OnShow", function() fitScreen(); updateTitle() end)
    frame:Hide()
    layoutTabs()
    selectTab("Roster")
    return frame
end

function addon.ShowPanel()
    if not panel then
        panel = createPanel()
    end
    panel:Show()
end

function addon.TogglePanel()
    if panel and panel:IsShown() then
        panel:Hide()
    else
        addon.ShowPanel()
    end
end
