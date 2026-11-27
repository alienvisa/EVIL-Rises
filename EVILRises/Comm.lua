local _, addon = ...
----------------------------------------------------------------------
-- EVIL Rises guild messages
--
-- Every sync message is one table with named fields, sent on the guild channel under PREFIX:
--
--   v    protocol version (PROTOCOL); a message with a higher one is dropped
--   g    guild ID, checked against the receiver's own
--   d    area, such as "bounty" or "craftorder"
--   a    action within the area
--   p    payload, checked by the area
--   ver  the sender's addon version, for the update reminder
--   to   the member a guild message is for, when it is for one only
--   c    the areas the sender understands, { [area] = version }: on its first message, then
--        at most every CAPS_EVERY seconds, and sooner when a new guildmate appears
--
-- A receiver reads the fields it knows and ignores the rest, so a field can be added without
-- breaking older copies. An area registers once with Comm:Register and sends with Comm:Send.
--
-- Copies from before this format (0.9.0 and older) listen only on the old prefixes. Every
-- message also goes out in the old format for STARTUP_LEGACY seconds after login, long enough
-- to hear any older copy online (they send a profession summary every 10 minutes), and for
-- LEGACY_FOR seconds after an older copy was last heard. The old-format copy is marked, so
-- newer clients skip it and read the new one instead.
----------------------------------------------------------------------
local comm = LibStub("AceComm-3.0")
local codec = LibStub("EVRFeatures-LibSerialize")
local wire = LibStub("LibDeflate")
local noop = function() end
local logSync = addon.LogSync or noop
local version, noteVersion = addon.Version or noop, addon.NoteVersion or noop

local PROTOCOL = 2
local PREFIX = "EVRSync2"
local MAX_BYTES = 96000
-- The old prefixes, the area names their messages map to, and their old size limits.
local LEGACY = {
    bounty = { prefix = "EVRBounty1", maxBytes = 32000 },
    crafts = { prefix = "EVRCrafts1", maxBytes = 96000 },
}

local Comm = { PROTOCOL = PROTOCOL, PREFIX = PREFIX, STARTUP_LEGACY = 900, LEGACY_FOR = 3600, CAPS_EVERY = 600 }
addon.Comm = Comm

local areas = {}   -- [area] = { label, priority, maxBytes, legacy, version, handle }
local peers = {}   -- [member key] = { caps = { [area] = version }, at = time heard }
local legacyUntil, capsSentAt, capsDue

local function owner(name) return addon.Owner and addon.Owner(name) end
local function guildID() return addon.GuildID and addon.GuildID() end

-- spec = { label = debug log category, priority = "BULK"|"NORMAL"|"ALERT", maxBytes = largest
-- message accepted, legacy = "bounty"|"crafts" for areas that existed before this format,
-- version = this area's capability number (1 by default), handle = function(action, payload,
-- sender, info) where info = { target = the member it was for, or nil; bytes = its size } }
function Comm:Register(area, spec)
    areas[area] = {
        label = spec.label or area, priority = spec.priority or "NORMAL",
        maxBytes = math.min(spec.maxBytes or MAX_BYTES, MAX_BYTES), legacy = spec.legacy,
        version = spec.version or 1, handle = spec.handle,
    }
end

function Comm:Caps()
    local caps = {}
    for area, spec in pairs(areas) do caps[area] = spec.version end
    return caps
end

-- What a guildmate said it understands, or nil when it has not said yet.
function Comm:PeerCaps(sender)
    local peer = peers[owner(sender) or ""]
    return peer and peer.caps
end

-- Whether a guildmate said it reads `area` at version `atLeast` (1 by default) or newer.
function Comm:Supports(sender, area, atLeast)
    local caps = self:PeerCaps(sender)
    local n = caps and caps[area]
    return type(n) == "number" and n >= (atLeast or 1)
end

-- Whether messages also go out in the old format (see the top of this file).
function Comm:SendsLegacy()
    local now = GetServerTime()
    if legacyUntil == nil then legacyUntil = now + self.STARTUP_LEGACY end
    return now < legacyUntil
end

