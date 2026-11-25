-- EVRNetNet - shared cross-addon presence handshake for the EVRNet addon family
-- (PartyLens, ProfessionHelper, EVRFeatures). SHIP THIS FILE IDENTICAL in each addon.
--
-- A single instance lives at _G.EVRNetNet; whichever addon loads first creates it,
-- the rest reuse it and call EVRNetNet:Register(tag, capsFn, onPeer). Every addon
-- stays fully standalone; when two are present they recognise each other.
--
-- Transport is LibEVRNetMesh (_G.EVRNetMesh): presence rides guild + group + SAY
-- proximity AND the realm-wide dedicated channel, so a HELLO reaches the whole
-- realm/faction, not just your guild. A group answers on first contact; the rest meet on the heartbeat.
--
-- v3: the HELLO now carries the sender's LAYER (mapID:zoneUID) so the whole mesh is
-- layer-aware, not just PartyLens users. Addons with real layer detection (PartyLens)
-- register CN.layerProvider; the rest use a built-in minimal detector (creature-GUID
-- field 5 = zoneUID) so EVRFeatures/ProfessionHelper users report their layer too.
-- v4: receives EVRNetAlert broadcasts and shows a dismissible popup in the host addon's
-- identity (CN:EnableAlerts{accent,title,priority,store}). One popup per client (highest
-- priority wins); "Dismiss" persists the alert id so it never shows again.
-- v5: alert popups are gated to an ALLOWLIST of sender names (CN.ALERT_SENDERS) — only the
-- operator's own characters can fire a popup. Names are unique per realm and the alert
-- buses are realm-local, so this is, in practice, "only alerts from the backoffice I run".
-- v6: the operator now SEES their own alert too (no self-skip) — confirmation it went out +
-- solo-testable. Still deduped by id, still allowlist-gated.
-- v7: the alert is now a QUIET, persistent top BANNER (no sound, no big centered popup) —
-- subtle but always visible until the operator clicks × (dismiss forever).
-- v8: WoW: Forever. A client knows itself by its full name ("First Surname", the way every
-- addon-message sender arrives), not by UnitName's first name: v7 took its own HELLO for a peer's
-- and answered itself. ALERT_SENDERS names the operator's characters in full, and a v8 loading
-- after a v7 adds them to the list it finds.
-- v9: retail. There UnitFullName's second slot is the realm, whatever ShouldDisplaySurname says, so
-- a retail client knows itself by UnitName: v8 could read "Name Realm" as a name and surname.
-- v10: launch day. A HELLO heard on a wide bus (GUILD, SAY, YELL) is no longer answered by whisper:
-- 500 clients on a realm would send each other some 125k whispers after a restart, and the peer's
-- own heartbeat brings the same news within HELLO_INTERVAL. A group's audience is bounded, so a
-- groupmate is still answered at once. A HELLO's level counts only as a whole number from 1 to 255.
-- v11: DIAG, for the backoffice (the CehulNet addon). "DIAG|<id>|<sent>" on EVRNetPing is answered by
-- whisper "DIAGR|<id>|<arrivalDist>|k=v;k=v": the lib versions this client runs, the mesh's counters,
-- its layer, instance and chat lockdown, plus what each host adds through CN:RegisterDiag(tag, fn).
-- Only the operator's characters (ALERT_SENDERS) are answered, each id once; one heard on a wide bus
-- waits a random 0-DIAG_JITTER seconds, so a census never lands as one burst. ALERT_SENDERS gains
-- "Chehul Lightdrizzle", the operator's character on WoW: Forever.
-- v12: the DIAG also says the client's guild, how many peers it heard on GUILD within PEER_TTL (gpeers) and how
-- many of those are in the mesh's directory (gdir). The directory lists only clients with LibEVRNetMesh v5+, and a
-- guild is where an older client is still heard; so the backoffice can estimate the whole network from the
-- directory and the share each guild has updated. A peer remembers when it was last heard on GUILD (gts), since a
-- HELLO whispered through the directory comes in later and would otherwise hide that.
-- v13 (chehulnet#1): the Forever server refused the directory's channel, and LibEVRNetMesh v7 reaches outside the
-- guild through peers it heard instead. The DIAG says how many fresh peers the mesh knows (view) and why the
-- directory is refused (dirx, empty when it is not).
-- v14 (chehulnet#3): LibEVRNetMesh v8 relays realm items and needs to know which peers take the relay. The HELLO's
-- caps carry the mesh version (mv=), and a HELLO heard tells the mesh the peer's addons and version (Mesh:Tag), so
-- a host can ask the mesh for the peers running it (Mesh:Peers(tag)). The DIAG says how many confirmed links the
-- mesh holds (links), how many peers take the relay (v8), what the relay did (rl=in/out/fwd/guild/dup) and the
-- last traces (trace=id:seconds:hops,..., newest first). CN:Trace() sends a trace by the relay; the backoffice reads
-- its reach in the DIAGs.
-- v15 (chehulnet#5): LibEVRNetMesh v9 brakes when its whispers keep finding nobody and keeps one directory per
-- ruleset. The DIAG says how many "No player named" the mesh got within its window (nf), whether the brake is on
-- (trip), which channel the directory uses (dirch) and how old its list is in seconds (dirage, empty before a read).

local VERSION = 15
if _G.EVRNetNet and (_G.EVRNetNet.version or 0) >= VERSION then
    return
end

local CN = _G.EVRNetNet or {}
_G.EVRNetNet = CN

CN.version        = VERSION
CN.PREFIX         = "EVRNetNet"
CN.PROTO          = "CHN1"
CN.HELLO_INTERVAL = 180 -- re-announce presence this often (seconds)
CN.PEER_TTL       = 600 -- forget a peer not heard within this
CN.REPLY_ON       = { PARTY = true, RAID = true, INSTANCE_CHAT = true } -- buses a new peer is answered on

CN.peers     = CN.peers or {}     -- [shortName] = { addons=set, class, level, caps, mapID, zoneUID, ts }
CN.providers = CN.providers or {} -- [tag] = { caps=function|nil, onPeer=function|nil }
CN.layer     = CN.layer or { mapID = 0, zoneUID = 0 } -- built-in detection (non-PL addons)

local Mesh = _G.EVRNetMesh -- shared transport (loaded before this file)

-- A retail client: the mainline project past interface 100000, the two signals EVRFeatures's
-- Client.isRetail reads (WoW: Forever may answer the mainline id; its interface is 16001). This
-- file ships identical in other addons and cannot ask EVRFeatures, so it reads them itself (v9).
local function IsRetail()
    local interface = GetBuildInfo and select(4, GetBuildInfo())
    return WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and (tonumber(interface) or 0) >= 100000
end

-- My own name as every addon-message sender writes it. On WoW: Forever UnitName gives the first
-- name only, and UnitFullName returns the first name and the surname apart (the realm, elsewhere;
-- never a surname on retail, as EVRFeatures's Client.has.surnames says).
local function MyShortName()
    if not IsRetail() and C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname and C_PlayerInfo.ShouldDisplaySurname() then
        local first, surname = UnitFullName("player")
        local secret = issecretvalue and (issecretvalue(first) or issecretvalue(surname))
        if not secret and first and surname and surname ~= "" then
            return first .. " " .. surname
        end
    end
    return UnitName("player") or ""
end

local function LocalTags()
    local tags = {}
    for tag in pairs(CN.providers) do
        tags[#tags + 1] = tag
    end
    table.sort(tags)
    return table.concat(tags, "+")
end

local function MergedCaps()
    local parts = {}
    if Mesh and tonumber(Mesh.version) then
        parts[1] = "mv=" .. Mesh.version -- v14: the relay goes in an envelope only to peers whose mesh takes it
    end
    for _, p in pairs(CN.providers) do
        if p.caps then
            local ok, c = pcall(p.caps)
            if ok and type(c) == "string" and c ~= "" then
                parts[#parts + 1] = c
            end
        end
    end
    return table.concat(parts, ",")
end

-- Our current layer as (mapID, zoneUID). A richer provider (PartyLens's Layer module,
-- NWB-aware) wins when registered; otherwise the built-in detector below fills CN.layer.
-- 0/0 = not detected yet (the receiver treats that as "layer unknown").
function CN:MyLayer()
    if CN.layerProvider then
        local ok, m, z = pcall(CN.layerProvider)
        if ok and type(z) == "number" and z > 0 then
            return m or 0, z
        end
        return 0, 0
    end
    return CN.layer.mapID or 0, CN.layer.zoneUID or 0
end

-- Minimal built-in layer detection (used ONLY when no provider is registered): field 5
-- of a non-player creature's GUID is its zoneUID = the physical layer. Same technique
-- PartyLens/NWB use, reimplemented here so cross-addon peers still report a layer.
local function DetectLayer(unit)
    if CN.layerProvider then
        return -- a richer provider (PartyLens) owns our layer
    end
    if not UnitExists(unit) or UnitIsPlayer(unit)
        or (UnitPlayerControlled and UnitPlayerControlled(unit)) then
        return
    end
    local guid = UnitGUID(unit)
    -- A restricted unit's GUID is a secret value; it cannot be split, so no layer is read from it.
    if not guid or (issecretvalue and issecretvalue(guid)) then
        return
    end
    local kind, _, _, _, zoneUID = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then
        return
    end
    zoneUID = tonumber(zoneUID)
    if not zoneUID or zoneUID == 0 then
        return
    end
    CN.layer.mapID = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 0
    CN.layer.zoneUID = zoneUID
end

-- CHN1|H|<addons +joined>|<class>|<level>|<caps ,joined>|<mapID>:<zoneUID>
-- caps may contain ':' and ',' (e.g. "craft:Enchanting,lfg") but never '|', and the
-- layer field is the LAST '|' field, so the two never collide.
function CN:BuildHello()
    local _, class = UnitClass("player")
    local level = UnitLevel("player") or 0
    local mapID, zoneUID = CN:MyLayer()
    return table.concat({
        CN.PROTO, "H", LocalTags(), class or "", tostring(level), MergedCaps(),
        tostring(mapID or 0) .. ":" .. tostring(zoneUID or 0),
    }, "|")
end

function CN:Announce()
    if not next(CN.providers) or not Mesh then
        return
    end
    local payload = self:BuildHello()
    Mesh:Guild(CN.PREFIX, payload)
    Mesh:Group(CN.PREFIX, payload)
    Mesh:Proximity(CN.PREFIX, payload)
    Mesh:Realm(CN.PREFIX, payload, CN.PREFIX .. ":hello") -- realm-wide (coalesced)
end

function CN:Prune()
    local now = time()
    for name, p in pairs(CN.peers) do
        if (now - (p.ts or 0)) > CN.PEER_TTL then
            CN.peers[name] = nil
        end
    end
end

-- A level off the network: a whole number in range or nothing (tonumber lets "inf" and "nan" through).
local function HelloLevel(level)
    local n = tonumber(level)
    if n and n >= 1 and n <= 255 and n == math.floor(n) then
        return n
    end
end

-- Inbound HELLO (routed here by LibEVRNetMesh for our prefix).
local function OnHello(payload, sender, dist)
    if type(payload) ~= "string" or not sender then
        return
    end
    local proto, op, addons, class, level, caps, layer = strsplit("|", payload)
    if proto ~= CN.PROTO or op ~= "H" then
        return
    end
    local short = (Ambiguate and Ambiguate(sender, "short")) or sender
    if short == MyShortName() then
        return -- ignore our own broadcast
    end
    local set = {}
    for t in string.gmatch(addons or "", "[^+]+") do
        set[t] = true
    end
    -- Layer field (v3+, optional): "mapID:zoneUID". Absent from v1/v2 senders -> 0/0.
    local mapID, zoneUID = 0, 0
    if layer and layer ~= "" then
        local m, z = strsplit(":", layer)
        mapID, zoneUID = tonumber(m) or 0, tonumber(z) or 0
    end
    if Mesh and Mesh.Tag then
        pcall(Mesh.Tag, Mesh, sender, set, caps and ("," .. caps):match(",mv=(%d+)")) -- v14
    end
    local old = CN.peers[short]
    local isNew = old == nil
    CN.peers[short] = {
        addons  = set,
        class   = (class ~= "" and class) or nil,
        level   = HelloLevel(level),
        caps    = caps or "",
        mapID   = mapID,
        zoneUID = zoneUID,
        ts      = time(),
        gts     = (dist == "GUILD") and time() or (old and old.gts) or nil, -- last heard on GUILD (v12)
    }
    -- Reply once to a newcomer heard in the group, so discovery there is two-way at once. Wider
    -- buses wait for the heartbeat; a whispered reply arrives as "WHISPER" -> no ping-pong.
    if isNew and CN.REPLY_ON[dist] and Mesh then
        Mesh:Whisper(CN.PREFIX, CN:BuildHello(), sender)
    end
    for _, p in pairs(CN.providers) do
        if p.onPeer then
            pcall(p.onPeer, short, CN.peers[short])
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public API (called by each addon's wiring).
-- ---------------------------------------------------------------------------
function CN:Register(tag, capsFn, onPeer)
    if type(tag) ~= "string" or tag == "" then
        return
    end
    CN.providers[tag] = { caps = capsFn, onPeer = onPeer }
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function() CN:Announce() end)
    end
end

function CN:Peers()
    return CN.peers
end

function CN:PeerRuns(name, tag)
    local short = (Ambiguate and Ambiguate(name or "", "short")) or name
    local p = short and CN.peers[short]
    return (p ~= nil) and (p.addons[tag] == true)
end

function CN:Count(tag)
    local n = 0
    for _, p in pairs(CN.peers) do
        if not tag or p.addons[tag] then
            n = n + 1
        end
    end
    return n
end

function CN:Start()
    if CN._started then
        return
    end
    CN._started = true
    if C_Timer then
        if C_Timer.After then
            C_Timer.After(5, function() CN:Announce() end)
        end
        if C_Timer.NewTicker then
            CN.ticker = C_Timer.NewTicker(CN.HELLO_INTERVAL, function()
                CN:Prune()
                CN:Announce()
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
if Mesh then Mesh:Register(CN.PREFIX, OnHello) end

CN.frame = CN.frame or CreateFrame("Frame")
CN.frame:RegisterEvent("PLAYER_LOGIN")
CN.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
CN.frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
CN.frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        DetectLayer("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        DetectLayer("mouseover")
    else
        CN:Start()
    end
end)
if C_Timer and C_Timer.After then
    C_Timer.After(8, function() CN:Start() end)
end

return CN
