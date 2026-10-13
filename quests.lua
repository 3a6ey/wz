-- ============================================================
-- QUESTS MODULE (FIXED)
-- ============================================================
-- Load this separately from main script, e.g.:

-- create a single persistent, live-updating notification via
-- Library:Notify({..., Persist = true}) instead of a stream of toast
-- popups - see the "PERSISTENT STATUS NOTIFICATION" section below.
--
-- It's loaded as its own chunk so it doesn't add to your main
-- script's local variable count (avoids "Out of local registers").
-- This module creates its own Tabs.Quests tab and tabbox - you
-- don't need to declare anything for it in your main script.
--
-- IMPORTANT: the game hands out quests from a big pool of random
-- numeric IDs (not a fixed set), so quests are matched by their
-- CONTENT (mob name / world / dungeon id / event key) instead of
-- by their numeric ID. That's what all the *Handlers tables below
-- are for.
-- ============================================================

local plr, rs, Window, Tabs, Toggles, noti, Library = ...

-- FIXED: Get actual shared modules and remotes from the correct paths
local Quests = require(game.ReplicatedStorage.Shared.Quests)
local Profile = require(game.ReplicatedStorage.Shared.Profile)
local Items = require(game.ReplicatedStorage.Shared.Items)
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild('Remotes')

-- Helper to safely get remotes (fallback for compatibility)
local function getRemote(name)
    return Remotes:FindFirstChild(name) or game.ReplicatedStorage:FindFirstChild(name)
end

Tabs.Quests = Window:AddTab('Quests', 'scroll-text')
local QuestsTabbox = Tabs.Quests:AddLeftTabbox('questsBox')
local QuestsMainTab = QuestsTabbox:AddTab('Quests')

-- Diagnostic: fires the moment this module loads
do
    if not Library then
        warn('[Quests] MODULE LOADED but Library was NOT passed in - update your loadstring call to include it as the 7th argument.')
    else
        local ok, err = pcall(function()
            Library:Notify({ Title = 'Quests', Description = 'Quests module loaded', Persist = false })
        end)
        if ok then
            warn('[Quests] MODULE LOADED, Library:Notify works.')
        else
            warn('[Quests] MODULE LOADED but Library:Notify FAILED: ' .. tostring(err))
        end
    end
end

