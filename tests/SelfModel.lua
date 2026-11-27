-- A solo install, no self flag, no GUID, no cached appearance, and a
-- DressUpModel that declines CanSetUnit until it has been initialized.
local noop=function() end
local card,listener,model,panel
local methods={}
local function widget()
    return setmetatable({scripts={}}, {__index=function(_,k) return methods[k] or noop end})
end
function methods:SetScript(k,fn) self.scripts[k]=fn end
methods.HookScript=methods.SetScript
methods.CreateTexture=widget
methods.CreateFontString=widget
function methods:GetFrameLevel() return 1 end
function methods:GetEffectiveScale() return 1 end
function methods:GetWidth() return 300 end
function methods:GetRight() return rawget(self,"right") end
function methods:SetPoint(point) self.anchor=point end
function methods:SetAlpha(a) self.alpha=a end
function methods:IsVisible() return true end
function methods:GetClubId() return 7 end
function methods:GetMemberInfo() return self.info end
function methods:CanSetUnit() return false end
function methods:SetAutoDress(value) self.dressed=value end
function methods:SetUnit(unit) self.unit=unit end
function methods:SetCamera(n) self.camera=n end
function methods:ClearModel() self.unit=nil end
function methods:Show() self.visible=true end
function methods:Hide() self.visible=false end
function methods:SetText(t) self.text=t end
function methods:SetCustomRace(race,sex) self.race,self.sex=race,sex end
function methods:SetDisplayInfo(id) self.display=id end
function methods:Undress() self.worn={} end
function methods:TryOn(item) self.worn[#self.worn+1]=item end
function CreateFrame(kind,_,parent,template)
    local f=widget()
    if template=="BackdropTemplate" then panel=f end
    if not parent then listener=f end
    if kind=="DressUpModel" then model=f end
    return f
end
UIParent=widget()
UIParent.GetWidth=function() return 1400 end
card=widget()
card.info={name="Sticky-Tickle"}
CommunitiesFrame={GuildMemberDetailFrame=card}
C_Club={GetGuildClubId=function() return 7 end}
GetInventoryItemLink=noop
GetInventorySlotInfo=noop
function hooksecurefunc(obj,k,fn) obj[k]=fn end
local addon={Crafting={Compat={IsSecret=function() return false end},BindGuild=noop,
    Professions={Get=noop},ProfCatalog={professions={}}},Profile={Get=noop,Request=noop}}
assert(loadfile("EVILRises/Bounty.lua"))("EVILRises",addon)
function UnitFullName() return "Sticky","Tickle" end
assert(loadfile("EVILRises/MemberFlyout.lua"))("EVILRises",addon)
listener.scripts.OnEvent(nil,"ADDON_LOADED")
assert(model.visible and model.unit=="player" and model.dressed and model.camera==0)
card.info={name="Sticky Lemon"}
card:DisplayMember()
assert(model.visible==false)
card.info={name="Sticky Tickle",isSelf=true}
card:DisplayMember()
assert(model.visible and model.unit=="player")
-- A guildmate out of range: the model is built from their shared race and sex and dressed in
-- their shared gear, without a model ID.
UnitGUID=function() return nil end
IsInRaid=function() return false end
GetNumGroupMembers=function() return 0 end
ITEM_QUALITY_COLORS={}
addon.Crafting.ProfDirectory={DisplayName=tostring}
addon.Crafting.Compat.GetItemInfo=noop
local shared={time=1,race=4,sex=1,items={[5]="item:42:0",[16]="item:123:9"}}
addon.Profile.Get=function(key) if key=="Far Lemon" then return shared end end
card.info={name="Far Lemon",guid="Player-1"}
card:DisplayMember()
assert(model.visible and rawget(model,"unit")==nil and model.race==4 and model.sex==1 and rawget(model,"display")==nil)
assert(#model.worn==2)
-- A snapshot from an older version has only a model ID.
shared={time=2,display=81,items={}}
card.info={name="Far Lemon",guid="Player-2"}
card:DisplayMember()
assert(rawget(model,"display")==81)
-- A snapshot with the outfit as worn: each slot's appearance goes onto the preview.
local applied={}
ItemUtil={CreateItemTransmogInfo=function(a,b,c) return {a,b,c} end}
methods.SetItemTransmogInfo=function(self,info,slot) applied[slot]=info end
shared={time=3,race=4,sex=1,mog={[1]={500,0,0},[16]={900,0,77}},items={[16]="item:123:9"}}
card.info={name="Far Lemon",guid="Player-3"}
card:DisplayMember()
assert(applied[1][1]==500 and applied[16][3]==77 and #model.worn==0)
-- Close enough for a nameplate: drawn live, and remembered once the model loads.
local remembered={}
addon.Profile.Remember=function(key,unit) remembered[#remembered+1]={key,unit} end
C_NamePlate={GetNamePlates=function() return {{namePlateUnitToken="nameplate3"}} end}
UnitGUID=function(unit) if unit=="nameplate3" then return "Player-4" end end
methods.CanSetUnit=function() return true end
card.info={name="Far Lemon",guid="Player-4"}
card:DisplayMember()
assert(model.unit=="nameplate3")
model.scripts.OnModelLoaded(model)
assert(#remembered==1 and remembered[1][1]=="Far Lemon" and remembered[1][2]=="nameplate3")
-- Nameplates for other players do not redraw the flyout; the shown member's do.
local timers=0
C_Timer={After=function() timers=timers+1 end}
listener.scripts.OnEvent(nil,"NAME_PLATE_UNIT_ADDED","nameplate9")
listener.scripts.OnEvent(nil,"UPDATE_MOUSEOVER_UNIT")
assert(timers==0)
listener.scripts.OnEvent(nil,"NAME_PLATE_UNIT_REMOVED","nameplate3")
assert(timers==1)
methods.CanSetUnit=function() return false end
print("Solo player model, missing roster identifiers, full surname match, member switching and shared race models, worn outfits, nameplate live models and event filtering passed.")

panel.scripts.OnShow(panel)
panel.scripts.OnUpdate(panel)
assert(panel.alpha==0)
card.right=1250
panel.scripts.OnUpdate(panel)
assert(panel.anchor=="TOPRIGHT" and panel.alpha==1)
-- ClassicUI docks the visible card after our DisplayMember hook.
card.right=620
panel.scripts.OnUpdate(panel)
assert(panel.anchor=="TOPLEFT" and panel.alpha==1)
card.right=1350
panel.scripts.OnUpdate(panel)
assert(panel.anchor=="TOPRIGHT")
print("Flyout tracks delayed docking and screen edges without another roster click.")

