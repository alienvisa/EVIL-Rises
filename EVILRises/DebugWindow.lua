local _, addon = ...
local engine = EVRFeatures
local debugWindow = { capturing = false }
engine.DebugWindow = debugWindow

local limit, lines, oldest, count = 200, {}, 1, 0
local frame, output, pause, status
local function updateStatus()
    status:SetText((debugWindow.capturing and "Recording" or "Paused") .. "  ·  " .. count .. "/" .. limit)
    pause:SetText(debugWindow.capturing and "Pause" or "Resume")
end

function debugWindow:Record(category, message, when)
    if not self.capturing then return end
    local text = tostring(message):gsub("[%c]+", " "):sub(1, 450)
    local line = date("%H:%M:%S", when or GetServerTime()) .. "  [" .. category .. "]  " .. text
    lines[(oldest + count - 1) % limit + 1] = line
    if count == limit then oldest = oldest % limit + 1 else count = count + 1 end
    output:AddMessage((line:gsub("|", "||")))
    updateStatus()
end

local types = { HD = "summary", HN = "snapshot request", HM = "missing update request",
    HV = "officer summary", BC = "roster", RQ = "catch-up request", SV = "feature update",
    RD = "raid snapshot", RI = "recruitment", MP = "map position" }

function debugWindow:Packet(direction, kind, channel, peer, bytes)
    local label = types[kind] or kind
    self:Record("Sync", string.format("%s %s  ·  %s%s  ·  %d bytes", direction, label,
        channel, peer and ("  ·  " .. peer) or "", bytes))
end

local function report()
    local version, build = GetBuildInfo()
    local result = { string.format("EVIL Rises %s | WoW %s (%s)", addon.version, version, build) }
    for i = 1, count do result[#result + 1] = lines[(oldest + i - 2) % limit + 1] end
    return table.concat(result, "\n")
end

local function build()
    frame = CreateFrame("Frame", "EVILRisesDebugWindow", UIParent)
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(math.min(630, UIParent:GetWidth()), math.min(345, UIParent:GetHeight()))
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    addon.SetGuildWindowBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("EVIL Rises  ·  Debug")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("RIGHT", close, "LEFT", -4, 0)

    local inset = addon.CreateInset(frame)
    inset:SetPoint("TOPLEFT", 9, -35)
    inset:SetPoint("BOTTOMRIGHT", -9, 43)
    output = CreateFrame("ScrollingMessageFrame", nil, inset)
    output:SetPoint("TOPLEFT", 7, -6)
    output:SetPoint("BOTTOMRIGHT", -7, 6)
    output:SetFontObject(GameFontHighlightSmall)
    output:SetJustifyH("LEFT")
    output:SetFading(false)
    output:SetMaxLines(limit)
    output:EnableMouseWheel(true)
    output:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)

    pause = addon.CreateThemeButton(frame, "Pause")
    pause:SetSize(82, 24)
    pause:SetPoint("BOTTOMLEFT", 12, 11)
    pause:SetScript("OnClick", function()
        if debugWindow.capturing then
            debugWindow:Record("Debug", "Capture paused")
            debugWindow.capturing = false
        else
            debugWindow.capturing = true
            debugWindow:Record("Debug", "Capture resumed")
        end
        updateStatus()
    end)
    local copy = addon.CreateThemeButton(frame, "Copy log")
    copy:SetSize(88, 24)
    copy:SetPoint("LEFT", pause, "RIGHT", 6, 0)
    copy:SetScript("OnClick", function() engine:ShowExportPopup("EVIL Rises debug log", report()) end)
    local clear = addon.CreateThemeButton(frame, "Clear")
    clear:SetSize(72, 24)
    clear:SetPoint("BOTTOMRIGHT", -12, 11)
    clear:SetScript("OnClick", function()
        lines, oldest, count = {}, 1, 0
        output:Clear()
        updateStatus()
    end)
    frame:SetScript("OnHide", function() debugWindow.capturing = false end)
    table.insert(UISpecialFrames, frame:GetName())
end

function debugWindow:Open()
    local first = not frame
    if first then build() end
    if frame:IsShown() then frame:Raise(); return end
    frame:Show()
    self.capturing = true
    if first then
        for _, err in ipairs(engine.State.errors) do self:Record("Earlier error", err.msg, err.when) end
    end
    local ready = engine.CommSystem.listening and engine:IsOnGuildDB() and engine:IsFeatureEnabled("commSystem")
    self:Record("Debug", "Capture started  ·  v" .. addon.version .. "  ·  Guild sync " .. (ready and "ready" or "inactive"))
end
