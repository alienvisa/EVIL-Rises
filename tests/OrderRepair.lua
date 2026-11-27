-- Run with Lua 5.1 from the repository root. Only the WoW transport is mocked.
-- Three guildmates on the new format; chosen order messages are lost on the way, and the
-- summaries repair every copy.
strmatch = string.match
local function noop() end
CreateFrame = function() return {SetScript=noop, RegisterEvent=noop} end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local codec, wire = LibStub("EVRFeatures-LibSerialize"), LibStub("LibDeflate")
local now, packets, pending = 2000000, {}, {}
local FILES = {"Debug","Version","Comm","Bounty","Sync","Crafting/Client","Crafting/ProfCatalogForever",
    "Crafting/Professions","Crafting/ProfDirectory","Crafting/ProfSync","Crafting/CraftOrders","Crafting/Sync","Crafting/Page"}
local function client(first, surname)
    local c = {guild=7, name=first.." "..surname}
    local comm, handlers = {}, {}
    function comm.RegisterComm(_,prefix,callback) handlers[prefix]=callback end
    c.receive=function(prefix,...) if handlers[prefix] then handlers[prefix](prefix,...) end end
    function comm:SendCommMessage(prefix,message,channel,_,prio)
        packets[#packets+1]={prefix,message,channel,c.name,prio}
    end
    local env=setmetatable({
        LibStub=function(name) if name=="AceComm-3.0" then return comm end return LibStub(name) end,
        GetServerTime=function() return now end, UnitFullName=function() return first,surname end,
        IsInGuild=function() return true end, GetGuildInfo=function() return "EVIL" end,
        GetRealmName=function() return "Forever" end, C_Club={GetGuildClubId=function() return c.guild end},
        C_AddOns={GetAddOnMetadata=function() return "0.10.0" end},
        GetProfessions=function() if first=="Second" then return 1 end end,
        GetProfessionInfo=function() return "Alchemy",nil,150,150,nil,nil,171 end,
        IsPlayerSpell=function(id) return id==2329 end,
        GetNumGuildMembers=function() return 0 end,
        securecallfunction=function(fn,...) return fn(...) end,
        GetTime=function() return now end, date=os.date, print=noop,
        C_Timer={NewTicker=noop, After=function(delay,fn) pending[#pending+1]={at=now+delay,fn=fn} end},
    },{__index=_G})
    for _,file in ipairs(FILES) do
        local chunk=assert(loadfile("EVILRises/"..file..".lua"))
        setfenv(chunk,env)("EVILRises",c)
    end
    c.Crafting.BindGuild()
    c.Orders=c.Crafting.CraftOrders
    return c
end
local a,b,c=client("First","Lemon"),client("Second","Lemon"),client("Third","Lemon")
local everyone={a,b,c}
local function decoded(packet)
    if packet[1]~="EVRSync2" then return nil end
    local ok,m=codec:Deserialize(wire:DecodeForWoWAddonChannel(packet[2]))
    return ok and m or nil
end
-- Delivers every message, except those `lost` returns true for (packet, receiver, message),
-- running the timers due in the next five minutes.
local sent={}
local function deliver(lost)
    while true do
        while #packets>0 do
            local packet=table.remove(packets,1)
            local m=decoded(packet)
            sent[#sent+1]={packet=packet,m=m}
            for _,peer in ipairs(everyone) do
                if not (lost and m and lost(packet,peer,m)) then peer.receive(unpack(packet)) end
            end
        end
        table.sort(pending,function(x,y) return x.at<y.at end)
        if #pending==0 or pending[1].at>now+300 then break end
        local timer=table.remove(pending,1)
        now=math.max(now,timer.at)
        timer.fn()
    end
end
-- Loses order action `act` on its way to the clients in `to`.
local function lose(act,to)
    return function(_,peer,m)
        if m.d~="craftorder" or m.a~=act then return false end
        for _,p in ipairs(to) do if p==peer then return true end end
        return false
    end
end
local function summaries(...)
    for _,p in ipairs({...}) do p.Orders:PublishSummary() end
    deliver()
end
local function count(where, d, act)
    local n=0
    for i=where,#sent do local m=sent[i].m if m and m.d==d and m.a==act then n=n+1 end end
    return n
end
deliver()
local recipe=2329
local item=a.Crafting.ProfCatalog.recipes[recipe][a.Crafting.ProfCatalog.F.out]

-- An acceptance lost on the way to the author and a bystander comes back from the crafter's summary,
-- in one answer to both.
local o1=assert(a.Orders:Place(item,{recipe=recipe,n=1,mode="mats"}))
deliver()
assert(b.Orders:Act(o1.id,"accept"))
deliver(lose("acc",{a,c}))
assert(a.Orders:Get(o1.id).st=="open" and c.Orders:Get(o1.id).st=="open")
local mark=#sent+1
summaries(b)
for _,p in ipairs(everyone) do
    local o=p.Orders:Get(o1.id)
    assert(o.st=="accepted" and o.cr==b.name, p.name)
end
assert(count(mark,"craftorder","get")==2 and count(mark,"craftorder","fix")==1)

-- Summaries, requests and answers are new-format only, and order actions do not wait behind bulk.
for i=mark,#sent do assert(sent[i].packet[1]=="EVRSync2") end
for _,s in ipairs(sent) do
    if s.m and s.m.d=="craftorder" then assert(s.packet[5]=="NORMAL") end
    if s.m and s.m.d=="prof" then assert(s.packet[5]=="BULK") end
end

-- A summary that matches asks for nothing.
mark=#sent+1
summaries(a,b,c)
assert(count(mark,"craftorder","get")==0)

-- Materials and completion, both lost to the bystander, are replayed in order.
assert(a.Orders:Act(o1.id,"mats"))
deliver(lose("mats",{c}))
assert(b.Orders:Act(o1.id,"done"))
deliver(lose("done",{c}))
assert(c.Orders:Get(o1.id).st=="accepted")
summaries(b)
assert(c.Orders:Get(o1.id).st=="done")

-- A release lost to the bystander: the crafter still speaks for the order it gave back.
local o2=assert(a.Orders:Place(item,{recipe=recipe,n=2,mode="own"}))
deliver()
assert(b.Orders:Act(o2.id,"accept"))
deliver()
assert(b.Orders:Act(o2.id,"release"))
deliver(lose("rel",{c}))
assert(c.Orders:Get(o2.id).cr==b.name)
summaries(b)
assert(c.Orders:Get(o2.id).st=="open" and c.Orders:Get(o2.id).cr==nil)

-- A decline lost to the bystander comes back from the one who declined.
local o3=assert(a.Orders:Place(item,{recipe=recipe,n=1,mode="own",to=b.name}))
deliver()
assert(b.Orders:Act(o3.id,"decline"))
deliver(lose("dec",{c}))
assert(c.Orders:Get(o3.id).to==b.name)
summaries(a)                      -- the author cannot speak for a decline...
assert(c.Orders:Get(o3.id).to==b.name)
summaries(b)                      -- ...the crafter who declined can.
assert(c.Orders:Get(o3.id).to==nil)

-- A cancellation lost to everyone but the author.
assert(a.Orders:Act(o3.id,"cancel"))
deliver(lose("can",{b,c}))
assert(b.Orders:Get(o3.id).st=="open")
summaries(a)
assert(b.Orders:Get(o3.id).st=="cancelled" and c.Orders:Get(o3.id).st=="cancelled")

-- A new order lost to one guildmate arrives from its author's summary.
local o4=assert(a.Orders:Place(item,{recipe=recipe,n=1,mode="own"}))
deliver(lose("new",{c}))
assert(not c.Orders:Get(o4.id))
summaries(a)
assert(c.Orders:Get(o4.id) and c.Orders:Get(o4.id).st=="open")

-- Two crafters accepted at once and each heard only itself: the earlier keeps the order everywhere.
assert(b.Orders:Apply("acc",{id=o4.id,at=now},b.name))
assert(c.Orders:Apply("acc",{id=o4.id,at=now+5},c.name))
now=now+b.Orders.TAKEOVER+10      -- heard late: the live "at once" rule no longer applies
summaries(c,b)
assert(b.Orders:Get(o4.id).cr==b.name and c.Orders:Get(o4.id).cr==b.name)

-- A difference replaying cannot settle (this copy says done, the crafter says accepted) is asked
-- about a few times, then no more.
local o5=a.Orders:Get(o4.id)
o5.st,o5.at="done",0
mark=#sent+1
for _=1,6 do now=now+b.Orders.REASK_AFTER+1; summaries(b) end
assert(count(mark,"craftorder","get")<=b.Orders.ASK_TIMES)
print("Order repair: lost acceptances, materials, completion, releases, declines, cancellations and new orders come back from summaries; races settle; repeats are capped.")
