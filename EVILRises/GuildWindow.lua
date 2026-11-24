local _, addon = ...

local guildFrames = { "GuildFrame", "CommunitiesFrame" }
local hookedFrames, hookedButtons = {}, {}
local hookedToggle
local queued, toggleQueued, closePending

local function isGuildView(frame)
    if frame == GuildFrame then
        return true
    end
    local guildClubID = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    return guildClubID and frame.GetSelectedClubId and frame:GetSelectedClubId() == guildClubID
end

local function closeGuildViews()
    local found = false
    for _, name in ipairs(guildFrames) do
        local frame = _G[name]
        if frame and frame:IsShown() and isGuildView(frame) then
            found = true
            if InCombatLockdown() then
                closePending = true
            else
                HideUIPanel(frame)
            end
        end
    end
    return found
end

local function toggleGuildWindow()
    closeGuildViews()
    addon.TogglePanel()
end

local function queueRedirect(toggle)
    if not IsInGuild() then return end
    toggleQueued = toggleQueued or toggle
    if queued then return end
    queued = true
    -- Let Blizzard finish its show/select/close operation before changing its panel.
    C_Timer.After(0, function()
        local shouldToggle = toggleQueued
        queued, toggleQueued = nil, nil
        if not IsInGuild() then return end
        local found = closeGuildViews()
        if shouldToggle then
            addon.TogglePanel()
        elseif found then
            addon.ShowPanel()
        end
    end)
end

local function hookGuildFrames()
    for _, name in ipairs(guildFrames) do
        local frame = _G[name]
        if frame and not hookedFrames[frame] then
            hookedFrames[frame] = true
            frame:HookScript("OnShow", function() queueRedirect(false) end)
            if frame == CommunitiesFrame and frame.SelectClub then
                hooksecurefunc(frame, "SelectClub", function(self)
                    if self:IsShown() and isGuildView(self) then
                        queueRedirect(false)
                    end
                end)
            end
            if frame:IsShown() then queueRedirect(false) end
        end
    end
    if not hookedToggle and type(ToggleGuildFrame) == "function" then
        hooksecurefunc("ToggleGuildFrame", function() queueRedirect(true) end)
        hookedToggle = true
    end
end

local function hookGuildButton()
    if InCombatLockdown() then return end
    local button = GuildMicroButton or CommunitiesMicroButton
    if not button or hookedButtons[button] then return end
    hookedButtons[button] = true
    if button:IsProtected() then
        button:HookScript("OnClick", function(_, mouseButton)
            if mouseButton == "LeftButton" then queueRedirect(true) end
        end)
    else
        local original = button:GetScript("OnClick")
        button:SetScript("OnClick", function(self, mouseButton, ...)
            if mouseButton == "LeftButton" and IsInGuild() then
                toggleGuildWindow()
            elseif original then
                original(self, mouseButton, ...)
            end
        end)
    end
end

local function updateBindings(owner)
    if InCombatLockdown() then return end
    ClearOverrideBindings(owner)
    if IsInGuild() then
        for _, key in ipairs({ GetBindingKey("TOGGLEGUILDTAB") }) do
            SetOverrideBindingClick(owner, false, key, owner:GetName(), "LeftButton")
        end
    end
end

function addon.InstallGuildWindow()
    local owner = CreateFrame("Button", "EVILRisesGuildBinding", UIParent)
    owner:SetScript("OnClick", function()
        if IsInGuild() then
            toggleGuildWindow()
        elseif ToggleGuildFrame then
            ToggleGuildFrame()
        end
    end)
    owner:RegisterEvent("ADDON_LOADED")
    owner:RegisterEvent("UPDATE_BINDINGS")
    owner:RegisterEvent("PLAYER_GUILD_UPDATE")
    owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    owner:SetScript("OnEvent", function(self, event)
        if event == "ADDON_LOADED" or event == "PLAYER_REGEN_ENABLED" then
            hookGuildFrames()
            hookGuildButton()
        end
        if event ~= "ADDON_LOADED" then
            updateBindings(self)
        end
        if event == "PLAYER_REGEN_ENABLED" and closePending then
            closePending = nil
            if IsInGuild() then closeGuildViews() end
        end
    end)
    hookGuildFrames()
    hookGuildButton()
    updateBindings(owner)
end
