local _, addon = ...

local slotNames = {
    "Head", "Neck", "Shoulders", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands",
    "Finger 1", "Finger 2", "Trinket 1", "Trinket 2", "Back", "Main hand", "Off hand", "Ranged", "Tabard",
}

local function matchingUnit(unit, guid)
    local unitGUID = UnitGUID(unit)
    return (not issecretvalue or not issecretvalue(unitGUID)) and unitGUID == guid
end

local function inspectableUnit(guid)
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do
        if matchingUnit(unit, guid) then return unit end
    end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for index = 1, count do
        local unit = prefix .. index
        if matchingUnit(unit, guid) then return unit end
    end
end

local function readGear(unit)
    local items = {}
    for index, slot in ipairs(slotNames) do
        local link = GetInventoryItemLink(unit, index)
        if link then
            local name = link:match("|h(.-)|h") or link
            items[#items + 1] = slot .. "  " .. name
        end
    end
    return #items > 0 and table.concat(items, "\n") or nil
end

function addon.CreateMemberTooltip(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPRIGHT", -2, -36)
    frame:SetPoint("BOTTOMRIGHT", -2, 2)
    frame:SetWidth(426)
    frame:SetFrameLevel(parent:GetFrameLevel() + 25)
    frame:EnableMouse(true)
    addon.SetWindowBackdrop(frame)
    frame:Hide()

    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 17, -13)
    name:SetPoint("RIGHT", -38, 0)
    name:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() frame:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -40)
    scroll:SetPoint("BOTTOMRIGHT", -31, 91)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(374, 1)
    scroll:SetScrollChild(child)

    local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT")
    text:SetPoint("TOPRIGHT")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetSpacing(3)

    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetPoint("BOTTOMLEFT", 23, 38)
    edit:SetSize(170, 24)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("BOTTOMLEFT", 18, 15)
    hint:SetPoint("RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")

    local function action(label, width)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(width, 23)
        button:SetText(label)
        return button
    end

    local link = action("Link alt", 66)
    link:SetPoint("LEFT", edit, "RIGHT", 5, 0)
    local unlink = action("Unlink", 62)
    unlink:SetPoint("LEFT", link, "RIGHT", 4, 0)
    local inspect = action("Inspect", 66)
    inspect:SetPoint("LEFT", unlink, "RIGHT", 4, 0)

    local roster, member
    local pending
    local gear, gearMessage

    local function display()
        local links = addon.GetAltLinks(roster)
        local mainID = links[member.id] or member.id
        local main = roster.byID[mainID]
        local characters = {}
        for id, root in pairs(links) do
            if root == mainID and roster.byID[id] then
                characters[#characters + 1] = roster.byID[id].name
            end
        end
        table.sort(characters)
        if #characters > 0 or links[member.id] then
            table.insert(characters, 1, (main and main.name or "Former member") .. " (main)")
        end
        unlink:SetEnabled(links[member.id] ~= nil)
        inspect:SetEnabled(not member.isPlayer and member.online and member.guid ~= nil and not pending)
        local lines = {
            string.format("Level %s %s  -  %s", member.level or "?", member.class or "Unknown class", member.rank or "Unknown rank"),
            "",
        }
        local function section(title, value, fallback)
            lines[#lines + 1] = "|cffffd100" .. title .. "|r"
            lines[#lines + 1] = value and value ~= "" and value or fallback
            lines[#lines + 1] = ""
        end
        section("Professions", table.concat(member.allProfessions, ", "), "Unavailable")
        section("Member note", member.note, "No note")
        if roster.canViewOfficerNote then
            section("Officer note", member.officerNote, "No note")
        end
        section("Linked characters", table.concat(characters, ", "), "No linked characters")
        section("Raid attendance", nil, "Tracking is not available yet.")
        section("Raid loot history", nil, "Tracking is not available yet.")
        section("Gear", gear, gearMessage or "Select a nearby guildmate and click Inspect.")
        text:SetText(table.concat(lines, "\n"))
        child:SetHeight(math.max(scroll:GetHeight(), text:GetStringHeight() + 4))
    end

    local function saveLink()
        local candidate = addon.FindRosterMember(roster, edit:GetText())
        local problem = addon.LinkRosterAlt(roster, member, candidate)
        if problem then
            hint:SetText(problem)
            return
        end
        edit:SetText("")
        edit:ClearFocus()
        hint:SetText("Alt linked on this account.")
        display()
    end
    link:SetScript("OnClick", saveLink)
    edit:SetScript("OnEnterPressed", saveLink)
    unlink:SetScript("OnClick", function()
        addon.GetAltLinks(roster)[member.id] = nil
        hint:SetText("Alt unlinked.")
        display()
    end)

    frame:RegisterEvent("INSPECT_READY")
    frame:SetScript("OnEvent", function(_, _, guid)
        if not pending or not member or guid ~= member.guid then
            return
        end
        local unit = pending.unit
        pending = nil
        gear = matchingUnit(unit, guid) and readGear(unit) or nil
        gearMessage = "Gear unavailable. Select the member and try again."
        display()
    end)

    inspect:SetScript("OnClick", function()
        if InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then
            gearMessage = "Inspect outside combat with Blizzard's Inspect window closed."
            display()
            return
        end
        local unit = inspectableUnit(member.guid)
        if not unit or not CanInspect(unit) or not CheckInteractDistance(unit, 1) then
            gearMessage = "Select a nearby guildmate and try again."
            display()
            return
        end
        local request = { unit = unit }
        pending, gear, gearMessage = request, nil, "Inspecting..."
        display()
        NotifyInspect(unit)
        C_Timer.After(5, function()
            if pending == request then
                pending, gearMessage = nil, "No inspect data received. Try again."
                display()
            end
        end)
    end)

    frame:SetScript("OnHide", function()
        pending = nil
        edit:ClearFocus()
    end)

    function frame:Open(currentRoster, selected)
        roster, member = currentRoster, selected
        pending, gear, gearMessage = nil, nil, nil
        if member.isPlayer then
            gear = readGear("player")
            gearMessage = "No equipped item links are available."
        elseif not member.online then
            gearMessage = "This member is offline."
        end
        name:SetText(member.name)
        edit:SetText("")
        hint:SetText("Enter a roster name to link an alt.")
        frame:Show()
        scroll:SetVerticalScroll(0)
        display()
    end

    function frame:Refresh(currentRoster)
        if not frame:IsShown() then return end
        local updated = currentRoster.byID[member.id]
        if not updated or roster.guildKey ~= currentRoster.guildKey then
            frame:Hide()
            return
        end
        roster, member = currentRoster, updated
        if member.isPlayer then gear = readGear("player") end
        display()
    end

    return frame
end
