local _, addon = ...

local rowHeight = 23
local blank = "-"
local columns = {
    { "online", "", 27, "Online status" },
    { "classFile", "", 28, "Class icon" },
    { "rankIndex", "", 27, "Guild rank" },
    { "name", "Name", 146 },
    { "level", "Lvl", 45, "Level" },
    { "class", "Class", 92 },
    { "race", "Race", 100 },
    { "elapsed", "Last seen", 104 },
    { "professions", "Primary professions", 232 },
    { "zone", "Zone", 197 },
}

local function fillWidth(text, width)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
end

local function smallIcon(parent, size, offset)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", offset, 0)
    return icon
end

function addon.CreateRoster(page)
    local searchLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 8, -11)
    searchLabel:SetText("Search roster")
    local search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    search:SetPoint("LEFT", searchLabel, "RIGHT", 12, 0)
    search:SetSize(196, 24)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    local summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPRIGHT", -10, -11)
    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", 0, -88)

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 5, -63)
    scroll:SetPoint("BOTTOMRIGHT", -27, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(998, 1)
    scroll:SetScrollChild(child)

    local detail = addon.CreateMemberTooltip(page)
    local rows, headers, visible = {}, {}, {}
    local roster
    local sortKey, descending = "name", false

    local classSheet = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
    local statusBase = "Interface\\AddOns\\" .. addon.folder .. "\\Textures\\"

    local function createRow()
        local row = CreateFrame("Frame", nil, child)
        row:SetSize(998, rowHeight)
        row.texts = {}
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints()
        row.status = smallIcon(row, 13, 7)
        row.class = smallIcon(row, 17, 32)
        row.class:SetTexture(classSheet)
        row.crown = smallIcon(row, 16, 61)
        row.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        local offset = 0
        for index, entry in ipairs(columns) do
            local width = entry[3]
            if index == 4 then
                local button = CreateFrame("Button", nil, row)
                button:SetPoint("LEFT", offset, 0)
                button:SetSize(width - 3, rowHeight)
                button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                local name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                name:SetPoint("LEFT", 3, 0)
                fillWidth(name, width - 9)
                row.texts[index] = name
                button:SetScript("OnClick", function()
                    search:ClearFocus()
                    detail:Open(roster, row.member)
                end)
            elseif index > 4 then
                local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                text:SetPoint("LEFT", offset + 4, 0)
                fillWidth(text, width - 8)
                row.texts[index] = text
            end
            offset = offset + width
        end
        return row
    end

    local function drawRows()
        local top = math.floor(scroll:GetVerticalScroll() / rowHeight)
        local count = math.ceil(scroll:GetHeight() / rowHeight) + 1
        for slot = 1, count do
            local index = top + slot
            local member = visible[index]
            local row = rows[slot]
            if member then
                if not row then row = createRow(); rows[slot] = row end
                row.member = member
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * rowHeight)
                row.background:SetColorTexture(0.23, 0.28, 0.12, index % 2 == 0 and 0.27 or 0.10)
                row.status:SetTexture(statusBase .. (member.online and "Online" or "Offline"))
                local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[member.classFile]
                if coords then row.class:SetTexCoord(unpack(coords)) end
                row.class:SetShown(coords ~= nil)
                local officer = member.rankIndex == 1 or (member.rank and member.rank:lower() == "officer")
                row.crown:SetShown(member.rankIndex == 0 or not not officer)
                if member.rankIndex == 0 then
                    row.crown:SetVertexColor(1, 0.92, 0.55)
                else
                    row.crown:SetVertexColor(0.74, 0.86, 0.93)
                end
                local nameColor = member.online and 0.97 or 0.70
                row.texts[4]:SetTextColor(nameColor, nameColor, nameColor)
                row.texts[4]:SetText(addon.FindRosterMember(roster, member.shortName) and member.shortName or member.name)
                for column = 5, #columns do
                    local key = columns[column][1]
                    local value = key == "elapsed" and member.lastSeen or member[key]
                    row.texts[column]:SetText(value and value ~= "" and value or blank)
                end
                row:Show()
            elseif row then
                row:Hide()
            end
        end
        for slot = count + 1, #rows do rows[slot]:Hide() end
    end

    scroll:HookScript("OnVerticalScroll", drawRows)

    local function render(resetScroll)
        addon.SortRoster(roster.members, sortKey, descending)
        local query = search:GetText():lower():match("^%s*(.-)%s*$")
        visible = {}
        for _, member in ipairs(roster.members) do
            if query == "" or table.concat({
                member.name, member.class or "", member.race or "", member.zone or "",
                member.professions or "", member.rank or "",
            }, " "):lower():find(query, 1, true) then
                visible[#visible + 1] = member
            end
        end

        local height = math.max(1, #visible * rowHeight)
        child:SetHeight(height)
        local scrollTo = resetScroll and 0 or math.min(scroll:GetVerticalScroll(), math.max(0, height - scroll:GetHeight()))
        scroll:SetVerticalScroll(scrollTo)
        local total = string.format("%d online / %d members", roster.online, #roster.members)
        summary:SetText(query == "" and total or (#visible .. " found  -  " .. total))
        if #visible == 0 then
            empty:SetText(not IsInGuild() and "You are not in a guild." or (query == "" and "Waiting for the guild roster." or "No matching members."))
        end
        empty:SetShown(#visible == 0)
        for _, entry in ipairs(columns) do
            local header = headers[entry[1]]
            header.arrow:SetShown(entry[1] == sortKey)
            header.arrow:SetRotation(descending and math.pi or 0)
        end
        drawRows()
        detail:Refresh(roster)
    end

    local offset = 5
    for _, entry in ipairs(columns) do
        local key, label, width, tooltip = unpack(entry)
        local header = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        header:SetPoint("TOPLEFT", offset, -37)
        header:SetSize(width - 1, 23)
        header:SetText(label)
        header.arrow = header:CreateTexture(nil, "OVERLAY")
        header.arrow:SetPoint("RIGHT", -5, 0)
        header.arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        header.arrow:SetSize(11, 11)
        if key == "online" then
            smallIcon(header, 12, 3):SetTexture(statusBase .. "Online")
        elseif key == "classFile" then
            local icon = smallIcon(header, 13, 3)
            icon:SetTexture(classSheet)
            if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS.WARRIOR then
                icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS.WARRIOR))
            end
        elseif key == "rankIndex" then
            smallIcon(header, 13, 3):SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        end
        header:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Sort by " .. (tooltip or label))
            GameTooltip:Show()
        end)
        header:SetScript("OnLeave", function() GameTooltip:Hide() end)
        header:SetScript("OnClick", function()
            descending = sortKey == key and not descending or sortKey ~= key and key == "online"
            sortKey = key
            render(true)
        end)
        headers[key] = header
        offset = offset + width
    end

    local refreshPending
    local function refresh()
        roster = addon.ReadRoster()
        render(false)
    end

    page:RegisterEvent("GUILD_ROSTER_UPDATE")
    page:RegisterEvent("GUILD_TRADESKILL_UPDATE")
    page:RegisterEvent("PLAYER_GUILD_UPDATE")
    page:RegisterEvent("PLAYER_TARGET_CHANGED")
    page:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    page:SetScript("OnEvent", function(_, event)
        if not page:IsVisible() or refreshPending then return end
        if event == "PLAYER_GUILD_UPDATE" then addon.RequestRoster() end
        refreshPending = true
        C_Timer.After(0, function()
            refreshPending = false
            if page:IsVisible() then refresh() end
        end)
    end)
    page:SetScript("OnShow", function()
        addon.RequestRoster()
        refresh()
    end)
    page:SetScript("OnHide", function()
        detail:Hide()
        search:ClearFocus()
    end)
    search:SetScript("OnTextChanged", function()
        if roster then render(true) end
    end)
end
