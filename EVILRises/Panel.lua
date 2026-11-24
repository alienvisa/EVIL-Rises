local _, addon = ...
local colors = addon.colors

local tabNames = { "Roster", "Raids", "Loot", "Professions", "Guild", "Alliances", "Recruitment", "Leadership", "Settings" }
local tabWidths = { Roster = 69, Raids = 58, Loot = 49, Professions = 94, Guild = 55, Alliances = 76, Recruitment = 103, Leadership = 92, Settings = 72 }
local minWidth, minHeight = 944, 420
local defaultWidth, defaultHeight = 1070, 620
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
    local frame = CreateFrame("Frame", "EVILRisesPanel", UIParent)
    frame:SetClipsChildren(true)
    addon.SetGuildWindowBackdrop(frame)
    frame:SetSize(defaultWidth, defaultHeight)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    tinsert(UISpecialFrames, frame:GetName())

    local settings = addon.settings
    local function fitScreen()
        local width, height = UIParent:GetSize()
        local scale = math.min(1, width / (minWidth + 30), height / (minHeight + 30))
        local maxWidth = math.max(minWidth, width / scale - 30)
        local maxHeight = math.max(minHeight, height / scale - 30)
        frame:SetScale(scale)
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
        frame:SetSize(
            math.max(minWidth, math.min(maxWidth, tonumber(settings.windowWidth) or defaultWidth)),
            math.max(minHeight, math.min(maxHeight, tonumber(settings.windowHeight) or defaultHeight))
        )
    end

    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 5, -5)
    titleBar:SetPoint("TOPRIGHT", -5, -5)
    titleBar:SetHeight(22)
    addon.SetGuildTitleBackdrop(titleBar)
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 52, 0)
    title:SetPoint("RIGHT", -52, 0)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    title:SetTextColor(unpack(colors.gold))
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnEnter", function(self)
        if title:IsTruncated() then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(title:GetText(), 1, 0.82, 0, 1, true)
            GameTooltip:Show()
        end
    end)
    titleBar:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetFrameLevel(titleBar:GetFrameLevel() + 1)
    close:SetScript("OnClick", function() frame:Hide() end)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetSize(18, 18)
    grip:SetFrameLevel(frame:GetFrameLevel() + 12)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForDrag("LeftButton")

    local resizing = false
    local function finishResize()
        if not resizing then return end
        frame:StopMovingOrSizing()
        resizing = false
        settings.windowWidth, settings.windowHeight = frame:GetSize()
    end
    grip:SetScript("OnDragStart", function()
        if settings.resizeLocked then return end
        resizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnDragStop", finishResize)
    grip:SetScript("OnHide", finishResize)
    frame:HookScript("OnHide", finishResize)

    local lock = CreateFrame("Button", nil, frame)
    lock:SetPoint("RIGHT", close, "LEFT", -3, 0)
    lock:SetSize(20, 20)
    lock:SetFrameLevel(close:GetFrameLevel())
    lock:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local lockIcon = lock:CreateTexture(nil, "ARTWORK")
    lockIcon:SetPoint("CENTER")
    lockIcon:SetSize(16, 16)
    local function updateLock()
        local locked = settings.resizeLocked == true
        frame:SetResizable(not locked)
        grip:SetShown(not locked)
        lockIcon:SetTexture("Interface\\AddOns\\" .. addon.folder .. "\\Textures\\" .. (locked and "ResizeLocked" or "ResizeUnlocked"))
    end
    local function showLockTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(settings.resizeLocked and "Unlock resizing" or "Lock resizing")
        GameTooltip:Show()
    end
    lock:SetScript("OnEnter", showLockTooltip)
    lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lock:SetScript("OnClick", function(self)
        finishResize()
        settings.resizeLocked = not settings.resizeLocked
        updateLock()
        showLockTooltip(self)
    end)
    updateLock()

    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", 13, -37)
    tabBar:SetPoint("TOPRIGHT", -13, -37)
    tabBar:SetHeight(30)

    local guildTab = CreateFrame("Frame", nil, tabBar, "BackdropTemplate")
    guildTab:SetPoint("BOTTOMLEFT")
    guildTab:SetSize(176, 24)
    addon.SetSurface(guildTab, colors.guild, colors.bronze)
    addon.AddSurfaceSheen(guildTab, 0.70, 0.75, 0.28, 0.15)
    local guildName = guildTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildName:SetPoint("LEFT", 8, 0)
    guildName:SetPoint("RIGHT", -8, 0)
    guildName:SetTextColor(unpack(colors.green))
    guildName:SetWordWrap(false)

    local body = addon.CreateInset(frame)
    body:SetPoint("TOPLEFT", 13, -67)
    body:SetPoint("BOTTOMRIGHT", -13, 19)

    local tabs, pages = {}, {}
    local activeTab
    local dragMarker = tabBar:CreateTexture(nil, "OVERLAY", nil, 7)
    dragMarker:SetSize(3, 27)
    dragMarker:SetColorTexture(0.80, 0.93, 0.25, 1)
    dragMarker:Hide()

    local order = loadTabOrder(addon.settings.tabOrder)
    addon.settings.tabOrder = order

    local function layoutTabs()
        -- Break the old chain before reordering so no tab anchors to itself indirectly.
        for _, button in pairs(tabs) do
            button:ClearAllPoints()
        end
        local previous = guildTab
        for _, name in ipairs(order) do
            local button = tabs[name]
            button:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 2, 0)
            previous = button
        end
    end

    local function selectTab(name)
        if activeTab then
            addon.SetGuildTabFocused(tabs[activeTab], false)
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
                local reset = addon.CreateThemeButton(page, "Reset tab order")
                reset:SetSize(140, 24)
                reset:SetPoint("TOPLEFT", 19, -52)
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
        addon.SetGuildTabFocused(tabs[name], true)
        layoutTabs()
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
        local button = addon.CreateGuildTab(tabBar, name, tabWidths[name])
        addon.SetGuildTabFocused(button, false)
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

    local function updateTitle(message)
        if IsInGuild() then
            local getMOTD = C_GuildInfo and C_GuildInfo.GetMOTD or GetGuildRosterMOTD
            if message == nil and getMOTD then message = getMOTD() end
            title:SetText(message and message:find("%S") and message or "No guild message of the day.")
        else
            title:SetText("")
        end
        guildName:SetText(GetGuildInfo("player") or addon.guildName)
    end

    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:RegisterEvent("GUILD_MOTD")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function(_, event, message)
        if event == "DISPLAY_SIZE_CHANGED" then
            finishResize()
            fitScreen()
        elseif event == "GUILD_MOTD" then
            updateTitle(message)
        else
            updateTitle()
        end
    end)
    frame:SetScript("OnShow", function() fitScreen(); updateTitle() end)
    frame:Hide()
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
