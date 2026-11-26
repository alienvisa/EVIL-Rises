local _, addon = ...
local craft = {}
addon.Crafting = craft
local Compat = {}
craft.Compat = Compat
craft.L = setmetatable({}, {__index=function(_, label) return label end})
local TRADE_SLOTS = 6
Compat.PlayerName = addon.Owner
Compat.After = C_Timer.After
Compat.NewTicker = C_Timer.NewTicker
function Compat.RegisterEvent(frame,event) pcall(frame.RegisterEvent,frame,event) end
function Compat.TradePartner()
    local first,last = UnitFullName("NPC")
    if first then return last and last ~= "" and first .. " " .. last or first end
end
function craft:SafeCall(fn,...) return securecallfunction(fn,...) end
function craft:Print(msg) print("EVIL Rises - " .. msg) end
function craft:RealmName() return GetRealmName() end
function craft.Finite(v)
    local n=tonumber(v)
    if n and n==n and math.abs(n)<math.huge then return n end
end

function Compat.BagIDs()
    local last = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
    local out = {}
    for b = 0, last do out[#out + 1] = b end
    return out
end

function Compat.ClearCursor()
    if ClearCursor then ClearCursor() end
end

function Compat.ClickSendMailItemButton(i)
    if ClickSendMailItemButton then ClickSendMailItemButton(i) end
end

function Compat.CursorHasItem()
    if CursorHasItem and CursorHasItem() then return true end
    return (GetCursorInfo and GetCursorInfo() ~= nil) and true or false
end

function Compat.FillSendMail(to, subject, copper)
    if SendMailNameEditBox and to then SendMailNameEditBox:SetText(to) end
    if SendMailSubjectEditBox and subject then SendMailSubjectEditBox:SetText(subject) end
    copper = math.min(tonumber(copper) or 0, Compat.PlayerMoney())
    if copper > 0 then
        -- "Send Money", never C.O.D.: the send reads the money field and charges it on delivery
        -- when the C.O.D. button is the one checked.
        if SendMailRadioButton_OnClick then pcall(SendMailRadioButton_OnClick, 1) end
        if SendMailMoney and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(SendMailMoney, copper) end
    end
end

function Compat.GetContainerItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then return C_Container.GetContainerItemInfo(bag, slot) end
    if GetContainerItemInfo then
        local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = GetContainerItemInfo(bag, slot)
        if not link then return nil end
        return { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality, isReadable = readable,
                 hasLoot = lootable, hyperlink = link, isFiltered = filtered, hasNoValue = noValue,
                 itemID = itemID or tonumber(link:match("item:(%d+)")) }
    end
end

function Compat.GetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end

function Compat.GetItemCount(item, includeBank)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item, includeBank or false) end
    if GetItemCount then return GetItemCount(item, includeBank) end
    return 0
end

function Compat.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if GetItemInfo then return GetItemInfo(item) end
end

function Compat.GetProfessionInfo(index)
    if not GetProfessionInfo then return nil end
    return GetProfessionInfo(index)
end

function Compat.GetProfessions()
    if not GetProfessions then return end
    return GetProfessions()
end

function Compat.GetSpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if not info then return nil end
        return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
    end
    if GetSpellInfo then return GetSpellInfo(spell) end
end

function Compat.GuildMemberProfessions()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return nil end
    local ids = C_Club.GetClubMembers(clubId)
    if Compat.IsSecret(ids) or type(ids) ~= "table" then return nil end
    local out = {}
    for _, memberId in ipairs(ids) do
        local m = C_Club.GetMemberInfo(clubId, memberId)
        if m and not Compat.IsSecret(m.name, m.profession1ID, m.profession2ID) and type(m.name) == "string" then
            local lines = {}
            if type(m.profession1ID) == "number" and m.profession1ID > 0 then lines[#lines + 1] = m.profession1ID end
            if type(m.profession2ID) == "number" and m.profession2ID > 0 then lines[#lines + 1] = m.profession2ID end
            out[#out + 1] = { name = m.name, lines = lines }
        end
    end
    return out
end

function Compat.HookSendMail(fn)
    if SendMail and hooksecurefunc then hooksecurefunc("SendMail", function(to, subject) fn(to, subject) end) end
end

function Compat.IsPlayerSpell(spellID)
    if not IsPlayerSpell then return false end
    return IsPlayerSpell(spellID) and true or false
end

function Compat.IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

function Compat.IsTradeComplete(messageType, message)
    if Compat.IsSecret(messageType, message) then return false end
    if LE_GAME_ERR_TRADE_COMPLETE ~= nil and messageType == LE_GAME_ERR_TRADE_COMPLETE then return true end
    return ERR_TRADE_COMPLETE ~= nil and message == ERR_TRADE_COMPLETE
end

function Compat.MailAttachMax()
    return tonumber(ATTACHMENTS_MAX_SEND) or 12
end

function Compat.MailFreeSlots()
    local out = {}
    for i = 1, Compat.MailAttachMax() do
        local name = GetSendMailItem and GetSendMailItem(i)
        if not name then out[#out + 1] = i end
    end
    return out
end

function Compat.PickupContainerItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then return C_Container.PickupContainerItem(bag, slot) end
    if PickupContainerItem then return PickupContainerItem(bag, slot) end
end

function Compat.PlayerMoney()
    return GetMoney and tonumber(GetMoney()) or 0
end

function Compat.RecipeLine(recipeID)
    local T = C_TradeSkillUI
    if not (T and T.GetTradeSkillLineForRecipe) then return nil end
    local _, _, parent = T.GetTradeSkillLineForRecipe(recipeID)
    return parent
end

function Compat.ShowSendMail()
    if MailFrameTab_OnClick and MailFrameTab2 then MailFrameTab_OnClick(MailFrameTab2, 2) end
end

function Compat.SplitContainerItem(bag, slot, count)
    if C_Container and C_Container.SplitContainerItem then return C_Container.SplitContainerItem(bag, slot, count) end
    if SplitContainerItem then return SplitContainerItem(bag, slot, count) end
end

function Compat.TradeItemLinks()
    local out = {}
    if not GetTradePlayerItemLink then return out end
    for i = 1, TRADE_SLOTS do
        local link = GetTradePlayerItemLink(i)
        if type(link) == "string" and not Compat.IsSecret(link) then out[#out + 1] = link end
    end
    return out
end

function Compat.TradeSkillLearned()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return nil end
    if T.IsDataSourceChanging and T.IsDataSourceChanging() then return nil end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
        or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember()) then
        return nil
    end
    local base = T.GetBaseProfessionInfo()
    local line = base and base.professionID
    if not line or line == 0 then return nil end
    local learned = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then learned[#learned + 1] = id end
    end
    return line, learned
end

function Compat.TradeTargetItemLinks()
    local out = {}
    if not GetTradeTargetItemLink then return out end
    for i = 1, TRADE_SLOTS do
        local link = GetTradeTargetItemLink(i)
        if type(link) == "string" and not Compat.IsSecret(link) then out[#out + 1] = link end
    end
    return out
end
