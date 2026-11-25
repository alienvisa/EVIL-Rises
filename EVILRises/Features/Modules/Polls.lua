----------------------------------------------------------------------
-- EVIL Rises - Polls / Voting
-- Officers create a poll; members vote. Polls are broadcast via
-- SyncService (domain "poll"): "create"/"close" are officer actions,
-- "vote" is a member action recorded per voter on every client.
----------------------------------------------------------------------
local Polls = {}
EVRFeatures.Polls = Polls
local L = EVRFeatures.L

function Polls:Initialize()
    EVRFeatures.db.polls = EVRFeatures.db.polls or { list = {} }
    EVRFeatures.db.polls.list = EVRFeatures.db.polls.list or {}
    if EVRFeatures.SyncService then
        EVRFeatures.SyncService:On("poll", function(env, sender) Polls:OnSync(env, sender) end)
    end
end

function Polls:GetList() return EVRFeatures.db.polls.list end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

local function keyOf(name)
    local short = (name or ""):match("^([^-]+)") or name
    -- Retail: the sender's own realm, or two connected-realm namesakes are one person (ADR-0026).
    local realm = EVRFeatures.Client.isRetail and (name or ""):match("^[^-]+%-(.+)$") or GetRealmName()
    return EVRFeatures:GetPlayerKey(short, realm)
end

-- Sorted polls: open first, then newest.
function Polls:GetSorted()
    local list = {}
    for _, p in pairs(self:GetList()) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        if (a.closed and true or false) ~= (b.closed and true or false) then return not a.closed end
        return (a.ts or 0) > (b.ts or 0)
    end)
    return list
end

----------------------------------------------------------------------
-- Mutations
----------------------------------------------------------------------
function Polls:Create(question, options)
    if not EVRFeatures:IsOfficer() then
        EVRFeatures:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    question = strtrim(question or "")
    if question == "" or type(options) ~= "table" or #options < 2 then
        EVRFeatures:Print(L["A poll needs a question and at least 2 options."])
        return
    end
    local p = {
        id = newId(), question = question, options = options, votes = {},
        author = EVRFeatures.Compat.PlayerName(), ts = GetServerTime(), closed = false,
    }
    self:GetList()[p.id] = p
    if EVRFeatures.SyncService then
        local rev = EVRFeatures.SyncService:NextRevision("poll", p.id)
        EVRFeatures.SyncService:Publish("poll", "create", { poll = {
            id = p.id, question = p.question, options = p.options, author = p.author, ts = p.ts,
        } }, { rev = rev })
    end
    self:Refresh()
end

function Polls:Vote(id, opt)
    local p = self:GetList()[id]
    if not p or p.closed then return end
    p.votes = p.votes or {}
    p.votes[keyOf(EVRFeatures.Compat.PlayerName())] = opt
    if EVRFeatures.SyncService then
        EVRFeatures.SyncService:Publish("poll", "vote", { id = id, opt = opt })
    end
    self:Refresh()
end

function Polls:Close(id)
    if not EVRFeatures:IsOfficer() then return end
    local p = self:GetList()[id]
    if not p then return end
    p.closed = true
    if EVRFeatures.SyncService then
        EVRFeatures.SyncService:Publish("poll", "close", { id = id })
    end
    self:Refresh()
end

