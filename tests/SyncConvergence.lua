-- Run with Lua 5.1 from the repository root. Only the WoW transport and clock are mocked.
-- A simulated guild: four members on the current format, one on 0.9.0 (tests/legacy) and one
-- that logs in halfway. For the first STORM seconds every new-format message is lost on its way
-- to each member with chance LOSS, and every member hears messages in a random order. A long
-- message the game splits into parts is lost when any part is; that is a lost message here too.
-- Then the channel is calm, and after CALM seconds every member must hold the same orders,
-- Bounty sheets, recipe lists and gear snapshots. Old-format messages are never lost: a 0.9.0
-- copy has no repair, so the suite measures what the current format repairs.
strmatch = string.match
local function noop() end
CreateFrame = function() return {SetScript=noop, RegisterEvent=noop} end
dofile("EVILRises/Libs/LibStub.lua")
dofile("EVILRises/Libs/LibSerialize.lua")
dofile("EVILRises/Libs/LibDeflate.lua")
local STORM, CALM, LOSS, SEEDS = 240, 900, 0.2, 12
local CURRENT = {"Debug","Version","Comm","Repair","Bounty","Sync","Crafting/Client","Crafting/ProfCatalogForever",
    "Crafting/Professions","Crafting/ProfDirectory","Crafting/ProfSync","Crafting/CraftOrders","Crafting/Sync",
    "Crafting/Page","MemberGear"}
local OLD = {Comm=false, Repair=false, Sync="../tests/legacy/Sync", ["Crafting/ProfSync"]="../tests/legacy/Crafting/ProfSync",
    ["Crafting/CraftOrders"]="../tests/legacy/Crafting/CraftOrders", ["Crafting/Sync"]="../tests/legacy/Crafting/Sync",
    MemberGear="../tests/legacy/MemberGear"}
local RECIPE = 2329

