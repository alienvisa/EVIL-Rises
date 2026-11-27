local _, addon = ...
local profile,craft=addon.Profile,addon.Crafting
local slots={
    {1,"HeadSlot"},{2,"NeckSlot"},{3,"ShoulderSlot"},{15,"BackSlot"},
    {5,"ChestSlot"},{4,"ShirtSlot"},{19,"TabardSlot"},{9,"WristSlot"},
    {10,"HandsSlot"},{6,"WaistSlot"},{7,"LegsSlot"},{8,"FeetSlot"},
    {11,"Finger0Slot"},{12,"Finger1Slot"},{13,"Trinket0Slot"},{14,"Trinket1Slot"},
    {16,"MainHandSlot"},{17,"SecondaryHandSlot"},{18,"RangedSlot"},
}
local card,panel,model,heading,caption,skills,balance,expander
local icons={}
local expanded=true
local modelUnit,modelGuid,modelSnapshot,modelKey
local function unitFor(info,key)
    -- The member card may omit isSelf and guid. The current character's
    -- guild name (including their Forever surname) still identifies our row.
    if info.isSelf or key==addon.Owner() then return "player" end
    if not info.guid then return end
    local function matches(token)
        local guid=UnitGUID(token)
        return not craft.Compat.IsSecret(guid) and guid==info.guid
    end
    for _,unit in ipairs({"player","target","focus","mouseover"}) do
        if matches(unit) then return unit end
    end
    local raid=IsInRaid()
    for i=1,GetNumGroupMembers() do
        local unit=(raid and "raid" or "party")..i
        if matches(unit) then return unit end
    end
    -- Anyone close enough to have a nameplate can be drawn live, exactly as they look.
    local ok,plates=pcall(C_NamePlate and C_NamePlate.GetNamePlates)
    if ok and type(plates)=="table" then
        for _,plate in ipairs(plates) do
            local unit=plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if type(unit)=="string" and matches(unit) then return unit end
        end
    end
end
-- Dress the preview: the outfit as worn (transmog, hidden slots, enchant effects) when the
-- snapshot has one and the client can apply it, else the equipped items.
local function outfit()
    if modelUnit or not modelSnapshot then return end
    model:Undress()
    local create=ItemUtil and ItemUtil.CreateItemTransmogInfo
    if modelSnapshot.mog and model.SetItemTransmogInfo and create then
        for slot,t in pairs(modelSnapshot.mog) do
            local ok,info=pcall(create,t[1],t[2],t[3])
            if ok and info then pcall(model.SetItemTransmogInfo,model,info,slot) end
        end
        return
    end
    for _,s in ipairs(slots) do
        local id=s[1]
        local item=modelSnapshot.items[id]
        if item and id~=2 and (id<11 or id>14) then
            model:TryOn(item,id==16 and "MAINHANDSLOT" or id==17 and "SECONDARYHANDSLOT" or nil)
        end
    end
end
local function setModel(key,unit,info,p)
    if modelKey==key and modelUnit==unit and modelGuid==info.guid and modelSnapshot==p then return end
    modelSnapshot=nil
    model:ClearModel()
    modelKey,modelUnit,modelGuid,modelSnapshot=key,unit,info.guid,p
    if unit then
        model:Show()
        model:SetAutoDress(true)
        model:SetUnit(unit)
        model:SetCamera(0)
        caption:SetText("Live appearance")
    elseif p and (p.race or p.display) then
        model:Show()
        -- Race and sex build the base model; a model ID from an older version is the fallback.
        local built=p.race and model.SetCustomRace and pcall(model.SetCustomRace,model,p.race,p.sex or 0)
        if not built and p.display then model:SetDisplayInfo(p.display) end
        outfit()
        caption:SetText("Shared gear preview")
    else
        model:Hide()
        caption:SetText("No appearance shared yet")
    end
    model:SetFacing(0.2)