-- Sends one message to the guild. options = { target = the member it is for, newOnly = true for
-- an action older copies do not know, so no old-format copy is sent }. Returns the new-format
-- message's size in bytes, or nil when nothing was sent (no guild, or an unknown area).
function Comm:Send(area, action, payload, options)
    local spec, guild = areas[area], guildID()
    if not (spec and guild) then return nil end
    local target = options and options.target
    local now = GetServerTime()
    local message = { v = PROTOCOL, g = guild, d = area, a = action, p = payload, ver = version(), to = target }
    if capsDue or not capsSentAt or now - capsSentAt >= self.CAPS_EVERY then
        message.c, capsSentAt, capsDue = self:Caps(), now, nil
    end
    local encoded = wire:EncodeForWoWAddonChannel(codec:Serialize(message))
    comm:SendCommMessage(PREFIX, encoded, "GUILD", nil, spec.priority)
    local legacy = spec.legacy and LEGACY[spec.legacy]
    if legacy and not (options and options.newOnly) and self:SendsLegacy() then
        -- The old fields in their old order, then PROTOCOL: older copies ignore the extra value,
        -- and newer ones read it as "this is a copy".
        local old
        if spec.legacy == "bounty" then
            old = codec:Serialize(guild, action, payload, version(), PROTOCOL)
        else
            old = codec:Serialize(guild, area, action, payload, target, version(), PROTOCOL)
        end
        comm:SendCommMessage(legacy.prefix, wire:EncodeForWoWAddonChannel(old), "GUILD", nil, spec.priority)
    end
    return #encoded
end

local function hear(sender, caps)
    local key = owner(sender)
    local peer = peers[key]
    if not peer then
        -- Someone this copy has not heard yet: it likely has not heard this copy either.
        peer = {}
        peers[key] = peer
        capsDue = true
    end
    peer.at = GetServerTime()
    if type(caps) == "table" then
        local clean = {}
        for area, n in pairs(caps) do
            if type(area) == "string" and type(n) == "number" then clean[area] = n end
        end
        peer.caps = clean
    end
end

-- Checks shared by both formats, then the area's handler.
local function dispatch(label, area, action, payload, sender, target, bytes, guild, theirs, caps)
    if guild ~= guildID() then
        logSync("drop", label, "from %s  ·  another guild", sender)
        return
    end
    hear(sender, caps)
    noteVersion(sender, theirs)
    local spec = areas[area]
    if not spec or type(action) ~= "string" then
        logSync("drop", label, "%s %s from %s  ·  unknown message", tostring(area), tostring(action), sender)
        return
    end
    if bytes > spec.maxBytes then
        logSync("drop", spec.label, "from %s  ·  %d bytes  ·  too large", sender, bytes)
        return
    end
    spec.handle(action, payload, sender, { target = target, bytes = bytes })
end

-- Own messages come back on the guild channel, and a sender must be a named player.
local function fromGuildmate(sender)
    local from = type(sender) == "string" and owner(sender)
    return from and from ~= owner()
end

local function decode(label, message, channel, sender, limit)
    if channel ~= "GUILD" or #message > limit then
        logSync("drop", label, "from %s on %s  ·  %d bytes  ·  not the guild channel or too large",
            sender, channel, #message)
        return nil
    end
    local raw = wire:DecodeForWoWAddonChannel(message)
    if not raw then
        logSync("drop", label, "from %s  ·  could not decode", sender)
        return nil
    end
    return raw
end

comm.RegisterComm(Comm, PREFIX, function(_, message, channel, sender)
    if not fromGuildmate(sender) then return end
    local raw = decode("Sync", message, channel, sender, MAX_BYTES)
    if not raw then return end
    local ok, m = codec:Deserialize(raw)
    if not ok or type(m) ~= "table" or type(m.v) ~= "number" or type(m.d) ~= "string" then
        logSync("drop", "Sync", "from %s  ·  could not read", sender)
        return
    end
    local spec = areas[m.d]
    local label = spec and spec.label or "Sync"
    if math.floor(m.v) > PROTOCOL then
        logSync("drop", label, "from %s  ·  newer message format (%d)", sender, math.floor(m.v))
        return
    end
    dispatch(label, m.d, m.a, m.p, sender, m.to, #message, m.g, m.ver, m.c)
end)

-- The old formats, from copies before this one. A message marked as a copy came from a newer
-- client, which sent the same message in the new format too.
local function legacyHandler(kind)
    local legacy = LEGACY[kind]
    local label = kind == "bounty" and "Bounty" or "Craft"
    return function(_, message, channel, sender)
        if not fromGuildmate(sender) then return end
        local raw = decode(label, message, channel, sender, legacy.maxBytes)
        if not raw then return end
        local ok, guild, area, action, payload, target, theirs, marker
        if kind == "bounty" then
            area = "bounty"
            ok, guild, action, payload, theirs, marker = codec:Deserialize(raw)
        else
            ok, guild, area, action, payload, target, theirs, marker = codec:Deserialize(raw)
        end
        if not ok or not guild then
            logSync("drop", label, "from %s  ·  could not read", sender)
            return
        end
        if type(marker) == "number" and marker >= PROTOCOL then return end
        legacyUntil = math.max(legacyUntil or 0, GetServerTime() + Comm.LEGACY_FOR)
        dispatch(label, area, action, payload, sender, target, #message, guild, theirs)
    end
end

for kind, legacy in pairs(LEGACY) do
    comm.RegisterComm(Comm, legacy.prefix, legacyHandler(kind))
end