local function simulate(seed)
    local rng = { seed = seed }
    -- The suite's own random numbers, apart from the addon's math.random.
    local function chance()
        rng.seed = (rng.seed * 1103515245 + 12345) % 2147483648
        return rng.seed / 2147483648
    end
    math.randomseed(seed)
    local now, pending, tickers, members = 3000000, {}, {}, {}
    local lossy, forced = true, nil
    local function deliverTo(peer, packet) peer.receive(unpack(packet)) end
    local function client(first, legacy, crafter)
        local c = {name=first.." Lemon", whisperName=first.."-Lemon", legacy=legacy, frames={}, inbox={},
            gear={[16]="|cff00ff00|Hitem:123:0|h[Sword]|h|r"}}
        local comm, handlers = {}, {}
        function comm.RegisterComm(_,prefix,callback) handlers[prefix]=callback end
        c.receive=function(prefix,...) if handlers[prefix] then handlers[prefix](prefix,...) end end
        function comm:SendCommMessage(prefix,message,channel,target)
            local packet={prefix,message,channel,c.name,to=target}
            for _,peer in ipairs(members) do
                if peer~=c and (not target or target==peer.whisperName) then
                    local lost=prefix=="EVRSync2" and ((lossy and chance()<LOSS) or (forced and forced(packet,peer)))
                    if not lost then peer.inbox[#peer.inbox+1]=packet end
                end
            end
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
            GetServerTime=function() return now end, UnitFullName=function() return first,"Lemon" end,
            IsInGuild=function() return true end, GetGuildInfo=function() return "EVIL" end,
            GetRealmName=function() return "Forever" end, C_Club={GetGuildClubId=function() return 7 end},
            C_AddOns={GetAddOnMetadata=function() return legacy and "0.9.0" or "0.10.0" end},
            GetProfessions=function() if crafter then return 1 end end,
            GetProfessionInfo=function() return "Alchemy",nil,150,150,nil,nil,171 end,
            IsPlayerSpell=function(id) return crafter and id==RECIPE end,
            GetNumGuildMembers=function() return 0 end,
            GetInventoryItemLink=function(_,slot) return c.gear[slot] end,
            GetInventoryItemID=function() return nil end,
            UnitRace=function() return "Human","Human",1 end, UnitSex=function() return 2 end,
            GetMoney=function() return 100 end,
            ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing.",
            securecallfunction=function(fn,...) return fn(...) end,
            GetTime=function() return now end, date=os.date, print=noop,
            C_Timer={NewTicker=function(every,fn) tickers[#tickers+1]={every=every,next=now+every,fn=fn} end,
                After=function(delay,fn) pending[#pending+1]={at=now+delay,fn=fn} end},
        },{__index=_G})
        members[#members+1]=c
        for _,f in ipairs(CURRENT) do
            local file=f
            if legacy and OLD[f]~=nil then file=OLD[f] end
            if file then
                local chunk=assert(loadfile("EVILRises/"..file..".lua"))
                setfenv(chunk,env)("EVILRises",c)
            end
        end
        c.Crafting.BindGuild()
        c.Orders=c.Crafting.CraftOrders
        -- Logging in: the events each module waits for.
        for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD"}) do
            for _,f in ipairs(c.frames) do
                if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event) end
            end
        end
        return c
    end
    -- Hears every message waiting, each member in a random order, then runs what is due, until
    -- `untilT`.
    local function run(untilT)
        while true do
            local busy=true
            while busy do
                busy=false
                for _,peer in ipairs(members) do
                    if #peer.inbox>0 then
                        busy=true
                        local packet=table.remove(peer.inbox,1+math.floor(chance()*#peer.inbox))
                        deliverTo(peer,packet)
                    end
                end
            end
            local nextAt,which,kind=math.huge
            for i,t in ipairs(pending) do if t.at<nextAt then nextAt,which,kind=t.at,i,"after" end end
            for i,t in ipairs(tickers) do if t.next<nextAt then nextAt,which,kind=t.next,i,"ticker" end end
            if nextAt>untilT then break end
            now=math.max(now,math.ceil(nextAt))   -- server time is whole seconds
            if kind=="after" then
                table.remove(pending,which).fn()
            else
                local t=tickers[which]
                t.next=t.next+t.every
                t.fn()
            end
        end
        now=math.max(now,untilT)
    end
    local start=now
    local function at(t) run(start+t) end

    local a,b,c,d=client("Ada"),client("Bea",false,true),client("Cal"),client("Dee")
    local old=client("Old",true)
    local item=a.Crafting.ProfCatalog.recipes[RECIPE][a.Crafting.ProfCatalog.F.out]
    at(20)
    -- Two crafters accept one order at once.
    local o1=assert(a.Orders:Place(item,{recipe=RECIPE,n=1,mode="mats"}))
    at(25)
    -- Either may not have heard of the order yet: its first message can be lost too.
    local raced=b.Orders:Act(o1.id,"accept")
    raced=c.Orders:Act(o1.id,"accept") or raced
    at(40)
    assert(not a:Post("Target A",100,"","kos","Horde",""))
    assert(not d:Post("Target D",200,"","camp","Horde",""))
    -- A guildmate misses an acceptance, then the release.
    at(60)
    local o2=assert(d.Orders:Place(item,{recipe=RECIPE,n=2,mode="own"}))
    at(70)
    forced=function(_,peer) return peer==c end
    b.Orders:Act(o2.id,"accept")
    at(80)
    b.Orders:Act(o2.id,"release")
    at(85)
    forced=nil
    -- A crafter gives an order back and another takes it within the minute; the author misses the
    -- release, so its copy still names the first crafter.
    local o5=assert(d.Orders:Place(item,{recipe=RECIPE,n=4,mode="own"}))
    at(88)
    local handedOn=c.Orders:Act(o5.id,"accept")
    at(91)
    forced=function(_,peer) return peer==d end
    handedOn=c.Orders:Act(o5.id,"release") and handedOn
    forced=nil
    at(95)
    handedOn=b.Orders:Act(o5.id,"accept") and handedOn
    at(98)
    handedOn=b.Orders:Act(o5.id,"done") and handedOn
    at(100)
    a.gear[1]="|cff00ff00|Hitem:77:0|h[Helm]|h|r"
    a.Profile.Request(a.name)
    c.gear[2]="|cff00ff00|Hitem:78:0|h[Necklace]|h|r"
    c.Profile.Request(c.name)
    -- A member logs in in the middle of it all, and crafts too.
    at(120)
    local e=client("Eve",false,true)
    at(130)
    local winner
    for _,p in ipairs({b,c}) do
        local o=p.Orders:Get(o1.id)
        if o and o.cr==p.Orders:MyKey() then winner=winner or p end
    end
    a.Orders:Act(o1.id,"mats")
    if winner then winner.Orders:Act(o1.id,"done") end
    at(150)
    -- An order from the 0.9.0 member, taken by a current one.
    local o3=assert(old.Orders:Place(item,{recipe=RECIPE,n=1,mode="own"}))
    at(160)
    a.Orders:Act(o3.id,"accept")
    local o4=assert(d.Orders:Place(item,{recipe=RECIPE,n=3,mode="own",to=e.name}))
    at(175)
    d.Orders:Act(o4.id,"cancel")
    at(200)
    assert(not b:Post("Target B",300,"","kos","Alliance",""))
    assert(not old:Post("Target O",400,"","kos","Horde",""))
    at(STORM)
    lossy=false
    at(STORM+CALM)
    -- A 0.9.0 member sends no gear summary: a guildmate who logged in after it gets its gear by
    -- viewing it, as with 0.9.0.
    for _,p in ipairs(members) do
        if p~=old and not p.Profile.Get(old.name) then p.Profile.Request(old.name) end
    end
    at(STORM+CALM+30)

    -- Everyone holds the same.
    local function fail(what) error(string.format("seed %d: %s", seed, what), 0) end
    local ids={}
    for _,p in ipairs(members) do for id in pairs(p.Crafting.db.craftOrders) do ids[id]=true end end
    for id in pairs(ids) do
        local ref
        for _,p in ipairs(members) do
            local o=p.Crafting.db.craftOrders[id]
            if o then
                local seen=table.concat({tostring(o.st),tostring(o.cr),tostring(o.to),tostring(o.who),tostring(o.n),tostring(o.mode)},"/")
                if ref and ref.seen~=seen then fail(("order %s: %s holds %s, %s holds %s"):format(id,ref.p.name,ref.seen,p.name,seen)) end
                ref=ref or {seen=seen,p=p}
                if p.Orders.IsActive(o,now) then
                    for _,q in ipairs(members) do
                        if not q.Crafting.db.craftOrders[id] then fail(("order %s (%s) missing on %s"):format(id,o.st,q.name)) end
                    end
                end
            end
        end
    end
    for _,author in ipairs(members) do
        local own=author.Records()[author.name]
        if own and own.rev then
            for _,p in ipairs(members) do
                local held=p.Records()[author.name]
                if not (held and held.rev==own.rev and #held.posts==#own.posts) then
                    fail(("%s's Bounty sheet on %s: rev %s, own rev %s"):format(author.name,p.name,tostring(held and held.rev),tostring(own.rev)))
                end
            end
        end
        local line=author.Crafting.Professions:OwnLine(171)
        if line and line.recipes then
            for _,p in ipairs(members) do
                local held=p~=author and p.Crafting.Professions:Get(author.name)
                held=held and held.profs[171]
                if p~=author and not (held and held.h==line.h and held.recipes) then
                    fail(("%s's recipes on %s: hash %s, own %s"):format(author.name,p.name,tostring(held and held.h),line.h))
                end
            end
        end
        local gear=author.Profile.Get(author.name)
        if not gear then fail(author.name.." has no gear snapshot of its own") end
        for _,p in ipairs(members) do
            local held=p.Profile.Get(author.name)
            if p~=author and not (held and held.time==gear.time) then
                fail(("%s's gear on %s: time %s, own %s"):format(author.name,p.name,tostring(held and held.time),gear.time))
            end
        end
    end
    -- The scenario happened: the race was settled, the missed release reached the bystander, the
    -- late member knows the orders still running.
    if raced and not a.Orders:Get(o1.id).cr then fail("nobody kept the raced order") end
    if c.Orders:Get(o2.id).st~="open" or c.Orders:Get(o2.id).cr then fail("the bystander kept the released order taken") end
    if not e.Orders:Get(o3.id) then fail("the late member lacks the 0.9.0 member's order") end
    if handedOn and (d.Orders:Get(o5.id).cr~=b.name or d.Orders:Get(o5.id).st~="done") then
        fail("the author kept the crafter who gave the order back")
    end
end

local failures={}
for seed=1,SEEDS do
    local ok,err=pcall(simulate,seed)
    if not ok then failures[#failures+1]=tostring(err) end
end
if #failures>0 then error(#failures.." of "..SEEDS.." runs did not converge:\n"..table.concat(failures,"\n"),0) end
print(("Sync convergence: %d simulated guilds with %d%% loss and reordering for %d s all agree after %d calm seconds."):format(
    SEEDS,LOSS*100,STORM,CALM))
