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
    for index in ipairs(slotNames) do
        local link = GetInventoryItemLink(unit, index)
        if link then
            items[index] = { link = link, id = tonumber(link:match("item:(%d+)")),
                name = link:match("|h%[(.-)%]|h") }
        elseif GetInventoryItemID then
            local id = GetInventoryItemID(unit, index)
            if id then items[index] = { id = id } end
        end
    end
    return items
end

local function itemString(item)
    if type(item) ~= "table" then return end
    if type(item.link) == "string" then
        local key = item.link:match("|H(item:%d+[^|]*)|h") or item.link:match("^(item:%d+[^|]*)$")
        if key then return key end
    end
    -- Earlier installs sent the enchant, gems and random suffix separately.
    local id = tonumber(item.id)
    if not id or id < 1 or id ~= math.floor(id) then return end
    if not (item.enchantId or item.gems or item.suffix) then return "item:" .. id end
    local fields = { "item", id, tonumber(item.enchantId) or 0 }
    for i = 1, 4 do
        local gem = type(item.gems) == "table" and item.gems[i]
        fields[#fields + 1] = type(gem) == "table" and tonumber(gem.id) or 0
    end
    fields[#fields + 1] = tonumber(item.suffix) or 0
    return table.concat(fields, ":")
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
    name:SetTextColor(unpack(addon.colors.green))

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
    local rows, waiting = {}, {}

    local function showItem(row)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(row.itemString)
        GameTooltip:Show()
    end

    local function hideItem(row)
        if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    end

    local function gearRow(index)
        if rows[index] then return rows[index] end
        local row = CreateFrame("Button", nil, child)
        row:SetSize(374, 20)
        local slot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        slot:SetPoint("LEFT")
        slot:SetText(slotNames[index])
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", 79, 0)
        label:SetPoint("RIGHT", -2, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.itemName = label
        row:SetScript("OnEnter", showItem)
        row:SetScript("OnLeave", hideItem)
        row:SetScript("OnHide", hideItem)
        rows[index] = row
        return row
    end

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
        inspect:SetEnabled(not member.isPlayer and not member.gear and member.online and member.guid ~= nil and not pending)
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
        local equipment = member.isPlayer and readGear("player") or member.gear or gear
        lines[#lines + 1] = "|cffffd100Gear|r"
        if not equipment then
            lines[#lines + 1] = gearMessage or "No gear shared by this member yet."
        elseif next(equipment) == nil then
            lines[#lines + 1] = "No equipped items."
        end
        text:SetText(table.concat(lines, "\n"))
        local offset = text:GetStringHeight() + 4
        local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
        waiting = {}
        for index in ipairs(slotNames) do
            local item = equipment and (equipment[index] or equipment[tostring(index)])
            local key = itemString(item)
            if key then
                local row = gearRow(index)
                local itemName, quality
                if getInfo then
                    local cachedName, _, cachedQuality = getInfo(key)
                    itemName, quality = cachedName, cachedQuality
                    if not cachedName then waiting[tonumber(key:match("^item:(%d+)"))] = true end
                end
                itemName = itemName or (item.name ~= "" and item.name) or key:match("^item:(%d+)")
                local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or item.quality]
                row.itemName:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
                row.itemName:SetText(itemName)
                row.itemString = key
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -offset)
                row:Show()
                if GameTooltip:IsOwned(row) then showItem(row) end
                offset = offset + row:GetHeight()
            elseif rows[index] then
                rows[index]:Hide()
            end
        end
        child:SetHeight(math.max(scroll:GetHeight(), offset))
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
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, event, guid, success)
        if event == "GET_ITEM_INFO_RECEIVED" then
            if success and frame:IsVisible() and waiting[guid] then display() end
            return
        end
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
        display()
    end

    return frame
end
