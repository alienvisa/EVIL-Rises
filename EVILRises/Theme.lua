local _, addon = ...

local white = "Interface\\Buttons\\WHITE8X8"
local rock = "Interface\\FrameGeneral\\UI-Background-Rock"
local colors = {
    window = { 0.135, 0.132, 0.106, 1 },
    panel = { 0.069, 0.063, 0.052, 1 },
    row = { 0.035, 0.031, 0.023, 0.56 },
    alternateRow = { 0.19, 0.16, 0.11, 0.32 },
    bronze = { 0.42, 0.32, 0.19, 1 },
    brass = { 0.67, 0.48, 0.23, 1 },
    trim = { 0.33, 0.31, 0.25, 1 },
    gold = { 0.94, 0.78, 0.39 },
    green = { 0.76, 0.84, 0.37 },
    guild = { 0.15, 0.17, 0.075, 1 },
    control = { 0.112, 0.104, 0.081, 1 },
    selected = { 0.185, 0.192, 0.092, 1 },
}
addon.colors = colors

local function setOpaqueFill(frame, color)
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetAllPoints()
    fill:SetColorTexture(unpack(color))
end

function addon.SetGuildWindowBackdrop(frame)
    -- All art stays inside the resize frame. The solid layers keep it opaque.
    setOpaqueFill(frame, colors.brass)
    local trim = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    trim:SetPoint("TOPLEFT", 1, -1)
    trim:SetPoint("BOTTOMRIGHT", -1, 1)
    trim:SetColorTexture(unpack(colors.bronze))
    local interior = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    interior:SetPoint("TOPLEFT", 3, -3)
    interior:SetPoint("BOTTOMRIGHT", -3, 3)
    interior:SetColorTexture(unpack(colors.window))

    local grain = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    grain:SetPoint("TOPLEFT", 3, -3)
    grain:SetPoint("BOTTOMRIGHT", -3, 3)
    grain:SetTexture(rock, "REPEAT", "REPEAT")
    grain:SetHorizTile(true)
    grain:SetVertTile(true)
    grain:SetVertexColor(0.87, 0.81, 0.72, 0.88)

    local rim = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rim:SetFrameLevel(frame:GetFrameLevel())
    rim:SetPoint("TOPLEFT", 1, -1)
    rim:SetPoint("BOTTOMRIGHT", -1, 1)
    rim:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 14 })
    rim:SetBackdropBorderColor(0.86, 0.72, 0.48, 1)
end

function addon.SetWindowBackdrop(frame)
    setOpaqueFill(frame, colors.window)
    local grain = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    grain:SetPoint("TOPLEFT", 5, -5)
    grain:SetPoint("BOTTOMRIGHT", -5, 5)
    grain:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background", "REPEAT", "REPEAT")
    grain:SetHorizTile(true)
    grain:SetVertTile(true)
    grain:SetVertexColor(0.93, 0.86, 0.69, 0.45)
    frame:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
    })
    frame:SetBackdropBorderColor(unpack(colors.brass))
end

function addon.CreateInset(parent)
    local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    setOpaqueFill(inset, colors.panel)
    inset.Bg:Hide()
    local grain = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
    grain:SetPoint("TOPLEFT", 3, -3)
    grain:SetPoint("BOTTOMRIGHT", -3, 3)
    grain:SetAtlas("collections-background-tile")
    grain:SetHorizTile(true)
    grain:SetVertTile(true)
    grain:SetVertexColor(0.42, 0.39, 0.31, 0.85)
    return inset
end

local function setSheen(texture, r, g, b, alpha)
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, alpha))
end

function addon.SetSurface(frame, color, edge)
    frame:SetBackdrop({ bgFile = white, edgeFile = white, edgeSize = 1 })
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(edge))
end

function addon.SetGuildTitleBackdrop(frame)
    addon.SetSurface(frame, colors.control, colors.bronze)
    local art = frame:CreateTexture(nil, "BORDER")
    art:SetPoint("TOPLEFT", 1, -1)
    art:SetPoint("BOTTOMRIGHT", -1, 1)
    art:SetAtlas("_UI-Frame-TitleTileBg")
    art:SetHorizTile(true)
end

function addon.AddSurfaceSheen(frame, r, g, b, alpha)
    local sheen = frame:CreateTexture(nil, "BORDER", nil, 2)
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("BOTTOMRIGHT", -1, 1)
    setSheen(sheen, r, g, b, alpha)
    return sheen
end

function addon.SetControlSelected(button, selected)
    button:SetBackdropColor(unpack(selected and colors.selected or colors.control))
    button:SetBackdropBorderColor(unpack(selected and colors.brass or colors.bronze))
    button:GetFontString():SetTextColor(unpack(selected and colors.green or colors.gold))
    if selected then
        setSheen(button.sheen, 0.70, 0.75, 0.28, 0.22)
    else
        setSheen(button.sheen, 0.90, 0.67, 0.35, 0.11)
    end
end

function addon.CreateThemeButton(parent, text)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetText(text)
    addon.SetSurface(button, colors.control, colors.bronze)
    button.sheen = addon.AddSurfaceSheen(button, 0.90, 0.67, 0.35, 0.11)
    addon.SetControlSelected(button, false)

    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", -1, 1)
    hover:SetColorTexture(1, 0.83, 0.49, 0.10)
    return button
end

function addon.CreateGuildTab(parent, text, width)
    local tab = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
    tab:SetText(text)
    PanelTemplates_TabResize(tab, 0, width)
    return tab
end

function addon.SetGuildTabFocused(tab, focused)
    if focused then
        PanelTemplates_SelectTab(tab)
        -- The selected tab still needs mouse input for drag reordering.
        tab:Enable()
        tab:SetNormalFontObject(GameFontHighlightSmall)
    else
        PanelTemplates_DeselectTab(tab)
        tab:SetNormalFontObject(GameFontNormalSmall)
    end
end

function addon.CreateRosterHeader(parent, text)
    local header = CreateFrame("Button", nil, parent)
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    header:SetFontString(label)
    header:SetText(text)

    local shade = header:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0.045, 0.035, 0.025, 0.75)

    header.rule = header:CreateTexture(nil, "BORDER")
    header.rule:SetPoint("BOTTOMLEFT")
    header.rule:SetPoint("BOTTOMRIGHT")
    header.rule:SetHeight(1)
    header.sheen = addon.AddSurfaceSheen(header, 1, 0.73, 0.17, 0.22)

    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 0.82, 0.40, 0.10)
    return header
end

function addon.SetRosterHeaderSelected(header, selected)
    header.sheen:SetShown(selected)
    if selected then
        header.rule:SetColorTexture(1, 0.77, 0.12, 1)
        header:GetFontString():SetTextColor(1, 0.94, 0.76)
    else
        header.rule:SetColorTexture(0.55, 0.39, 0.11, 0.68)
        header:GetFontString():SetTextColor(1, 0.82, 0)
    end
end
