----------------------------------------------------------------------
-- EVIL Rises - Login Digest
-- "Since your last login: N new members, X items looted, ..." — a quick
-- catch-up shown once on login (and on demand via /eviltools digest).
-- Build() is pure data; the popup uses the UI factories at runtime.
----------------------------------------------------------------------
local Digest = {}
EVRFeatures.Digest = Digest
local L = EVRFeatures.L

function Digest:Initialize()
    EVRFeatures.db.digest = EVRFeatures.db.digest or {}
    if EVRFeatures.db.digest.enabled == nil then EVRFeatures.db.digest.enabled = true end
    if EVRFeatures.db.digest.lastSeen == nil then EVRFeatures.db.digest.lastSeen = 0 end
end

local function myKey()
    return EVRFeatures:GetPlayerKey(EVRFeatures.Compat.PlayerName(), GetRealmName())
end

----------------------------------------------------------------------
-- Build the digest lines for everything that changed since `since`
-- (a server timestamp). Returns an array of strings.
----------------------------------------------------------------------
-- opts.login: the login's digest, where the bulletin tells only the notices not told yet (#418); elsewhere (the
-- Activity sub-tab, /eviltools digest) it lists the notices posted since `since`, as it always did.
function Digest:Build(since, opts)
    since = since or EVRFeatures.db.digest.lastSeen or 0
    local lines = {}
    local told = {}

    -- New members (first observed by EVIL Rises since last login, after its first look at the guild)
    local newCount, newNames = 0, {}
    local newSince = math.max(since, EVRFeatures.db.firstSeenSince or 0)
    for key, ts in pairs(EVRFeatures.db.firstSeen or {}) do
        if ts and ts > newSince then
            newCount = newCount + 1
            if #newNames < 3 then newNames[#newNames + 1] = key:match("^([^-]+)") or key end
        end
    end
    if newCount > 0 then
        local names = table.concat(newNames, ", ")
        if newCount > #newNames then names = names .. " +" .. (newCount - #newNames) end
        lines[#lines + 1] = string.format(L["%d new member(s): %s"], newCount, names)
    end

    -- Roster changes since last login (from the audit log)
    if EVRFeatures.RosterLog then
        local c = EVRFeatures.RosterLog:CountsSince(since)
        if c.kick > 0 then lines[#lines + 1] = string.format(L["%d member(s) removed"], c.kick) end
        if c.leave > 0 then lines[#lines + 1] = string.format(L["%d member(s) left"], c.leave) end
    end

    -- Raid sessions tracked since last login
    local raidCount = 0
    if EVRFeatures.db.raidTracker and EVRFeatures.db.raidTracker.sessions then
        for _, s in pairs(EVRFeatures.db.raidTracker.sessions) do
            if s.startTime and s.startTime > since then raidCount = raidCount + 1 end
        end
    end
    if raidCount > 0 then
        lines[#lines + 1] = string.format(L["%d raid session(s) tracked"], raidCount)
    end

    -- Loot recorded since last login
    local lootCount = 0
    for _, e in ipairs(EVRFeatures.db.lootHistory or {}) do
        if (e.timestamp or 0) > since then lootCount = lootCount + 1 end
    end
    if lootCount > 0 then
        lines[#lines + 1] = string.format(L["%d item(s) looted"], lootCount)
    end

    -- Your own points change since last login
    if EVRFeatures.Points and EVRFeatures.db.points and EVRFeatures.db.points.log then
        local mk = myKey()
        local delta = 0
        for _, e in ipairs(EVRFeatures.db.points.log) do
            if e.key == mk and (e.ts or 0) > since then delta = delta + (e.delta or 0) end
        end
        if delta ~= 0 then
            lines[#lines + 1] = string.format(L["Your points changed by %+d (now %d)"], delta, EVRFeatures.Points:Get(mk))
        end
    end

    -- Milestones & guild anniversaries
    if EVRFeatures.Milestones then
        for _, line in ipairs(EVRFeatures.Milestones:GetDigestLines(since, told)) do
            lines[#lines + 1] = line
        end
    end
    -- WoW: Forever's founding: who joined as a founder, the window, the guild's anniversaries (#209)
    if EVRFeatures.Founding then
        for _, line in ipairs(EVRFeatures.Founding:GetDigestLines(since, GetServerTime(), told)) do
            lines[#lines + 1] = line
        end
    end

    -- Today's birthdays and join anniversaries (#428): at the first login of the day, and on demand.
    if EVRFeatures.Birthdays and not (opts and opts.login and EVRFeatures.Birthdays:ToldToday(GetServerTime())) then
        for _, line in ipairs(EVRFeatures.Birthdays:GetDigestLines(GetServerTime())) do
            lines[#lines + 1] = "|cffEDCC7B" .. line .. "|r"
        end
    end

    -- Upcoming raid reminder (event within the next 24h)
    if EVRFeatures.Calendar and EVRFeatures.Calendar.GetDigestLines then
        local calLines = EVRFeatures.Calendar:GetDigestLines()
        if calLines then
            for _, line in ipairs(calLines) do
                lines[#lines + 1] = "|cff4CB8FF" .. line .. "|r"
            end
        end
    end

    -- Alliance: how many allied raids are coming up in the next week. One line,
    -- and only when this guild is federated and something is actually scheduled.
    if EVRFeatures.Alliance and EVRFeatures.Alliance:Get() and EVRFeatures.Calendar
        and EVRFeatures.Calendar.AllianceEvents then
        local horizon = GetServerTime() + (7 * 86400)
        local count = 0
        for _, e in ipairs(EVRFeatures.Calendar:AllianceEvents()) do
            if (tonumber(e.when) or 0) <= horizon then
                count = count + 1
            end
        end
        if count > 0 then
            local gold = EVRFeatures.Colors.gold
            lines[#lines + 1] = string.format("|cff%02x%02x%02x", gold.r * 255, gold.g * 255, gold.b * 255) ..
                string.format(L["%d allied event(s) this week"], count) .. "|r"
        end
    end

    -- Bulletin notices. At login, the active ones this player has not been told about (issue #418), the newest
    -- few: each once, whenever it was posted, never one that has ended; ShowOnLogin marks them told. Anywhere
    -- else, the most recent few posted since `since`.
    if EVRFeatures.Bulletin then
        if opts and opts.login then
            for _, m in ipairs(EVRFeatures.Bulletin:Unseen(GetServerTime(), 3)) do
                lines[#lines + 1] = EVRFeatures.Bulletin.Line(m)
            end
        else
            local shown = 0
            for _, m in ipairs(EVRFeatures.Bulletin:GetMessages()) do
                if type(m) == "table" and (tonumber(m.ts) or 0) > since and shown < 3 then
                    lines[#lines + 1] = EVRFeatures.Bulletin.Line(m)
                    shown = shown + 1
                end
            end
        end
    end

    -- New polls opened since last login
    if EVRFeatures.Polls then
        local newPolls = 0
        for _, p in pairs(EVRFeatures.Polls:GetList()) do
            if not p.closed and (p.ts or 0) > since then newPolls = newPolls + 1 end
        end
        if newPolls > 0 then
            lines[#lines + 1] = string.format(L["%d new poll(s) — cast your vote"], newPolls)
        end
    end

    -- Officer-only catch-up
    if EVRFeatures:IsOfficer() then
        if EVRFeatures.TrialTracker then
            -- Ready to review: their end, from the guild's length, has passed with no decision (#249).
            local due = EVRFeatures.TrialTracker:CountReady()
            if due > 0 then
                lines[#lines + 1] = string.format(L["%d trial(s) ready for decision"], due)
            end
        end
        if EVRFeatures.GuildManager and EVRFeatures.GuildManager.GetInactiveMembers then
            local inactive = EVRFeatures.GuildManager:GetInactiveMembers(EVRFeatures.GuildManager.DEFAULT_INACTIVE_DAYS)
            if inactive and #inactive > 0 then
                lines[#lines + 1] = string.format(L["%d inactive member(s)"], #inactive)
            end
        end
    end

    return lines
end

-- The login digest showed these: they are not shown again, and what is too old to come back is forgotten.

----------------------------------------------------------------------
-- The popup window.
----------------------------------------------------------------------
function Digest:Show(lines)
    local UI = EVRFeatures.UI
    local C = EVRFeatures.Colors
    lines = lines or self:Build()

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "EVRFeaturesDigestFrame", UIParent, "BackdropTemplate")
        f:SetSize(360, 280)
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = EVRFeatures.UI:Edge(f) })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f, { shadowSize = 16 })
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
        f:SetScript("OnDragStop", function(self2) self2:StopMovingOrSizing() end)

        f.title = UI:CreateTitle(f, L["Since your last login"], 15)
        f.title:SetPoint("TOPLEFT", 16, -14)

        f.close = UI:CreateCloseButton(f)
        f.close:SetPoint("TOPRIGHT", -8, -8)
        f.close:SetScript("OnClick", function() f:Hide() end)

        f.body = CreateFrame("Frame", nil, f)
        f.body:SetPoint("TOPLEFT", 16, -44)
        f.body:SetPoint("BOTTOMRIGHT", -16, 48)

        f.openBtn = UI:CreateButton(f, L["Open EVIL Rises"], 140, 26)
        f.openBtn:SetPoint("BOTTOM", 0, 14)
        f.openBtn:SetScript("OnClick", function()
            f:Hide()
            EVRFeatures:ToggleRoster()
        end)
        self.frame = f
    end

    -- (Re)populate the body
    for _, c in pairs({ f.body:GetChildren() }) do c:Hide() end
    for _, r in pairs({ f.body:GetRegions() }) do r:Hide() end

    local y = 0
    if #lines == 0 then
        local empty = UI:CreateText(f.body, L["Nothing new since your last login."], 11, C.silver.r, C.silver.g, C.silver.b)
        empty:SetPoint("TOPLEFT", 2, -y)
        empty:SetWidth(f.body:GetWidth() - 4)
    else
        for _, line in ipairs(lines) do
            local dot = UI:CreateText(f.body, "|cffEDCC7B*|r", 12, C.gold.r, C.gold.g, C.gold.b)
            dot:SetPoint("TOPLEFT", 2, -y)
            local fs = UI:CreateText(f.body, line, 11, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 18, -y)
            fs:SetWidth(f.body:GetWidth() - 22)
            fs:SetJustifyH("LEFT")
            y = y + math.max(20, (fs:GetStringHeight() or 14) + 8)
        end
    end
    -- The title above and the button below: a long digest grows, never runs under the button.
    f:SetHeight(math.max(280, 44 + y + 48))

    f:Show()
    return f
end

----------------------------------------------------------------------
-- Auto-show once on login (skipped on first run and when disabled).
----------------------------------------------------------------------
function Digest:ShowOnLogin()
    local B = EVRFeatures.Bulletin
    -- From now on a notice that arrives is told in the chat (issue #418).
    if B then B:LoginDone() end
    if not EVRFeatures.db.digest or not EVRFeatures.db.digest.enabled then
        -- No digest: the notices not told yet get a chat line each, and so do today's birthdays (#428).
        if B then B:TellInChat(GetServerTime()) end
        if EVRFeatures.Birthdays then EVRFeatures.Birthdays:TellInChat(GetServerTime()) end
        return
    end
    if self.shownThisSession then return end
    -- A raid owner's prompt took this login (issue #400): one popup at a time, and the raid about to start is the
    -- one that cannot wait. Nothing is marked seen: the digest shows once the prompt is put off (Later or its close,
    -- RaidStart:PromptDismissed), and after Raid ready waits for the next login, or /eviltools digest.
    if EVRFeatures.RaidStart and EVRFeatures.RaidStart:PromptedAtLogin() then
        self.deferred = true
        return
    end

    local since = EVRFeatures.db.digest.lastSeen or 0
    -- First ever run: nothing to compare against — just start the clock.
    if since == 0 then
        EVRFeatures.db.digest.lastSeen = GetServerTime()
        -- The board is not part of that clock: what is on it now is told in the chat.
        if B then B:TellInChat(GetServerTime()) end
        return
    end

    local lines = self:Build(since, { login = true })
    if B then B:MarkSeen(GetServerTime()) end
    if EVRFeatures.Birthdays then EVRFeatures.Birthdays:MarkTold(GetServerTime()) end
    EVRFeatures.db.digest.lastSeen = GetServerTime()
    self.shownThisSession = true
    if #lines > 0 then
        self:Show(lines)
    end
end
