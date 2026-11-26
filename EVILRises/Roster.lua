local _, addon = ...
local colors = addon.colors

local rowHeight = 23
local gutter = 7
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

local function fullName(name)
    if not name:find("-", 1, true) then name = name .. "-" .. GetNormalizedRealmName() end
    return name:lower()
end

local function openMemberMenu(row)
    local member = row.member
    local clubId = C_Club.GetGuildClubId()
    local club = clubId and C_Club.GetClubInfo(clubId)
    if club and club.clubType == Enum.ClubType.Guild then
        for _, id in ipairs(C_Club.GetClubMembers(clubId) or {}) do
            local info = C_Club.GetMemberInfo(clubId, id)
            if info and not EVRFeatures.Compat.IsSecret(info.guid, info.name, member.guid) and info.name then
                local haveGUIDs = member.guid and info.guid
                if (haveGUIDs and member.guid == info.guid)
                    or (not haveGUIDs and fullName(member.name) == fullName(info.name)) then
                    UnitPopup_OpenMenu("COMMUNITIES_GUILD_MEMBER", {
                        name = info.name, guid = info.guid, isSelf = info.isSelf,
                        isMobile = info.presence == Enum.ClubMemberPresence.OnlineMobile,
                        isGuildMember = true, clubInfo = club, clubMemberInfo = info,
                        clubPrivileges = C_Club.GetClubPrivileges(clubId) or {},
                        clubAssignableRoles = C_Club.GetAssignableRoles(clubId, id),
                        ownerFrame = row,
                    })
                    return
                end
            end
        end
    end
    UIErrorsFrame:AddMessage("Guild member information is unavailable. Try again after the roster updates.")
end

