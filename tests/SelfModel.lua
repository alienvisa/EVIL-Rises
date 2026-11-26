-- A solo install, no self flag, no GUID, no cached appearance, and a
-- DressUpModel that declines CanSetUnit until it has been initialized.
local noop=function() end
local card,listener,model
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
function methods:GetRight() return 500 end
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
function CreateFrame(kind,_,parent)
    local f=widget()
    if not parent then listener=f end
    if kind=="DressUpModel" then model=f end
    return f
end
UIParent=widget()
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
print("Solo player model, missing roster identifiers, full surname match and member switching passed.")
