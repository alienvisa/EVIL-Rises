local addonName, addon = ...

addon.folder = addonName
addon.title = "EVIL Rises"
addon.guildName = "EVIL: Every Villian Is Lemons"
addon.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

local function printMessage(message)
    print("|cffd9e85b" .. addon.title .. "|r " .. message)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then
            return
        end

        if type(EVILRisesDB) ~= "table" then
            EVILRisesDB = {}
        end
        if type(EVILRisesDB.showLoginMessage) ~= "boolean" then
            EVILRisesDB.showLoginMessage = false
        end
        addon.settings = EVILRisesDB

        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        addon.InstallGuildWindow()
        if addon.settings.showLoginMessage then
            printMessage("v" .. addon.version .. " loaded. Type /evil to open the guild panel.")
        end
    end
end)

SLASH_EVILRISES1 = "/evil"
SLASH_EVILRISES2 = "/evilrises"
SlashCmdList.EVILRISES = function(message)
    local command = message:match("^%s*(.-)%s*$"):lower()
    if command == "" then
        addon.TogglePanel()
    elseif command == "version" then
        printMessage("v" .. addon.version)
    else
        printMessage("/evil opens the guild panel. /evil version shows the installed version.")
    end
end
