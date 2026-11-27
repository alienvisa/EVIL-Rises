-- Run with Lua 5.1 from the repository root. Only the WoW transport is mocked.
-- Two clients on the new message format and one 0.9.0 client (tests/legacy) share a guild.
strmatch = string.match
local function noop() end
CreateFrame = function() return {SetScript=noop, RegisterEvent=noop} end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local codec, wire = LibStub("EVRFeatures-LibSerialize"), LibStub("LibDeflate")
local now, packets, pending = 2000000, {}, {}
local CRAFTING = {"Crafting/Client","Crafting/ProfCatalogForever","Crafting/Professions","Crafting/ProfDirectory",
    "Crafting/ProfSync","Crafting/CraftOrders"}
local function files(legacy)
    local list = legacy and {"Debug","Bounty","../tests/legacy/Sync"} or {"Debug","Version","Comm","Bounty","Sync"}
    for _, f in ipairs(CRAFTING) do list[#list+1] = f end
    list[#list+1] = legacy and "../tests/legacy/Crafting/Sync" or "Crafting/Sync"
    list[#list+1] = "Crafting/Page"
    return list
end
local function client(first, surname, legacy)
    local c = {guild=7, name=first.." "..surname}
    local comm, handlers = {}, {}
    function comm.RegisterComm(_,prefix,callback) handlers[prefix]=callback end
    c.receive=function(prefix,...) if handlers[prefix] then handlers[prefix](prefix,...) end end
    function comm:SendCommMessage(prefix,message,channel)
        packets[#packets+1]={prefix,message,channel,c.name}
    end
    local env=setmetatable({
        LibStub=function(name) if name=="AceComm-3.0" then return comm end return LibStub(name) end,
        GetServerTime=function() return now end, UnitFullName=function() return first,surname end,
        IsInGuild=function() return c.guild~=nil end, GetGuildInfo=function() return "EVIL" end,
        GetRealmName=function() return "Forever" end, C_Club={GetGuildClubId=function() return c.guild end},
        C_AddOns={GetAddOnMetadata=function() return legacy and "0.9.0" or "0.10.0" end},
        GetProfessions=function() if first=="Second" then return 1 end end,
        GetProfessionInfo=function() return "Alchemy",nil,150,150,nil,nil,171 end,
        IsPlayerSpell=function(id) return id==2329 end,
        GetNumGuildMembers=function() return 0 end,
        securecallfunction=function(fn,...) return fn(...) end,
        GetTime=function() return now end, date=os.date, print=noop,
        C_Timer={NewTicker=noop, After=function(delay,fn) pending[#pending+1]={at=now+delay,fn=fn} end},
    },{__index=_G})
    c.env=env
    for _,file in ipairs(files(legacy)) do
        local chunk=assert(loadfile("EVILRises/"..file..".lua"))
        setfenv(chunk,env)("EVILRises",c)
    end
    c.Crafting.BindGuild()
    return c
end
local a,b,l=client("First","Lemon"),client("Second","Lemon"),client("Legacy","Lemon",true)
local online={a,b,l}
-- Delivers every message, running the timers due in the next five minutes; later ones (such as
-- bounty expiry a week out) stay pending.
local function deliver()
    while true do
        while #packets>0 do
            local packet=table.remove(packets,1)
            for _,c in ipairs(online) do c.receive(unpack(packet)) end
        end
        table.sort(pending,function(x,y) return x.at<y.at end)
        if #pending==0 or pending[1].at>now+300 then break end
        local timer=table.remove(pending,1)
        now=math.max(now,timer.at)
        timer.fn()
    end
end
local function count(c, pattern)
    local n=0
    for _,line in ipairs(c.DebugLog.Lines()) do if line:find(pattern) then n=n+1 end end
    return n
end
local function sentBy(c, prefix)
    local n=0
    for _,p in ipairs(packets) do if p[4]==c.name and p[1]==prefix then n=n+1 end end
    return n
end
deliver()

-- Bounties travel both ways between the formats, and a new client reads each message once.
assert(not a:Post("Target One",100,"","kos","Horde",""))
assert(sentBy(a,"EVRSync2")==1 and sentBy(a,"EVRBounty1")==1)
deliver()
assert(#l.Records()[a.name].posts==1 and #b.Records()[a.name].posts==1)
assert(count(b,"%[Bounty In%]  sheet rev %d+, 1 posts from First Lemon")==1)
assert(not l:Post("Target Two",100,"","kos","Horde",""))
deliver()
assert(#a.Records()[l.name].posts==1 and #b.Records()[l.name].posts==1)

-- Crafting orders too: one placed by the old client is accepted by a new one, and the other way.
local A,B,L=a.Crafting,b.Crafting,l.Crafting
local recipe=2329
local item=A.ProfCatalog.recipes[recipe][A.ProfCatalog.F.out]
local old=assert(L.CraftOrders:Place(item,{recipe=recipe,n=1,mode="own",to=b.name}))
deliver()
assert(B.CraftOrders:Get(old.id) and A.CraftOrders:Get(old.id))
assert(B.CraftOrders:Act(old.id,"accept"))
deliver()
assert(old.cr==b.name and A.CraftOrders:Get(old.id).cr==b.name)
local new=assert(A.CraftOrders:Place(item,{recipe=recipe,n=2,mode="own"}))
deliver()
assert(L.CraftOrders:Get(new.id) and B.CraftOrders:Get(new.id))
assert(count(b,"%[Craft In%]  Orders new %(order "..new.id)==1)

-- New clients learn what each other understand; the old client never says.
assert(a.Comm:Supports(b.name,"bounty") and a.Comm:Supports(b.name,"craftorder"))
assert(not a.Comm:Supports(b.name,"craftorder",2))
assert(not a.Comm:Supports(l.name,"bounty") and not a.Comm:PeerCaps(l.name))

-- A newer client's message: an unknown field is ignored, a newer format and an unknown area are
-- dropped and logged.
local function inject(to, message)
    to.receive("EVRSync2", wire:EncodeForWoWAddonChannel(codec:Serialize(message)), "GUILD", b.name)
end
inject(a,{v=2,g="7",d="bounty",a="hello",p=false,ver="0.11.0",future={1,2,3}})
assert(count(a,"%[Bounty In%]  hello %(asks for revisions%) from Second Lemon")>=1)
inject(a,{v=3,g="7",d="bounty",a="hello",p=false})
assert(count(a,"%[Bounty Drop%]  from Second Lemon  ·  newer message format %(3%)")==1)
inject(a,{v=2,g="7",d="raid",a="pull",p={}})
assert(count(a,"%[Sync Drop%]  raid pull from Second Lemon  ·  unknown message")==1)
inject(a,{v=2,g="8",d="bounty",a="hello",p=false})
assert(count(a,"%[Bounty Drop%]  from Second Lemon  ·  another guild")==1)
deliver()

-- Once the old client has been gone for LEGACY_FOR seconds, only the new format goes out...
online={a,b}
now=now+a.Comm.LEGACY_FOR+1
assert(not a.Comm:SendsLegacy())
assert(not a:Post("Target Three",100,"","kos","Horde",""))
assert(sentBy(a,"EVRSync2")==1 and sentBy(a,"EVRBounty1")==0)
deliver()
assert(#b.Records()[a.name].posts==2)
-- ...until it is heard again.
online={a,b,l}
assert(not l:Post("Target Four",100,"","kos","Horde",""))
deliver()
assert(a.Comm:SendsLegacy())
assert(not a:Post("Target Five",100,"","kos","Horde",""))
assert(sentBy(a,"EVRBounty1")==1)
deliver()
assert(#l.Records()[a.name].posts==3)
print("Sync formats: old and new clients side by side, one read per message, capabilities, unknown fields and areas, and old-format copies stopping and resuming passed.")
