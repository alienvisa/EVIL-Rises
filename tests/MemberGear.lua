local now=1000
local wallet=123456
function GetMoney() return wallet end
local onEvent
local handlers={}
local sent={}
local noop=function() end
local craft={guild="7",db={},SyncService={}}
function craft.SyncService:On(k,fn) handlers[k]=fn end
function craft.SyncService:Publish(k,act,p,opts) sent[#sent+1]={k,act,p,opts} end
local addon={Crafting=craft,GuildID=function() return craft.guild end,Owner=function(n) return n or "Self Lemon" end}
C_Timer={After=function(_,fn) fn() end}
function GetServerTime() return now end
function UnitRace() return "Night Elf","NightElf",4 end
function UnitSex() return 3 end
GetTime=GetServerTime
function GetInventoryItemID(_,s) if s==16 then return 123 end end
function GetInventoryItemLink(_,s) if s==16 then return "|cff00ff00|Hitem:123:9|h[Sword]|h|r" end end
local modelId,model=0
function CreateFrame(kind)
    local f={SetSize=noop,SetPoint=noop,SetAlpha=noop,SetUnit=noop,RegisterEvent=noop,GetDisplayInfo=function() return modelId end,
        SetScript=function(self,name,fn) if name=="OnEvent" then onEvent=fn else self[name]=fn end end}
    if kind=="PlayerModel" then model=f end
    return f
end
assert(loadfile("EVILRises/MemberGear.lua"))("EVILRises",addon)
assert(loadfile("EVILRises/MemberFlyout.lua"))
local p=addon.Profile
p.Request("Self Lemon")
-- The model is still loading: the first snapshot has no appearance yet.
assert(#sent==1 and p.Get("Self Lemon").display==nil)
-- Race and sex go out even before the model loads.
assert(sent[1][3].race==4 and sent[1][3].sex==1)
modelId=80
model.OnModelLoaded(model)
local own=p.Get("Self Lemon")
assert(#sent==2 and sent[2][3].display==80 and own.display==80 and own.items[16]=="item:123:9")
p.Request("Self Lemon")
assert(#sent==2)
handlers.memberGear({act="gear",data={time=now,display=81,items={[5]="item:42:0"}}},"Other Lemon")
assert(p.Get("Other Lemon").items[5]=="item:42:0")
handlers.memberGear({act="gear",data={time=now-1,items={}}},"Other Lemon")
assert(p.Get("Other Lemon").items[5])
handlers.memberGear({act="gear",data={time=now+1,items={[20]="item:33"}}},"Other Lemon")
assert(p.Get("Other Lemon").display==81)
handlers.memberGear({act="gear",data={time=now+1,race=0,items={}}},"Other Lemon")
assert(p.Get("Other Lemon").time==now, "invalid race rejected")
now=now+2
handlers.memberGear({act="gear",data={time=now,display=81,items={}}},"Other Lemon")
assert(not p.Get("Other Lemon").items[5])
p.Request("Other Lemon")
p.Request("Other Lemon")
assert(#sent==3 and sent[3][4].target=="Other Lemon")
assert(own.copper==123456 and p.Get("Other Lemon").copper==nil)
wallet=0
onEvent(nil,"PLAYER_MONEY")
local message=sent[#sent]
assert(message[2]=="gear" and message[3].copper==0)
handlers.memberGear({act="gear",data=message[3]},"Peer Lemon")
assert(p.Get("Peer Lemon").copper==0)
wallet=50709
onEvent(nil,"PLAYER_MONEY")
handlers.memberGear({act="gear",data=sent[#sent][3]},"Peer Lemon")
assert(p.Get("Peer Lemon").copper==50709)
-- The probe's model reports the outfit as worn; a change goes out once, and a reload
-- that shows the same outfit sends nothing.
local outfit={{appearanceID=0},{appearanceID=0},{appearanceID=0},{appearanceID=0},{appearanceID=700,secondaryAppearanceID=0,illusionID=0}}
for slot=6,19 do outfit[slot]={appearanceID=0} end
outfit[16]={appearanceID=900,secondaryAppearanceID=0,illusionID=55}
model.GetItemTransmogInfoList=function() return outfit end
local before=#sent
model.OnModelLoaded(model)
assert(#sent==before+1 and sent[#sent][3].mog[5][1]==700 and sent[#sent][3].mog[16][3]==55 and not sent[#sent][3].mog[1])
model.OnModelLoaded(model)
assert(#sent==before+1)
-- A guildmate's outfit is checked before it is kept.
now=now+10
handlers.memberGear({act="gear",data={time=now,items={},mog={[5]={1,2,3}}}},"Mog Lemon")
assert(p.Get("Mog Lemon").mog[5][3]==3)
handlers.memberGear({act="gear",data={time=now+1,items={},mog={[20]={1,0,0}}}},"Mog Lemon")
handlers.memberGear({act="gear",data={time=now+1,items={},mog={[5]={-1,0,0}}}},"Mog Lemon")
assert(p.Get("Mog Lemon").time==now)
-- A guildmate drawn live is remembered at most once every five minutes, and the newer of
-- that sighting and their own snapshot is what the flyout draws.
local seenModel={GetItemTransmogInfoList=function() return {[5]={appearanceID=321}} end}
p.Remember("Mog Lemon","nameplate3",seenModel)
assert(p.Preview("Mog Lemon").mog[5][1]==321 and p.Preview("Mog Lemon").race==4)
seenModel.GetItemTransmogInfoList=function() return {[5]={appearanceID=999}} end
now=now+60
p.Remember("Mog Lemon","nameplate3",seenModel)
assert(p.Preview("Mog Lemon").mog[5][1]==321, "throttled")
now=now+300
p.Remember("Mog Lemon","nameplate3",seenModel)
assert(p.Preview("Mog Lemon").mog[5][1]==999, "refreshed after five minutes")
handlers.memberGear({act="gear",data={time=now+1,items={},mog={[5]={444,0,0}}}},"Mog Lemon")
assert(p.Preview("Mog Lemon").mog[5][1]==444, "their newer snapshot wins")
-- Nothing is remembered for this character, or before anything has loaded.
p.Remember("Self Lemon","player",seenModel)
local links=GetInventoryItemLink
GetInventoryItemLink=function(unit,slot) if unit~="nameplate4" then return links(unit,slot) end end
p.Remember("Blank Lemon","nameplate4",{GetItemTransmogInfoList=function() return {} end})
GetInventoryItemLink=links
-- This character keeps its own snapshot, untouched by the sighting.
assert(not p.Preview("Blank Lemon") and p.Preview("Self Lemon").mog[5][1]==700)
craft.db={}
assert(not p.Get("Other Lemon"))
print("Gear capture, late model loads, worn outfits, live sightings, exact item strings, author snapshots, unequipping, request throttling and guild cache isolation passed.")
