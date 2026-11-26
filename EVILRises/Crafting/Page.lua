local _, addon = ...
local craft = addon.Crafting
local D, O = craft.ProfDirectory, craft.CraftOrders
local function text(parent, caption, x, y, font)
    local f = parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlight")
    f:SetPoint("TOPLEFT",x,y)
    f:SetJustifyH("LEFT")
    f:SetText(caption)
    return f
end
local function button(parent, caption, x, y, width, fn)
    local b = CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,22)
    b:SetPoint("TOPLEFT",x,y)
    b:SetText(caption)
    b:SetScript("OnClick",fn)
    return b
end
local function input(parent,x,y,width,max,numeric)
    local box = CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
    box:SetSize(width,22)
    box:SetPoint("TOPLEFT",x,y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(max)
    box:SetNumeric(numeric or false)
    box:SetScript("OnEscapePressed",box.ClearFocus)
    box:SetScript("OnEnterPressed",box.ClearFocus)
    return box
end
local function menu(parent,x,y,width,choices,selected,choose)
    local b = CreateFrame("DropdownButton",nil,parent,"WowStyle1DropdownTemplate")
    b:SetWidth(width)
    b:SetPoint("TOPLEFT",x,y)
    b:SetupMenu(function(_,root)
        for _,entry in ipairs(choices()) do
            root:CreateRadio(entry[2],function() return selected()==entry[1] end,function() choose(entry[1]) end)
        end
    end)
    return b
end
local function itemName(id)
    return craft.Compat.GetItemInfo(id) or ("Item #"..id)
end
local function pane(parent)
    local f = CreateFrame("Frame",nil,parent)
    f:SetAllPoints()
    return f
end
local function buildListing(parent)
    local rows = {}
    local scroll = CreateFrame("ScrollFrame",nil,parent,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",10,-109)
    scroll:SetPoint("BOTTOMRIGHT",-32,10)
    local child = CreateFrame("Frame",nil,scroll)
    child:SetSize(1,1)
    scroll:SetScrollChild(child)
    local data,describe,selectRow
    local function draw()
        local start = math.floor(scroll:GetVerticalScroll()/23)
        for i=1,math.ceil(scroll:GetHeight()/23)+1 do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button",nil,child)
                row:SetHeight(23)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
                row.label = text(row,"",3,-4)
                row.label:SetPoint("RIGHT",-4,0)
                row.label:SetWordWrap(false)
                row:SetScript("OnClick",function() if row.value then selectRow(row.value) end end)
                rows[i] = row
            end
            local index = start+i
            row.value = data and data[index]
            row:SetShown(row.value~=nil)
            if row.value then
                row:SetPoint("TOPLEFT",0,-(index-1)*23)
                row:SetWidth(child:GetWidth())
                row.label:SetText(describe(row.value))
            end
        end
        for i=math.ceil(scroll:GetHeight()/23)+2,#rows do rows[i]:Hide() end
    end
    scroll:HookScript("OnVerticalScroll",draw)
    scroll:SetScript("OnSizeChanged",function(_,w) child:SetWidth(math.max(1,w)); draw() end)
    return function(values,caption,click,reset)
        data,describe,selectRow = values,caption,click
        child:SetHeight(math.max(1,#values*23))
        if reset then scroll:SetVerticalScroll(0) end
        draw()
    end
end
function craft.Build(page)
    text(page,"Crafting Orders",10,-9,"GameFontNormalLarge")
    local browse, detail = pane(page),pane(page)
    local mode,line,coverage,queue = "Recipes",0,"all","mine"
    local selectedRecipe,selectedOrder,recipient,material
    local render,showRecipe,showOrder
    local search=input(browse,14,-77,190,80)
    local lines = {{0,"All professions"}}
    for _,id in ipairs(D.Lines()) do lines[#lines+1]={id,D.DisplayName(id)} end
    local profMenu=menu(browse,10,-48,163,function() return lines end,function() return line end,function(v) line=v;render(true) end)
    local filters={{"all","All recipes"},{"guild","Known by guild"},{"gaps","Missing in guild"}}
    local views={{"mine","My requests"},{"forme","Assigned to me"},{"open","Available to craft"}}
    local filter=menu(browse,180,-48,161,function() return mode=="Orders" and views or filters end,
        function() return mode=="Orders" and queue or coverage end,
        function(v) if mode=="Orders" then queue=v else coverage=v end;render(true) end)
    local count=text(browse,"",215,-83,"GameFontDisableSmall")
    local setRows=buildListing(browse)
    local modes={}
    for i,m in ipairs({"Recipes","Crafters","Orders"}) do
        modes[m]=button(browse,m,10+(i-1)*92,-25,90,function() mode=m;render(true) end)
    end
    local function list()
        detail:Hide()
        browse:Show()
        render(true)
    end
    render=function(reset)
        for key,b in pairs(modes) do b:SetEnabled(key~=mode) end
        profMenu:SetShown(mode~="Orders")
        filter:SetShown(mode~="Crafters")
        filter:GenerateMenu()
        local q=search:GetText():lower()
        local values={}
        local describe,click
        if mode=="Recipes" then
            values=D.RecipeRows(line~=0 and line or nil,coverage,q)
            describe=function(r) return r.name.."   |cffaaaaaa"..D.DisplayName(r.line).."  ·  "..#r.crafters.." crafters|r" end
            click=showRecipe
        elseif mode=="Crafters" then
            for _,entry in ipairs(lines) do
                if entry[1]~=0 and (line==0 or line==entry[1]) then
                    for _,r in ipairs(D.MemberRows(entry[1])) do
                        if r.key:lower():find(q,1,true) then
                            r.line=entry[1]
                            values[#values+1]=r
                        end
                    end
                end
            end
            describe=function(r) return r.key.."   "..D.DisplayName(r.line).."   "..(r.rank or "?").."/"..(r.max or "?").."   "..r.count.." recipes" end
            click=function(r)
                local known=D.RecipeRows(r.line,"guild")
                local mine={}
                for _,e in ipairs(known) do if craft.Professions:KnowsRecipe(r.key,e.id) then mine[#mine+1]=e end end
                count:SetText(r.key.." · "..#mine.." recipes")
                setRows(mine,function(e) return e.name end,function(e) showRecipe(e,r.key) end,true)
            end
        else
            for _,o in ipairs(O:Rows(queue)) do
                if (itemName(o.item).." "..o.who.." "..(o.cr or "")):lower():find(q,1,true) then values[#values+1]=o end
            end
            describe=function(o) return itemName(o.item).." ×"..o.n.."    "..O.StateOf(o).."    "..o.who end
            click=showOrder
        end
        count:SetText(#values==0 and "No matches" or #values.." results")
        setRows(values,describe,click,reset)
    end
    search:SetScript("OnTextChanged",function() render(true) end)
    button(detail,"Back",10,-35,68,list)
    local title=text(detail,"",88,-38,"GameFontNormal")
    title:SetPoint("TOPRIGHT",detail,"TOPRIGHT",-10,-38)
    title:SetWordWrap(false)
    local description=CreateFrame("ScrollFrame",nil,detail,"UIPanelScrollFrameTemplate")
    description:SetPoint("TOPLEFT",12,-67)
    local content=CreateFrame("Frame",nil,description)
    content:SetSize(1,1)
    description:SetScrollChild(content)
    local info=text(content,"",0,0)
    local function sizeDescription()
        local width=math.max(1,description:GetWidth())
        info:SetWidth(width)
        content:SetSize(width,math.max(1,info:GetStringHeight()+4))
    end
    description:SetScript("OnSizeChanged",sizeDescription)
    local function describeDetail(value,bottom)
        description:SetPoint("BOTTOMRIGHT",detail,"BOTTOMRIGHT",-32,bottom)
        info:SetText(value)
        sizeDescription()
        description:SetVerticalScroll(0)
    end
    local form=CreateFrame("Frame",nil,detail)
    form:SetPoint("BOTTOMLEFT",10,10)
    form:SetPoint("BOTTOMRIGHT",-10,10)
    form:SetHeight(145)
    local qty=input(form,4,-18,46,2,true)
    text(form,"Quantity",0,0)
    local tip=input(form,80,-18,85,10,true)
    text(form,"Tip (copper)",76,0)
    local note=input(form,190,-18,205,80)
    text(form,"Note",186,0)
    local who=menu(form,0,-50,184,function()
        local options={{false,"Any guild crafter"}}
        for _,key in ipairs(selectedRecipe and selectedRecipe.crafters or {}) do
            if key~=O:MyKey() then options[#options+1]={key,key} end
        end
        return options
    end,function() return recipient end,function(v) recipient=v end)
    local materials=menu(form,196,-50,177,function() return {{"mats","I supply materials"},{"own","Crafter supplies"}} end,
        function() return material end,function(v) material=v end)
    local status=text(form,"",0,-110,"GameFontHighlightSmall")
    button(form,"Place order",0,-82,108,function()
        if not selectedRecipe then return end
        local n=qty:GetNumber()
        if n<1 or n>O.MAX_N then status:SetText("Enter a quantity from 1 to "..O.MAX_N..".");return end
        local o,err=O:Place(selectedRecipe.out,{recipe=selectedRecipe.id,n=n,tip=tip:GetNumber(),note=note:GetText(),to=recipient or nil,mode=material})
        if o then mode,queue="Orders","mine";search:SetText("");showOrder(o) else status:SetText(err) end
    end)
    local actions={}
    local function clearActions() for _,b in ipairs(actions) do b:Hide() end end
    local function action(caption,fn)
        local i=1
        while actions[i] and actions[i]:IsShown() do i=i+1 end
        local b=actions[i] or button(detail,"",10+(i-1)*105,-235,103,fn)
        b:ClearAllPoints();b:SetPoint("BOTTOMLEFT",detail,"BOTTOMLEFT",10+(i-1)*105,10)
        actions[i]=b;b:SetText(caption);b:SetScript("OnClick",fn);b:Show()
    end
    showRecipe=function(r,to)
        selectedRecipe,selectedOrder,recipient,material=r,nil,to or false,"mats"
        if recipient==O:MyKey() then recipient=false end
        browse:Hide();detail:Show();clearActions()
        title:SetText(r.name)
        local ingredients={}
        for _,v in ipairs(D.Reagents(r.id)) do ingredients[#ingredients+1]=itemName(v.itemID).." ×"..v.count end
        local source=r.src==3 and "Automatic" or (r.src==2 and ((r.recipeItem or 0)>0 and itemName(r.recipeItem) or "Recipe item") or "Trainer")
        describeDetail(D.DisplayName(r.line).."   Skill "..(r.reqSkill or 0).."   "..source.."\n"..table.concat(ingredients,", ").."\nCrafters: "..(#r.crafters>0 and table.concat(r.crafters,", ") or "None known"),r.out and r.out>0 and 158 or 10)
        form:SetShown(r.out and r.out>0)
        qty:SetText("1");tip:SetText("");note:SetText("");status:SetText("")
        who:GenerateMenu();materials:GenerateMenu()
    end
    showOrder=function(o)
        selectedRecipe,selectedOrder=nil,o
        browse:Hide();detail:Show();form:Hide();clearActions()
        title:SetText(itemName(o.item).." ×"..o.n)
        local state,me=O.StateOf(o),O:MyKey()
        local desc={state.."   Requested by "..o.who,"Crafter: "..(o.cr or o.to or "Open to guild"),
            (o.mode=="own" and "Crafter supplies materials" or "Requester supplies materials").."   Tip: "..GetCoinTextureString(o.tip or 0)}
        for _,r in ipairs(O:Needs(o)) do desc[#desc+1]=itemName(r.itemID).."   "..r.have.."/"..r.need end
        desc[#desc+1]=o.note or ""
        describeDetail(table.concat(desc,"\n"),42)
        local function act(label,verb) action(label,function() O:Act(o.id,verb);showOrder(o) end) end
        if state=="open" and o.who~=me and (o.to==me or not o.to) and O:CanCraft(o.item) then act("Accept","accept") end
        if state=="open" and o.to==me then act("Decline","decline") end
        if (state=="accepted" or state=="mats") and (o.who==me or o.cr==me) then
            if state=="accepted" and o.mode=="mats" then act("Materials sent","mats") end
            act("Complete","done")
            if o.cr==me then act("Release","release") end
        end
        if o.who==me and O.IsActive(o) then act("Cancel order","cancel") end

    end
    function page:List() selectedRecipe,selectedOrder=nil,nil;list() end
    craft.ResetPage=function() if page:IsVisible() then page:List() end end
    O.uiRefresh=function()
        if not page:IsVisible() then return end
        if selectedOrder then showOrder(selectedOrder) elseif browse:IsShown() then render(false) end
    end
end
