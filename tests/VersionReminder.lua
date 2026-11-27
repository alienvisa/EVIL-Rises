-- Run with Lua 5.1 from the repository root. Only the WoW transport is mocked.
strmatch = string.match
local function noop() end
CreateFrame = function() return {SetScript=noop, RegisterEvent=noop} end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local now, packets, pending, later = 2000000, {}, {}, {}
local function client(first, surname, version, files)
    local c = {guild=7, name=first.." "..surname, printed={}, tickers={}}
    local comm = {}
    function comm.RegisterComm(_,prefix,callback) c.receive=callback end
    function comm:SendCommMessage(prefix,message,channel)
        packets[#packets+1]={prefix,message,channel,c.name}
    end
    local env=setmetatable({
        LibStub=function(name) if name=="AceComm-3.0" then return comm end return LibStub(name) end,
        GetServerTime=function() return now end, UnitFullName=function() return first,surname end,
        IsInGuild=function() return true end, GetGuildInfo=function() return "EVIL" end,
        GetRealmName=function() return "Forever" end, C_Club={GetGuildClubId=function() return c.guild end},
        C_AddOns={GetAddOnMetadata=function() return version end},
        print=function(text) c.printed[#c.printed+1]=text end,
        date=os.date,
        C_Timer={NewTicker=function(every,fn) c.tickers[#c.tickers+1]={every=every,fn=fn} end,
            After=function(delay,fn)
                if delay<2 then pending[#pending+1]=fn else later[#later+1]={delay=delay,fn=fn} end
            end},
    },{__index=_G})
    for _,file in ipairs(files or {"Debug","Version","Bounty","Sync"}) do
        local chunk=assert(loadfile("EVILRises/"..file..".lua"))
        setfenv(chunk,env)("EVILRises",c)
    end
    return c
end
local old=client("Old","Lemon","0.8.1")
local new=client("New","Lemon","0.9.0")
local older=client("Older","Lemon","0.7.4")
-- A client from before this change: no version in its messages, and no reminder module.
local legacy=client("Legacy","Lemon","0.8.0",{"Bounty","Sync"})
local everyone={old,new,older,legacy}
local function deliver()
    while #pending>0 or #packets>0 do
        while #pending>0 do table.remove(pending,1)() end
        while #packets>0 do
            local packet=table.remove(packets,1)
            for _,c in ipairs(everyone) do c.receive(unpack(packet)) end
        end
    end
end
-- Everyone posts, so every client hears every other one.
for _,c in ipairs(everyone) do assert(not c:Post("Target "..c.name,100,"","kos","Horde","")) end
deliver()

-- Nobody is told before the first wait is over.
for _,c in ipairs(everyone) do assert(#c.printed==0) end
-- Then the out-of-date clients are told once, naming the newest version and their own, even
-- the one that heard 0.8.1 before 0.9.0.
for _,t in ipairs(later) do if t.delay==10 then t.fn() end end
assert(#old.printed==1 and old.printed[1]:find("version 0.9.0 is out, and you have 0.8.1", 1, true))
assert(#older.printed==1 and older.printed[1]:find("version 0.9.0 is out, and you have 0.7.4", 1, true))
assert(#older.tickers==2)
assert(#new.printed==0 and #legacy.printed==0)
-- ...then every 30 minutes while they stay out of date.
assert(#old.tickers==2 and old.tickers[2].every==1800)
old.tickers[2].fn()
assert(#old.printed==2)
-- A second sighting does not start another timer, and a forged version is ignored.
old.NoteVersion("Forger Lemon","99999999999999999999.0.0")
old.NoteVersion("Forger Lemon","1.0")
old.NoteVersion("Forger Lemon","1000.0.0")
old.NoteVersion("Forger Lemon",{})
assert(#old.tickers==2 and #old.printed==2)
-- Messages that carry the version still reach a client from before this change.
assert(legacy.Records()[new.name] and #legacy.Records()[new.name].posts==1)
assert(new.Records()[legacy.name] and #new.Records()[legacy.name].posts==1)
-- The debug log says who runs the newer version.
local found
for _,line in ipairs(old.DebugLog.Lines()) do
    if line:find("New Lemon runs EVIL Rises 0.9.0, newer than this copy (0.8.1)", 1, true) then found=true end
end
assert(found)
print("Update reminder: newer versions seen in sync, one reminder then every 30 minutes, forged versions and older clients passed.")
