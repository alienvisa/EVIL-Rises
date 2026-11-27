local _, addon = ...
----------------------------------------------------------------------
-- EVIL Rises debug log
--
-- The last LIMIT addon events, kept from login so the window shows what happened before it
-- opened. Sync traffic is tagged In (from a guildmate), Out (sent to the guild) or Drop (a
-- message this client ignored, and why). /evil debug opens the window.
--
--   addon.Log(category, format, ...)                 an addon event
--   addon.LogSync("in"|"out"|"drop", category, format, ...)   a sync message
----------------------------------------------------------------------
local LIMIT = 500
local MAX_TEXT = 400
local entries, first, count = {}, 1, 0
local paused, syncOnly = false, false
local frame, output, copyScroll, copyBox, status, pauseButton, copyButton

local DIRECTIONS = {
    ["in"] = { tag = "In", color = "ff66dd66" },
    out = { tag = "Out", color = "ff66ccff" },
    drop = { tag = "Drop", color = "ffff9933" },
}

local function compose(fmt, ...)
    local n = select("#", ...)
    local text = tostring(fmt)
    if n > 0 then
        local args = { ... }
        for i = 1, n do
            if type(args[i]) ~= "number" then args[i] = tostring(args[i]) end
        end
        local ok, formatted = pcall(string.format, text, unpack(args, 1, n))
        if ok then text = formatted end
    end
    return (text:gsub("%c+", " "):sub(1, MAX_TEXT))
end

local function prefix(entry)
    local dir = DIRECTIONS[entry.dir]
    return entry.cat .. (dir and (" " .. dir.tag) or "")
end

-- A line as the window shows it: the tag colored by direction, and | escaped so a message
-- cannot draw textures or links.
local function display(entry)
    local tag = "[" .. prefix(entry) .. "]"
    local dir = DIRECTIONS[entry.dir]
    if dir then tag = "|c" .. dir.color .. tag .. "|r" end
    return entry.time .. "  " .. tag .. "  " .. entry.text:gsub("|", "||")
end

local function plain(entry)
    return entry.time .. "  [" .. prefix(entry) .. "]  " .. entry.text
end

local function visible(entry)
    return not syncOnly or entry.dir ~= nil
end

local function each(fn)
    for i = 1, count do fn(entries[(first + i - 2) % LIMIT + 1]) end
end

local function updateStatus()
    if not frame then return end
    status:SetText((paused and "Paused" or "Recording") .. "  ·  " .. count .. "/" .. LIMIT)
    pauseButton:SetText(paused and "Resume" or "Pause")
end

local function record(dir, cat, fmt, ...)
    if paused then return end
    local entry = { time = date("%H:%M:%S"), dir = dir, cat = tostring(cat), text = compose(fmt, ...) }
    entries[(first + count - 1) % LIMIT + 1] = entry
    if count == LIMIT then first = first % LIMIT + 1 else count = count + 1 end
    if frame and frame:IsShown() then
        if visible(entry) then output:AddMessage(display(entry)) end
        updateStatus()
    end
end

function addon.Log(cat, fmt, ...) record(nil, cat, fmt, ...) end
function addon.LogSync(dir, cat, fmt, ...) record(DIRECTIONS[dir] and dir or nil, cat, fmt, ...) end

local debug = {}
addon.DebugLog = debug

-- The recorded lines, oldest first, without color codes.
function debug.Lines()
    local out = {}
    each(function(entry) out[#out + 1] = plain(entry) end)
    return out
end

function debug.Clear()
    entries, first, count = {}, 1, 0
    if output then output:Clear() end
    updateStatus()
end

local function report()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("EVILRises", "Version") or "?"
    local game, build = GetBuildInfo()
    local lines = debug.Lines()
    table.insert(lines, 1, string.format("EVIL Rises %s  ·  WoW %s (%s)", version, tostring(game), tostring(build)))
    return table.concat(lines, "\n")
end

local function replay()
    output:Clear()
    each(function(entry) if visible(entry) then output:AddMessage(display(entry)) end end)
end

local function showLog()
    copyScroll:Hide()
    copyBox:ClearFocus()
    output:Show()
    copyButton:SetText("Copy log")
end

local function showCopy()
    output:Hide()
    copyScroll:Show()
    copyBox:SetText(report())
    copyBox:SetCursorPosition(0)
    copyBox:HighlightText()
    copyBox:SetFocus()
    copyButton:SetText("Back")
end

local function button(text, width)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function build()
    frame = CreateFrame("Frame", "EVILRisesDebugWindow", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(680, 380)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("EVIL Rises debug log")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("RIGHT", close, "LEFT", -4, 0)

    output = CreateFrame("ScrollingMessageFrame", nil, frame)
    output:SetPoint("TOPLEFT", 12, -36)
    output:SetPoint("BOTTOMRIGHT", -12, 44)
    output:SetFontObject(GameFontHighlightSmall)
    output:SetJustifyH("LEFT")
    output:SetFading(false)
    output:SetMaxLines(LIMIT)
    output:EnableMouseWheel(true)
    output:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        elseif delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)

    -- Copy view: the whole log, selected, in an edit box the player can Ctrl+C from.
    copyScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    copyScroll:SetPoint("TOPLEFT", 12, -36)
    copyScroll:SetPoint("BOTTOMRIGHT", -32, 44)
    copyScroll:Hide()
    copyBox = CreateFrame("EditBox", nil, copyScroll)
    copyBox:SetMultiLine(true)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject(GameFontHighlightSmall)
    copyBox:SetWidth(620)
    copyBox:SetScript("OnEscapePressed", showLog)
    copyScroll:SetScrollChild(copyBox)
    copyScroll:SetScript("OnSizeChanged", function(_, width) copyBox:SetWidth(math.max(1, width)) end)

    pauseButton = button("Pause", 82)
    pauseButton:SetPoint("BOTTOMLEFT", 12, 12)
    pauseButton:SetScript("OnClick", function()
        if paused then
            paused = false
            addon.Log("Debug", "Recording resumed")
        else
            addon.Log("Debug", "Recording paused")
            paused = true
        end
        updateStatus()
    end)
    copyButton = button("Copy log", 88)
    copyButton:SetPoint("LEFT", pauseButton, "RIGHT", 6, 0)
    copyButton:SetScript("OnClick", function()
        if copyScroll:IsShown() then showLog() else showCopy() end
    end)
    local filter = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    filter:SetSize(24, 24)
    filter:SetPoint("LEFT", copyButton, "RIGHT", 10, 0)
    filter.Text:SetText("Sync only")
    filter:SetScript("OnClick", function(self)
        syncOnly = self:GetChecked() and true or false
        replay()
    end)
    local clear = button("Clear", 72)
    clear:SetPoint("BOTTOMRIGHT", -12, 12)
    clear:SetScript("OnClick", debug.Clear)

    frame:SetScript("OnShow", function()
        showLog()
        replay()
        updateStatus()
    end)
    table.insert(UISpecialFrames, "EVILRisesDebugWindow")
end

function debug.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("EVILRises", "Version")
    addon.Log("Addon", "EVIL Rises %s loaded", version or "?")
end)
