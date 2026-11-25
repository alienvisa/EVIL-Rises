----------------------------------------------------------------------
-- EVIL Rises - Configuration
-- Single source of truth for all addon-wide constants.
-- This file is loaded first (before Core.lua) so every module can
-- safely reference EVRFeatures.* constants from the start.
----------------------------------------------------------------------

-- Create the primary namespace. Using "or {}" is idempotent — safe to
-- call even if a future loader has already created the table.
--
_G.EVRFeatures = _G.EVRFeatures or {}

-- ── Product identity ─────────────────────────────────────────────
EVRFeatures.ADDON_NAME        = "EVIL Rises"
EVRFeatures.NAMESPACE         = "EVRFeatures"

-- ── Version ───────────────────────────────────────────────────────
EVRFeatures.VERSION           = "1.40.0"  -- kept in sync with EVRFeatures.toc by the release workflow
EVRFeatures.COMM_VERSION      = 1

-- ── SavedVariables ────────────────────────────────────────────────
EVRFeatures.DB_GLOBAL         = "EVRFeaturesDB"

-- ── Communication prefixes ────────────────────────────────────────
EVRFeatures.PREFIX            = "EVRF"

-- ── Slash commands ────────────────────────────────────────────────
EVRFeatures.SLASH_PRIMARY     = "/eviltools"