end
-- The stock card can be docked to another window after DisplayMember returns.
-- Resolve its screen edge just before drawing, independently of data refresh.
local anchoredRight
local function positionFlyout()
    local right=card:GetRight()
    if not right then
        panel:SetAlpha(0)
        anchoredRight=nil
        return
    end
    local screenRight=UIParent:GetWidth()*UIParent:GetEffectiveScale()
    local fitsRight=right*card:GetEffectiveScale()+(panel:GetWidth()+4)*panel:GetEffectiveScale()<=screenRight
    if anchoredRight~=fitsRight then
        panel:ClearAllPoints()
        if fitsRight then
            panel:SetPoint("TOPLEFT",card,"TOPRIGHT",4,0)
        else
            panel:SetPoint("TOPRIGHT",card,"TOPLEFT",-4,0)
        end
        anchoredRight=fitsRight
        panel:SetAlpha(1)
    end
end
local function render(ask)
    if not card:IsVisible() or not card:GetClubId() or card:GetClubId()~=C_Club.GetGuildClubId() then panel:Hide();expander:Hide();return end
    local info=card:GetMemberInfo()
    if not info or craft.Compat.IsSecret(info.name,info.guid,info.isSelf) or not info.name then
        panel:Hide();expander:Hide();return
    end
    expander:Show()
    expander:SetText(expanded and "Hide gear & professions" or "Gear & professions")
    panel:SetShown(expanded)
    if not expanded then return end
    craft.BindGuild()
    local key=addon.Owner(info.name)
    local unit=unitFor(info,key)
    if unit and unit~="player" and model.CanSetUnit and not model:CanSetUnit(unit) then unit=nil end
    if ask then profile.Request(key) end
    local p=profile.Get(key)
    -- The model and gear icons come from the newest of their snapshot and the last live sighting.
    local look=profile.Preview and profile.Preview(key) or p
    local shown=look and next(look.items or {}) and look or p
    if p and p.copper~=nil then
        local copper=p.copper
        balance:SetFormattedText("Funds   %d |TInterface\\MoneyFrame\\UI-GoldIcon:12|t   %d |TInterface\\MoneyFrame\\UI-SilverIcon:12|t   %d |TInterface\\MoneyFrame\\UI-CopperIcon:12|t",
            math.floor(copper/10000),math.floor(copper/100)%100,copper%100)
    else
        balance:SetText("Funds: not shared yet")
    end
    heading:SetText(info.name)
    setModel(key,unit,info,look)
    for i,s in ipairs(slots) do
        local icon=icons[i]
        local live=unit and GetInventoryItemLink(unit,s[1])
        if craft.Compat.IsSecret(live) then live=nil end
        local item=live or (shown and shown.items[s[1]])
        icon.item=item
        local texture=icon.empty
        local quality
        if item then
            local _,_,q,_,_,_,_,_,_,t=craft.Compat.GetItemInfo(item)
            texture=t or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)) or 134400
            quality=q
        end
        icon.picture:SetTexture(texture)
        local color=quality and ITEM_QUALITY_COLORS[quality]
        icon.border:SetColorTexture(color and color.r or 0.32,color and color.g or 0.32,color and color.b or 0.32)
    end
    local lines={}
    local record=craft.Professions:Get(key)
    for line,data in pairs(record and record.profs or {}) do
        lines[#lines+1]=craft.ProfDirectory.DisplayName(line)..(data.rank and (" "..data.rank.."/"..data.max) or "")
    end
    if #lines==0 then
        for _,line in ipairs({info.profession1ID or 0,info.profession2ID or 0}) do
            if not craft.Compat.IsSecret(line) and craft.ProfCatalog.professions[line] then
                lines[#lines+1]=craft.ProfDirectory.DisplayName(line)
            end
        end
    end
    table.sort(lines)
    skills:SetText(#lines>0 and table.concat(lines,"   ·   ") or "No professions recorded")
end
local function label(font,x,y)
    local f=panel:CreateFontString(nil,"OVERLAY",font)
    f:SetPoint("TOPLEFT",x,y)
    f:SetPoint("TOPRIGHT",-x,y)
    return f
end
local function attach()
    if card or not CommunitiesFrame or not CommunitiesFrame.GuildMemberDetailFrame then return end
    card=CommunitiesFrame.GuildMemberDetailFrame
    panel=CreateFrame("Frame",nil,card,"BackdropTemplate")
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(card:GetFrameLevel()+5)
    panel:SetSize(288,380)
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    panel:SetBackdropColor(0.1,0.1,0.1,1)
    panel:EnableMouse(true)
    panel:SetScript("OnShow",function(self)
        anchoredRight=nil
        self:SetAlpha(0)
    end)
    panel:SetScript("OnUpdate",positionFlyout)
    panel:Hide()
    heading=label("GameFontNormalLarge",12,-10)
    model=CreateFrame("DressUpModel",nil,panel)
    model:SetPoint("TOPLEFT",46,-36)
    model:SetPoint("BOTTOMRIGHT",-46,138)
    model:SetScript("OnModelLoaded",function()
        if modelUnit then
            if profile.Remember then profile.Remember(modelKey,modelUnit,model) end
        else
            outfit()
        end
    end)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown",function(self)
        local last=GetCursorPosition()
        self:SetScript("OnUpdate",function(m)
            local x=GetCursorPosition()
            m:SetFacing(m:GetFacing()+(x-last)*0.012)
            last=x
        end)
    end)
    local function stop(m) m:SetScript("OnUpdate",nil) end
    model:SetScript("OnMouseUp",stop)
    model:SetScript("OnHide",function(m) stop(m);modelKey=nil end)
    caption=label("GameFontDisableSmall",40,-249)
    label("GameFontNormal",10,-289):SetText("Professions")
    skills=label("GameFontHighlightSmall",10,-308)
    balance=label("GameFontHighlight",10,-355)
    for i,s in ipairs(slots) do
        local b=CreateFrame("Button",nil,panel)
        b:SetSize(25,25)
        if i<=8 then b:SetPoint("TOPLEFT",10,-34-(i-1)*28)
        elseif i<=16 then b:SetPoint("TOPRIGHT",-10,-34-(i-9)*28)
        else b:SetPoint("TOP", (i-18)*30,-261) end
        local ok,_,empty=pcall(GetInventorySlotInfo,s[2])
        b.empty=ok and empty or "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
        b.border=b:CreateTexture(nil,"BACKGROUND");b.border:SetAllPoints()
        b.picture=b:CreateTexture(nil,"ARTWORK")
        b.picture:SetPoint("TOPLEFT",1,-1);b.picture:SetPoint("BOTTOMRIGHT",-1,1)
        b:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            if self.item then GameTooltip:SetHyperlink(self.item)
            else GameTooltip:SetText(_G[s[2]:upper()] or s[2]);GameTooltip:AddLine("No item recorded") end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        icons[i]=b
    end
    expander=CreateFrame("Button",nil,card,"UIPanelButtonTemplate")
    expander:SetSize(158,20)
    expander:SetPoint("TOP",card,"BOTTOM",0,0)
    expander:SetScript("OnClick",function() expanded=not expanded;render(true) end)
    hooksecurefunc(card,"DisplayMember",function() render(true) end)
    card:HookScript("OnHide",function() panel:Hide();modelKey=nil end)
    card:HookScript("OnShow",function() render(true) end)
    render(card:IsVisible())
end
local queued
function profile.Refresh(key)
    if not panel or not panel:IsVisible() or queued or (key and key~=modelKey) then return end
    queued=true
    C_Timer.After(0,function() queued=false;render(false) end)
end
-- Unit events redraw the flyout only when they concern the member it shows, so a busy city
-- full of nameplates does not redraw it every frame.
local UNIT_EVENTS={PLAYER_TARGET_CHANGED="target",PLAYER_FOCUS_CHANGED="focus",UPDATE_MOUSEOVER_UNIT="mouseover"}
local function concernsShown(unit)
    if not unit or not modelKey then return false end
    if unit==modelUnit then return true end
    local guid=UnitGUID(unit)
    return modelGuid~=nil and not craft.Compat.IsSecret(guid) and guid==modelGuid
end
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED","GROUP_ROSTER_UPDATE","UPDATE_MOUSEOVER_UNIT","GET_ITEM_INFO_RECEIVED","UNIT_MODEL_CHANGED","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event,unit)
    if event=="ADDON_LOADED" then
        attach()
    elseif UNIT_EVENTS[event] then
        -- The member came into this unit, or the unit drawn live now shows someone else.
        if concernsShown(UNIT_EVENTS[event]) or modelUnit==UNIT_EVENTS[event] then profile.Refresh() end
    elseif event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED" or event=="UNIT_MODEL_CHANGED" then
        if concernsShown(unit) then profile.Refresh() end
    else
        profile.Refresh()
    end
end)
