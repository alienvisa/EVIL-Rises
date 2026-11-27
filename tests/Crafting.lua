-- Run with Lua 5.1 from the repository root. Only the WoW transport is mocked.
strmatch = string.match
local function noop() end
CreateFrame = function() return {SetScript=noop, RegisterEvent=noop} end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local now, packets, pending = 2000000, {}, {}
local function client(first, surname)
    local c = {guild=7, name=first.." "..surname}
    local comm = {}
    local handlers={}
    function comm.RegisterComm(_,prefix,callback) handlers[prefix]=callback end
    c.receive=function(prefix,...) if handlers[prefix] then handlers[prefix](prefix,...) end end
    function comm:SendCommMessage(prefix,message,channel,target)
        packets[#packets+1]={prefix,message,channel,c.name,to=target}
    end
    local env=setmetatable({
        LibStub=function(name) if name=="AceComm-3.0" then return comm end return LibStub(name) end,
        GetServerTime=function() return now end, UnitFullName=function() return first,surname end,
        IsInGuild=function() return c.guild~=nil end, GetGuildInfo=function() return "EVIL" end,
        GetRealmName=function() return "Forever" end, C_Club={GetGuildClubId=function() return c.guild end},
        GetProfessions=function() if first=="Second" then return 1 end end,
        GetProfessionInfo=function() return "Alchemy",nil,150,150,nil,nil,171 end,
        IsPlayerSpell=function(id) return id==2329 end,
        GetNumGuildMembers=function() return 0 end,
        securecallfunction=function(fn,...) return fn(...) end,
        GetTime=function() return now end, date=os.date,
        C_Timer={NewTicker=noop, After=function(delay,fn) pending[#pending+1]={at=now+delay,fn=fn} end},
    },{__index=_G})
    c.env=env
    for _,file in ipairs({"Debug","Comm","Repair","Bounty","Crafting/Client","Crafting/ProfCatalogForever","Crafting/Professions","Crafting/ProfDirectory","Crafting/ProfSync","Crafting/CraftOrders","Crafting/Sync","Crafting/Page"}) do
        local chunk=assert(loadfile("EVILRises/"..file..".lua"))
        setfenv(chunk,env)("EVILRises",c)
    end
    c.Crafting.BindGuild()
    return c
end
local a,b=client("First","Lemon"),client("Second","Lemon")
local function deliver()
    while #pending>0 or #packets>0 do
        if #pending>0 then
            table.sort(pending,function(x,y) return x.at<y.at end)
            local timer=table.remove(pending,1)
            now=timer.at
            timer.fn()
        end
        while #packets>0 do
            local packet=table.remove(packets,1)
            for _,c in ipairs({a,b}) do if not packet.to or packet.to:gsub("-"," ")==c.name then c.receive(unpack(packet)) end end
        end
    end
end

deliver()
local A,B=a.Crafting,b.Crafting
local recipe=2329
local item=A.ProfCatalog.recipes[recipe][A.ProfCatalog.F.out]
assert(A.Professions:KnowsRecipe(b.name,recipe))
assert(not A.Professions:KnowsRecipe(a.name,recipe))
assert(#A.ProfDirectory.RecipeRows(171,"guild")==1)
local order=assert(A.CraftOrders:Place(item,{recipe=recipe,n=3,mode="mats",tip=110,note="Raid",to=b.name}))
deliver()
local incoming=assert(B.CraftOrders:Rows("forme")[1])
assert(incoming.id==order.id and incoming.who==a.name and incoming.n==3)
assert(B.CraftOrders:Act(order.id,"decline"))
deliver()
assert(B.CraftOrders:Rows("open")[1].id==order.id)
assert(B.CraftOrders:Act(order.id,"accept"))
deliver()
assert(order.cr==b.name and #A.CraftOrders:Needs(order)>0)
assert(A.CraftOrders:Act(order.id,"mats"))
deliver()
assert(B.CraftOrders:Act(order.id,"done"))
deliver()
assert(order.st=="done")
b.guild=8
B.BindGuild()
assert(not B.CraftOrders:Get(order.id))
-- The debug log names crafting traffic in both directions and the guild switch.
local function logged(c, pattern)
    for _,line in ipairs(c.DebugLog.Lines()) do if line:find(pattern) then return true end end
    return false
end
assert(logged(b,"%[Craft In%]  Orders new %(order "))
assert(logged(a,"%[Craft Out%]  Orders new %(order "))
assert(logged(a,"%[Craft In%]  Professions list %(line 171, 1 recipes%) from Second Lemon  ·  addressed to you"))
assert(logged(b,"%[Craft Out%]  Professions list %(line 171, 1 recipes%)  ·  to First Lemon"))
assert(logged(b,"%[Orders%]  Accepted order "))
assert(logged(a,"%[Orders%]  Applied acc from Second Lemon"))
assert(logged(b,"%[Guild%]  Crafting and gear sync bound to guild 8"))
print("Crafting: recipe discovery, guild sync, directed and open queues, materials, completion and guild switch passed.")