----------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------
function Polls:OnSync(env, sender)
    local d = env.data
    if env.act == "create" and d and d.poll then
        local p = d.poll
        if EVRFeatures.SyncService:ShouldApply("poll", p.id, env.rev) then
            local existing = self:GetList()[p.id]
            p.votes = (existing and existing.votes) or {}
            self:GetList()[p.id] = p
            EVRFeatures.SyncService:SetRevision("poll", p.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "close" and d and d.id then
        local p = self:GetList()[d.id]
        if p then p.closed = true; self:Refresh() end
    elseif env.act == "vote" and d and d.id and d.opt then
        local p = self:GetList()[d.id]
        if p and not p.closed then
            p.votes = p.votes or {}
            p.votes[keyOf(sender)] = d.opt
            self:Refresh()
        end
    end
end

function Polls:Refresh()
    if self.uiRefresh then EVRFeatures:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function Polls:Show()
    local UI = EVRFeatures.UI
    local C = EVRFeatures.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "EVRFeaturesPollsFrame", UIParent, "BackdropTemplate")
        f:SetSize(480, 440)
        f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = EVRFeatures.UI:Edge(f) })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

        local title = UI:CreateTitle(f, L["Guild Polls"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        local listTop = -44
        if EVRFeatures:IsOfficer() then
            -- The shared fields (#371): the question's hint inside it while empty, the options box
            -- three lines tall with its hint right under it.
            local qBox = UI:CreateInput(f, 330, 24, { max = 150, placeholder = L["Question..."] })
            qBox:SetPoint("TOPLEFT", 16, -42)

            local oArea = UI:CreateTextArea(f, 0, 56)   -- a multi-line EditBox alone shrinks to one line
            oArea:SetPoint("TOPLEFT", qBox, "BOTTOMLEFT", 0, -8)
            oArea:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -74)
            local oBox = oArea.edit
            local oHint = UI:CreateText(f, L["One option per line (2-6)"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            oHint:SetPoint("TOPLEFT", oArea, "BOTTOMLEFT", 0, -4)

            local createBtn = UI:CreateButton(f, L["Create Poll"], 110, 24)
            createBtn:SetPoint("LEFT", qBox, "RIGHT", 8, 0)
            createBtn:SetScript("OnClick", function()
                local opts = {}
                for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                    local t = strtrim(line)
                    if t ~= "" and #opts < 6 then opts[#opts + 1] = t end
                end
                EVRFeatures.Polls:Create(qBox:GetText(), opts)
                qBox:SetText(""); oBox:SetText(""); qBox:ClearFocus(); oBox:ClearFocus()
            end)
            listTop = -156
        end

        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 16, listTop)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "EVRFeaturesPollsScroll")
        scroll:SetAllPoints()
        -- The rows hang from both of the child's top corners; it keeps the list's width (#371).
        UI:BindScrollChildWidth(scroll, child)
        f.child = child
        f.holder = holder
        self.frame = f
    end

    local function refresh()
        if not f:IsShown() then return end
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end

        local polls = EVRFeatures.Polls:GetSorted()
        local isOfficer = EVRFeatures:IsOfficer()
        local myKey = keyOf(EVRFeatures.Compat.PlayerName())
        local y = 0
        for _, p in ipairs(polls) do
            -- Question: the text colour, a closed one the soft one (#371).
            local qc = p.closed and C.textSoft or C.text
            local closable = isOfficer and not p.closed
            local q = UI:CreateText(child, (p.closed and "[" .. L["closed"] .. "] " or "") .. p.question, 12, qc.r, qc.g, qc.b)
            q:SetPoint("TOPLEFT", 0, -y)
            q:SetPoint("TOPRIGHT", closable and -64 or 0, -y)
            q:SetJustifyH("LEFT")
            if closable then
                local closeBtn = UI:CreateButton(child, L["Close"], 56, 18)
                closeBtn:SetPoint("TOPRIGHT", 0, -y)
                local id = p.id
                closeBtn:SetScript("OnClick", function() EVRFeatures.Polls:Close(id) end)
            end
            y = y + math.max(18, (q:GetStringHeight() or 14) + 4)

            -- Tally
            local total = 0
            local counts = {}
            for _, opt in pairs(p.votes or {}) do
                counts[opt] = (counts[opt] or 0) + 1
                total = total + 1
            end
            local myVote = p.votes and p.votes[myKey]

            for idx, optText in ipairs(p.options or {}) do
                local n = counts[idx] or 0
                local pct = total > 0 and math.floor(n / total * 100 + 0.5) or 0
                local label = string.format("%s  (%d · %d%%)", optText, n, pct)
                local btn = UI:CreateButton(child, label, 1, 20)
                btn:SetPoint("TOPLEFT", 0, -y)
                btn:SetPoint("TOPRIGHT", 0, -y)
                -- My vote is the selected option, as every selection is marked (#371).
                UI:SetSelected(btn, myVote == idx)
                btn.label:SetJustifyH("LEFT")
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", 8, 0)
                if not p.closed then
                    local id, oi = p.id, idx
                    btn:SetScript("OnClick", function() EVRFeatures.Polls:Vote(id, oi) end)
                end
                y = y + 22
            end

            local meta = UI:CreateText(child, string.format(L["%d vote(s) · by %s"], total, p.author or "?"),
                11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            meta:SetPoint("TOPLEFT", 0, -y)
            y = y + 22
        end
        if #polls == 0 then
            local empty = UI:CreateText(child, L["No polls yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end
