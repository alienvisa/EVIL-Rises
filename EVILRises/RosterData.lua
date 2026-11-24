local _, addon = ...

local secondarySkills = { [129] = true, [185] = true, [356] = true, [794] = true }
local function hasText(value)
    return type(value) == "string" and value ~= ""
end

local function shortName(name)
    return name:match("^[^-]+") or name
end

local function nameKey(name)
    return name:lower():gsub("%s", "")
end

local function offlineTime(index, online)
    if online then
        return 0, "Now"
    end
    local years, months, days, hours = GetGuildRosterLastOnline(index)
    if not (years or months or days or hours) then
        return nil, "Unknown"
    end
    years, months, days, hours = years or 0, months or 0, days or 0, hours or 0
    local elapsed = ((years * 365 + months * 30 + days) * 24 + hours) + 1
    if years > 0 then return elapsed, years .. "y " .. months .. "mo ago" end
    if months > 0 then return elapsed, months .. "mo " .. days .. "d ago" end
    if days > 0 then return elapsed, days .. "d " .. hours .. "h ago" end
    if hours > 0 then return elapsed, hours .. "h ago" end
    return elapsed, "<1h ago"
end

local function readGuildProfessions(roster)
    if not (GetNumGuildTradeSkill and GetGuildTradeSkillInfo) then
        return
    end

    local skillID, skillName
    local index = 1
    while index <= GetNumGuildTradeSkill() do
        local id, collapsed, _, header, _, _, _, name, fullName, _, _, _, skill = GetGuildTradeSkillInfo(index)
        if hasText(header) then
            skillID, skillName = id, header
            if collapsed and ExpandGuildTradeSkillHeader then
                ExpandGuildTradeSkillHeader(index)
            end
        elseif skillID and (hasText(fullName) or hasText(name)) then
            local member = addon.FindRosterMember(roster, hasText(fullName) and fullName or name)
            if member then
                member.skills[skillID] = { name = skillName, rank = skill }
            end
        end
        index = index + 1
    end
end

local function readPlayerProfessions(member)
    if not (GetProfessions and GetProfessionInfo) then
        return
    end
    local prof1, prof2, archaeology, fishing, cooking, firstAid = GetProfessions()
    for _, index in pairs({ prof1, prof2, archaeology, fishing, cooking, firstAid }) do
        local name, _, rank, _, _, _, skillID = GetProfessionInfo(index)
        if skillID and hasText(name) then
            member.skills[skillID] = { name = name, rank = rank }
        end
    end
end

function addon.FindRosterMember(roster, input)
    local key = nameKey(input)
    if key:find("-", 1, true) then
        return roster.byName[key]
    end
    return roster.byShortName[key] or nil
end

function addon.ReadRoster()
    local roster = { members = {}, byID = {}, byName = {}, byShortName = {}, online = 0 }
    if not IsInGuild() then
        return roster
    end
    local guild, _, _, realm = GetGuildInfo("player")
    local clubID = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if guild then
        roster.guildKey = clubID and ("club:" .. clubID) or nameKey((realm or GetRealmName()) .. "-" .. guild)
    end
    local canViewOfficerNote = C_GuildInfo.CanViewOfficerNote or CanViewOfficerNote
    roster.canViewOfficerNote = canViewOfficerNote and canViewOfficerNote()
    local playerGUID = UnitGUID("player")
    for index = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, class, zone, note, officer, online, _, classFile,
            _, _, _, _, _, guid = GetGuildRosterInfo(index)
        if hasText(name) then
            local elapsed, lastSeen = offlineTime(index, online)
            local race = guid and GetPlayerInfoByGUID and select(3, GetPlayerInfoByGUID(guid))
            local isPlayer = guid and guid == playerGUID
            if isPlayer then
                race = UnitRace("player")
            end
            local member = {
                id = guid or nameKey(name), guid = guid, name = name, shortName = shortName(name),
                rank = rank, rankIndex = rankIndex, level = level, class = class,
                classFile = classFile, zone = zone, online = not not online, elapsed = elapsed,
                lastSeen = lastSeen, race = hasText(race) and race or nil, note = note,
                officerNote = roster.canViewOfficerNote and officer or nil, skills = {}, isPlayer = isPlayer,
            }
            roster.members[#roster.members + 1] = member
            roster.byID[member.id], roster.byName[nameKey(name)] = member, member
            local short = nameKey(member.shortName)
            if roster.byShortName[short] == nil then
                roster.byShortName[short] = member
            else
                roster.byShortName[short] = false
            end
            if online then roster.online = roster.online + 1 end
        end
    end

    readGuildProfessions(roster)
    for _, member in ipairs(roster.members) do
        if member.isPlayer then
            readPlayerProfessions(member)
        end
        local primary, all = {}, {}
        for id, skill in pairs(member.skills) do
            local line = skill.name
            if type(skill.rank) == "number" and skill.rank > 0 then
                line = line .. " (" .. skill.rank .. ")"
            end
            all[#all + 1] = line
            if not secondarySkills[id] then
                primary[#primary + 1] = skill.name
            end
        end
        table.sort(primary)
        table.sort(all)
        member.professions = #primary > 0 and table.concat(primary, ", ") or nil
        member.allProfessions = all
    end
    return roster
end

function addon.RequestRoster()
    if IsInGuild() then
        if SetGuildRosterShowOffline and GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
            SetGuildRosterShowOffline(true)
        end
        C_GuildInfo.GuildRoster()
    end
end

function addon.GetAltLinks(roster)
    if not roster.guildKey then
        return {}
    end
    local settings = addon.settings
    if type(settings.altLinks) ~= "table" then settings.altLinks = {} end
    if type(settings.altLinks[roster.guildKey]) ~= "table" then settings.altLinks[roster.guildKey] = {} end
    return settings.altLinks[roster.guildKey]
end

function addon.LinkRosterAlt(roster, member, candidate)
    if not roster.guildKey then return "Guild information is still loading." end
    if not candidate then return "Enter a unique roster name or Name-Realm." end
    local links = addon.GetAltLinks(roster)
    local mainID = links[member.id] or member.id
    if candidate.id == mainID or candidate.id == member.id then
        return "Choose a different character."
    end
    if links[candidate.id] then
        return "Unlink that character from its current main first."
    end
    for _, parentID in pairs(links) do
        if parentID == candidate.id then
            return "That character is already the main of another group."
        end
    end
    links[candidate.id] = mainID
end

function addon.SortRoster(members, column, descending)
    table.sort(members, function(a, b)
        local left, right = a[column], b[column]
        if type(left) == "string" then left = left ~= "" and left:lower() or nil end
        if type(right) == "string" then right = right ~= "" and right:lower() or nil end
        if type(left) == "boolean" then left = left and 1 or 0 end
        if type(right) == "boolean" then right = right and 1 or 0 end
        if left == right then return a.name:lower() < b.name:lower() end
        if left == nil then return false end
        if right == nil then return true end
        if descending then return left > right end
        return left < right
    end)
end
