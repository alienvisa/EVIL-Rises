local _, addon = ...
local craft = addon.Crafting
local profile = {}
addon.Profile = profile
local domain = "memberGear"
local log = addon.Log or function() end
local probe, display, ownOutfit, due, lastGuild, previous, schedule, reloadPending
-- Coins change in bursts while looting or vending, so a funds-only change waits longer
-- before it goes to the guild. Gear changes and requests still go out within a second.
local GEAR_DELAY, MONEY_DELAY = 0.7, 30
-- An equipment change waits this long for the probe's model to load before it goes out
-- without a new outfit.
local EQUIP_FALLBACK = 5
-- A guildmate seen live is remembered at most this often.
local SEEN_EVERY = 300
local function isSecret(...)
    return craft.Compat and craft.Compat.IsSecret and craft.Compat.IsSecret(...) or false
end
local function store()
    if not craft.db or not craft.guild or craft.guild~=addon.GuildID() then return end
    craft.db.memberGear = craft.db.memberGear or {}
    return craft.db.memberGear
end
local function itemString(link)
    return type(link)=="string" and link:match("|H(item:[%d:%-]+)|h")
end
-- The outfit a model shows, slot by slot: { [slot] = { appearance, secondary appearance,
-- illusion } }, with transmog, hidden slots and weapon enchant effects as worn. Nil when the
-- model has not loaded or the client cannot say.
local function readOutfit(m)
    if not (m and m.GetItemTransmogInfoList) then return nil end
    local ok,list=pcall(m.GetItemTransmogInfoList,m)
    if not ok or type(list)~="table" or isSecret(list) then return nil end
    local out,n={},0
    for slot=1,19 do
        local info=list[slot]
        if type(info)=="table" then
            local a,s,i=info.appearanceID,info.secondaryAppearanceID,info.illusionID
            if not isSecret(a,s,i) and type(a)=="number" and a>0 then
                out[slot]={a,type(s)=="number" and s or 0,type(i)=="number" and i or 0}
                n=n+1
            end
        end
    end
    return n>0 and out or nil
end
local function sameOutfit(a,b)
    if a==b then return true end
    if not a or not b then return false end
    for slot=1,19 do
        local x,y=a[slot],b[slot]
        if (x==nil)~=(y==nil) then return false end
        if x and (x[1]~=y[1] or x[2]~=y[2] or x[3]~=y[3]) then return false end
    end
    return true
end
local function outfitSlots(mog)
    local n=0
    for _ in pairs(mog or {}) do n=n+1 end
    return n
end
-- The player's model ID, which guildmates need to draw this character. A model loads
-- asynchronously, so the ID is often still 0 right after SetUnit. Keep the last ID the
-- probe reported, and share again when a load brings a new one.
local function readDisplay()
    local id=probe:GetDisplayInfo()
    if type(id)=="number" and id>0 and id~=display then
        display=id
        log("Gear","Own model loaded: display %d",id)
        return true
    end
end
local function loadProbe()
    if not probe then
        probe=CreateFrame("PlayerModel",nil,UIParent)
        probe:SetSize(1,1)
        -- On screen and transparent: a model placed off screen may never load.
        probe:SetPoint("BOTTOMLEFT")
        probe:SetAlpha(0)
        -- A load after login, a gear or transmog change, or a model change. The update that
        -- follows only goes out when something differs from the last snapshot.
        probe:SetScript("OnModelLoaded",function()
            readDisplay()
            local mog=readOutfit(probe)
            if mog and not sameOutfit(mog,ownOutfit) then
                ownOutfit=mog
                log("Gear","Own outfit read: %d slots",outfitSlots(mog))
            end
            schedule(false)
        end)
    end
    probe:SetUnit("player")
end
-- Equipment sets and transmog fire a burst of events: reload the probe once for all of them.
local function reloadProbe()
    if reloadPending then return end
    reloadPending=true
    C_Timer.After(0.5,function()
        reloadPending=false
        loadProbe()
    end)
