local _, addon = ...
local craft = addon.Crafting
local comm = LibStub("AceComm-3.0")
local codec = LibStub("EVRFeatures-LibSerialize")
local wire = LibStub("LibDeflate")
local prefix = "EVRCrafts1"
local callbacks = {}
craft.SyncService = {}
function craft.SyncService:On(domain, fn) callbacks[domain] = fn end
function craft.SyncService:Publish(domain, action, data, options)
    local guild = addon.GuildID()
    if not guild or guild ~= craft.guild then return end
    local target = options and options.target
    local message = codec:Serialize(guild,domain,action,data,target)
    comm:SendCommMessage(prefix,wire:EncodeForWoWAddonChannel(message),"GUILD",nil,"BULK")
end
comm.RegisterComm(craft,prefix,function(_,message,channel,sender)
    if channel ~= "GUILD" or #message > 96000 or addon.Owner(sender)==addon.Owner() then return end
    local bytes = wire:DecodeForWoWAddonChannel(message)
    if not bytes then return end
    local ok,guild,domain,act,data,target = codec:Deserialize(bytes)
    if not ok or not guild or guild~=craft.guild or guild~=addon.GuildID() then return end
    if target and (type(target)~="string" or addon.Owner(target)~=addon.Owner()) then return end
    if callbacks[domain] and type(act)=="string" and type(data)=="table" then
        callbacks[domain]({act=act,data=data},sender)
    end
end)
local initialized
function craft.BindGuild()
    local guild = addon.GuildID()
    if craft.db and craft.guild==guild then return end
    EVILRisesCrafting = EVILRisesCrafting or {}
    craft.guild = guild
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
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("CLUBS_LOADED")
events:SetScript("OnEvent",craft.BindGuild)
