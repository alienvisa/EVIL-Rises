local _, addon = ...
local craft = addon.Crafting
local comm = LibStub("AceComm-3.0")
local codec = LibStub("EVRFeatures-LibSerialize")
local wire = LibStub("LibDeflate")
local prefix = "EVRCrafts1"
local callbacks = {}
local noop = function() end
local log, logSync = addon.Log or noop, addon.LogSync or noop
local version, noteVersion = addon.Version or noop, addon.NoteVersion or noop
local AREAS = { prof="Professions", craftorder="Orders", memberGear="Gear" }
local function count(t) return type(t)=="table" and #t or 0 end
-- A message as the debug log names it: its area, action and the detail that tells two apart.
local function describe(domain, act, data)
    local detail = ""
    if type(data)=="table" then
        if domain=="prof" and act=="sum" and type(data.p)=="table" then
            local n=0
            for _ in pairs(data.p) do n=n+1 end
            detail=" ("..n.." professions)"
        elseif domain=="prof" and act=="req" then
            detail=" ("..count(data.l).." recipe lists)"
        elseif domain=="prof" and act=="list" then
            detail=" (line "..tostring(data.l)..", "..(count(data.r)+count(data.x)).." recipes)"
        elseif domain=="craftorder" and act=="have" then
            detail=" ("..count(data.l).." orders)"
        elseif domain=="craftorder" and data.id then
            detail=" (order "..tostring(data.id)..(data.item and (", item "..tostring(data.item)) or "")..")"
        elseif domain=="memberGear" and act=="gear" and type(data.items)=="table" then
            local n=0
            for _ in pairs(data.items) do n=n+1 end
            detail=" ("..n.." items, model "..tostring(data.display or "none")..")"
        end
    end
    return (AREAS[domain] or tostring(domain)).." "..tostring(act)..detail
end
craft.SyncService = {}
function craft.SyncService:On(domain, fn) callbacks[domain] = fn end
function craft.SyncService:Publish(domain, action, data, options)
    local guild = addon.GuildID()
    if not guild or guild ~= craft.guild then return end
    local target = options and options.target
    -- The trailing version is read by newer clients and ignored by older ones.
    local message = codec:Serialize(guild,domain,action,data,target,version())
    local encoded = wire:EncodeForWoWAddonChannel(message)
    comm:SendCommMessage(prefix,encoded,"GUILD",nil,"BULK")
    logSync("out","Craft",describe(domain,action,data)..(target and "  ·  to %s" or "%s").."  ·  %d bytes",target or "",#encoded)
end
comm.RegisterComm(craft,prefix,function(_,message,channel,sender)
    -- The guild channel echoes our own messages back: those are not logged twice.
    if addon.Owner(sender)==addon.Owner() then return end
    if channel ~= "GUILD" or #message > 96000 then
        logSync("drop","Craft","from %s on %s  ·  %d bytes  ·  not the guild channel or too large",sender,channel,#message)
        return
    end
    local bytes = wire:DecodeForWoWAddonChannel(message)
    if not bytes then
        logSync("drop","Craft","from %s  ·  could not decode",sender)
        return
    end
    local ok,guild,domain,act,data,target,theirs = codec:Deserialize(bytes)
    if not ok or not guild or guild~=craft.guild or guild~=addon.GuildID() then
        logSync("drop","Craft","from %s  ·  %s",sender,ok and "another guild" or "could not read")
        return
    end
    noteVersion(sender,theirs)
    if target and (type(target)~="string" or addon.Owner(target)~=addon.Owner()) then
        logSync("drop","Craft",describe(domain,act,data).." from %s  ·  addressed to %s",sender,target)
        return
    end
    if callbacks[domain] and type(act)=="string" and type(data)=="table" then
        logSync("in","Craft",describe(domain,act,data).." from %s"..(target and "  ·  addressed to you" or "").."  ·  %d bytes",sender,#message)
        callbacks[domain]({act=act,data=data},sender)
    else
        logSync("drop","Craft","%s %s from %s  ·  unknown message",tostring(domain),tostring(act),sender)
    end
end)
local initialized
function craft.BindGuild()
    local guild = addon.GuildID()
    if craft.db and craft.guild==guild then return end
    EVILRisesCrafting = EVILRisesCrafting or {}
    craft.guild = guild
    log("Guild", guild and "Crafting and gear sync bound to guild %s" or "No guild: crafting and gear sync are idle", guild)
    craft.db = guild and EVILRisesCrafting[guild] or nil
    if not craft.db then
        craft.db = {professions={},craftOrders={}}
        if guild then EVILRisesCrafting[guild]=craft.db end
    end
    local P,S,O = craft.Professions,craft.ProfSync,craft.CraftOrders
    -- The first bind's Initialize calls ask the guild a few seconds after login. Asking here
    -- as well would make every member answer twice.
    local first = not initialized
    if first then
        initialized=true
        P:Initialize()
        S:Initialize()
        O:Initialize()
    else
        P.index,P.nativeAt,P.pendingExtra=nil,0,nil
        S.receivedDigests,S.asked,S.outgoing={},{},{}
        O.trade,O.mailPending,O.answeredAt=nil,nil,nil
        O:ForgetCrafters()
    end
    if guild then
        P:Scan()
        P:ReadNative()
        O:Prune()
        if not first then
            craft.SyncService:Publish("craftorder","ask",{})
            craft.SyncService:Publish("prof","ask",{})
        end
    end
    if craft.ResetPage then craft.ResetPage() end
end
-- The handler goes on first, and each event through Compat: a client without one of these events
-- (WoW: Forever has no CLUBS_LOADED) rejects it with an error, which must not stop the others.
local events=CreateFrame("Frame")
events:SetScript("OnEvent",craft.BindGuild)
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_GUILD_UPDATE","CLUBS_LOADED"}) do craft.Compat.RegisterEvent(events,event) end