-- Quests Tab
;(function()
    local function GetMyProfile()
        return Profile:GetProfile(plr)
    end

    local function GetQuestData(questId)
        return Quests:GetQuestDataFromID(questId)
    end

    local function GetProgress(questId)
        return Quests:GetQuestProgress(plr, questId)
    end

    -- {questId, questId, ...} in slot order (Slot1..Slot10)
    -- FIXED: Now supports "only Hot quests" option
    local function GetActiveDailyQuestIds(onlyHot)
        local profile = GetMyProfile()
        if not profile then return {} end
        local raw = Quests:GetDailyQuests(profile) -- {[slot] = questId}
        local ids = {}
        local maxSlot = onlyHot and 3 or 10  -- Only slots 1-3 for "Hot" quests
        for slot = 1, maxSlot do
            if raw[slot] then
                table.insert(ids, raw[slot])
            end
        end
        return ids
    end

    -- VIP gamepass check
    local MarketplaceService = game:GetService("MarketplaceService")
    local VIP_GAMEPASS_ID = 8136226
    local HasVIP
    do
        local ok, owns = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, VIP_GAMEPASS_ID)
        end)
        HasVIP = ok and owns or false
        warn('[Quests] VIP gamepass check: owns=' .. tostring(HasVIP) .. (ok and '' or ' (check FAILED, defaulting to false)'))
    end

    local function GetWeeklyData()
        local ok, data = pcall(function()
            return Remotes:WaitForChild('Quests_GetWeeklyQuestData'):InvokeServer()
        end)
        if ok then return data end
        return nil
    end

    local function GetActiveWeeklyQuestIds(weeklyData)
        local ids = {}
        if weeklyData and weeklyData.quests then
            for _, q in ipairs(weeklyData.quests) do
                if q.isVIP and not HasVIP then
                    -- filtered out, VIP-gated and you don't own it
                else
                    table.insert(ids, q.id)
                end
            end
        end
        return ids
    end

    local function GetWeeklyQuestEntry(weeklyData, questId)
        if not weeklyData or not weeklyData.quests then return nil end
        for _, q in ipairs(weeklyData.quests) do
            if tostring(q.id) == tostring(questId) then return q end
        end
        return nil
    end

    -- Persisted state for class switching and other handlers
    getgenv().QuestsPersist = getgenv().QuestsPersist or {}
    local Persist = getgenv().QuestsPersist

    local claimedQuestIds = {}

    -- Daily Login rewards
    local function TryClaimDailyLogin()
        for _ = 1, 5 do
            local ok, current, claimedUpTo = pcall(function()
                return Profile:GetCurrentDailyLogin(plr)
            end)
            if not ok then
                warn('[Quests] Failed to check Daily Login status: ' .. tostring(current))
                return
            end
            if not (current and claimedUpTo and claimedUpTo < current) then
                break
            end
            local ok2, err2 = pcall(function()
                Profile:AwardDailyLoginReward(plr)
            end)
            if ok2 then
                noti('Daily login reward claimed!')
            else
                warn('[Quests] Failed to claim Daily Login reward: ' .. tostring(err2))
                break
            end
            task.wait(0.5)
        end
    end

    local function GetQuestStatus(questId, questData, isWeekly, weeklyData)
        local required = questData.Objective[2]
        local current, claimed

        if isWeekly then
            local entry = GetWeeklyQuestEntry(weeklyData, questId)
            if not entry then
                return nil, nil, nil
            end
            if entry.isVIP and not HasVIP then
                return nil, nil, nil
            end
            current = entry.value or 0
            claimed = entry.claimed or false
        else
            local c, cl = GetProgress(questId)
            current = c or 0
            claimed = cl or false
        end

        if claimed then
            claimedQuestIds[questId] = true
        end

        return current, (current >= required), claimed
    end

    -- Claims the reward for a finished quest
    local function ClaimQuest(questId, isWeekly, questName)
        if claimedQuestIds[questId] then return end
        claimedQuestIds[questId] = true

        if Persist.firedQuestIds then
            Persist.firedQuestIds[questId] = nil
        end

        local claimRemote = getRemote('Quests_ClaimQuest')
        if claimRemote then
            claimRemote:FireServer(questId)
        end
        noti((questName or tostring(questId)) .. ' — claimed!')

        if isWeekly then
            pcall(function()
                local claimWeeklyRemote = getRemote('Quests_ClaimWeeklyReward')
                if claimWeeklyRemote then
                    claimWeeklyRemote:FireServer()
                end
            end)
        end
    end

    -- ========================================================
    -- HANDLERS
    -- ========================================================

    local DungeonPlaceIds = {
        [1] = '2978696440',   [49] = '107701891477606', [3] = '4310476380',
        [2] = '4310464656',   [4] = '4310478830',       [6] = '3383444582',
        [11] = '3885726701',  [12] = '3994953548',      [13] = '4050468028',
        [7] = '3165900886',   [14] = '4465988196',      [15] = '4465989351',
        [16] = '4465989998',  [20] = '4646473427',      [19] = '4646475342',
        [18] = '4646475570',  [24] = '6386112652',      [35] = '11466514043',
        [21] = '5703353651',  [25] = '6510862058',      [36] = '11533444995',
        [23] = '6075085184',  [26] = '6847034886',      [37] = '11644048314',
        [27] = '7071564842',  [30] = '9944263348',      [31] = '10014664329',
        [29] = '10089970465', [32] = '10651527284',     [33] = '10727165164',
        [34] = '10795158121', [41] = '14914700740',     [42] = '14914855930',
        [43] = '15121292578', [38] = '13988110964',     [39] = '14400549310',
        [22] = '5862277651',  [17] = '4526768588',      [44] = '18567068844',
        [45] = '75540798045662', [46] = '81373988789544', [52] = '110769392907898',
        [47] = '102111805987017', [48] = '138178936582742', [50] = '109614960834199',
        [51] = '93889085342251',
    }

    local function FireRaidIfNeeded(raidId, difficulty)
        local ok, currentMissionId = pcall(function()
            return workspace:GetAttribute("MissionId")
        end)
        if ok and currentMissionId ~= nil and tostring(currentMissionId) == tostring(raidId) then
            return
        end

        local targetPlaceId = DungeonPlaceIds[raidId]
        if targetPlaceId and tostring(game.PlaceId) == tostring(targetPlaceId) then
            return
        end

        StartRaid(raidId, difficulty)
    end

    -- FIXED: Added missing mobs (e.g., Charged Boarwolf)
    local MobRaid = {}
    MobRaid["Boarwolf"] = {2, 5}
    MobRaid["ChargedBoarwolf"] = {2, 5}
    MobRaid["EliteBoarwolf"] = {2, 5}
    MobRaid["Toucan"] = {3, 5}
    MobRaid["EarthCrab"] = {4, 5}
    MobRaid["ElectricCrab"] = {4, 5}
    MobRaid["FireCrab"] = {4, 5}
    MobRaid["GrassCobra"] = {3, 5}
    MobRaid["PoisonCobra"] = {3, 5}
    MobRaid["Quillodile"] = {12, 1}
    MobRaid["GoblinSpear"] = {13, 1}
    MobRaid["GoblinSlingshot"] = {13, 1}
    MobRaid["GoblinGatekeeper"] = {13, 1}
    MobRaid["RedGoblinSpear"] = {13, 1}
    MobRaid["RedGoblinSlingshot"] = {13, 1}
    MobRaid["RedGoblinGatekeeper"] = {13, 1}
    MobRaid["IcyGoo"] = {15, 1}
    MobRaid["SnowRaptor"] = {15, 1}
    MobRaid["FrostGolem"] = {15, 1}
    MobRaid["HappyCactus"] = {18, 5}
    MobRaid["GoldCobra"] = {18, 5}
    MobRaid["RockGolem"] = {18, 5}
    MobRaid["PinkBoarwolf"] = {24, 5}
    MobRaid["BlueGoblinSlingshot"] = {24, 5}
    MobRaid["BlueGoblinElite"] = {24, 5}
    MobRaid["BlueGoblinGatekeeper"] = {24, 5}
    MobRaid["BlossomTree"] = {24, 5}
    MobRaid["SeaSerpent"] = {36, 5}
    MobRaid["JellyfishSlime"] = {36, 5}
    MobRaid["Parrot"] = {36, 5}
    MobRaid["GoblinGladiator"] = {37, 5}
    MobRaid["GoblinSpartan"] = {37, 5}
    MobRaid["Kirin"] = {37, 5}
    MobRaid["ScorpionGold"] = {37, 5}
    MobRaid["Gargoyle"] = {26, 5}
    MobRaid["GargoyleGrey"] = {26, 5}
    MobRaid["RuinGuardian"] = {30, 5}
    MobRaid["Alligator"] = {30, 5}
    MobRaid["Rapigator"] = {30, 5}

    local function MobHandlerFor(mobName)
        local raid = mobName and MobRaid[mobName]
        return function(questData, amount)
            if raid then
                FireRaidIfNeeded(raid[1], raid[2])
            else
                -- Infinite Tower fallback for unknown mobs
                FireRaidIfNeeded(38, nil)
            end
        end
    end

    -- FIXED: Added worlds 5-10 for DungeonWorldRaid
    local DungeonWorldRaid = {
        [1] = {1, 5},
        [2] = {11, 5},
        [3] = {15, 1},
        [4] = {18, 5},
        [5] = {24, 5},   -- Konoh Heartlands
        [6] = {25, 5},   -- Rough Waters
        [7] = {26, 5},   -- The Underworld
        [8] = {30, 5},   -- Rescue in the Ruins
        [9] = {32, 5},   -- Treetop Trouble
        [10] = {41, 5},  -- Crystal Chaos
    }

    local DungeonIdHandlers = {}
    DungeonIdHandlers[1] = 5
    DungeonIdHandlers[3] = 5
    DungeonIdHandlers[2] = 5
    DungeonIdHandlers[4] = 5
    DungeonIdHandlers[6] = 5
    DungeonIdHandlers[11] = 5
    DungeonIdHandlers[12] = 5
    DungeonIdHandlers[13] = 5
    DungeonIdHandlers[7] = 5
    DungeonIdHandlers[14] = 5
    DungeonIdHandlers[15] = 5
    DungeonIdHandlers[16] = 5
    DungeonIdHandlers[20] = 5
    DungeonIdHandlers[19] = 5
    DungeonIdHandlers[18] = 5
    DungeonIdHandlers[24] = 5
    DungeonIdHandlers[35] = 5
    DungeonIdHandlers[25] = 5
    DungeonIdHandlers[36] = 5
    DungeonIdHandlers[26] = 5
    DungeonIdHandlers[37] = 5
    DungeonIdHandlers[30] = 5
    DungeonIdHandlers[31] = 5
    DungeonIdHandlers[32] = 5
    DungeonIdHandlers[33] = 5
    DungeonIdHandlers[41] = 5
    DungeonIdHandlers[42] = 5

    local WorldEventHandlers = {}

    local function TimeInWorldHandler(questData, amount, hubId)
        if hubId then
            local teleportRemote = getRemote('Teleport_TeleportToHub')
            if teleportRemote then
                teleportRemote:FireServer(hubId)
            end
        end
    end

    -- Upgrade items
    local PlayerEquips = game.ReplicatedStorage:WaitForChild('PlayerEquips'):WaitForChild(plr.Name)
    local EquipPrimary = PlayerEquips:WaitForChild('Primary')
    local EquipOffhand = PlayerEquips:WaitForChild('Offhand')
    local EquipArmor = PlayerEquips:WaitForChild('Armor')

    local UpgradeState = {
        running = false,
        savedPrimary = nil,
        savedOffhand = nil,
        savedArmor = nil,
    }

    local function UpgradeItemToLimit(item)
        if not (item and item:FindFirstChild('UpgradeLimit') and item.UpgradeLimit.Value ~= 0) then
            return
        end
        local profile = Profile:GetProfile(plr)
        local goldValue = profile.Currency.Gold
        local oldGold = goldValue.Value
        local timer = tick()
        while task.wait(0.1) do
            if item:FindFirstChild('Upgrade') and item.Upgrade.Value == item.UpgradeLimit.Value then
                break
            else
                local upgradeRemote = getRemote('ItemUpgrade_Upgrade')
                if upgradeRemote then
                    upgradeRemote:FireServer(item)
                end
                if goldValue.Value ~= oldGold then
                    oldGold = goldValue.Value
                    timer = tick()
                end
                if tick() - timer >= 2 then break end
            end
        end
    end

    local function FindUpgradeableItem()
        local profile = Profile:GetProfile(plr)
        local invItems = profile.Inventory.Items
        for _, item in pairs(invItems:GetChildren()) do
            local limit = item:FindFirstChild('UpgradeLimit')
            if limit and limit.Value > 0 then
                local cur = item:FindFirstChild('Upgrade')
                local curVal = cur and cur.Value or 0
                if curVal < limit.Value then
                    local data = Items[item.Name]
                    if data and (data.Type == 'Weapon' or data.Type == 'Armor') then
                        return item, data.Type
                    end
                end
            end
        end
        return nil
    end

    local CustomEventHandlers = {}

    CustomEventHandlers["UpgradeCompleted"] = function(questData, amount)
        if UpgradeState.running then return end
        UpgradeState.running = true

        UpgradeState.savedPrimary = EquipPrimary:GetChildren()[1]
        UpgradeState.savedOffhand = EquipOffhand:GetChildren()[1]
        UpgradeState.savedArmor = EquipArmor:GetChildren()[1]

        task.spawn(function()
            while UpgradeState.running do
                local item, itemType = FindUpgradeableItem()
                if not item then
                    warn('[Quests] No upgradeable items left in inventory for the Upgrade quest')
                    break
                end

                local targetFolder = (itemType == 'Weapon') and EquipPrimary or EquipArmor
                local equipRemote = getRemote('Inventory_EquipItem')
                if equipRemote then
                    equipRemote:FireServer(item, targetFolder)
                end
                task.wait(0.5)

                UpgradeItemToLimit(item)
                task.wait(0.5)
            end
        end)
    end

    CustomEventHandlers["CollectEquipmentInDungeon"] = function(questData, amount)
        FireRaidIfNeeded(2, 5)
    end

    CustomEventHandlers["HatchPetEgg"] = function(questData, amount)
        task.spawn(function()
            for i = 1, amount do
                local eggRemote = getRemote('Pets_BuyEgg')
                if eggRemote then
                    eggRemote:FireServer("StarEgg", "Gold")
                end
                task.wait(0.3)
            end
        end)
    end

    CustomEventHandlers["CompletedInfiniteTowerFloor"] = function(questData, amount)
        FireRaidIfNeeded(38, nil)
    end

    -- FIXED: Completely rewritten class switching logic
    -- Supports tiers 2, 3, and 4 with proper state management
    local TierToClass = {
        [2] = "IcefireMage",  -- or DualWielder, Guardian
        [3] = "Berserker",    -- Tier 3 class
        [4] = "Archer",       -- or Demon, Dragoon
    }

    local function DungeonWithClassHandler(questData, amount, tier)
        local className = TierToClass[tier]
        if not className then
            warn('[Quests] No class mapped for tier ' .. tostring(tier))
            return
        end

        if not Persist.classBeforeSwitch then
            local profile = Profile:GetProfile(plr)
            Persist.classBeforeSwitch = profile and profile.Class and profile.Class.Value
        end

        -- Step 1: Switch to the required class (with verification)
        if not Persist.tierClassSwitched then
            Persist.tierClassSwitched = true
            local switchRemote = getRemote('Profile_SwitchClass')
            if switchRemote then
                switchRemote:FireServer(className)
            end

            -- Wait and verify the class actually switched
            local maxWaits = 20
            for i = 1, maxWaits do
                task.wait(0.5)
                local profile = Profile:GetProfile(plr)
                if profile and profile.Class and profile.Class.Value == className then
                    break  -- Class switched successfully
                end
            end
        end

        -- Step 2: Run the dungeon (will be re-invoked after restart)
        FireRaidIfNeeded(1, 5)
    end

    local DungeonWithClassHandlers = {}
    DungeonWithClassHandlers[2] = function(questData, amount)
        DungeonWithClassHandler(questData, amount, 2)
    end
    DungeonWithClassHandlers[3] = function(questData, amount)
        DungeonWithClassHandler(questData, amount, 3)
    end
    DungeonWithClassHandlers[4] = function(questData, amount)
        DungeonWithClassHandler(questData, amount, 4)
    end

    -- DoDungeonWithWorldAndDifficulty support
    local function DungeonWorldWithDifficultyHandler(questData, amount, difficulty)
        local raid = questData.LinkedWorld and DungeonWorldRaid[questData.LinkedWorld]
        if raid then
            FireRaidIfNeeded(raid[1], difficulty)
        end
    end

    -- Random Nightmare Dungeon support
    local NightmareDungeonIds = {1005, 1006, 1007}
    local function RandomDungeonHandler(questData, amount, difficulty)
        local randomId = NightmareDungeonIds[math.random(1, #NightmareDungeonIds)]
        FireRaidIfNeeded(randomId, difficulty)
    end

    -- ========================================================
    -- CanHandle — check if we can handle this quest
    -- ========================================================
    local function CanHandle(questData, objective)
        local objType = objective[1]
        local args = objective[3] or {}

        if objType == "KillMob" or objType == "KillMobInWorld" or objType == "KillAnyMob" then
            return true
        elseif objType == "DoDungeonInWorld" then
            return questData.LinkedWorld ~= nil and DungeonWorldRaid[questData.LinkedWorld] ~= nil
        elseif objType == "DoDungeon" then
            local dungeonId = args[1]
            return dungeonId ~= nil and DungeonIdHandlers[dungeonId] ~= nil
        elseif objType == "CompleteWorldEvent" then
            return questData.LinkedWorld ~= nil and WorldEventHandlers[questData.LinkedWorld] ~= nil
        elseif objType == "TimeInWorld" then
            return true
        elseif objType == "CustomEvent" then
            local key = args[1]
            return key ~= nil and CustomEventHandlers[key] ~= nil
        elseif objType == "DoDungeonWithClass" then
            local tier = args[1]
            return tier ~= nil and DungeonWithClassHandlers[tier] ~= nil
        elseif objType == "DoDungeonWithWorldAndDifficulty" then
            return questData.LinkedWorld ~= nil and DungeonWorldRaid[questData.LinkedWorld] ~= nil
        elseif objType == "DoRandomDungeonWithDifficulty" then
            return true
        elseif objType == "DoTowerFloor" then
            return true  -- Tower support
        end

        return false
    end

    -- ========================================================
    -- DISPATCHER
    -- ========================================================
    local function RunHandlerFor(questData, objective, amount)
        local objType = objective[1]
        local args = objective[3] or {}

        if objType == "KillMob" or objType == "KillMobInWorld" then
            local mobName = args[1]
            return true, pcall(MobHandlerFor(mobName), questData, amount)

        elseif objType == "KillAnyMob" then
            return true, pcall(MobHandlerFor(nil), questData, amount)

        elseif objType == "DoDungeonInWorld" then
            local raid = questData.LinkedWorld and DungeonWorldRaid[questData.LinkedWorld]
            if raid then
                return true, pcall(FireRaidIfNeeded, raid[1], raid[2])
            end
            return false

        elseif objType == "DoDungeon" then
            local dungeonId = args[1]
            local diff = dungeonId and DungeonIdHandlers[dungeonId]
            if diff then
                return true, pcall(FireRaidIfNeeded, dungeonId, diff)
            end
            return false

        elseif objType == "CompleteWorldEvent" then
            local handler = questData.LinkedWorld and WorldEventHandlers[questData.LinkedWorld]
            if handler then
                return true, pcall(handler, questData, amount)
            end
            return false

        elseif objType == "TimeInWorld" then
            local hubId = args[1]
            return true, pcall(TimeInWorldHandler, questData, amount, hubId)

        elseif objType == "CustomEvent" then
            local key = args[1]
            local handler = key and CustomEventHandlers[key]
            if handler then
                return true, pcall(handler, questData, amount)
            end
            return false

        elseif objType == "DoDungeonWithClass" then
            local tier = args[1]
            local handler = tier and DungeonWithClassHandlers[tier]
            if handler then
                return true, pcall(handler, questData, amount)
            end
            return false

        elseif objType == "DoDungeonWithWorldAndDifficulty" then
            if questData.LinkedWorld and DungeonWorldRaid[questData.LinkedWorld] then
                return true, pcall(DungeonWorldWithDifficultyHandler, questData, amount, args[1])
            end
            return false

        elseif objType == "DoRandomDungeonWithDifficulty" then
            return true, pcall(RandomDungeonHandler, questData, amount, args[1])

        elseif objType == "DoTowerFloor" then
            return true, pcall(FireRaidIfNeeded, 38, nil)
        end

        return false
    end

    local function StopCurrentAction(questId, questData)
        if questData.Objective[1] == "DoDungeonWithClass" then
            if Persist.classBeforeSwitch then
                local switchRemote = getRemote('Profile_SwitchClass')
                if switchRemote then
                    switchRemote:FireServer(Persist.classBeforeSwitch)
                end
                Persist.classBeforeSwitch = nil
            end
            Persist.tierClassSwitched = nil
        elseif questData.Objective[1] == "CustomEvent" and questData.Objective[3] and questData.Objective[3][1] == "UpgradeCompleted" then
            UpgradeState.running = false
            local equipRemote = getRemote('Inventory_EquipItem')
            if equipRemote then
                if UpgradeState.savedPrimary then equipRemote:FireServer(UpgradeState.savedPrimary, EquipPrimary) end
                if UpgradeState.savedOffhand then equipRemote:FireServer(UpgradeState.savedOffhand, EquipOffhand) end
                if UpgradeState.savedArmor then equipRemote:FireServer(UpgradeState.savedArmor, EquipArmor) end
            end
        end
    end

    local function GetNextIncompleteQuest(questIds, isWeekly, weeklyData)
        local skippedNames = {}
        for _, questId in ipairs(questIds) do
            if not claimedQuestIds[questId] then
                local questData = GetQuestData(questId)
                if questData and not questData.Disabled then
                    local vipBlocked = false
                    if isWeekly then
                        local entry = GetWeeklyQuestEntry(weeklyData, questId)
                        if entry and entry.isVIP and not HasVIP then
                            vipBlocked = true
                        end
                    end

                    if vipBlocked then
                        table.insert(skippedNames, (questData.Name or tostring(questId)) .. ' (VIP required)')
                    else
                        local current, isDone, claimed = GetQuestStatus(questId, questData, isWeekly, weeklyData)
                        if current == nil then
                            -- status unknown this tick
                        elseif isDone then
                            if not claimed then
                                ClaimQuest(questId, isWeekly, questData.Name)
                            end
                        else
                            local objective = questData.Objective
                            if CanHandle(questData, objective) then
                                return questId, questData, current
                            else
                                table.insert(skippedNames, questData.Name or tostring(questId))
                            end
                        end
                    end
                end
            end
        end
        return nil, nil, nil, skippedNames
    end

    -- ========================================================
    -- MAIN LOOP
    -- ========================================================

    local runToken = 0
    local Running = false
    local CurrentQuestId = nil
    local CheckInterval = 2
    local lastSkippedKey = nil
    local StatusText = 'Idle'
    local statusNotification = nil

    local function DestroyStatusNotification()
        if statusNotification then
            pcall(function() statusNotification:Destroy() end)
            statusNotification = nil
        end
    end

    local function SetStatus(text)
        StatusText = text
        if statusNotification then
            local ok = pcall(function() statusNotification:ChangeDescription(text) end)
            if ok then return end
            statusNotification = nil
        end
        if not Library then
            warn('[Quests] Library was not passed to this module - persistent notification cannot be created.')
            return
        end
        local ok, result = pcall(function()
            return Library:Notify({
                Title = 'Current Quest',
                Description = text,
                Persist = true,
                Position = UDim2.new(1, -20, 1, -160),
                Size = UDim2.new(0, 320, 0, 90),
            })
        end)
        if ok then
            statusNotification = result
        else
            warn('[Quests] Library:Notify failed: ' .. tostring(result))
        end
    end

    Persist.firedQuestIds = Persist.firedQuestIds or {}
    local firedQuestIds = Persist.firedQuestIds
    local currentRunningMode = nil

    local function PickQuest(mode, onlyHot)
        if mode == 'Both' then
            local dIds = GetActiveDailyQuestIds(onlyHot)
            local weeklyData = GetWeeklyData()
            local wIds = GetActiveWeeklyQuestIds(weeklyData)

            local dQ, dData, dCur, dSkip
            if #dIds > 0 then
                dQ, dData, dCur, dSkip = GetNextIncompleteQuest(dIds, false)
            end
            dSkip = dSkip or {}

            local wQ, wData, wCur, wSkip
            if #wIds > 0 then
                wQ, wData, wCur, wSkip = GetNextIncompleteQuest(wIds, true, weeklyData)
            end
            wSkip = wSkip or {}

            if dQ then return dQ, dData, dCur, dSkip, 'Daily' end
            if wQ then return wQ, wData, wCur, wSkip, 'Weekly' end

            local merged = {}
            for _, n in ipairs(dSkip) do table.insert(merged, n) end
            for _, n in ipairs(wSkip) do table.insert(merged, n) end
            return nil, nil, nil, merged
        elseif mode == 'Daily' then
            local ids = GetActiveDailyQuestIds(onlyHot)
            local qId, qData, cur, skipped = GetNextIncompleteQuest(ids, false)
            return qId, qData, cur, skipped, mode
        else -- 'Weekly'
            local weeklyData = GetWeeklyData()
            local ids = GetActiveWeeklyQuestIds(weeklyData)
            local qId, qData, cur, skipped = GetNextIncompleteQuest(ids, true, weeklyData)
            return qId, qData, cur, skipped, mode
        end
    end

    local function RunLoop(mode, onlyHot)
        runToken += 1
        local myToken = runToken
        Running = true
        currentRunningMode = mode

        SetStatus('Starting ' .. mode .. ' quests' .. (onlyHot and ' (Hot only)' or '') .. '...')

        while Running and myToken == runToken do
            local questId, questData, current, skippedNames, activeSubMode = PickQuest(mode, onlyHot)

            if not questId then
                if skippedNames and #skippedNames > 0 then
                    local key = table.concat(skippedNames, ', ')
                    SetStatus('Waiting on: ' .. key)
                    if key ~= lastSkippedKey then
                        warn('[Quests] No handler yet for: ' .. key)
                        lastSkippedKey = key
                    end
                else
                    SetStatus(mode .. ' Quests: all done!')
                    if lastSkippedKey ~= 'DONE_' .. mode then
                        noti(mode .. ' Quests: all done!')
                        lastSkippedKey = 'DONE_' .. mode
                    end
                end
                task.wait(5)
            else
                lastSkippedKey = nil
                local objective = questData.Objective
                local amount = objective[2]

                CurrentQuestId = questId
                local lastRemaining = amount - (current or 0)
                SetStatus((questData.Name or tostring(questId)) .. ' — ' .. tostring(lastRemaining) .. ' left')

                local alwaysReinvoke = (objective[1] == "DoDungeonWithClass")
                local isFirstTime = not firedQuestIds[questId]

                if alwaysReinvoke or isFirstTime then
                    firedQuestIds[questId] = true
                    local handled, ok, err = RunHandlerFor(questData, objective, amount)
                    if not ok and handled then
                        warn('[Quests] Error running handler for "' .. tostring(questData.Name) .. '": ' .. tostring(err))
                    end
                end

                while Running and myToken == runToken do
                    local isWeekly = (activeSubMode == 'Weekly')
                    local weeklyData = isWeekly and GetWeeklyData() or nil
                    local newCurrent, isDone, claimed = GetQuestStatus(questId, questData, isWeekly, weeklyData)

                    if not Running or myToken ~= runToken then break end

                    -- Claim other finished quests opportunistically
                    if mode == 'Daily' or mode == 'Both' then
                        for _, otherId in ipairs(GetActiveDailyQuestIds(onlyHot)) do
                            if otherId ~= questId and not claimedQuestIds[otherId] then
                                local od = GetQuestData(otherId)
                                if od and not od.Disabled then
                                    local _, oDone, oClaimed = GetQuestStatus(otherId, od, false, nil)
                                    if oDone and not oClaimed then
                                        ClaimQuest(otherId, false, od.Name)
                                    end
                                end
                            end
                        end
                    end
                    if mode == 'Weekly' or mode == 'Both' then
                        local wData = isWeekly and weeklyData or GetWeeklyData()
                        for _, otherId in ipairs(GetActiveWeeklyQuestIds(wData)) do
                            if otherId ~= questId and not claimedQuestIds[otherId] then
                                local od = GetQuestData(otherId)
                                if od and not od.Disabled then
                                    local _, oDone, oClaimed = GetQuestStatus(otherId, od, true, wData)
                                    if oDone and not oClaimed then
                                        ClaimQuest(otherId, true, od.Name)
                                    end
                                end
                            end
                        end
                    end

                    if newCurrent == nil then
                        task.wait(CheckInterval)
                    elseif isDone then
                        pcall(StopCurrentAction, questId, questData)
                        if not claimed then
                            ClaimQuest(questId, isWeekly, questData.Name)
                        end
                        break
                    else
                        local remaining = amount - newCurrent
                        if remaining ~= lastRemaining then
                            lastRemaining = remaining
                            SetStatus((questData.Name or tostring(questId)) .. ' — ' .. tostring(remaining) .. ' left')
                        end
                        task.wait(CheckInterval)
                    end
                end
            end
        end

        if myToken == runToken then
            Running = false
            currentRunningMode = nil
            DestroyStatusNotification()
        end
    end

    local function StopQuests()
        Running = false
        runToken += 1
        currentRunningMode = nil
        if CurrentQuestId then
            local questData = GetQuestData(CurrentQuestId)
            if questData then
                pcall(StopCurrentAction, CurrentQuestId, questData)
            end
        end
        CurrentQuestId = nil
        DestroyStatusNotification()
    end

    -- ========================================================
    -- Quests Tab UI
    -- ========================================================

    task.spawn(function()
        while true do
            pcall(TryClaimDailyLogin)
            task.wait(60)
        end
    end)

    -- FIXED: Added toggle for "Only Hot (🔥)" quests
    QuestsMainTab:AddToggle('autoHotQuestsOnly', {
        Text = 'Only Hot (🔥) Daily',
        Tooltip = 'Complete only the Hot quests (slots 1-3) that count toward tier progression',
        Default = false,
        Callback = function(value)
            Toggles.autoHotQuestsOnly.Value = value
        end,
    })

    QuestsMainTab:AddToggle('autoBothQuests', {
        Text = 'Complete All',
        Tooltip = 'Works through your Daily quests first, then automatically moves on to Weekly once Daily is done',
        Default = false,
        Callback = function(value)
            if value then
                if currentRunningMode == 'Both' then return end
                if Toggles.autoDailyQuests and Toggles.autoDailyQuests.Value then Toggles.autoDailyQuests:SetValue(false) end
                if Toggles.autoWeeklyQuests and Toggles.autoWeeklyQuests.Value then Toggles.autoWeeklyQuests:SetValue(false) end
                local onlyHot = Toggles.autoHotQuestsOnly and Toggles.autoHotQuestsOnly.Value
                task.spawn(RunLoop, 'Both', onlyHot)
            else
                if currentRunningMode == 'Both' then StopQuests() end
            end
        end,
    })

    QuestsMainTab:AddDivider()

    QuestsMainTab:AddToggle('autoDailyQuests', {
        Text = 'Complete Daily',
        Default = false,
        Callback = function(value)
            if value then
                if currentRunningMode == 'Daily' then return end
                if Toggles.autoWeeklyQuests and Toggles.autoWeeklyQuests.Value then Toggles.autoWeeklyQuests:SetValue(false) end
                if Toggles.autoBothQuests and Toggles.autoBothQuests.Value then Toggles.autoBothQuests:SetValue(false) end
                local onlyHot = Toggles.autoHotQuestsOnly and Toggles.autoHotQuestsOnly.Value
                task.spawn(RunLoop, 'Daily', onlyHot)
            else
                if currentRunningMode == 'Daily' then StopQuests() end
            end
        end,
    })

    QuestsMainTab:AddToggle('autoWeeklyQuests', {
        Text = 'Complete Weekly',
        Default = false,
        Callback = function(value)
            if value then
                if currentRunningMode == 'Weekly' then return end
                if Toggles.autoDailyQuests and Toggles.autoDailyQuests.Value then Toggles.autoDailyQuests:SetValue(false) end
                if Toggles.autoBothQuests and Toggles.autoBothQuests.Value then Toggles.autoBothQuests:SetValue(false) end
                task.spawn(RunLoop, 'Weekly', false)
            else
                if currentRunningMode == 'Weekly' then StopQuests() end
            end
        end,
    })
end)()