end
local function capture()
    local items={}
    for slot=1,19 do
        local link=itemString(GetInventoryItemLink("player",slot))
        local id=GetInventoryItemID("player",slot)
        if link or id then items[slot]=link or ("item:"..id) end
    end
    if not probe then loadProbe() end
    readDisplay()
    -- Race and sex let a guildmate build this character's model without a model ID,
    -- which the client may not report for a model drawn from a live unit.
    local _,_,race=UnitRace("player")
    local sex=UnitSex("player")
    return {items=items,copper=GetMoney(),display=display,mog=ownOutfit,
        race=type(race)=="number" and race>0 and race or nil,
        sex=sex==2 and 0 or sex==3 and 1 or nil}
end
local function update(force)
    local data=store()
    if not data then return end
    local snapshot=capture()
    local key=addon.Owner()
    local old=data[key]
    if not snapshot.display and old then snapshot.display=old.display end
    if not snapshot.mog and old then snapshot.mog=old.mog end
    local changed=not old or old.display~=snapshot.display or old.copper~=snapshot.copper
        or old.race~=snapshot.race or old.sex~=snapshot.sex or not sameOutfit(old.mog,snapshot.mog)
    for i=1,19 do
        if not old or old.items[i]~=snapshot.items[i] then changed=true;break end
    end
    if changed or force or lastGuild~=craft.guild then
        snapshot.time=math.max(GetServerTime(),old and old.time+(changed and 1 or 0) or 0)
        data[key]=snapshot
        local count=0
        for _ in pairs(snapshot.items) do count=count+1 end
        log("Gear","Sharing own snapshot (%s): %d items, %d outfit slots, race %s, sex %s",
            changed and "changed" or force and "asked for" or "new guild",count,outfitSlots(snapshot.mog),
            snapshot.race or "unknown",snapshot.sex or "unknown")
        lastGuild=craft.guild
        craft.SyncService:Publish(domain,"gear",snapshot)
        if profile.Refresh then profile.Refresh(key) end
    end
end
-- One update at the earliest time asked for. A sooner request replaces a later one,
-- and the replaced timer does nothing when it fires.
function schedule(force,delay)
    previous=previous or force
    local at=GetTime()+(delay or GEAR_DELAY)
    if due and due<=at then return end
    due=at
    C_Timer.After(at-GetTime(),function()
        if due~=at then return end
        due=nil
        local send=previous
        previous=nil
        update(send)
    end)
end
function profile.Get(key)
    local data=store()
    return data and data[key]
end
local function seenStore()
    if not craft.db or not craft.guild or craft.guild~=addon.GuildID() then return end
    craft.db.memberSeen = craft.db.memberSeen or {}
    return craft.db.memberSeen
end
-- A guildmate the flyout drew live: keep how they looked, so the preview still matches once
-- they are out of range. At most once per SEEN_EVERY each, and only what the model loaded.
function profile.Remember(key,unit,m)
    local seen=seenStore()
    if not seen or not key or not unit or unit=="player" or key==addon.Owner() then return end
    local now=GetServerTime()
    local old=seen[key]
    if old and now-old.time<SEEN_EVERY then return end
    local mog=readOutfit(m)
    local _,_,race=UnitRace(unit)
    local sex=UnitSex(unit)
    if isSecret(race,sex) then return end
    local items={}
    for slot=1,19 do
        local link=GetInventoryItemLink(unit,slot)
        local item=not isSecret(link) and itemString(link)
        if item then items[slot]=item end
    end
    if not mog and not next(items) then return end
    seen[key]={time=now,mog=mog,items=items,
        race=type(race)=="number" and race>0 and race or nil,sex=sex==2 and 0 or sex==3 and 1 or nil}
    log("Gear","Remembered %s's live appearance: %d outfit slots",key,outfitSlots(mog))
