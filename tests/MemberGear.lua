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
craft.db={}
assert(not p.Get("Other Lemon"))
print("Gear capture, late model loads, exact item strings, author snapshots, unequipping, request throttling and guild cache isolation passed.")
