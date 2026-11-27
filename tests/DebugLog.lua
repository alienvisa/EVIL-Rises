-- Run with Lua 5.1 from the repository root. Only the WoW transport is mocked.
strmatch = string.match
local function noop() end
CreateFrame = function() return {SetScript=noop, RegisterEvent=noop} end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local now, packets, pending = 2000000, {}, {}
local function client(first, surname, guild)
    local c = {guild=guild, name=first.." "..surname}
    local comm = {}
    function comm.RegisterComm(_,prefix,callback) c.receive=callback end
    function comm:SendCommMessage(prefix,message,channel)
        packets[#packets+1]={prefix,message,channel,c.name}
    end
    local env=setmetatable({
        LibStub=function(name) if name=="AceComm-3.0" then return comm end return LibStub(name) end,
        GetServerTime=function() return now end, UnitFullName=function() return first,surname end,
        IsInGuild=function() return c.guild~=nil end, GetGuildInfo=function() return "EVIL" end,
        GetRealmName=function() return "Forever" end, C_Club={GetGuildClubId=function() return c.guild end},
        date=function() return "12:00:00" end,
        C_Timer={NewTicker=noop, After=function(delay,fn) if delay<2 then pending[#pending+1]=fn end end},
    },{__index=_G})
    c.env=env
    for _,file in ipairs({"Debug","Bounty","Sync"}) do
        local chunk=assert(loadfile("EVILRises/"..file..".lua"))
        setfenv(chunk,env)("EVILRises",c)
    end
    return c
end
local a,b,c=client("First","Lemon",7),client("Second","Lemon",7),client("Other","Guild",8)
local function deliver()
    while #pending>0 or #packets>0 do
        while #pending>0 do table.remove(pending,1)() end
        while #packets>0 do
            local packet=table.remove(packets,1)
            for _,peer in ipairs({a,b,c}) do peer.receive(unpack(packet)) end
        end
    end
end
local function has(client, pattern)
    for _,line in ipairs(client.DebugLog.Lines()) do
        if line:find(pattern) then return line end
    end
end

-- Formatting survives nil arguments and strips control characters.
a.Log("Test","value %s and %d",nil,3)
assert(has(a,"%[Test%]  value nil and 3"))
a.Log("Test","line\nbreak")
assert(has(a,"line break"))

assert(not a:Post("Target Lemon",10000,"Ganked","kos","Horde",""))
deliver()
assert(has(a,"%[Bounty%]  Posted a bounty on Target Lemon"))
assert(has(a,"%[Bounty Out%]  sheet rev %d+, 1 posts"))
assert(has(b,"%[Bounty In%]  sheet rev %d+, 1 posts from First Lemon"))
assert(has(b,"Stored First Lemon's sheet"))
-- A guild's traffic reaches another guild's member only as a dropped message.
assert(has(c,"%[Bounty Drop%]  from First Lemon  ·  another guild"))
assert(not has(c,"Bounty In"))
-- Own messages come back on the guild channel and are not logged as incoming.
assert(not has(a,"Bounty In%]  sheet rev %d+, 1 posts from First Lemon"))

-- The log keeps the newest 500 lines.
for i=1,600 do b.Log("Fill","line %d",i) end
local lines=b.DebugLog.Lines()
assert(#lines==500 and lines[1]:find("line 101$") and lines[500]:find("line 600$"))
b.DebugLog.Clear()
assert(#b.DebugLog.Lines()==0)
print("Debug log: formatting, bounty sync in/out/drop lines, own echoes, ring limit and clearing passed.")