function addon.CreateRoster(page, frame)
    local toolbar = CreateFrame("Frame", nil, page, "BackdropTemplate")
    toolbar:SetPoint("TOPLEFT", gutter, -6)
    toolbar:SetPoint("TOPRIGHT", -gutter, -6)
    toolbar:SetHeight(27)
    addon.SetSurface(toolbar, colors.control, colors.trim)
    addon.AddSurfaceSheen(toolbar, 0.90, 0.67, 0.35, 0.11)
    local searchLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("LEFT", 8, 0)
    searchLabel:SetText("Search roster")
    searchLabel:SetTextColor(unpack(colors.gold))
    local search = CreateFrame("EditBox", nil, toolbar, "InputBoxTemplate")
    search:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    search:SetSize(196, 22)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    local offline = CreateFrame("CheckButton", nil, toolbar, "UICheckButtonTemplate")
    offline:SetPoint("LEFT", search, "RIGHT", 12, 0)
    offline:SetSize(22, 22)
    offline:SetChecked(addon.settings.showOfflineMembers == true)
    local offlineLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    offlineLabel:SetPoint("LEFT", offline, "RIGHT", 2, 0)
    offlineLabel:SetText("Show offline members")
    offline:SetHitRectInsets(0, -(offlineLabel:GetStringWidth() + 2), 0, 0)

    local summary = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("RIGHT", -8, 0)
    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", 0, -88)

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", gutter, -60)
    scroll:SetPoint("BOTTOMRIGHT", -29, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local detail = addon.CreateMemberTooltip(page)
    local rows, headers, visible = {}, {}, {}
    local widths, offsets = {}, {}
    local roster
    local sortKey, descending = "name", false

    local classSheet = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
    local statusBase = "Interface\\AddOns\\" .. addon.folder .. "\\Textures\\"

    local layoutColumns
    local minimum = { 19, 21, 21, 38, 29, 38, 38, 44, 52, 38 }
    local desired = {}
    local function cellValue(member, i)
        if i == 4 then
            return addon.FindRosterMember(roster, member.shortName) and member.shortName or member.name
        end
        local value = i == 8 and member.lastSeen or member[columns[i][1]]
        return value and value ~= "" and value or blank
    end
    local function probe(font)
        local text = page:CreateFontString(nil, "OVERLAY", font)
        text:Hide()
        return text
    end
    local nameProbe, cellProbe, headerProbe = probe("GameFontHighlight"), probe("GameFontHighlightSmall"), probe("GameFontNormalSmall")

    local function layoutRow(row)
        row:SetWidth(child:GetWidth())
        for i, icon in ipairs({row.status, row.class, row.crown}) do
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", row, "LEFT", offsets[i] + (widths[i] - icon:GetWidth()) / 2, 0)
        end
        row.nameButton:ClearAllPoints()
        row.nameButton:SetPoint("LEFT", offsets[4], 0)
        row.nameButton:SetWidth(widths[4] - 3)
        fillWidth(row.texts[4], widths[4] - 9)
        for index = 5, #columns do
            local text = row.texts[index]
            text:ClearAllPoints()
            text:SetPoint("LEFT", offsets[index] + 4, 0)
            fillWidth(text, widths[index] - 8)
        end
    end

    local function createRow()
        local row = CreateFrame("Button", nil, child)
        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnClick", openMemberMenu)
        row:SetHeight(rowHeight)
        row.texts = {}
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints()
        row.divider = row:CreateTexture(nil, "ARTWORK")
        row.divider:SetPoint("TOPLEFT")
        row.divider:SetPoint("TOPRIGHT")
        row.divider:SetHeight(1)
        row.divider:SetColorTexture(unpack(colors.bronze))
        row.status = smallIcon(row, 13, 7)
        row.class = smallIcon(row, 17, 32)
        row.class:SetTexture(classSheet)
        row.crown = smallIcon(row, 16, 61)
        local button = CreateFrame("Button", nil, row)
        row.nameButton = button
        button:SetHeight(rowHeight)
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", 3, 0)
        row.texts[4] = name
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            search:ClearFocus()
            if mouseButton == "RightButton" then openMemberMenu(row); return end
            detail:Open(roster, row.member)
        end)
        for index = 5, #columns do
            row.texts[index] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        end
        layoutRow(row)
        return row
    end

    local function drawRows()
        if not widths[4] then return end
        local top = math.floor(scroll:GetVerticalScroll() / rowHeight)
        local count = math.ceil(scroll:GetHeight() / rowHeight) + 1
        for slot = 1, count do
            local index = top + slot
            local member = visible[index]
            local row = rows[slot]
            if member then
                if not row then row = createRow(); rows[slot] = row end
                row.member = member
                row.divider:SetShown(not member.online and index > 1 and visible[index - 1].online)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * rowHeight)
                row.background:SetColorTexture(unpack(index % 2 == 0 and colors.alternateRow or colors.row))
                row.status:SetTexture(statusBase .. (member.online and "Online" or "Offline"))
                local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[member.classFile]
                if coords then row.class:SetTexCoord(unpack(coords)) end
                row.class:SetShown(coords ~= nil)
                row.crown:SetShown(member.rankIndex == 0 or member.officerCrown == true)
                row.crown:SetTexture(member.rankIndex == 0 and "Interface\\GroupFrame\\UI-Group-LeaderIcon"
                    or statusBase .. "OfficerCrown")
                local nameColor = member.online and 0.97 or 0.70
                row.texts[4]:SetTextColor(nameColor, nameColor, nameColor)
                for column = 4, #columns do
                    row.texts[column]:SetText(cellValue(member, column))
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
            if (member.online or addon.settings.showOfflineMembers == true) and (query == "" or table.concat({
                member.name, member.class or "", member.race or "", member.zone or "",
                member.professions or "", member.rank or "",
            }, " "):lower():find(query, 1, true)) then
                visible[#visible + 1] = member
            end
        end

        if not addon.settings.rosterColumnWeights then
            for i = 4, #columns do
                headerProbe:SetText(columns[i][2])
                desired[i] = math.ceil(headerProbe:GetStringWidth()) + 24
                local measure = i == 4 and nameProbe or cellProbe
                local seen = {}
                for _, member in ipairs(visible) do
                    local value = cellValue(member, i)
                    if not seen[value] then
                        seen[value] = true
                        measure:SetText(value)
                        desired[i] = math.max(desired[i], math.ceil(measure:GetStringWidth()) + 10)
                    end
                end
            end
        end
        layoutColumns()
        local height = math.max(1, #visible * rowHeight)
        child:SetHeight(height)
        local scrollTo = resetScroll and 0 or math.min(scroll:GetVerticalScroll(), math.max(0, height - scroll:GetHeight()))
        scroll:SetVerticalScroll(scrollTo)
        local total = string.format("%d online / %d members", roster.online, #roster.members)
        summary:SetText(query == "" and total or (#visible .. " found  -  " .. total))
        if #visible == 0 then
            local message = "No matching members."
            if not IsInGuild() then message = "You are not in a guild."
            elseif #roster.members == 0 then message = "Waiting for the guild roster."
            elseif query == "" then message = "No members online." end
            empty:SetText(message)
        end
        empty:SetShown(#visible == 0)
        for _, entry in ipairs(columns) do
            local header = headers[entry[1]]
            local selected = entry[1] == sortKey
            addon.SetRosterHeaderSelected(header, selected)
            header.arrow:SetShown(selected)
            header.arrow:SetRotation(descending and math.pi or 0)
        end
        drawRows()
        detail:Refresh(roster)
    end

    for _, entry in ipairs(columns) do
        local key, label, _, tooltip = unpack(entry)
        local header = addon.CreateRosterHeader(page, label)
        header:SetHeight(22)
        header.arrow = header:CreateTexture(nil, "OVERLAY")
        header.arrow:SetPoint("RIGHT", -5, 0)
        header.arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        header.arrow:SetTexCoord(0.30, 0.70, 0.28, 0.68)
        header.arrow:SetSize(8, 8)
        if key == "online" then
            smallIcon(header, 12, 3):SetTexture(statusBase .. "Online")
            header:DisableDrawLayer("HIGHLIGHT")
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
            GameTooltip:SetText(key == "online" and "Solid dot: online. Hollow circle: offline." or "Sort by " .. (tooltip or label))
            GameTooltip:Show()
        end)
        header:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if key ~= "online" then
            header:SetScript("OnClick", function()
                descending = sortKey == key and not descending
                sortKey = key
                render(true)
            end)
        end
        headers[key] = header
    end

    local function applyWidths()
        local offset = 0
        for i, entry in ipairs(columns) do
            offsets[i] = offset
            local header = headers[entry[1]]
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", gutter + offset, -35)
            header:SetWidth(widths[i] - 1)
            offset = offset + widths[i]
        end
        for _, row in ipairs(rows) do layoutRow(row) end
    end

    layoutColumns = function()
        local width = math.floor(scroll:GetWidth())
        local custom = addon.settings.rosterColumnWeights
        local spare = width
        for i = 1, #columns do
            widths[i] = minimum[i]
            spare = spare - widths[i]
            if type(custom) ~= "table" or type(custom[i]) ~= "number" or custom[i] < 0 then custom = nil end
        end
        if spare < 0 then return end
        child:SetWidth(width)
        if not custom then
            local extra = math.min(spare, math.max(0, (desired[4] or 0) - widths[4]))
            widths[4], spare = widths[4] + extra, spare - extra
        end
        local weights, total = {}, 0
        for i = 1, #columns do
            weights[i] = custom and custom[i] or math.max(0, (desired[i] or 0) - widths[i])
            total = total + weights[i]
        end
        -- Once every label fits, distribute the remaining space across the text columns.
        if not custom and spare > total then
            for i = 1, #columns do widths[i] = widths[i] + weights[i] end
            spare, total = spare - total, 0
        end
        if total == 0 then
            for i, entry in ipairs(columns) do
                weights[i] = i >= 4 and entry[3] or 0
                total = total + weights[i]
            end
        end
        local sum, used = 0, 0
        for i = 1, #columns do
            sum = sum + weights[i]
            local allocated = math.floor(spare * sum / total + 0.5)
            widths[i] = widths[i] + allocated - used
            used = allocated
        end
        applyWidths()
    end

    for i = 1, #columns - 1 do
        local grip = CreateFrame("Button", nil, headers[columns[i][1]])
        grip:SetPoint("RIGHT", 3, 0)
        grip:SetSize(7, 22)
        grip:RegisterForDrag("LeftButton")
        grip:RegisterForClicks("RightButtonUp")
        local function cursor() return GetCursorPosition() / grip:GetEffectiveScale() end
        grip:SetScript("OnDragStart", function(self)
            local start, left, right = cursor(), widths[i], widths[i+1]
            self:SetScript("OnUpdate", function()
                local delta = math.floor(cursor() - start + 0.5)
                delta = math.max(minimum[i] - left, math.min(right - minimum[i+1], delta))
                if widths[i] == left + delta then return end
                widths[i], widths[i+1] = left + delta, right - delta
                local saved = {}
                for j = 1, #columns do saved[j] = widths[j] - minimum[j] end
                addon.settings.rosterColumnWeights = saved
                applyWidths()
            end)
        end)
        local function stop(self) self:SetScript("OnUpdate", nil) end
        grip:SetScript("OnDragStop", stop)
        grip:SetScript("OnHide", stop)
        grip:SetScript("OnClick", function()
            addon.settings.rosterColumnWeights = nil
            render(false)
        end)
        grip:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Drag to resize. Right-click to auto-fit all columns.")
            GameTooltip:Show()
        end)
        grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    scroll:HookScript("OnSizeChanged", function()
        layoutColumns()
        if roster then
            local maxScroll = math.max(0, child:GetHeight() - scroll:GetHeight())
            scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), maxScroll))
            drawRows()
        end
    end)

    local refreshPending
    local function refresh()
        roster = addon.ReadRoster()
        render(false)
    end

    page:RegisterEvent("GUILD_ROSTER_UPDATE")
    EVRFeatures.Compat.RegisterEvent(page, "GUILD_RANKS_UPDATE", true)
    page:RegisterEvent("GUILD_TRADESKILL_UPDATE")
    page:RegisterEvent("PLAYER_GUILD_UPDATE")
    page:RegisterEvent("PLAYER_TARGET_CHANGED")
    page:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    local function queueRefresh(_, event)
        if not page:IsVisible() or refreshPending then return end
        if event == "PLAYER_GUILD_UPDATE" then addon.RequestRoster() end
        refreshPending = true
        C_Timer.After(0, function()
            refreshPending = false
            if page:IsVisible() then refresh() end
        end)
    end
    frame.RefreshRoster = queueRefresh
    page:SetScript("OnEvent", queueRefresh)
    page:SetScript("OnShow", function()
        layoutColumns()
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
    offline:SetScript("OnClick", function(self)
        addon.settings.showOfflineMembers = not not self:GetChecked()
        if roster then render(true) end
    end)
end
