----------------------------------------------------------------------
-- EVIL Rises - Slash Commands
-- /eviltools and /eviltools dispatch table.
----------------------------------------------------------------------

-- Primary slash command: /eviltools and /eviltools
SLASH_EVRF1 = "/eviltools"



local L = EVRFeatures.L

----------------------------------------------------------------------
-- /eviltools help listing
--
-- Lives in helpers so the command branch stays a single call. Colour
-- escapes are built here and never stored inside an L[] key, so a
-- translation can never break "|cff......" / "|r".
----------------------------------------------------------------------
local HELP_HEADER_COLOR = "|cff00CCFF"   -- section headers
local HELP_CMD_COLOR    = "|cffFFD700"   -- command verbs (addon gold)

local function helpHeader(text)
    EVRFeatures:Print(HELP_HEADER_COLOR .. text .. "|r")
end

local function helpLine(verb, desc)
    EVRFeatures:Print("  " .. HELP_CMD_COLOR .. verb .. "|r  " .. desc)
end

local function printHelp()
    EVRFeatures:Print(HELP_CMD_COLOR .. L["EVIL Rises commands (/eviltools or /eviltools):"] .. "|r")

    helpHeader(L["General"])
    helpLine("/eviltools",             L["Open EVIL Rises"])
    helpLine("/eviltools open <feature>", L["Open a tab (roster, raids, loot, guild...)"])
    helpLine("/eviltools find <text>", L["Search members by name, class, level or note"])
    helpLine("/eviltools analytics",   L["Guild analytics and activity stats"])
    helpLine("/eviltools map",         L["Open the live guild map"])
    helpLine("/eviltools style [name]", L["List the interface styles, or switch to one"])
    helpLine("/eviltools pug",         L["Check who you're grouped with"])
    helpLine("/eviltools calendar",    L["Guild calendar and events"])
    helpLine("/eviltools polls",       L["Guild polls"])
    helpLine("/eviltools bulletin",    L["Guild bulletin board"])
    helpLine("/eviltools bank [sort [all] | stop | sync | need]", L["Guild bank: open, organize the tab, ask for it, what it needs"])
    helpLine("/eviltools cta [type] [message]", L["Call to Arms: rally the guild (officers)"])
    helpLine("/eviltools ally",        L["Alliance status and allied guilds"])

    helpHeader(L["Raid and loot"])
    if EVRFeatures.LootMaster then helpLine("/eviltools lm", L["Master Loot helper status"]) end  -- not on retail (ADR-0026)
    if EVRFeatures.Points then helpLine("/eviltools points", L["Points and DKP window"]) end
    if EVRFeatures.TradeCouncil then   -- retail's loot council by trade (issue #185)
        helpLine("/eviltools offer [item]", L["Offer a tradeable item to the raid, or open the loot council"])
    end
    if EVRFeatures.ConsumableChecker then  -- Anniversary and retail, not Forever (ADR-0014, issue #187)
        helpLine("/eviltools cons",      L["Check raid consumables"])
    end
    helpLine("/eviltools specs",         L["Scan group talent specs"])
    helpLine("/eviltools export <what>", EVRFeatures.LootTracker and L["Export roster, attendance or loot"]
        or L["Export roster or attendance"])   -- the loot history is on retail too since issue #183
    if EVRFeatures.Companion then helpLine("/eviltools web [on|off]", L["Copy your guild into the web companion"]) end
    if EVRFeatures.CompanionImport then helpLine("/eviltools roster", L["Bring the raid roster in from the website"]) end
    if EVRFeatures.RaidStart then   -- issue #400: the Iniciar raide button's next step
        helpLine("/eviltools raid start", L["Start the website's raid: invite and arrange, one step a click"])
    end

    helpHeader(L["Personal"])
    helpLine("/eviltools avail",         L["List yourself as available for a group"])
    helpLine("/eviltools signup <core>", L["Sign up for a raid core"])
    helpLine("/eviltools rules",         L["The guild's rules"])
    helpLine("/eviltools mentions",      L["Name mention alerts"])
    helpLine("/eviltools myalts",        L["Detect and link your own alts"])
    helpLine("/eviltools birthday <DD/MM | off>", L["Share your birthday with the guild (day and month only)"])
    if EVRFeatures.AttunementTracker then  -- TBC content (ADR-0014)
        helpLine("/eviltools attune",    L["Your attunement progress"])
    end
    helpLine("/eviltools craft <item>",  L["Who can craft an item"])
    helpLine("/eviltools order <item>",  L["Ask the guild's crafters to make an item"])

    helpHeader(L["Diagnostics"])
    helpLine("/eviltools selftest", L["Run the built-in self test"])
    helpLine("/eviltools errors",   L["Show recent errors"])
    helpLine("/eviltools perf [reset]", L["Where EVIL Rises spends its time since login, or zero the counters"])
    helpLine("/eviltools probe",    L["Record this client's facts for support"])
    helpLine("/eviltools probe chat", L["Post two test lines in guild chat to see whether an addon may post on its own"])
    helpLine("/eviltools probe channel", L["Join a temporary channel to see whether an addon message may go through one"])
    helpLine("/eviltools style preview", L["Show the Forever style's pieces side by side"])
    helpLine("/eviltools debug",    L["Toggle debug output"])

    -- These verbs are refused inside their own modules for non-officers, so
    -- showing them to a member would only advertise commands that do nothing.
    if EVRFeatures:IsOfficer() then
        helpHeader(L["Officers"])
        helpLine("/eviltools ban <name>",            L["Ban a player from invites"])
        helpLine("/eviltools tempban <name> <days>", L["Ban a player for a number of days"])
        helpLine("/eviltools unban <name>",          L["Lift a ban"])
        helpLine("/eviltools banlist",               L["Open the ban list"])
        if EVRFeatures.BulkActions then
            helpLine("/eviltools bulk [next | skip | stop]", L["Promote, demote or remove by rules, one member per click"])
            helpLine("/eviltools altgroup <promote | demote> <name> [rank]",
                L["Promote or demote a member's alts to their main's rank, or to a rank, one per click"])
        end
        helpLine("/eviltools altlimit <number>",     L["List the alt groups with more alts than that"])
        helpLine("/eviltools birthday <name> <DD/MM | off>", L["Correct or remove a member's birthday"])
        if EVRFeatures.NoteDates then
            helpLine("/eviltools joindate [<name> | all | import]", L["Write a member's join date into their note, or read the dates already in the notes"])
            helpLine("/eviltools safe [<name>]",     L["The safe list: never in a bulk removal or demotion"])
            helpLine("/eviltools nick <name> [nickname]", L["The officers' nickname for a member"])
        end
        helpLine("/eviltools record <name>",         L["A member's disciplinary record"])
        helpLine("/eviltools warn <name> [reason]",  L["Warn a member, with one click"])
        helpLine("/eviltools record term <days>",    L["How long a warning counts"])
        helpLine("/eviltools autoinvite",            L["Auto-invite settings"])
        helpLine("/eviltools note <name> <text>",    L["Add an officer note"])
        if EVRFeatures.Wishlist then helpLine("/eviltools wish", L["Open the loot wishlist"]) end
        helpLine("/eviltools scout",                 L["Scan for unguilded recruits"])
        helpLine("/eviltools ally create <tag> <name>", L["Found an alliance with other guilds"])
        helpLine("/eviltools ally invite <officer>",    L["Invite a guild into the alliance"])
        helpLine("/eviltools ally leave",               L["Leave the alliance"])
    end
end

----------------------------------------------------------------------
-- What a command and a button share (#142): every /eviltools command has a way in
-- from the interface too, and both call the one function here, so the button
-- does exactly what the command does.
----------------------------------------------------------------------
function EVRFeatures:CollectMyDataNow()
    if not EVRFeatures.DataCollector then return end
    EVRFeatures.DataCollector:CollectMyData()
    EVRFeatures:Print(L["Data collected."])
end

function EVRFeatures:MergeRaidSessions()
    if not EVRFeatures.RaidTracker then return end
    EVRFeatures:Print(L["Merging duplicate raid sessions\226\128\166"])
    if EVRFeatures.RaidTracker:MergeDuplicateSessions() == 0 then
        EVRFeatures:Print(L["|cffAAAAAA[EVIL Rises] No duplicates found.|r"])
    end
end

-- Start-up problems first: the ring below is capped and shared with runtime
-- errors, so it can already have lost them.
function EVRFeatures:ShowErrors()
    local startup = EVRFeatures:ListStartupProblems()
    local shown = {}
    if #startup > 0 then
        EVRFeatures:Print(string.format(L["%d start-up problem(s):"], #startup))
        for _, line in ipairs(startup) do
            shown[line] = true
            EVRFeatures:Print("|cffFF8800" .. line .. "|r")
        end
    end
    -- The ring also holds the start-up problems just listed; skip those.
    local ring, rest = (EVRFeatures.State and EVRFeatures.State.errors) or {}, {}
    for _, e in ipairs(ring) do
        if not shown[e.msg] then rest[#rest + 1] = e end
    end
    if #rest == 0 then
        if #startup == 0 then EVRFeatures:Print(L["No errors recorded this session."]) end
    else
        EVRFeatures:Print(string.format(L["%d recent error(s):"], #rest))
        for i = math.max(1, #rest - 9), #rest do
            EVRFeatures:Print("|cffFF4444" .. (rest[i].msg or "?") .. "|r")
        end
    end
end

-- Whether this client is the Master Looter, as one line.
function EVRFeatures:LootMasterStatus()
    if not EVRFeatures.LootMaster then return nil end
    return EVRFeatures.LootMaster:IsMasterLooter() and L["Loot Master mode active. Open loot to start."]
        or L["You are not the Master Looter."]
end

-- The string to paste into the web companion, in a popup; or why there is none.

-- Every EVIL Rises record of this guild, gone, and the interface reloaded.
function EVRFeatures:EraseGuildData()
    if EVRFeatures.guildKey and EVRFeaturesDB then EVRFeaturesDB[EVRFeatures.guildKey] = nil end
    ReloadUI()
end

-- The verbs of what retail does not have (ADR-0026): no Master Loot, and no soft reserves (softres.it
-- runs Classic raids only). Each module is absent, so its verb says so rather than doing nothing or
-- raising. The site's verbs (web, companion, roster) are retail's too since issue #182, equity since
-- issue #183, and points, dkp and wish since issue #185.
local RETAIL_ABSENT = { "^lm$", "^lm%s", "^lootmaster$", "^softres" }

local function absentHere(msg)
    if not EVRFeatures.Client.isRetail then return false end
    for _, pat in ipairs(RETAIL_ABSENT) do
        if msg:match(pat) then return true end
    end
    return false
end

local function handleCommand(msg)
    msg = strtrim(msg or "")
    if absentHere(msg) then
        EVRFeatures:Print(L["Not available on this client."])
        return
    end
    -- Deliberately the first branch: "help", "?" and "commands" are exact
    -- literals, so this can never swallow another verb, and sitting at the top
    -- means no present or future prefix pattern below can ever swallow them.
    if msg == "help" or msg == "?" or msg == "commands" then
        printHelp()
    elseif msg == "scan" then
        EVRFeatures:CollectMyDataNow()
    elseif msg == "selftest" then
        if EVRFeatures.SelfTest then EVRFeatures.SelfTest:Run() end
    elseif msg == "myalts" then
        if EVRFeatures.AltAutoDetect then EVRFeatures.AltAutoDetect:PromptNow() end
    elseif msg == "perf" then
        EVRFeatures.Perf:Print()
    elseif msg == "perf reset" then
        EVRFeatures.Perf:Reset()
        EVRFeatures:Print(L["Performance counters zeroed."])
    elseif msg == "points" or msg == "dkp" then
        if EVRFeatures.ShowPointsFrame then
            EVRFeatures:ShowPointsFrame()
        end
    elseif msg == "equity" or msg == "lootequity" then
        if EVRFeatures.LootEquity then
            EVRFeatures.LootEquity:PrintSummary(15)
        end
    elseif msg == "digest" then
        if EVRFeatures.Digest then
            EVRFeatures.Digest:Show()
        end
    elseif msg == "backup" then
        if EVRFeatures.Backup then EVRFeatures.Backup:ShowExport() end
    elseif msg == "restore" then
        if EVRFeatures.Backup then EVRFeatures.Backup:ShowRestore() end
    elseif msg == "bank" or msg:match("^bank%s") then
        -- /eviltools bank [sort [all] | stop | sync | need]: the guild bank (issue #380)
        if EVRFeatures.GuildBank then
            local a = {}
            for w in msg:gmatch("%S+") do a[#a + 1] = w end
            table.remove(a, 1)
            EVRFeatures.GuildBank:HandleCommand(a)
        end
    elseif msg == "rules" then
        -- /eviltools rules: the guild's rules, for any member (#407).
        if EVRFeatures.GuildRules then EVRFeatures.GuildRules:Show() end
    elseif msg == "bulletin" or msg == "board" then
        if EVRFeatures.Bulletin then EVRFeatures.Bulletin:Show() end
    elseif msg == "cta" or msg:match("^cta%s") then
        -- /eviltools cta: the panel. /eviltools cta <type> [message]: send it (issue #108).
        local rest = strtrim((msg:gsub("^cta%s*", "")))
        local kind = rest:match("^(%S+)")
        local CTA = EVRFeatures.CallToArms
        if not kind then
            EVRFeatures.UI:OpenWindow("guild", "cta")
        elseif CTA and CTA:Template(kind:lower()) then
            CTA:Send(kind:lower(), rest:match("^%S+%s+(.+)$"))
        else
            EVRFeatures:Print(L["Usage: /eviltools cta [worldboss|pvp|defend|event|rally] [message]"])
        end
    elseif msg == "ally" or msg:match("^ally%s") or msg == "alliance" or msg:match("^alliance%s") then
        -- Cross-guild federation. Officer-only verbs refuse inside the module,
        -- so this stays a thin router.
        if EVRFeatures.Alliance then
            EVRFeatures.Alliance:HandleCommand(msg:match("^%a+%s+(.*)$") or "")
        end
    elseif msg == "analytics" or msg == "stats" then
        if EVRFeatures.GuildAnalytics then EVRFeatures.GuildAnalytics:Show() end
    elseif msg == "polls" or msg == "poll" then
        if EVRFeatures.Polls then EVRFeatures.Polls:Show() end
    elseif msg == "calendar" or msg == "cal" or msg == "events" then
        if EVRFeatures.ShowCalendar then EVRFeatures:ShowCalendar() end
    elseif msg == "search" or msg:match("^find") then
        if EVRFeatures.Search then
            local q = strtrim((msg:gsub("^find%s*", "")))
            EVRFeatures.Search:Show(q ~= "search" and q or "")
        end
    elseif msg:match("^order") and EVRFeatures.ShowCraftOrderDialog then
        -- /eviltools order [item link or id] — a craft order (issue #389); no item opens the Orders tab.
        local arg = strtrim((msg:gsub("^order%s*", "")))
        local itemId = tonumber(arg:match("item:(%d+)")) or tonumber(arg:match("^(%d+)$"))
        if itemId then
            EVRFeatures:ShowCraftFor(itemId)
        else
            EVRFeatures.UI:OpenWindow("recipes", "mine")
        end
    elseif msg:match("^craft") then
        -- /eviltools craft <item link or id> — who can craft this, guild + realm.
        local arg = strtrim((msg:gsub("^craft%s*", "")))
        local itemId = tonumber(arg:match("item:(%d+)")) or tonumber(arg:match("^(%d+)$"))
        if not itemId then
            -- No item given: open the Craft Finder popup instead.
            if EVRFeatures.ShowCraftFinder then
                EVRFeatures:ShowCraftFinder()
            else
                EVRFeatures:Print(L["Usage: /eviltools craft [item link or id]"])
            end
        else
            local itemName = EVRFeatures.Compat.GetItemInfo(itemId) or ("item:" .. itemId)
            local seen = {}
            -- Guild crafters are already known locally (RecipeTracker sync).
            local guild = EVRFeatures.RecipeTracker and EVRFeatures.RecipeTracker:GetCraftersForItem(itemId)
            if guild and #guild > 0 then
                local names = {}
                for _, c in ipairs(guild) do
                    if not seen[c.playerName] then
                        seen[c.playerName] = true
                        names[#names + 1] = c.playerName
                    end
                end
                EVRFeatures:Print(string.format(L["Crafters for %s in guild: %s"], itemName, table.concat(names, ", ")))
            else
                EVRFeatures:Print(string.format(L["No guild crafter for %s - asking the realm..."], itemName))
            end
            -- Alliance: straight from the synced directory, offline crafters included.
            if EVRFeatures.Alliance and EVRFeatures.Alliance:Get() then
                for _, c in ipairs(EVRFeatures.Alliance:FindCrafters(itemId)) do
                    if not seen[c.name] then
                        seen[c.name] = true
                        EVRFeatures:Print("   " .. string.format(L["%s of %s can craft %s (%s)"],
                            c.name, c.guild, itemName, L[c.prof or "?"])
                            .. (c.online and "" or " " .. L["(offline)"]))
                    end
                end
            end
            -- Realm-wide: answers trickle in over the mesh (out-of-guild reach).
            if EVRFeatures.CraftNet then
                EVRFeatures.CraftNet:Query(itemId, function(short, label)
                    if seen[short] then return end
                    seen[short] = true
                    EVRFeatures:Print("   " .. string.format(L["%s can craft %s (%s)"], short, itemName, L[label or "?"]))
                end)
            end
        end
    elseif msg == "scout" or msg == "recruitscan" then
        -- Officer: /who-scan unguilded candidates, mass-whisper a template.
        if EVRFeatures.RecruitScanner then EVRFeatures.RecruitScanner:Show() end
    elseif msg == "beacon" or msg == "recruitbeacon" then
        -- Officer: compose/toggle the guild recruitment beacon.
        if EVRFeatures.ShowRecruitBeacon then EVRFeatures:ShowRecruitBeacon() end
    elseif msg == "lfg" or msg == "recruiting" then
        -- Anyone: browse guilds recruiting nearby. With no guild, on Forever and retail, that is the
        -- guild finder; otherwise the inbox of what was heard over the mesh.
        if IsInGuild() then
            if EVRFeatures.ShowRecruitInbox then EVRFeatures:ShowRecruitInbox() end
        else
            EVRFeatures:OpenGuildFinder()
        end
    elseif msg == "map" or msg == "guildmap" then
        -- Anyone: open the live guild map (world map pins + list overlay).
        if EVRFeatures.ToggleGuildMap then EVRFeatures:ToggleGuildMap() end
    elseif msg == "pug" then
        -- Anyone: classify the current party/raid against what EVRFeatures knows.
        if EVRFeatures.TogglePugInspector then EVRFeatures:TogglePugInspector() end
    elseif msg == "debug" then
        EVRFeatures.Logger.debug = not EVRFeatures.Logger.debug
        EVRFeatures:Print(EVRFeatures.Logger.debug and L["Debug mode ON."] or L["Debug mode OFF."])
    elseif msg == "resscan" then
        -- Diagnostic: run the resistance scan (equipped + bags) and print the max
        -- wearable per school, so the tooltip-based read can be verified in-game.
        local r = EVRFeatures.Resistances and EVRFeatures.DataCollector and EVRFeatures.DataCollector:CollectResistances()
        if not EVRFeatures.Resistances then
            EVRFeatures:Print(L["Not available on this client."])   -- no resistance gear on retail (#184)
        elseif r then
            EVRFeatures:Print(string.format(
                "Resistances (max wearable) - Shadow %d | Nature %d | Frost %d | Fire %d | Arcane %d",
                r.shadow or 0, r.nature or 0, r.frost or 0, r.fire or 0, r.arcane or 0))
        else
            EVRFeatures:Print("Resistance scan unavailable.")
        end
    elseif msg == "errors" then
        EVRFeatures:ShowErrors()
    elseif msg == "probe" then
        -- Client facts for the WoW: Forever beta, into EVRFeaturesDB.probe (ADR-0015).
        if EVRFeatures.Probe then EVRFeatures.Probe:Run() end
    elseif msg == "probe chat" then
        -- Whether chat from a timer gets through, measured (issue #75).
        if EVRFeatures.Probe then EVRFeatures.Probe:RunChat() end
    elseif msg == "probe channel" then
        -- Whether an addon message may go through a created channel, measured (specs/071-o-recrutamento).
        if EVRFeatures.Probe then EVRFeatures.Probe:RunChannel() end
    elseif msg == "reset" then
        EVRFeatures:EraseGuildData()
    elseif msg:match("^recruit") then
        local rest = msg:gsub("^recruit%s*", "")
        local args = {}
        for word in rest:gmatch("%S+") do
            table.insert(args, word)
        end
        if EVRFeatures.Recruitment then
            EVRFeatures.Recruitment:HandleCommand(args)
        end
    elseif msg == "consumables" or msg == "cons" then
        if EVRFeatures.ConsumableChecker then
            local results = EVRFeatures.ConsumableChecker:CheckRaid()
            if results then
                local missing = EVRFeatures.ConsumableChecker:GetMissingCount(results)
                EVRFeatures:Print(string.format(L["Consumable check done. %d players missing buffs."], missing))
                -- Retail: what the client could not read is said apart, never counted as missing (#187).
                local unknown = EVRFeatures.ConsumableChecker:GetUnknownCount(results)
                if unknown > 0 then
                    EVRFeatures:Print(string.format(L["%d could not be read (out of range, or hidden by the game)."], unknown))
                end
            end
        else
            EVRFeatures:Print(L["Not available on this client."])
        end
    elseif msg == "consreport" then
        if EVRFeatures.ConsumableChecker then
            EVRFeatures.ConsumableChecker:ReportToChat("RAID")
        else
            EVRFeatures:Print(L["Not available on this client."])
        end
    elseif msg:match("^trial") then
        -- The roster's key, so a guildmate on a connected realm is found as the roster menu finds
        -- them: the whole rest when it is somebody (two words on Forever), else the first word, as
        -- it always was (issue #177).
        local rest = strtrim((msg:gsub("^trial%s*", "")))
        local key = EVRFeatures:RosterKey(rest)
        local name = rest:match("^(%S+)")
        if not key and name then key = EVRFeatures:RosterKey(name) or EVRFeatures:GetPlayerKey(name) end
        if key and EVRFeatures.TrialTracker then
            EVRFeatures.TrialTracker:AddTrial(key)
        else
            EVRFeatures:Print(L["Usage: /eviltools trial <PlayerName>"])
        end
    elseif msg == "note" or msg:match("^note%s") then
        local rest = msg:gsub("^note%s*", "")
        -- A Forever name is two words, and the note lands on the key the roster gives (issue #49).
        local target, noteText = EVRFeatures:SplitNameAndText(rest)
        if target and noteText and EVRFeatures.OfficerNotes then
            local key = EVRFeatures:RosterKey(target)
            -- Somebody off the roster still gets the note (the PUG inspector reads them), but
            -- the officer is told: "Lethaniel" on Forever is nobody's sheet.
            if EVRFeatures.OfficerNotes:AddNote(key or EVRFeatures:GetPlayerKey(target), noteText) then
                EVRFeatures:Print(key and (L["Note added for "] .. target)
                    or string.format(L["Note added for %s, who matches no single guild member: check the full name."], target))
            end
        else
            EVRFeatures:Print(L["Usage: /eviltools note <PlayerName> <text>"])
        end
    elseif msg == "offer" or msg:match("^offer%s") then
        -- /eviltools offer [item link]: retail's loot council by trade (issue #185); the link keeps its case.
        local link = strtrim((msg:gsub("^offer%s*", "")))
        if not EVRFeatures.TradeCouncil then
            EVRFeatures:Print(L["Not available on this client."])
        elseif link == "" then
            EVRFeatures:ShowTradeCouncil()
        else
            EVRFeatures.TradeCouncil:Offer(link)
        end
    elseif msg == "lm undo" then
        -- /eviltools lm undo - take the last award back (issue #294), as the Master Loot window's button
        if EVRFeatures.LootMaster then
            local award, why = EVRFeatures.LootMaster:UndoLastAward()
            EVRFeatures:Print(award and string.format(L["|cffFFD700Undone:|r %s"], award.link) or why)
        end
    elseif msg == "lm" or msg == "lootmaster" then
        local status = EVRFeatures:LootMasterStatus()
        if status then EVRFeatures:Print(status) end
    elseif msg:match("^lm announce") then
        -- /eviltools lm announce - manually announce item from target tooltip
        EVRFeatures:Print(L["Open loot window as Master Looter to announce items."])
    elseif msg == "exportatt" or msg == "exportattendance" then
        if EVRFeatures.RaidTracker then
            local json, err = EVRFeatures.RaidTracker:ExportForTMB()
            if json then
                EVRFeatures:ShowExportPopup(L["Attendance Export"], json)
            else
                EVRFeatures:Print(L["|cffFF4444Export failed:|r "] .. (err or L["unknown error"]))
            end
        end
    elseif msg:match("^export") then
        -- /eviltools export <roster|attendance|loot|readiness|standings|equity> [csv|tsv|discord]
        local rest = strtrim((msg:gsub("^export%s*", "")))
        local dataset, fmt = rest:match("^(%S*)%s*(%S*)$")
        dataset = (dataset and dataset ~= "") and dataset or "roster"
        fmt = (fmt and fmt ~= "") and fmt or "csv"
        local text, title = nil, nil
        if EVRFeatures.Exporter then
            text, title = EVRFeatures.Exporter:Build(dataset, fmt)
        end
        if text then
            EVRFeatures:ShowExportPopup(string.format("%s (%s)", title or L["Export"], fmt), text)
        elseif title == "absent" then
            EVRFeatures:Print(L["Not available on this client."])
        elseif title == "officer" then
            EVRFeatures:Print(L["|cffFF4444Officers only.|r"])
        elseif EVRFeatures.Exporter then
            EVRFeatures:Print(string.format(L["Usage: /eviltools export <%s> [csv|tsv|discord]"], EVRFeatures.Exporter:Names()))
        end
    elseif msg:match("^wish") then
        if not EVRFeatures:IsOfficer() then
            EVRFeatures:Print(L["|cffFF4444Wishlist is currently available to officers only.|r"])
            return
        end
        local rest = strtrim((msg:gsub("^wish%s*", "")))
        if rest == "" or rest == "list" then
            -- Show wishlist frame
            EVRFeatures:ShowWishlistFrame()
        elseif rest:match("^remove%s+") then
            local link = rest:match("^remove%s+(.+)$")
            local itemId = link and tonumber(link:match("item:(%d+)"))
            if itemId and EVRFeatures.Wishlist then
                EVRFeatures.Wishlist:RemoveFromWishlist(itemId)
            else
                EVRFeatures:Print(L["Usage: /eviltools wish remove [itemlink]"])
            end
        else
            -- Treat remainder as an item link to add
            local itemId = tonumber(rest:match("item:(%d+)"))
            if itemId and EVRFeatures.Wishlist then
                EVRFeatures.Wishlist:AddToWishlist(itemId, rest, false)
            else
                EVRFeatures:Print(L["Usage: /eviltools wish [itemlink] | /eviltools wish remove [itemlink]"])
            end
        end
    elseif msg == "mergeraids" then
        EVRFeatures:MergeRaidSessions()
    elseif msg == "specs" then
        if EVRFeatures.SpecChecker then
            EVRFeatures.SpecChecker:ScanGroup()
        end
    elseif msg == "attune" or msg == "attunements" then
        -- Print attunement status for the logged-in character to chat.
        if EVRFeatures.AttunementTracker then
            local atts = EVRFeatures.AttunementTracker:ScanAttunements()
            EVRFeatures:Print(L["|cffFFD700Attunements:|r"])
            for _, att in ipairs(atts) do
                if not att.alwaysComplete then
                    local status
                    if att.complete then
                        status = L["|cff00FF00Done|r"]
                    elseif att.progress and att.progress > 0 then
                        status = format("|cffFFD700%d%%|r", math.floor(att.progress * 100))
                    else
                        status = L["|cffFF4444Not started|r"]
                    end
                    EVRFeatures:Print(format("  [%s] %s \226\128\148 %s", att.tier, att.name, status))
                end
            end
        else
            EVRFeatures:Print(L["Not available on this client."])
        end
    elseif msg == "attune debug" or msg == "attunements debug" then
        -- Debug mode: prints per-quest IsQuestFlaggedCompleted results.
        if EVRFeatures.AttunementTracker then
            EVRFeatures:Print("|cffFFD700Attunement debug (per quest):|r")
            for _, attDef in ipairs(EVRFeatures.AttunementTracker.ATTUNEMENTS) do
                if not attDef.alwaysComplete and attDef.finalQuestId then
                    EVRFeatures:Print(format("|cffAAAAAA--- %s (final=%d) ---|r", attDef.name, attDef.finalQuestId))
                    for _, q in ipairs(attDef.quests) do
                        if q.ids then
                            local anyDone = false
                            for _, qid in ipairs(q.ids) do
                                if EVRFeatures.AttunementTracker:IsQuestComplete(qid) then anyDone = true end
                            end
                            local col = anyDone and "|cff00FF00" or "|cffFF4444"
                            local ids = table.concat(q.ids, "/")
                            EVRFeatures:Print(format("  %s[%s] %s (Aldor|Scryers)|r", col, ids, q.name))
                        else
                            local done = EVRFeatures.AttunementTracker:IsQuestComplete(q.id)
                            local col = done and "|cff00FF00" or "|cffFF4444"
                            EVRFeatures:Print(format("  %s[%d] %s|r", col, q.id, q.name))
                        end
                    end
                    if attDef.keyItemId then
                        local count = EVRFeatures.Compat.GetItemCount(attDef.keyItemId) or 0
                        local col = count > 0 and "|cff00FF00" or "|cffFF4444"
                        EVRFeatures:Print(format("  %sKey item %d: %d in bags|r", col, attDef.keyItemId, count))
                    end
                end
            end
        else
            EVRFeatures:Print(L["Not available on this client."])
        end
    elseif msg == "attune dumpquests" and not EVRFeatures.AttunementTracker then
        EVRFeatures:Print(L["Not available on this client."])   -- TBC's attunement quests (issue #184)
    elseif msg == "attune dumpquests" then
        -- Dumps all completed quest IDs in the TBC attunement range.
        -- Covers T4/T5/T6 + some headroom for anniversary-specific hidden flags.
        EVRFeatures:Print("|cffFFD700Completed quests in range 9800-11500:|r")
        local found = 0
        for qid = 9800, 11500 do
            -- Compat, not the tracker: the tracker does not exist outside TBC Anniversary.
            if EVRFeatures.Compat.IsQuestComplete(qid) then
                -- Try to get the quest title (may be nil for hidden server-side quests)
                local title = nil
                if C_QuestLog and C_QuestLog.GetTitleForQuestID then
                    title = C_QuestLog.GetTitleForQuestID(qid)
                end
                if title and title ~= "" then
                    EVRFeatures:Print(format("  |cff00FF00[%d]|r %s", qid, title))
                else
                    EVRFeatures:Print(format("  |cff00FF00[%d]|r |cffAAAAAA(no title \226\128\148 hidden/anniversary quest)|r", qid))
                end
                found = found + 1
            end
        end
        if found == 0 then
            EVRFeatures:Print("|cffFF4444No completed quests found in that range.|r")
        else
            EVRFeatures:Print(format("|cffAAAAAA%d quests found. Run on main to compare IDs.|r", found))
        end
    elseif msg:match("^signup") then
        -- /eviltools signup <CoreName> [tank|healer|melee|ranged] [note]
        local rest     = strtrim((msg:gsub("^signup%s*", "")))
        local coreName = rest:match("^(%S+)")
        local note     = rest:match("^%S+%s+(.+)$") or ""
        -- A role word right after the core is the role (issue #94); one the class cannot play
        -- falls back to the class's own in BroadcastSignup.
        local word = note:match("^(%S+)")
        local role = word and EVRFeatures.CoreManager and EVRFeatures.CoreManager.ROLE_WORDS[word:lower()]
        if role then note = note:match("^%S+%s+(.+)$") or "" end
        if (not coreName or coreName == "") and EVRFeatures.ShowCoreSignupFrame then
            -- The window, as the Raids tab's button opens it: the way in at any width, and with the
            -- Raids tab switched off (#377).
            EVRFeatures:ShowCoreSignupFrame()
        elseif not coreName or coreName == "" then
            EVRFeatures:Print(L["Usage: /eviltools signup <CoreName> [tank|healer|melee|ranged] [note]"])
        elseif not EVRFeatures.CoreManager then
            EVRFeatures:Print(L["Core Manager not loaded."])
        elseif not EVRFeatures.CoreManager:Exists(coreName) then
            EVRFeatures:Print(string.format(L["Core \"%s\" not found."], coreName))
        else
            EVRFeatures.CoreManager:BroadcastSignup(coreName, note, role)
            EVRFeatures:Print(string.format(L["Sign-up sent for core: %s"], coreName))
        end
    elseif msg:match("^unsignup") then
        -- /eviltools unsignup <CoreName>  — withdraw your own application
        local coreName = strtrim((msg:gsub("^unsignup%s*", "")))
        if coreName == "" then
            EVRFeatures:Print(L["Usage: /eviltools unsignup <CoreName>"])
        elseif EVRFeatures.CoreManager then
            local playerKey = EVRFeatures:GetPlayerKey(EVRFeatures.Compat.PlayerName(), GetRealmName())
            EVRFeatures.CoreManager:DeclineSignup(playerKey, coreName)
            EVRFeatures:Print(string.format(L["Sign-up withdrawn from core: %s"], coreName))
        end
    elseif msg:match("^tempban%s") then
        -- /eviltools tempban <name> <days> [reason]  — officer-gated inside BanList:Add.
        local rest = strtrim((msg:gsub("^tempban%s+", "")))
        local name, days, reason = rest:match("^(%S+)%s+(%d+)%s*(.*)$")
        local numDays = days and tonumber(days)
        if name and numDays and numDays > 0 then
            if EVRFeatures.BanList and EVRFeatures.BanList:Add(name, reason, numDays * 86400) then
                EVRFeatures:Print(L["Temp-banned "] .. name .. " (" .. days .. L[" days)"])
            end
        else
            EVRFeatures:Print(L["Usage: /eviltools tempban <name> <days> [reason]"])
        end
    elseif msg:match("^ban%s") then
        -- /eviltools ban <name> [reason]  — officer-gated inside BanList:Add.
        local rest = strtrim((msg:gsub("^ban%s+", "")))
        local name, reason = rest:match("^(%S+)%s*(.*)$")
        if name then
            if EVRFeatures.BanList and EVRFeatures.BanList:Add(name, reason) then
                EVRFeatures:Print(L["Banned "] .. name)
            end
        else
            EVRFeatures:Print(L["Usage: /eviltools ban <name> [reason]"])
        end
    elseif msg:match("^unban%s") then
        -- /eviltools unban <name>  — officer-gated inside BanList:Remove.
        local name = strtrim((msg:gsub("^unban%s+", "")))
        if name ~= "" and EVRFeatures.BanList and EVRFeatures.BanList:Remove(name) then
            EVRFeatures:Print(L["Unbanned "] .. name)
        elseif name ~= "" and EVRFeatures.BanList and EVRFeatures:IsOfficer() then
            EVRFeatures:Print(string.format(L["No ban to lift for %s."], name))   -- nothing stood there (#184)
        end
    elseif msg:match("^warn%s") then
        -- /eviltools warn <name> [reason]  — the Warn window (#403), officers only.
        local name, rest = EVRFeatures:SplitNameAndText(strtrim((msg:gsub("^warn%s+", ""))))
        name = name or strtrim((msg:gsub("^warn%s+", "")))
        local key = EVRFeatures:RosterKey(name)
        if not EVRFeatures:IsOfficer() then
            EVRFeatures:Print(L["|cffFF4444Officers only.|r"])
        elseif not key then
            EVRFeatures:Print(string.format(L["%s is not on the guild roster."], name))
        else
            local _, shown = EVRFeatures:RosterKey(name)
            EVRFeatures:ShowWarnDialog(key, shown, { reason = rest and strtrim(rest):lower() or nil })
        end
    elseif msg:match("^record%s+term%s") then
        -- /eviltools record term <days>  — the guild's term for warnings (#402), officers only.
        local days = strtrim((msg:gsub("^record%s+term%s+", "")))
        local ok, why = false, "range"
        if EVRFeatures.Discipline then ok, why = EVRFeatures.Discipline:SetTerm(days) end
        if ok then
            EVRFeatures:Print(string.format(L["Warnings now count for %d days."], EVRFeatures.Discipline:GetTerm()))
        elseif why == "officer" then
            EVRFeatures:Print(L["|cffFF4444Officers only.|r"])
        else
            EVRFeatures:Print(L["Usage: /eviltools record term <1-365>"])
        end
    elseif msg:match("^record%s") then
        -- /eviltools record <name>  — a member's disciplinary record (#402), officers only.
        local name = strtrim((msg:gsub("^record%s+", "")))
        local D = EVRFeatures.Discipline
        if not (D and EVRFeatures:IsOfficer()) then
            EVRFeatures:Print(L["|cffFF4444Officers only.|r"])
        elseif name == "" then
            EVRFeatures:Print(L["Usage: /eviltools record <name>"])
        else
            local key = EVRFeatures:RosterKey(name) or EVRFeatures:GetPlayerKey(name)
            local now, term = GetServerTime(), D:GetTerm()
            local record = D:Record(key)
            EVRFeatures:Print(string.format(L["%s: step %d, %d warning(s)."], name, D.Step(record, term, now), #record))
            for i = 1, math.min(5, #record) do
                local w = record[i]
                local state = w.revokedAt and L["revoked"] or (D.Active(w, term, now) and L["standing"] or L["lapsed"])
                EVRFeatures:Print(string.format("  %s  %s  %s (%s)", EVRFeatures:DateText(w.at or 0), D.ReasonText(w.reason), state, w.by or "?"))
            end
        end
    elseif msg == "bulk" or msg:match("^bulk%s") then
        -- /eviltools bulk [next | skip | stop] — Leadership > Bulk actions (#420). A typed command is addon code, which may
        -- not run the game's protected rank commands: `next` says who is next; the Next button or a
        -- /click EVRFeaturesBulkNext macro acts.
        if EVRFeatures.BulkActions then
            EVRFeatures.BulkActions:Command((msg:gsub("^bulk%s*", "")))
        else
            EVRFeatures:Print(L["Not available on this client."])
        end
    elseif msg == "altgroup" or msg:match("^altgroup%s") then
        -- /eviltools altgroup <promote | demote> <name> [rank] (#424): a queue in Leadership > Bulk actions, one alt per click.
        if EVRFeatures.BulkActions then
            EVRFeatures.BulkActions:CommandGroup((msg:gsub("^altgroup%s*", "")))
        else
            EVRFeatures:Print(L["Not available on this client."])
        end
    elseif msg == "birthday" or msg:match("^birthday%s") or msg == "aniversario" or msg:match("^aniversario%s") then
        -- /eviltools birthday [DD/MM | off] (#428), Settings > Profile's Birthday; an officer adds a name first.
        if EVRFeatures.Birthdays then EVRFeatures.Birthdays:Command((msg:gsub("^%a+%s*", ""))) end
    elseif msg == "joindate" or msg:match("^joindate%s") then
        -- /eviltools joindate [<name> | all | import] (#429): Leadership > Notes and marks.
        if EVRFeatures.NoteDates then EVRFeatures.NoteDates:Command((msg:gsub("^joindate%s*", ""))) end
    elseif msg == "safe" or msg:match("^safe%s") then
        -- /eviltools safe [<name>] (#429): the safe list the bulk actions never remove or demote.
        if EVRFeatures.MemberMarks then EVRFeatures.MemberMarks:CommandSafe((msg:gsub("^safe%s*", ""))) end
    elseif msg == "nick" or msg:match("^nick%s") then
        -- /eviltools nick <name> [nickname] (#429): the officers' nickname, on the tooltip and in chat.
        if EVRFeatures.MemberMarks then EVRFeatures.MemberMarks:CommandNick((msg:gsub("^nick%s*", ""))) end
    elseif msg == "altlimit" or msg:match("^altlimit%s") then
        -- /eviltools altlimit N (#424): the groups with more than N alts, in chat.
        if EVRFeatures.AltSync then EVRFeatures.AltSync:CommandLimit((msg:gsub("^altlimit%s*", ""))) end
    elseif msg == "banlist" then
        EVRFeatures.UI:OpenWindow("management", "ban")
    elseif msg == "autoinvite" or msg:match("^autoinvite%s") or msg == "ai" or msg:match("^ai%s") then
        if EVRFeatures.Recruitment then
            local rest = strtrim((msg:gsub("^ai%s*", ""):gsub("^autoinvite%s*", "")))
            local a = {}
            for w in rest:gmatch("%S+") do a[#a + 1] = w end
            EVRFeatures.Recruitment:HandleAutoInviteCommand(a)
        end
    elseif msg == "mentions" or msg:match("^mentions%s") then
        if EVRFeatures.Mentions then
            local rest = strtrim((msg:gsub("^mentions%s*", "")))
            local a = {}
            for w in rest:gmatch("%S+") do a[#a + 1] = w end
            EVRFeatures.Mentions:HandleCommand(a)
        end
    elseif msg == "notecmd" or msg:match("^notecmd%s") then
        if EVRFeatures.NoteCommand then
            local rest = strtrim((msg:gsub("^notecmd%s*", "")))
            local a = {}; for w in rest:gmatch("%S+") do a[#a+1] = w end
            EVRFeatures.NoteCommand:HandleCommand(a)
        end
    elseif msg == "avail" or msg:match("^avail%s") then
        -- /eviltools avail [off | notify [on|off] | [tank|healer|dps|any] <text>]
        -- Anchored on "^avail%s" so it can never swallow a sibling verb.
        -- (/eviltools lfg is already the recruitment beacon inbox, hence "avail".)
        if EVRFeatures.LFGBoard then
            -- gsub returns (string, count); the extra parens drop the count so it
            -- cannot reach strtrim's optional "characters to trim" argument. The
            -- note here is free text, so "avail 10 man" must not lose its "1".
            local rest = strtrim((msg:gsub("^avail%s*", "")))
            local a = {}; for w in rest:gmatch("%S+") do a[#a+1] = w end
            EVRFeatures.LFGBoard:HandleCommand(a, rest)
        end
    elseif msg == "open" or msg:match("^open%s") then
        -- /eviltools open <feature> [sub] — one uniform way to open any feature
        -- tab. A dedicated verb rather than a bare-id fallback: several
        -- feature ids (roster, trials, dkp, alliance) are already verbs
        -- above, and "^trial" would even prefix-match "trials" and eat the
        -- "s" as a player name. "open" itself is not a prefix of, nor
        -- prefixed by, any other verb in this chain.
        local id  = msg:match("^open%s+(%S+)")
        local sub = msg:match("^open%s+%S+%s+(%S+)")
        local def = id and EVRFeatures.UI and EVRFeatures.UI.GetFeature and EVRFeatures.UI:GetFeature(id)
        if def and (def.tab or def.opens) then
            EVRFeatures.UI:OpenWindow(id, sub)
        else
            EVRFeatures:Print(L["Usage: /eviltools open <feature>. Try /eviltools open roster."])
        end
    else
        -- Unknown verb: point at the listing, then keep the historic
        -- behaviour of opening the roster. A bare /eviltools is the documented way
        -- to open the roster and is not a typo, so it stays silent.
        if msg ~= "" then
            EVRFeatures:Print(string.format(L["Unknown command. Type %s for the list."], "|cffFFD700/eviltools help|r"))
        end
        EVRFeatures:ToggleRoster()
    end
end

-- Dispatch: /eviltools and /eviltools (primary)
SlashCmdList["EVRF"] = handleCommand

