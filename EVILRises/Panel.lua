local _, addon = ...

local panel

local function createPanel()
    local frame = CreateFrame("Frame", "EVILRisesPanel", UIParent, "BackdropTemplate")
    frame:SetSize(336, 320)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.06, 0.10, 0.08, 0.98)
    frame:SetBackdropBorderColor(0.38, 0.46, 0.28, 1)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    tinsert(UISpecialFrames, frame:GetName())

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetTextColor(0.85, 0.91, 0.36)
    title:SetText(addon.title)

    local guildName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    guildName:SetPoint("TOP", title, "BOTTOM", 0, -7)
    guildName:SetText(addon.guildName)

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOP", guildName, "BOTTOM", 0, -14)
    logo:SetSize(192, 192)
    logo:SetTexture(addon.iconTexture)

    local loginMessage = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    loginMessage:SetPoint("BOTTOMLEFT", 16, 13)
    loginMessage:SetChecked(addon.settings.showLoginMessage)
    loginMessage:SetScript("OnClick", function(self)
        addon.settings.showLoginMessage = not not self:GetChecked()
    end)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", loginMessage, "RIGHT", 3, 0)
    label:SetText("Show a message on login")

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("BOTTOMRIGHT", -16, 23)
    version:SetText("v" .. addon.version)

    return frame
end

function addon.TogglePanel()
    if not panel then
        panel = createPanel()
    elseif panel:IsShown() then
        panel:Hide()
        return
    end
    panel:Show()
end
