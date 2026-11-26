local _, addon = ...
local craft = addon.Crafting
local orders = craft.CraftOrders

-- Keep delivery available while the guild window is closed. Filling the trade
-- or mail is a player click; the native confirmation still completes it.
local function deliveryBar(parent, rows, submit)
    local bar=CreateFrame("Frame",nil,parent)
    bar:SetPoint("TOPLEFT",parent,"BOTTOMLEFT",4,0)
    bar:SetSize(302,28)
    local picker=CreateFrame("DropdownButton",nil,bar,"WowStyle1DropdownTemplate")
    picker:SetPoint("LEFT")
    picker:SetWidth(184)
    local send=CreateFrame("Button",nil,bar,"UIPanelButtonTemplate")
    send:SetSize(110,22)
    send:SetPoint("LEFT",picker,"RIGHT",4,0)
    local selected
    local function current()
        local list=rows()
        for _,row in ipairs(list) do if row.o.id==selected then return row end end
        return list[1]
    end
    picker:SetupMenu(function(_,root)
        for _,row in ipairs(rows()) do
            local name=craft.Compat.GetItemInfo(row.o.item) or ("Item #"..row.o.item)
            root:CreateRadio(name.." x"..row.o.n,function()
                local picked=current()
                return picked and picked.o.id==row.o.id
            end,function() selected=row.o.id end)
        end
    end)
    send:SetScript("OnClick",function()
        local row=current()
        if row then submit(row) end
    end)
    return function(caption)
        bar:SetShown(caption~=nil and current()~=nil)
        if bar:IsShown() then send:SetText(caption);picker:GenerateMenu() end
    end
end
local trade,mail
orders.uiTrade=function(open)
    if not trade and open and TradeFrame then
        trade=deliveryBar(TradeFrame,function() return orders:OrdersWith(orders.trade and orders.trade.partner) end,function(row)
            local wants,tip=orders:ToHand(row.o,row.role)
            local slots={}
            for i=1,6 do if not GetTradePlayerItemLink(i) then slots[#slots+1]=i end end
            orders.trade.pick=row.o.id
            orders:PutItems(wants,slots,ClickTradeButton)
            if tip>0 and GetMoney()>=tip then SetTradeMoney(tip);orders.trade.tipPut=true end
        end)
    end
    if trade then trade(open and "Fill trade" or nil) end
end
orders.uiMail=function(open)
    if not mail and open and MailFrame then
        mail=deliveryBar(MailFrame,function() return orders:MailRows() end,function(row) orders:FillMail(row) end)
    end
    if mail then mail(open and "Prepare mail" or nil) end
end
