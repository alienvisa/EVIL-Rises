local _, board = ...
local function label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end
local function button(parent, text, width, x, y, click)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", click)
    return b
end
local function field(parent, caption, x, y, width, max, numeric)
    label(parent, caption, x, y)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", x+4, y-18)
    box:SetSize(width, 22)
    box:SetMaxBytes(max)
    box:SetAutoFocus(false)
    box:SetNumeric(numeric or false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end
function board.Build(page)
    board.page = page
    label(page, "Bounty Board", 10, -10, "GameFontNormalLarge")
    local list = CreateFrame("Frame", nil, page)
    list:SetAllPoints()
    local form = CreateFrame("Frame", nil, page)
    form:SetAllPoints()
    form:Hide()
    local help = label(list, "Whisper the poster to agree on completion and payment. Posters withdraw settled bounties. Open bounties expire after seven days.", 10, -65, "GameFontHighlightSmall")
    help:SetPoint("TOPRIGHT", list, "TOPRIGHT", -12, -65)
    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -102)
    scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1,1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(_, width) child:SetWidth(math.max(1,width)) end)
    local empty = label(child, "No open bounties.", 2, -4, "GameFontDisable")
    local rows = {}
    function page:Refresh()
        local items = {}
        for author, sheet in pairs(board.Records() or {}) do
            for index, post in ipairs(sheet.posts) do
                items[#items+1] = {author=author, post=post, index=index}
            end
        end
        table.sort(items, function(a,b)
            if a.post.time ~= b.post.time then return a.post.time > b.post.time end
            if a.author ~= b.author then return a.author < b.author end
            return a.index < b.index
        end)
        local offset = 0
        for i, item in ipairs(items) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row.title = label(row,"",2,-3)
                row.meta = label(row,"",2,-21,"GameFontHighlightSmall")
                row.reason = label(row,"",2,-38,"GameFontHighlightSmall")
                row.reason:SetPoint("TOPRIGHT",row,"TOPRIGHT",-4,-38)
                row.title:SetPoint("TOPRIGHT",row,"TOPRIGHT",-88,-3)
                row.title:SetWordWrap(false)
                row.withdraw = button(row,"Withdraw",80,0,0,function() board:Withdraw(row.post) end)
                row.withdraw:ClearAllPoints()
                row.withdraw:SetPoint("TOPRIGHT")
                rows[i] = row
            end
            local p = item.post
            row.post = p
            row:SetPoint("TOPLEFT",0,-offset)
            row:SetPoint("TOPRIGHT",0,-offset)
            row.title:SetText(p.target .. "   " .. p.faction .. (p.class ~= "" and "  " .. p.class or ""))
            row.meta:SetText(board.modes[p.mode] .. "    " .. p.reward .. "    Posted by " .. item.author)
            row.reason:SetText(p.reason)
            row.withdraw:SetShown(item.author == board.Owner())
            local height = 45 + row.reason:GetStringHeight()
            row:SetHeight(height)
            offset = offset + height
            row:Show()
        end
        for i=#items+1,#rows do rows[i]:Hide() end
        child:SetHeight(math.max(25,offset))
        empty:SetShown(#items==0)
    end
    local name = field(form,"Bounty Target Name",10,-44,202,72)
    local reason = field(form,"Reason (optional)",10,-102,390,180)
    local gold = field(form,"Gold",10,-161,94,8,true)
    local silver = field(form,"Silver",128,-161,55,2,true)
    local copper = field(form,"Copper",212,-161,55,2,true)
    local status = label(form,"",10,-284,"GameFontHighlightSmall")
    local class, resolved, faction, factionButton
    local function setFaction(value)
        faction = value
        factionButton:SetText(value)
    end
    factionButton = button(form,"",90,229,-62,function()
        setFaction(faction == "Horde" and "Alliance" or "Horde")
    end)
    label(form,"Faction",229,-44)
    local function fill(info)
        name:SetText(info.name)
        resolved, class = info.name, info.class
        if info.faction == "Horde" or info.faction == "Alliance" then setFaction(info.faction) end
        status:SetText(class or "")
    end
    local function resolve()
        if name:GetText() ~= resolved then
            local info = board.MatchName(name:GetText())
            if info then fill(info) end
        end
    end
    name:SetScript("OnEditFocusLost",resolve)
    name:SetScript("OnTextChanged",function() resolved,class=nil,nil; status:SetText("") end)
    button(form,"Use target",92,328,-62,function()
        local info = board.ReadUnit("target")
        if info then fill(info) else status:SetText("Select a player first.") end
    end)
    local function check(text,x)
        local box=CreateFrame("CheckButton",nil,form,"UICheckButtonTemplate")
        box:SetPoint("TOPLEFT",x,-210)
        box:SetSize(24,24)
        box.Text:SetText(text)
        return box
    end
    local kos, camp = check("Kill on sight",10), check("Camp",134)
    function page:Compose(info)
        list:Hide()
        form:Show()
        for _, box in ipairs({name,reason,gold,silver,copper}) do box:SetText("") end
        kos:SetChecked(true)
        camp:SetChecked(false)
        resolved,class=nil,nil
        setFaction(UnitFactionGroup("player")=="Alliance" and "Horde" or "Alliance")
        status:SetText("")
        if info then fill(info) end
        name:SetFocus()
    end
    function page:List()
        form:Hide()
        list:Show()
        page:Refresh()
    end
    button(form,"Post bounty",100,10,-249,function()
        resolve()
        local mode = kos:GetChecked() and (camp:GetChecked() and "both" or "kos") or (camp:GetChecked() and "camp")
        local amount = gold:GetNumber()*10000 + silver:GetNumber()*100 + copper:GetNumber()
        local err = board:Post(name:GetText(),amount,reason:GetText(),mode,faction,class)
        if err then status:SetText(err) else page:List() end
    end)
    button(form,"Cancel",76,120,-249,function() page:List() end)
    button(list,"Post a bounty",112,10,-35,function() page:Compose() end)
    local how = button(list,"How to post",100,129,-35,function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText("Creating a bounty")
        GameTooltip:AddLine("Enter any target name, choose Use target, or right-click a player portrait and choose Create bounty. Set a faction, action and reward of at least one copper. You can add a reason.",1,1,1,true)
        GameTooltip:Show()
    end)
    how:SetScript("OnLeave",function() GameTooltip:Hide() end)
end
