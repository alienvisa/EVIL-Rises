local _, board = ...
local lifetime = 7 * 24 * 60 * 60
local limit = 20
local modes = { kos = "Kill on sight", camp = "Camp", both = "Kill on sight + camp" }
board.modes = modes

local function owner(name)
    if not name then
        local first, surname = UnitFullName("player")
        name = surname and surname ~= "" and first .. " " .. surname or first
    end
    return name and name:gsub("-", " ")
end
board.Owner = owner

local function clean(s, size)
    if type(s) ~= "string" then return "" end
    return s:gsub("[|%c]", ""):sub(1, size):match("^%s*(.-)%s*$")
end

function board.GuildID()
    local id = IsInGuild() and C_Club.GetGuildClubId()
    if id then return tostring(id) end
end

local function records()
    local id = board.GuildID()
    if not id then return end
    EVILRisesBounties = EVILRisesBounties or {}
    local data = EVILRisesBounties[id]
    if not data then data = {}; EVILRisesBounties[id] = data end
    local guild = GetGuildInfo("player")
    if guild and not data.imported then
        local realm = GetRealmName() or ""
        local legacy = EVRFeaturesDB and EVRFeaturesDB[guild .. "-" .. realm]
        for author, sheet in pairs(legacy and legacy.bounties or {}) do
            local suffix = "-" .. realm
            local name = realm ~= "" and author:sub(-#suffix) == suffix and author:sub(1,-#suffix-1) or author
            board.Import(data, owner(name), sheet)
        end
        data.imported = true
    end
    data.authors = data.authors or {}
    return data.authors
end
board.Records = records
local function refresh()
    if board.page and board.page:IsVisible() then board.page:Refresh() end
end

local function prune(sheet, now)
    local removed, earliest = false, nil
    for i = #sheet.posts, 1, -1 do
        local expires = sheet.posts[i].time + lifetime
        if expires <= now then
            table.remove(sheet.posts, i)
            removed = true
        elseif not earliest or expires < earliest then
            earliest = expires
        end
    end
    return removed, earliest
end

local nextWake
local function maintain(data, broadcastOwn)
    if not data then return end
    local now, ownKey, earliest = GetServerTime(), owner(), nil
    for key, sheet in pairs(data) do
        local removed, expires = prune(sheet, now)
        if expires and (not earliest or expires < earliest) then earliest = expires end
        -- Peers expire cached posts independently. Only the author advances the revision.
        if key == ownKey then
            if removed then sheet.rev = math.max(now, sheet.rev + 1) end
            if removed or broadcastOwn then board.SendSheet(sheet) end
        end
    end
    if earliest and (not nextWake or earliest < nextWake) then
        nextWake = earliest
        C_Timer.After(earliest - now, function()
            if nextWake ~= earliest then return end
            nextWake = nil
            maintain(records())
            refresh()
        end)
    end
end

function board:Broadcast()
    maintain(records(), true)
end

local function save(key, sheet)
    sheet.rev = math.max(GetServerTime(), sheet.rev + 1)
    records()[key] = sheet
    board:Broadcast()
    refresh()
end

local function validCopper(amount)
    return type(amount) == "number" and amount >= 1 and amount <= 999999999999
        and amount == math.floor(amount)
end

local function money(amount)
    return string.format("%dg %ds %dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

local function readUnit(unit)
    if not unit or not UnitIsPlayer(unit) then return end
    local first, surname = UnitFullName(unit)
    local name = first and (surname and surname ~= "" and first .. " " .. surname or first)
    if not name or name == "" then return end
    return { name = name, class = UnitClass(unit), faction = UnitFactionGroup(unit) }
end

local function matchName(text)
    local wanted = clean(text, 72):lower()
    if wanted == "" then return end
    local function matches(name)
        if not name then return false end
        local full = name:lower()
        return wanted == full or wanted == full:match("^([^-]+)")
    end
    local function matchUnit(unit)
        if UnitExists(unit) and UnitIsPlayer(unit) and UnitIsConnected(unit)
            and matches(GetUnitName(unit, true)) then return readUnit(unit) end
    end
    for _, unit in ipairs({"target", "mouseover", "focus"}) do
        local info = matchUnit(unit)
        if info then return info end
    end
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local info = matchUnit((raid and "raid" or "party") .. i)
        if info then return info end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            if plate.namePlateUnitToken then
                local info = matchUnit(plate.namePlateUnitToken)
                if info then return info end
            end
        end
    end
    if C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo then
        for i = 1, C_FriendList.GetNumWhoResults() or 0 do
            local who = C_FriendList.GetWhoInfo(i)
            if who and matches(who.fullName) then
                return { name = who.fullName, class = who.classStr or who.filename }
            end
        end
    end
end

function board:Post(target, copper, reason, mode, faction, class)
    local data = records()
    if not data then return "Join a guild and reload to post a bounty." end
    target, reason = clean(target, 72), clean(reason, 180)
    if target == "" then return "Enter a bounty target name." end
    if not modes[mode] then return "Select Kill on sight, Camp, or both." end
    if not validCopper(copper) then return "Enter a reward of at least one copper." end
    if faction ~= "Alliance" and faction ~= "Horde" then return "Choose a faction." end
    local key = owner()
    local sheet = data[key] or { rev = 0, posts = {} }
    prune(sheet, GetServerTime())
    if #sheet.posts >= limit then return "Withdraw an open bounty before posting another." end
    table.insert(sheet.posts, 1, { target = target, reward = money(copper), copper = copper, class = clean(class, 40), reason = reason, mode = mode,
        faction = faction, time = GetServerTime() })
    save(key, sheet)
end

function board:Withdraw(post)
    local data = records()
    local key = owner()
    local sheet = data and data[key]
    if not sheet then return end
    for i, entry in ipairs(sheet.posts) do
        if entry == post then table.remove(sheet.posts, i); save(key, sheet); return end
    end
end

board.ReadUnit = readUnit
board.MatchName = matchName

function board.Import(bucket, author, sheet)
    bucket.authors = bucket.authors or {}
    local data = bucket.authors
    local now = GetServerTime()
    if type(author) ~= "string" or author == "" or type(sheet) ~= "table"
        or type(sheet.rev) ~= "number" or sheet.rev ~= math.floor(sheet.rev)
        or sheet.rev <= 0 or sheet.rev > now + 86400
        or type(sheet.posts) ~= "table" or #sheet.posts > limit
        or (data[author] and data[author].rev >= sheet.rev) then return end
    local posts = {}
    for _, p in ipairs(sheet.posts) do
        if type(p) ~= "table" or not modes[p.mode] or (p.faction ~= "Horde" and p.faction ~= "Alliance")
            or type(p.time) ~= "number" or not (p.time > 0 and p.time <= sheet.rev)
            or clean(p.target,72) == "" then return end
        local reward = validCopper(p.copper) and money(p.copper) or clean(p.reward,64)
        if reward == "" then return end
        if now < p.time + lifetime then
            posts[#posts+1] = {target=clean(p.target,72), faction=p.faction, class=clean(p.class,40),
                reward=reward, copper=validCopper(p.copper) and p.copper or nil, mode=p.mode,
                reason=clean(p.reason,180), time=p.time}
        end
    end
    data[author] = { rev=sheet.rev, posts=posts }
    return true
end

function board.Update()
    maintain(records())
    refresh()
end
