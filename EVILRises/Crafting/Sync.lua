local _, addon = ...
local craft = addon.Crafting
local callbacks = {}
local noop = function() end
local log, logSync = addon.Log or noop, addon.LogSync or noop
local AREAS = { prof="Professions", craftorder="Orders", memberGear="Gear" }
-- Order actions race (two crafters accepting at once), so they do not wait behind recipe lists and
-- gear. An area's capability number goes up when it learns actions older copies do not know.
local PRIORITY = { craftorder="NORMAL" }
local VERSION = { craftorder=2 }
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

-- Comm has checked the channel, the guild and the size, and that the sender is a guildmate.
local function receive(domain)
    return function(act,data,sender,info)
        if craft.guild~=addon.GuildID() then
            logSync("drop","Craft","from %s  ·  another guild",sender)
            return
        end
        local target=info.target
        if target and (type(target)~="string" or addon.Owner(target)~=addon.Owner()) then
            logSync("drop","Craft",describe(domain,act,data).." from %s  ·  addressed to %s",sender,target)
            return
        end
        if callbacks[domain] and type(data)=="table" then
            logSync("in","Craft",describe(domain,act,data).." from %s"..(target and "  ·  addressed to you" or "").."  ·  %d bytes",sender,info.bytes)
            callbacks[domain]({act=act,data=data},sender)
        else
            logSync("drop","Craft","%s %s from %s  ·  unknown message",tostring(domain),tostring(act),sender)
        end
    end
end
local function register(domain)
    addon.Comm:Register(domain,{label="Craft",priority=PRIORITY[domain] or "BULK",maxBytes=96000,legacy="crafts",
        version=VERSION[domain],handle=receive(domain)})
end
-- The areas older copies send on the crafting prefix, known before any module asks for them.
for domain in pairs(AREAS) do register(domain) end

function craft.SyncService:On(domain, fn)
    if not AREAS[domain] then register(domain) end
    callbacks[domain] = fn
end
function craft.SyncService:Publish(domain, action, data, options)
    local guild = addon.GuildID()
    if not guild or guild ~= craft.guild then return end
    local target = options and options.target
    local bytes = addon.Comm:Send(domain,action,data,{target=target,newOnly=options and options.newOnly})
    if bytes then
        logSync("out","Craft",describe(domain,action,data)..(target and "  ·  to %s" or "%s").."  ·  %d bytes",target or "",bytes)
    end
end

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
        O.asked,O.fixWaiting=nil,nil
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
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("CLUBS_LOADED")
events:SetScript("OnEvent",craft.BindGuild)
