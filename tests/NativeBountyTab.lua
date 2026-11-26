local noop=function() end
local function frame(parent)
    local f={parent=parent,shown=true}
    function f:IsShown() return self.shown end
    function f:Show() self.shown=true; if self.OnShow then self:OnShow() end end
    function f:Hide() self.shown=false end
    function f:SetShown(v) self.shown=v end
    function f:SetChecked(v) self.checked=v end
    function f:SetScript(k,fn) self[k]=fn end
    f.HookScript=f.SetScript
    function f:SetPoint(_,other) self.anchor=other end
    function f:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel()+1) or 1 end
    function f:SetFrameLevel(value) self.level=value end
    function f:SetFrameStrata(value) self.strata=value end
    function f:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
    function f:CreateTexture() return {SetAllPoints=noop,SetColorTexture=noop} end
    f.SetClipsChildren,f.EnableMouse=noop,noop
    f.RegisterEvent,f.UnregisterEvent,f.ClearAllPoints=noop,noop,noop
    return f
end
local event,tab,craftTab
function CreateFrame(_,_,parent,template)
    local f=frame(parent)
    if not parent then event=f end
    if template=="CommunitiesFrameTabTemplate" then
        if tab then craftTab=f else tab=f end
        f.Icon={SetTexture=function(self,id) self.id=id end}
    end
    return f
end
function hooksecurefunc(obj,key,callback)
    local fn=assert(obj[key])
    obj[key]=function(...) fn(...); callback(...) end
end
local b={Update=noop,Request=noop}
function b.Build(page)
    b.page=page
    page.list,page.form=frame(page),frame(page)
    page.List=noop
    page.Compose=function(_,info) b.target=info end
end
b.Crafting={BindGuild=noop,Build=function(p) p.List=noop; b.crafts=p end}
C_Club={GetGuildClubId=function() return 5 end}
SlashCmdList={}
COMMUNITIES_FRAME_DISPLAY_MODES={GUILD_INFO="info",MINIMIZED="min"}
RightSideTabMixin={OnClick=noop}
assert(loadfile("EVILRises/GuildWindow.lua"))("EVILRises",b)
local h=frame()
CommunitiesFrame=h
for _,key in ipairs({"GuildDetailsFrame","GuildLogButton","CommunitiesControlFrame","CommunitiesList","ChatTab","RosterTab","GuildBenefitsTab","GuildInfoTab","GuildPreferredPlaySettingsTab"}) do h[key]=frame(h) end
h.GuildPreferredPlaySettingsTab:Hide()
function h:GetDisplayMode() return self.mode end
function h:UpdateCommunitiesTabs() self.GuildInfoTab:SetChecked(self.mode=="info") end
function h:SetDisplayMode(mode)
    if self.mode==mode then return end
    self.mode=mode
    self.GuildDetailsFrame:SetShown(mode=="info")
    self.GuildLogButton:SetShown(mode=="info")
    self.CommunitiesControlFrame:SetShown(mode=="info" or mode=="roster")
    self:UpdateCommunitiesTabs()
end
function h:UpdateSelectedClubInfo(id) self.id=id end
function h:GetSelectedClubId() return self.id end
h:UpdateSelectedClubInfo(5)
event:OnEvent()
assert(tab:IsShown() and tab.anchor==h.GuildInfoTab and not b.page)
tab:SetFrameLevel(510)
h.GuildDetailsFrame:SetFrameLevel(700)
tab:OnClick()
for _,part in ipairs({b.page,b.page.list,b.page.form}) do
    assert(part:GetFrameStrata()=="DIALOG" and part:GetFrameLevel()>700)
end
assert(b.page:IsShown() and tab.checked and not h.GuildInfoTab.checked)
assert(not h.GuildDetailsFrame:IsShown() and not h.GuildLogButton:IsShown() and not h.CommunitiesControlFrame:IsShown())
h.GuildDetailsFrame:Show()
assert(not h.GuildDetailsFrame:IsShown())
assert(craftTab.anchor==tab and craftTab.Icon.id==132763)
craftTab:OnClick()
assert(craftTab.checked and not tab.checked and b.crafts:IsShown() and not b.page:IsShown())
tab:OnClick()
assert(tab.checked and not craftTab.checked and b.page:IsShown() and not b.crafts:IsShown())
h:SetDisplayMode("roster")
assert(h.CommunitiesControlFrame:IsShown() and not h.GuildLogButton:IsShown())
assert(not b.page:IsShown() and not tab.checked)
tab:OnClick()
h:SetDisplayMode("info")
assert(not b.page:IsShown() and h.GuildInfoTab.checked and h.GuildDetailsFrame:IsShown() and h.GuildLogButton:IsShown())
h.GuildPreferredPlaySettingsTab:Show()
h:UpdateCommunitiesTabs()
assert(tab.anchor==h.GuildPreferredPlaySettingsTab)
tab:OnClick()
h:UpdateSelectedClubInfo(9)
assert(not b.page:IsShown() and not tab:IsShown())
print("Passed native side-tab placement, guild-only visibility, selection and return navigation.")
