-- Run with Lua 5.1 from the repository root. Only the WoW transport is mocked.
-- Three guildmates on the current format: gear and Bounty sheets lost on the way come back from
-- summaries, and a message for one member goes to that member only, by whisper.
strmatch = string.match
local function noop() end
CreateFrame = function() return {SetScript=noop, RegisterEvent=noop} end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local codec, wire = LibStub("EVRFeatures-LibSerialize"), LibStub("LibDeflate")
local now, packets, pending = 2000000, {}, {}
local FILES = {"Debug","Version","Comm","Repair","Bounty","Sync","Crafting/Client","Crafting/ProfCatalogForever",
    "Crafting/Professions","Crafting/ProfDirectory","Crafting/ProfSync","Crafting/CraftOrders","Crafting/Sync",
    "Crafting/Page","MemberGear"}
local function client(first, surname)
    local c = {guild=7, name=first.." "..surname, whisperName=first.."-"..surname, tickers={}, frames={},
        gear={[16]="|cff00ff00|Hitem:123:0|h[Sword]|h|r"}}
    local comm, handlers = {}, {}
    function comm.RegisterComm(_,prefix,callback) handlers[prefix]=callback end
    c.receive=function(prefix,...) if handlers[prefix] then handlers[prefix](prefix,...) end end
    function comm:SendCommMessage(prefix,message,channel,target,prio)
        packets[#packets+1]={prefix,message,channel,c.name,prio,to=target}
    end
    local function frame()
        local f={events={},scripts={}}
        function f.RegisterEvent(self,event) self.events[event]=true end
        function f.SetScript(self,name,fn) self.scripts[name]=fn end
        for _,m in ipairs({"SetSize","SetPoint","SetAlpha","SetUnit","Hide","Show"}) do f[m]=noop end
        f.GetDisplayInfo=function() return 0 end
        c.frames[#c.frames+1]=f
        return f
    end
    local env=setmetatable({
        LibStub=function(name) if name=="AceComm-3.0" then return comm end return LibStub(name) end,
        CreateFrame=frame,
        GetServerTime=function() return now end, UnitFullName=function() return first,surname end,
        IsInGuild=function() return true end, GetGuildInfo=function() return "EVIL" end,
        GetRealmName=function() return "Forever" end, C_Club={GetGuildClubId=function() return c.guild end},
        C_AddOns={GetAddOnMetadata=function() return "0.10.0" end},
        GetProfessions=function() if first=="Second" then return 1 end end,
        GetProfessionInfo=function() return "Alchemy",nil,150,150,nil,nil,171 end,
        IsPlayerSpell=function(id) return id==2329 end,
        GetNumGuildMembers=function() return 0 end,
        GetInventoryItemLink=function(_,slot) return c.gear[slot] end,
        GetInventoryItemID=function() return nil end,
        UnitRace=function() return "Human","Human",1 end, UnitSex=function() return 2 end,
        GetMoney=function() return 100 end,
        ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing.",
        securecallfunction=function(fn,...) return fn(...) end,
        GetTime=function() return now end, date=os.date, print=noop,
        C_Timer={NewTicker=function(every,fn) c.tickers[#c.tickers+1]={every=every,fn=fn} end,
            After=function(delay,fn) pending[#pending+1]={at=now+delay,fn=fn} end},
    },{__index=_G})
    for _,file in ipairs(FILES) do
        local chunk=assert(loadfile("EVILRises/"..file..".lua"))
        setfenv(chunk,env)("EVILRises",c)
    end
    c.Crafting.BindGuild()
    return c
end
local a,b,c=client("First","Lemon"),client("Second","Lemon"),client("Third","Lemon")
local everyone={a,b,c}
local function decoded(packet)
    if packet[1]~="EVRSync2" then return nil end
    local ok,m=codec:Deserialize(wire:DecodeForWoWAddonChannel(packet[2]))
    return ok and m or nil
end
-- Delivers every message (a whisper to its target only), except those `lost` returns true for
-- (packet, receiver, message), running the timers due in the next five minutes.
local sent={}
local function deliver(lost)
    while true do
        while #packets>0 do
            local packet=table.remove(packets,1)
            local m=decoded(packet)
            sent[#sent+1]={packet=packet,m=m}
            for _,peer in ipairs(everyone) do
                local reaches=not packet.to or packet.to==peer.whisperName
                if reaches and not (lost and m and lost(packet,peer,m)) then peer.receive(unpack(packet)) end
            end
        end
        table.sort(pending,function(x,y) return x.at<y.at end)
        if #pending==0 or pending[1].at>now+300 then break end
        local timer=table.remove(pending,1)
        now=math.max(now,math.ceil(timer.at))   -- server time is whole seconds
        timer.fn()
    end
end
-- Loses `area`'s `act` messages on their way to the clients in `to`.
local function lose(area,act,to)
    return function(_,peer,m)
        if m.d~=area or m.a~=act then return false end
        for _,p in ipairs(to) do if p==peer then return true end end
        return false
    end
end
-- Runs `who`'s timers that repeat every `every` seconds, then delivers.
local function tick(who,every,lost)
    for _,t in ipairs(who.tickers) do if t.every==every then t.fn() end end
    deliver(lost)
end
-- Messages of `area`'s `act` sent since `from`, and those among them that went by whisper.
local function count(from,area,act)
    local n,whispered=0,0
    for i=from,#sent do
        local m=sent[i].m
        if m and m.d==area and m.a==act then
            n=n+1
            if sent[i].packet[3]=="WHISPER" then whispered=whispered+1 end
        end
    end
    return n,whispered
end
local function logged(who,pattern)
    local n=0
    for _,line in ipairs(who.DebugLog.Lines()) do if line:find(pattern) then n=n+1 end end
    return n
end
deliver()

-- Every message addressed to one member went by whisper, and only that member got it. The
-- recipe lists asked for at login arrived.
local addressed=0
for _,s in ipairs(sent) do
    if s.m and s.m.to then
        addressed=addressed+1
        assert(s.packet[3]=="WHISPER" and s.packet.to==s.m.to:gsub(" ","-",1), s.m.d.." "..s.m.a)
    end
end
assert(addressed>0)
local own=b.Crafting.Professions:OwnLine(171)
for _,p in ipairs({a,c}) do
    local held=p.Crafting.Professions:Get(b.name)
    assert(held and held.profs[171] and held.profs[171].h==own.h and held.profs[171].recipes, p.name)
end

-- A gear snapshot lost on the way to one guildmate comes back from the next summary, by whisper
-- to that guildmate only.
local G="memberGear"
a.Profile.Request(a.name)
deliver(lose(G,"gear",{c}))
assert(b.Profile.Get(a.name) and not c.Profile.Get(a.name))
local mark=#sent+1
tick(a,600)
assert(c.Profile.Get(a.name).time==a.Profile.Get(a.name).time)
assert(c.Profile.Get(a.name).items[16]=="item:123:0")
local asks,askWhispers=count(mark,G,"request")
local answers,answerWhispers=count(mark,G,"gear")
assert(asks==1 and askWhispers==1 and answers==1 and answerWhispers==1)
-- A summary that matches asks for nothing.
mark=#sent+1
tick(a,600)
assert(count(mark,G,"request")==0)

-- A change lost to both guildmates: one answer to the whole guild.
now=now+5
a.gear[1]="|cff00ff00|Hitem:77:0|h[Helm]|h|r"
a.Profile.Request(a.name)
deliver(lose(G,"gear",{b,c}))
assert(b.Profile.Get(a.name).items[1]==nil and c.Profile.Get(a.name).items[1]==nil)
mark=#sent+1
tick(a,600)
answers,answerWhispers=count(mark,G,"gear")
assert(count(mark,G,"request")==2 and answers==1 and answerWhispers==0)
assert(b.Profile.Get(a.name).items[1]=="item:77:0" and c.Profile.Get(a.name).items[1]=="item:77:0")

-- A Bounty sheet lost to one guildmate: the next revision announcement brings it, by whisper.
assert(not a:Post("Target One",100,"","kos","Horde",""))
deliver(lose("bounty","sheet",{c}))
assert(#b.Records()[a.name].posts==1 and not (c.Records()[a.name] and #c.Records()[a.name].posts==1))
mark=#sent+1
tick(a,60)
assert(#c.Records()[a.name].posts==1)
local gets,getWhispers=count(mark,"bounty","get")
local sheets,sheetWhispers=count(mark,"bounty","sheet")
assert(gets==1 and getWhispers==1 and sheets==1 and sheetWhispers==1)

-- A whisper that bounces goes again on the guild channel, and that member gets guild messages
-- for a while.
local function bounce(who,name)
    for _,f in ipairs(who.frames) do
        if f.events.CHAT_MSG_SYSTEM and f.scripts.OnEvent then
            f.scripts.OnEvent(f,"CHAT_MSG_SYSTEM",string.format("No player named '%s' is currently playing.",name))
        end
    end
end
now=now+a.Comm.BOUNCE_WITHIN+1   -- the Bounty sheet whispered above is not sent again
a.gear[2]="|cff00ff00|Hitem:78:0|h[Necklace]|h|r"
a.Profile.Request(a.name)
deliver(lose(G,"gear",{c}))
local whispersLost=function(packet) return packet[3]=="WHISPER" and packet.to==c.whisperName end
mark=#sent+1
tick(a,600,whispersLost)
assert(c.Profile.Get(a.name).items[2]==nil)
bounce(a,c.whisperName)
deliver()
assert(c.Profile.Get(a.name).items[2]=="item:78:0")
answers,answerWhispers=count(mark,G,"gear")
assert(answers==2 and answerWhispers==1)
assert(logged(a,"whisper to Third Lemon bounced, sent on the guild channel")==1)
assert(not a.Comm:WhisperName(c.name) and a.Comm:WhisperName(b.name)==b.whisperName)
now=now+a.Comm.LEGACY_FOR+1
assert(a.Comm:WhisperName(c.name)==c.whisperName)
-- A bounce heard long after the whisper sends nothing again.
mark=#sent+1
assert(a.Comm:Send("bounty","hello",false,{target=c.name}))
deliver()
assert(count(mark,"bounty","hello")==1 and sent[mark].packet[3]=="WHISPER")
now=now+a.Comm.BOUNCE_WITHIN+1
bounce(a,c.whisperName)
deliver()
assert(logged(a,"bounced, sent on the guild channel")==1)

-- A whisper is read only from a member heard on the guild channel.
local stranger=wire:EncodeForWoWAddonChannel(codec:Serialize({v=2,g="7",d="bounty",a="hello",p=false}))
a.receive("EVRSync2",stranger,"WHISPER","Stranger Lemon")
assert(logged(a,"whisper from Stranger Lemon  ·  not heard in the guild")==1)
print("Area repair: gear and Bounty sheets come back from summaries, messages for one member go by whisper, bounced whispers fall back to the guild channel.")
