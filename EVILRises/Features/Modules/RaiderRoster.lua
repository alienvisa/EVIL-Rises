----------------------------------------------------------------------
-- EVIL Rises - Raider Roster
-- An officer-curated pool of the guild's raiders, independent of any one
-- raid. Officers hand-manage columns (which roles each person can fill —
-- multi-role, a gear-readiness status, and a free note) so the data does
-- NOT require the listed player to run the addon. When a player DOES run
-- it, the UI enriches the row read-only with their synced iLvl + spec.
--
-- Officer-authored, synced between clients like OfficerNotes/TrialTracker:
-- the whole (small) table is broadcast on edit / on request, merged
-- per-player by updatedAt (newest wins) so concurrent edits don't clobber.
----------------------------------------------------------------------
local RaiderRoster = {}
EVRFeatures.RaiderRoster = RaiderRoster
local LibSerialize = LibStub("EVRFeatures-LibSerialize")

RaiderRoster.ROLES = { "TANK", "HEALER", "DPS" }
-- Gear-readiness cycle (officer-set); "" = unset.
RaiderRoster.GEAR_CYCLE = { "", "ready", "gearing", "missing" }

function RaiderRoster:Initialize()
    EVRFeatures.db.raiders = EVRFeatures.db.raiders or {}
end

function RaiderRoster:GetAll() return EVRFeatures.db.raiders or {} end
function RaiderRoster:Get(key) return EVRFeatures.db.raiders and EVRFeatures.db.raiders[key] or nil end

-- Effective roles = the officer override once an officer has touched this row
-- (rolesSet), otherwise the player's own self-declared roles (synced in their
-- member data as prefRoles). This is what the roster shows and counts.
function RaiderRoster:EffectiveRoles(key)
    local r = EVRFeatures.db.raiders and EVRFeatures.db.raiders[key]
    if r and r.rolesSet then return r.roles or {} end
    local mem = EVRFeatures.db.members and EVRFeatures.db.members[key]
    return (mem and mem.prefRoles) or {}
end

local function getOrNew(key)
    EVRFeatures.db.raiders = EVRFeatures.db.raiders or {}
    local r = EVRFeatures.db.raiders[key]
    if not r then
        r = { roles = {}, gear = "", note = "" }
        EVRFeatures.db.raiders[key] = r
    end
    r.roles = r.roles or {}
    return r
end

local function touch(r)
    r.updatedBy = EVRFeatures.Compat.PlayerName()
    r.updatedAt = GetServerTime()
end

----------------------------------------------------------------------
-- Officer edits (each refreshes the UI + queues a sync broadcast).
----------------------------------------------------------------------
function RaiderRoster:ToggleRole(key, role)
    if not EVRFeatures:IsOfficer() then return end
    local r = getOrNew(key)
    -- First officer touch seeds the override from the player's self-declared
    -- roles, so the officer starts from what the raider already said.
    if not r.rolesSet then
        r.roles = {}
        for k, v in pairs(self:EffectiveRoles(key)) do if v then r.roles[k] = true end end
        r.rolesSet = true
    end
    r.roles[role] = (not r.roles[role]) and true or nil
    touch(r)
    self:Refresh(); self:Broadcast()
end

function RaiderRoster:CycleGear(key)
    if not EVRFeatures:IsOfficer() then return end
    local r = getOrNew(key)
    local cur, idx = r.gear or "", 1
    for i, v in ipairs(self.GEAR_CYCLE) do if v == cur then idx = i break end end
    r.gear = self.GEAR_CYCLE[(idx % #self.GEAR_CYCLE) + 1]
    touch(r)
    self:Refresh(); self:Broadcast()
end

function RaiderRoster:SetNote(key, text)
    if not EVRFeatures:IsOfficer() then return end
    local r = getOrNew(key)
    r.note = strtrim(text or "")
    touch(r)
    self:Refresh(); self:Broadcast()
end

function RaiderRoster:Refresh()
    if self.uiRefresh then EVRFeatures:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Sync (officer -> guild). The table is small, so we broadcast it whole
-- (debounced); receivers merge per-player by updatedAt.
----------------------------------------------------------------------
function RaiderRoster:Broadcast()
    if not EVRFeatures.CommSystem or not IsInGuild() then return end
    if not EVRFeatures:IsOfficer() then return end
    if self._bcastPending then return end
    self._bcastPending = true
    C_Timer.After(1.5, function()
        self._bcastPending = nil
        local payload = LibSerialize:Serialize(self:GetAll())
        EVRFeatures.CommSystem:SendMessage("RR", payload)
    end)
end

-- Officers answer a sync REQUEST with the current table (login backfill).
function RaiderRoster:RespondToSync()
    if EVRFeatures:IsOfficer() then self:Broadcast() end
end

-- Apply an incoming table (only trusted from a verified officer). Merge
-- per-player: keep whichever record has the newer updatedAt.
function RaiderRoster:HandleIncoming(sender, data)
    if not (EVRFeatures.IsOfficerByName and EVRFeatures:IsOfficerByName(sender)) then return end
    local ok, tbl = LibSerialize:Deserialize(data)
    if not ok or type(tbl) ~= "table" then return end
    EVRFeatures.db.raiders = EVRFeatures.db.raiders or {}
    local changed = false
    for incomingKey, rec in pairs(tbl) do
        local key = EVRFeatures:LocalMemberKey(incomingKey)   -- the sender's key, as this client's (#97)
        if type(rec) == "table" then
            local cur = EVRFeatures.db.raiders[key]
            if not cur or (rec.updatedAt or 0) >= (cur.updatedAt or 0) then
                rec.roles = rec.roles or {}
                -- Officers only, as OfficerNotes (#170). A copy with no note is a member's who was
                -- promoted: it clears nothing, since clearing a note sends "". A rank the client has
                -- not loaded yet reads as no officer (#79), and that is no reason to drop one.
                if rec.note == nil and cur then rec.note = cur.note end
                local _, _, rank = GetGuildInfo("player")
                if rank and not EVRFeatures:IsOfficer() then rec.note = nil end
                EVRFeatures.db.raiders[key] = rec
                changed = true
            end
        end
    end
    if changed then self:Refresh() end
end
