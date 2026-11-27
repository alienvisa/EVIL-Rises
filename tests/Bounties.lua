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
        C_Timer={NewTicker=noop, After=function(delay,fn) if delay<5 then pending[#pending+1]=fn end end},
    },{__index=_G})
    c.env=env
    for _,file in ipairs({"Comm","Repair","Bounty","Sync"}) do
        local chunk=assert(loadfile("EVILRises/"..file..".lua"))
        setfenv(chunk,env)("EVILRises",c)
    end
    return c
end
local a,b=client("First","Lemon"),client("Second","Lemon")
local function deliver()
    while #pending>0 or #packets>0 do
        while #pending>0 do table.remove(pending,1)() end
        while #packets>0 do
            local packet=table.remove(packets,1)
            for _,c in ipairs({a,b}) do if not packet.to or packet.to:gsub("-"," ")==c.name then c.receive(unpack(packet)) end end
        end
    end
end
a.env.EVRFeaturesDB={["EVIL-Forever"]={bounties={["First Lemon-Forever"]={rev=now-1,posts={
    {target="Old target",faction="Horde",reward="1g",reason="Bridge",mode="kos",time=now-86400}
}}}}}
assert(#a.Records()[a.name].posts==1)
b.Request()
deliver()
assert(b.Records()[a.name].posts[1].target=="Old target")
assert(not a:Post("Test",10001,"Bridge","both","Horde","Mage"))
local stale=packets[1]
deliver()
local copy=b.Records()[a.name].posts[1]
assert(copy.copper==10001 and copy.reward=="1g 0s 1c" and copy.mode=="both")
b:Withdraw(copy)
assert(#b.Records()[a.name].posts==2)
a:Withdraw(a.Records()[a.name].posts[1])
deliver()
b.receive(unpack(stale))
assert(#b.Records()[a.name].posts==1)
b.guild=8
b.receive(unpack(stale))
assert(not b.Records()[a.name])
b.guild=7
now=now+7*86400
b.Update()
a.Update()
deliver()
assert(#a.Records()[a.name].posts==0 and #b.Records()[a.name].posts==0)
assert(a:Post("Test",0,"","both","Horde",""))
print("Passed migration, catch-up, posting, authorization, withdrawal, replay, guild isolation and expiry.")

