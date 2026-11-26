local now=1000
local handlers={}
local sent={}
local noop=function() end
local craft={guild="7",db={},SyncService={}}
function craft.SyncService:On(k,fn) handlers[k]=fn end
function craft.SyncService:Publish(k,act,p,opts) sent[#sent+1]={k,act,p,opts} end
local addon={Crafting=craft,GuildID=function() return craft.guild end,Owner=function(n) return n or "Self Lemon" end}
C_Timer={After=function(_,fn) fn() end}
function GetServerTime() return now end
GetTime=GetServerTime
function GetInventoryItemID(_,s) if s==16 then return 123 end end
function GetInventoryItemLink(_,s) if s==16 then return "|cff00ff00|Hitem:123:9|h[Sword]|h|r" end end
function CreateFrame() return {SetSize=noop,SetPoint=noop,SetUnit=noop,GetDisplayInfo=function() return 80 end,RegisterEvent=noop,SetScript=noop} end
assert(loadfile("EVILRises/MemberGear.lua"))("EVILRises",addon)
assert(loadfile("EVILRises/MemberFlyout.lua"))
local p=addon.Profile
p.Request("Self Lemon")
local own=p.Get("Self Lemon")
assert(own.display==80 and own.items[16]=="item:123:9")
p.Request("Self Lemon")
assert(#sent==1)
handlers.memberGear({act="gear",data={time=now,display=81,items={[5]="item:42:0"}}},"Other Lemon")
assert(p.Get("Other Lemon").items[5]=="item:42:0")
handlers.memberGear({act="gear",data={time=now-1,items={}}},"Other Lemon")
assert(p.Get("Other Lemon").items[5])
handlers.memberGear({act="gear",data={time=now+1,items={[20]="item:33"}}},"Other Lemon")
assert(p.Get("Other Lemon").display==81)
now=now+2
handlers.memberGear({act="gear",data={time=now,display=81,items={}}},"Other Lemon")
assert(not p.Get("Other Lemon").items[5])
p.Request("Other Lemon")
p.Request("Other Lemon")
assert(#sent==2 and sent[2][4].target=="Other Lemon")
craft.db={}
assert(not p.Get("Other Lemon"))
print("Gear capture, exact item strings, author snapshots, unequipping, request throttling and guild cache isolation passed.")
