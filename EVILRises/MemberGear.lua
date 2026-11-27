local _, addon = ...
local craft = addon.Crafting
local profile = {}
addon.Profile = profile
local domain = "memberGear"
local log = addon.Log or function() end
local probe, display, due, lastGuild, previous, schedule
-- Coins change in bursts while looting or vending, so a funds-only change waits longer
-- before it goes to the guild. Gear changes and requests still go out within a second.
local GEAR_DELAY, MONEY_DELAY = 0.7, 30
local function store()
    if not craft.db or not craft.guild or craft.guild~=addon.GuildID() then return end
    craft.db.memberGear = craft.db.memberGear or {}
    return craft.db.memberGear
end
local function itemString(link)
    return type(link)=="string" and link:match("|H(item:[%d:%-]+)|h")
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
        probe:SetScript("OnModelLoaded",function()
            if readDisplay() then schedule(false) end
        end)
    end
    probe:SetUnit("player")
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
    return {items=items,copper=GetMoney(),display=display,
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
    local changed=not old or old.display~=snapshot.display or old.copper~=snapshot.copper
        or old.race~=snapshot.race or old.sex~=snapshot.sex
    for i=1,19 do
        if not old or old.items[i]~=snapshot.items[i] then changed=true;break end
    end
    if changed or force or lastGuild~=craft.guild then
        snapshot.time=math.max(GetServerTime(),old and old.time+(changed and 1 or 0) or 0)
        data[key]=snapshot
        local count=0
        for _ in pairs(snapshot.items) do count=count+1 end
        log("Gear","Sharing own snapshot (%s): %d items, race %s, sex %s, model %s",
            changed and "changed" or force and "asked for" or "new guild",count,snapshot.race or "unknown",
            snapshot.sex or "unknown",snapshot.display or "not loaded yet")
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
    local items={}
    for slot,item in pairs(p.items) do
        if type(slot)~="number" or slot%1~=0 or slot<1 or slot>19 or type(item)~="string"
            or #item>768 or not item:match("^item:%d+[%d:%-]*$") then return ignore("invalid item") end
        items[slot]=item
    end
    data[key]={time=p.time,display=p.display,items=items,copper=p.copper,race=p.race,sex=p.sex}
    log("Gear","Stored %s's gear: race %s, sex %s, model %s",key,p.race or "not shared",p.sex or "not shared",
        p.display or "not shared")
    if profile.Refresh then profile.Refresh(key) end
end)
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_EQUIPMENT_CHANGED","PLAYER_MONEY","PLAYER_GUILD_UPDATE","CLUBS_LOADED","UNIT_MODEL_CHANGED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event,unit)
    if event=="PLAYER_MONEY" then
        schedule(false,MONEY_DELAY)
    elseif event~="UNIT_MODEL_CHANGED" or unit=="player" then
        if event=="PLAYER_ENTERING_WORLD" or event=="UNIT_MODEL_CHANGED" then loadProbe() end
        schedule(event=="PLAYER_ENTERING_WORLD")
    end
end)
