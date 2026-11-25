local _, addon = ...
local engine = EVRFeatures
local ui = engine.UI

local ids = {
    Roster = "roster", Professions = "recipes",
    Guild = "guild", Chat = "chat", Bounty = "bounty", Alliances = "alliance", Recruitment = "recruitment",
    Leadership = "management", Settings = "settings",
}
local refreshers = {}

function addon.BindFeatureWindow(frame)
    engine.RosterFrame = frame
    frame.tabPanels = {}
    if engine.db then ui:ApplyScale() end
    function frame:UpdateTabVisibility()
        for _, refresh in pairs(refreshers) do refresh() end
    end
end

function addon.AttachFeaturePage(page, frame, name)
    local id = ids[name]
    local def = ui:GetFeature(id)
    local content = CreateFrame("Frame", nil, page)
    content:SetPoint("TOPLEFT", 8, name == "Settings" and -82 or -8)
    content:SetPoint("BOTTOMRIGHT", -8, 8)
    content:SetClipsChildren(true)
    content.featureId = id
    content:Hide()
    frame.tabPanels[id] = content

    local notice = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    notice:SetPoint("CENTER")
    local built, failed
    local function refresh()
        if not page:IsVisible() then return end
        local reason
        if not engine.db then
            reason = "Waiting for guild data."
        elseif failed or engine:FeatureStartFailed(id) then
            reason = "This feature could not start. See /eviltools errors."
        elseif not engine:IsFeatureEnabled(id) then
            reason = "This feature is disabled in Settings."
        elseif not ui:IsFeatureAllowed(def) then
            reason = name == "Leadership" and "Guild officers only." or "Unavailable for your guild or rank."
        elseif not built then
            built = true
            failed = not engine:RunStartup("Tab:" .. id, nil, def.build, content, frame)
            if failed then reason = "This feature could not start. See /eviltools errors." end
        end
        notice:SetText(reason or "")
        content:SetShown(not reason)
    end
    refreshers[id] = refresh
    page:RegisterEvent("GUILD_ROSTER_UPDATE")
    page:RegisterEvent("PLAYER_GUILD_UPDATE")
    page:SetScript("OnEvent", refresh)
    page:SetScript("OnShow", refresh)
    refresh()
end

function ui:OpenWindow(id, sub, filter)
    if id == "guild" and sub == "chat" then id, sub = "chat", filter end
    if not id or id == "home" then id = "roster" end
    local def = self:GetFeature(id)
    if not engine.db or not self:IsFeatureAllowed(def) then return false end
    if def.opens then
        if def.opens[1] == "guild" and (id == "raids" or id == "loot") then
            return self:OpenWindow("guild", id, sub)
        end
        return self:OpenWindow(def.opens[1], sub or def.opens[2], filter)
    end
    for name, key in pairs(ids) do
        if key == id then
            local frame = addon.ShowPanel()
            frame.SelectGuildTab(name)
            local content = frame.tabPanels[id]
            if content and not content:IsShown() then return false end
            if sub and content and content.SelectSub then return content.SelectSub(sub, filter) ~= false end
            return true
        end
    end
    return false
end

function ui:ToggleMain() addon.TogglePanel() end
function ui:OnFeatureToggled()
    local frame = engine.RosterFrame
    if frame then frame:UpdateTabVisibility() end
end
function ui:ApplyScale()
    local frame = engine.RosterFrame
    if frame then frame:SetScale(engine:GetSetting("uiScale") or 1) end
    self:RefreshHairlines()
end
