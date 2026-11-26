local _, board = ...
local host, tab, page, craftTab, bountyPage, craftPage
local sides = {"ChatTab","RosterTab","GuildBenefitsTab","GuildInfoTab","GuildPreferredPlaySettingsTab"}
-- These are the native children listed by Forever's GUILD_INFO display mode.
-- The communities sidebar stays visible while the board owns the content area.
local infoChildren = {"GuildDetailsFrame","GuildLogButton","CommunitiesControlFrame"}
local restoreShown = {}
local function hideInfoChild(child)
    if child:IsShown() then
        restoreShown[child] = true
        child:Hide()
    end
end
local function hideBoard()
    page:Hide()
    for child in pairs(restoreShown) do
        if host:GetDisplayMode() == COMMUNITIES_FRAME_DISPLAY_MODES.GUILD_INFO then
            child:Show()
        end
        restoreShown[child] = nil
    end
end
local function guildSelected()
    local id = C_Club.GetGuildClubId()
    return id and host:GetSelectedClubId() == id
end
local function updateTabs()
    local last
    if guildSelected() then
        for _, key in ipairs(sides) do
            local side = host[key]
            if side and side:IsShown() then last = side end
        end
    end
    tab:SetShown(last ~= nil)
    craftTab:SetShown(last ~= nil)
    if last then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT",last,"BOTTOMLEFT",0,-20)
    else
        hideBoard()
    end
    if page:IsShown() then host.GuildInfoTab:SetChecked(false) end
    tab:SetChecked(page == bountyPage and page:IsShown())
    craftTab:SetChecked(page == craftPage and page:IsShown())
end
local function close()
    if page:IsShown() then
        hideBoard()
        host:UpdateCommunitiesTabs()
    end
end
local function open(info, crafting)
    if not host or not guildSelected() then return end
    if host:GetDisplayMode() == COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED then
        host.MaximizeMinimizeFrame.MaximizeButton:Click()
    end
    -- Use the guild-info pane as the backing surface so chat input never
    -- captures keys while someone is filling out a posting.
    host:SetDisplayMode(COMMUNITIES_FRAME_DISPLAY_MODES.GUILD_INFO)
    page = crafting and craftPage or bountyPage
    -- The native content has multiple frame levels, and UI skins can
    -- change them after load. Stack with the visible side tabs on each open.
    page:SetFrameStrata("DIALOG")
    page:SetFrameLevel(math.max(tab:GetFrameLevel(),host.GuildInfoTab:GetFrameLevel(),
        host.GuildDetailsFrame:GetFrameLevel()) + 1)
    if crafting then
        board.Crafting.BindGuild()
        if not page.List then board.Crafting.Build(page) end
    elseif not board.page then
        board.Build(page)
    end
    page:Show()
    for _, key in ipairs(infoChildren) do hideInfoChild(host[key]) end
    page:List()
    if info then page:Compose(info) end
    updateTabs()
    if not crafting then
        board.Update()
        board.Request()
    end
end
local function makePage()
    local page = CreateFrame("Frame",nil,host)
    page:SetPoint("TOPLEFT",host.CommunitiesList,"TOPRIGHT",5,0)
    page:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",-5,4)
    -- Own the background directly so an inset skin cannot add a foreground shade.
    local base = page:CreateTexture(nil,"BACKGROUND",nil,-8)
    base:SetAllPoints()
    base:SetColorTexture(0.10,0.10,0.10,1)
    page:EnableMouse(true)
    page:SetClipsChildren(true)
    page:Hide()
    return page
end
local function attach()
    if host or not CommunitiesFrame then return end
    host = CommunitiesFrame
    bountyPage, craftPage = makePage(), makePage()
    page = bountyPage
    tab = CreateFrame("CheckButton",nil,host,"CommunitiesFrameTabTemplate")
    tab.Icon:SetTexture("Interface\\AddOns\\EVILRises\\BountySkull")
    tab.tooltip = "Bounty Board"
    tab:SetScript("OnClick",function(self)
        RightSideTabMixin.OnClick(self)
        open()
    end)
    craftTab = CreateFrame("CheckButton",nil,host,"CommunitiesFrameTabTemplate")
    craftTab.Icon:SetTexture(132763)
    craftTab.tooltip = "Crafting Orders"
    craftTab:SetPoint("TOPLEFT",tab,"BOTTOMLEFT",0,-20)
    craftTab:SetScript("OnClick",function(self)
        RightSideTabMixin.OnClick(self)
        open(nil,true)
    end)
    for _, key in ipairs(infoChildren) do
        host[key]:HookScript("OnShow",function(child)
            if page:IsShown() and host:GetDisplayMode() == COMMUNITIES_FRAME_DISPLAY_MODES.GUILD_INFO then
                hideInfoChild(child)
            end
        end)
    end
    hooksecurefunc(host,"UpdateCommunitiesTabs",updateTabs)
    hooksecurefunc(host,"SetDisplayMode",close)
    hooksecurefunc(host,"UpdateSelectedClubInfo",function()
        if not guildSelected() then close() end
        updateTabs()
    end)
    host:HookScript("OnHide",hideBoard)
    host:HookScript("OnShow",updateTabs)
    updateTabs()
end
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(self)
    attach()
    if host then self:UnregisterEvent("ADDON_LOADED") end
end)
local function showBoard(info)
    if InCombatLockdown() or not IsInGuild() then return end
    if not CommunitiesFrame or not CommunitiesFrame:IsShown() then ToggleGuildFrame() end
    attach()
    local id = C_Club.GetGuildClubId()
    if host and host:IsShown() and id then
        host:SelectClub(id)
        open(info)
    end
end
SLASH_EVILRISES1 = "/evil"
SlashCmdList.EVILRISES = function(command)
    if command:lower():match("^%s*version%s*$") then
        print("EVIL Rises " .. C_AddOns.GetAddOnMetadata("EVILRises","Version"))
    else
        showBoard()
    end
end
if Menu and Menu.ModifyMenu then
    for _, tag in ipairs({"TARGET","PLAYER","ENEMY_PLAYER","PARTY","RAID_PLAYER","FOCUS"}) do
        Menu.ModifyMenu("MENU_UNIT_"..tag,function(_,root,context)
            if not IsInGuild() then return end
            local info = board.ReadUnit(context and context.unit)
            if info then root:CreateButton("Create bounty",function() showBoard(info) end) end
        end)
    end
end