end
-- What to draw for a guildmate out of range: their own snapshot, or the last live sighting
-- when that is as new or newer.
function profile.Preview(key)
    local shared=profile.Get(key)
    local seen=seenStore()
    seen=seen and seen[key]
    if seen and (not shared or seen.time>=shared.time) then return seen end
    return shared
end
local requests={}
function profile.Request(key)
    if key==addon.Owner() then update(false);return end
    local id=addon.GuildID()
    if not id then return end
    local tag=id..":"..key
    if GetTime()<(requests[tag] or 0) then return end
    requests[tag]=GetTime()+30
    craft.SyncService:Publish(domain,"request",{}, {target=key})
end
craft.SyncService:On(domain,function(env,sender)
    local key=addon.Owner(sender)
    if env.act=="request" then
        log("Gear","%s asked for this character's gear",key)
        schedule(true)
        return
    end
    local function ignore(why) log("Gear","Ignored %s's gear: %s",key,why) end
    local data=store()
    local p=env.data
    if not data or env.act~="gear" then return end
    if type(p.items)~="table" or type(p.time)~="number"
        or not (p.time>0 and p.time<=GetServerTime()+300) or p.time%1~=0 then return ignore("invalid time or items") end
    if data[key] and data[key].time>=p.time then return ignore("not newer than the one held") end
    if p.display~=nil and (type(p.display)~="number" or not (p.display>=1 and p.display<=2147483647) or p.display%1~=0) then return ignore("invalid model") end
    if p.copper~=nil and (type(p.copper)~="number" or not (p.copper>=0 and p.copper<=9007199254740991) or p.copper%1~=0) then return ignore("invalid funds") end
    if p.race~=nil and (type(p.race)~="number" or not (p.race>=1 and p.race<=1000) or p.race%1~=0) then return ignore("invalid race") end
    if p.sex~=nil and p.sex~=0 and p.sex~=1 then return ignore("invalid sex") end
    local mog
    if p.mog~=nil then
        if type(p.mog)~="table" then return ignore("invalid outfit") end
        mog={}
        for slot,t in pairs(p.mog) do
            if type(slot)~="number" or slot%1~=0 or slot<1 or slot>19 or type(t)~="table" then return ignore("invalid outfit") end
            for i=1,3 do
                local v=t[i]
                if type(v)~="number" or v<0 or v>2147483647 or v%1~=0 then return ignore("invalid outfit") end
            end
            mog[slot]={t[1],t[2],t[3]}
        end
    end
    local items={}
    for slot,item in pairs(p.items) do
        if type(slot)~="number" or slot%1~=0 or slot<1 or slot>19 or type(item)~="string"
            or #item>768 or not item:match("^item:%d+[%d:%-]*$") then return ignore("invalid item") end
        items[slot]=item
    end
    data[key]={time=p.time,display=p.display,items=items,copper=p.copper,race=p.race,sex=p.sex,mog=mog}
    log("Gear","Stored %s's gear: %d outfit slots, race %s, sex %s",key,outfitSlots(mog),p.race or "not shared",
        p.sex or "not shared")
    if profile.Refresh then profile.Refresh(key) end
end)
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_EQUIPMENT_CHANGED","PLAYER_MONEY","PLAYER_GUILD_UPDATE","CLUBS_LOADED","UNIT_MODEL_CHANGED","TRANSMOGRIFY_SUCCESS"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event,unit)
    if event=="PLAYER_MONEY" then
        schedule(false,MONEY_DELAY)
    elseif event=="PLAYER_ENTERING_WORLD" then
        loadProbe()
        schedule(true)
    elseif event=="PLAYER_EQUIPMENT_CHANGED" or event=="TRANSMOGRIFY_SUCCESS" then
        -- The reloaded model sends the update with the new outfit; this goes out if it never loads.
        reloadProbe()
        schedule(false,EQUIP_FALLBACK)
    elseif event=="UNIT_MODEL_CHANGED" then
        if unit=="player" then reloadProbe() end
    else
        schedule(false)
    end
end)
