-- Run the guild communication regressions in separate Lua states.
-- The release workflow invokes this file with Lua 5.1 on Ubuntu.
for _, test in ipairs({"AreaRepair", "Bounties", "Crafting", "CraftingPage", "DebugLog", "MemberGear", "NativeBountyTab", "OrderRepair", "SelfModel", "SyncFormats", "VersionReminder"}) do
    assert(os.execute("lua5.1 tests/" .. test .. ".lua") == 0, test .. " failed")
end
