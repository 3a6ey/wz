-- ============================================================
-- QUESTS MODULE
-- ============================================================
-- Load this separately from your main script, e.g.:
--   loadstring(game:HttpGet('YOUR_RAW_URL_HERE'))(plr, rs, Window, Tabs, Toggles, noti, Library)
--
-- Needs `Library` now too (in addition to the usual args) so it can
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

local Quests = require(game.ReplicatedStorage.Shared.Quests)
local Profile = require(game.ReplicatedStorage.Shared.Profile)
local Items = require(game.ReplicatedStorage.Shared.Items)

Tabs.Quests = Window:AddTab('Quests', 'scroll-text')
local QuestsTabbox = Tabs.Quests:AddLeftTabbox('questsBox')
local QuestsMainTab = QuestsTabbox:AddTab('Quests')

-- Quests Tab
;(function()
    local function GetMyProfile()
        return Profile:GetProfile(plr)
    end

    local function GetQuestData(questId)
        return Quests:GetQuestDataFromID(questId)
    end

    -- IMPORTANT: the 2nd return value here is NOT "is this quest done" -
    -- it's "has the reward already been claimed" (confirmed straight from
    -- the game's own quest GUI script: `value, claimed = GetQuestProgress(...)`).
    -- "Done" is determined by comparing `value` against the quest's
    -- required amount (Objective[2]) yourself - see GetQuestStatus below.
    local function GetProgress(questId)
        return Quests:GetQuestProgress(plr, questId)
    end

    -- {questId, questId, ...} in slot order (Slot1..Slot10)
    local function GetActiveDailyQuestIds()
        local profile = GetMyProfile()
        if not profile then return {} end
        local raw = Quests:GetDailyQuests(profile) -- {[slot] = questId}
        local ids = {}
        for slot = 1, 10 do
            if raw[slot] then
                table.insert(ids, raw[slot])
            end
        end
        return ids
    end

    -- ========================================================
    -- VIP gamepass check (id 8136226, per roblox.com/game-pass/8136226/VIP)
    -- --------------------------------------------------------
    -- Weekly quests can be flagged isVIP=true in the payload from
    -- Quests_GetWeeklyQuestData - if you don't own the VIP gamepass, we
    -- skip those entirely instead of wasting time working on/claiming
    -- something that's gated behind it. Checked once and cached, since
    -- gamepass ownership doesn't change mid-session (short of buying it
    -- right now, which is rare enough not to worry about re-checking).
    -- ========================================================
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

    -- Fetches the full Weekly quest payload once. IMPORTANT: Weekly quests
    -- do NOT use GetQuestProgress at all - the real game GUI reads
    -- progress/claimed straight off this payload's per-quest {id, value,
    -- claimed, isVIP} entries instead. We fetch this once per loop pass
    -- and reuse it for both the id list AND progress checks, to stay
    -- consistent and avoid extra InvokeServer calls.
    local function GetWeeklyData()
        local ok, data = pcall(function()
            return rs.Quests_GetWeeklyQuestData:InvokeServer()
        end)
        if ok then return data end
        return nil
    end

    -- Skips VIP-flagged quests entirely if you don't own the gamepass -
    -- they won't show up as pickable OR claimable for you.
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

    -- Persisted via getgenv() so state (like per-quest "already fired"
    -- flags, or a class you switched away from) survives a script
    -- restart. Entering a dungeon is a REAL Roblox place teleport, which
    -- fully destroys and reloads this whole script - a plain local
    -- variable can't survive that, but getgenv() can (your main script
    -- already relies on this elsewhere). Declared early so every
    -- function below can use it.
    getgenv().QuestsPersist = getgenv().QuestsPersist or {}
    local Persist = getgenv().QuestsPersist

    -- Tracks which questIds we've already claimed this session (whether we
    -- claimed them ourselves or they were already claimed by the time we
    -- checked - e.g. you claimed it manually in the UI). Once a quest is
    -- in here we never touch or notify about it again this session.
    local claimedQuestIds = {}

    -- ========================================================
    -- Daily Login rewards (the LEFT-side tier track on the Daily tab,
    -- separate from the quest rewards on the right).
    -- --------------------------------------------------------
    -- The real game UI claims these through the Profile module itself,
    -- not a raw remote call directly - GetCurrentDailyLogin returns
    -- (currentStreak, claimedUpTo), and AwardDailyLoginReward(plr)
    -- claims whatever's newly available. The same call works for every
    -- tier - the server figures out which one(s) based on those two
    -- numbers, so we just loop it while there's a gap to close.
    -- ========================================================
    local function TryClaimDailyLogin()
        for _ = 1, 5 do -- at most 5 tiers exist, so this can never loop forever
            local ok, current, claimedUpTo = pcall(function()
                return Profile:GetCurrentDailyLogin(plr)
            end)
            if not ok then
                warn('[Quests] Failed to check Daily Login status: ' .. tostring(current))
                return
            end
            if not (current and claimedUpTo and claimedUpTo < current) then
                break -- nothing left to claim
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

    -- Unified status check for both Daily and Weekly quests.
    -- Returns: current progress, whether it's reached the target amount,
    -- and whether the reward's already been claimed.
    -- IMPORTANT: for Weekly quests, if the data fetch fails or the quest
    -- entry can't be found this tick, we return nil (unknown) instead of
    -- guessing "0/not done" - a failed InvokeServer shouldn't make an
    -- already-finished-and-claimed quest look incomplete again.
    local function GetQuestStatus(questId, questData, isWeekly, weeklyData)
        local required = questData.Objective[2]
        local current, claimed

        if isWeekly then
            local entry = GetWeeklyQuestEntry(weeklyData, questId)
            if not entry then
                return nil, nil, nil -- unknown this tick, don't guess
            end
            if entry.isVIP and not HasVIP then
                -- defense in depth: even if this id somehow made it past
                -- GetActiveWeeklyQuestIds' filtering, never treat a
                -- VIP-gated quest as workable/claimable without VIP
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

    -- Claims the reward for a finished quest. If it's a Weekly quest,
    -- also tries to claim the Weekly Progress (points/tier) reward,
    -- since finishing a weekly quest is what unlocks those.
    local function ClaimQuest(questId, isWeekly, questName)
        if claimedQuestIds[questId] then return end
        claimedQuestIds[questId] = true

        -- Also clear the "already fired" marker for this id now that
        -- it's done - quest ids get recycled from a shared pool, so if
        -- we left this marked forever, a LATER unrelated quest that
        -- happens to reuse the same numeric id would silently never
        -- have its handler run (it would look "already fired").
        if Persist.firedQuestIds then
            Persist.firedQuestIds[questId] = nil
        end

        rs.Quests_ClaimQuest:FireServer(questId)
        noti((questName or tostring(questId)) .. ' — claimed!')

        if isWeekly then
            pcall(function()
                rs.Quests_ClaimWeeklyReward:FireServer()
            end)
        end
    end

    -- ========================================================
    -- HANDLERS — THIS IS WHERE YOU PUT YOUR OWN CODE
    -- --------------------------------------------------------
    -- Quests are matched by CONTENT, not by their numeric ID
    -- (the game randomly assigns IDs from a big pool, so a fixed
    -- id -> handler map doesn't work). Each table below is keyed
    -- by whatever actually identifies the quest: mob name, world
    -- number, dungeon id, or custom event key.
    --
    -- IMPORTANT - why this uses game.PlaceId instead of `mission`:
    -- entering a dungeon actually teleports you to a DIFFERENT
    -- Roblox Place (each dungeon has its own PlaceId in your
    -- missionList), which fully restarts your whole script (since
    -- you have autoload on). That wipes any in-memory "already
    -- fired" tracking. game.PlaceId, on the other hand, is always
    -- instantly accurate the moment the script starts on the new
    -- place - no timing races, no dependency on HUD/GUI state -
    -- so every raid-firing handler checks it directly before
    -- firing, and skips firing if you're already on that dungeon's
    -- place.
    -- ========================================================

    -- Dungeon id -> Roblox PlaceId, pulled from your missionList
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

    -- Fires StartRaid(raidId, difficulty), but ONLY if you're not already
    -- sitting in that exact mission. Two checks, either one is enough:
    --   1) workspace:GetAttribute("MissionId") == raidId - the server sets
    --      this the moment a mission starts, and it reflects the mission
    --      SLOT id (so this works for Nightmare Portal dungeons too, even
    --      though their underlying dungeon rotates and has no fixed PlaceId)
    --   2) game.PlaceId matches this raid's known static PlaceId (for
    --      regular dungeons where we know the PlaceId ahead of time)
    -- This is what makes re-toggling / script restarts safe - no duplicate
    -- teleports, no getting stuck re-firing the same raid every restart.
    local function FireRaidIfNeeded(raidId, difficulty)
        local ok, currentMissionId = pcall(function()
            return workspace:GetAttribute("MissionId")
        end)
        if ok and currentMissionId ~= nil and tostring(currentMissionId) == tostring(raidId) then
            return -- already in this exact mission
        end

        local targetPlaceId = DungeonPlaceIds[raidId]
        if targetPlaceId and tostring(game.PlaceId) == tostring(targetPlaceId) then
            return -- already on this dungeon's place, do nothing
        end

        StartRaid(raidId, difficulty)
    end

    -- KillMob / KillMobInWorld / KillAnyMob
    -- Objective args = list of mob names that count (usually 1).
    -- Keyed by mob name -> {raidId, difficulty}
    local MobRaid = {}
    MobRaid["Boarwolf"] = {2, 5}
    MobRaid["EliteBoarwolf"] = {2, 5}
    MobRaid["Toucan"] = {3, 5}
    MobRaid["EarthCrab"] = {4, 5}
    MobRaid["ElectricCrab"] = {4, 5}
    MobRaid["FireCrab"] = {4, 5}
    MobRaid["GrassCobra"] = {3, 5} -- Scarecrow Defense (1-2), Challenge
    MobRaid["PoisonCobra"] = {3, 5} -- Scarecrow Defense (1-2), Challenge
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
                FireRaidIfNeeded(38, nil) -- Infinite Tower fallback, counts any kill
            end
        end
    end

    -- DoDungeonInWorld -> "finish any dungeon in World X"
    -- Keyed by LinkedWorld -> {raidId, difficulty}
    local DungeonWorldRaid = {
        [1] = {1, 5},
        [2] = {11, 5},
        [3] = {15, 1},
        [4] = {18, 5},
        -- TODO: add 5,6,7,8,9,10 etc as you go
    }

    -- DoDungeon -> "defeat dungeon '<Name>' at any difficulty"
    -- Objective args = {dungeonId}. Keyed by dungeon id -> difficulty to
    -- send with StartRaid. Challenge (5) picked as default since it's
    -- generally faster/better rewards - change any of these to 1 (Normal)
    -- if you'd rather play it safe on a specific one.
    local DungeonIdHandlers = {}
    DungeonIdHandlers[1] = 5   -- Crabby Crusade (1-1)
    DungeonIdHandlers[3] = 5   -- Scarecrow Defense (1-2)
    DungeonIdHandlers[2] = 5   -- Dire Problem (1-3)
    DungeonIdHandlers[4] = 5   -- Kingslayer (1-4)
    DungeonIdHandlers[6] = 5   -- Gravetower Dungeon (1-5)
    DungeonIdHandlers[11] = 5  -- Temple of Ruin (2-1)
    DungeonIdHandlers[12] = 5  -- Mama Trauma (2-2)
    DungeonIdHandlers[13] = 5  -- Volcano's Shadow (2-3)
    DungeonIdHandlers[7] = 5   -- Volcano Dungeon (2-4)
    DungeonIdHandlers[14] = 5  -- Mountain Pass (3-1)
    DungeonIdHandlers[15] = 5  -- Winter Cavern (3-2)
    DungeonIdHandlers[16] = 5  -- Winter Dungeon (3-3)
    DungeonIdHandlers[20] = 5  -- Scrap Canyon (4-1)
    DungeonIdHandlers[19] = 5  -- Deserted Burrowmine (4-2)
    DungeonIdHandlers[18] = 5  -- Pyramid Dungeon (4-3)
    DungeonIdHandlers[24] = 5  -- Konoh Heartlands (5-1)
    DungeonIdHandlers[35] = 5  -- Konoh Inferno (5-2)
    DungeonIdHandlers[25] = 5  -- Rough Waters (6-1)
    DungeonIdHandlers[36] = 5  -- Treasure Hunt (6-2)
    DungeonIdHandlers[26] = 5  -- The Underworld (7-1)
    DungeonIdHandlers[37] = 5  -- The Labyrinth (7-2)
    DungeonIdHandlers[30] = 5  -- Rescue in the Ruins (8-1)
    DungeonIdHandlers[31] = 5  -- Ruin Rush (8-2)
    DungeonIdHandlers[32] = 5  -- Treetop Trouble (9-1)
    DungeonIdHandlers[33] = 5  -- Aether Fortress (9-2)
    DungeonIdHandlers[41] = 5  -- Crystal Chaos (10-1)
    DungeonIdHandlers[42] = 5  -- Astral Academy (10-2)

    -- CompleteWorldEvent -> keyed by LinkedWorld (doing these later per your note)
    local WorldEventHandlers = {}
    -- WorldEventHandlers[1] = function(questData, amount) -- TODO end
    -- WorldEventHandlers[2] = function(questData, amount) -- TODO end
    -- WorldEventHandlers[3] = function(questData, amount) -- TODO end
    -- WorldEventHandlers[4] = function(questData, amount) -- TODO end
    -- WorldEventHandlers[5] = function(questData, amount) -- TODO end
    -- WorldEventHandlers[6] = function(questData, amount) -- TODO end
    -- WorldEventHandlers[7] = function(questData, amount) -- TODO end
    -- WorldEventHandlers[9] = function(questData, amount) -- TODO end

    -- TimeInWorld -> "fight in the PvP Arena for 10 min" and similar.
    -- Objective args = {hubId}. Generic handler: teleport to that hub
    -- and just stay there, progress ticks up on its own.
    local function TimeInWorldHandler(questData, amount, hubId)
        if hubId then
            rs.Teleport_TeleportToHub:FireServer(hubId)
        end
    end

    -- ========================================================
    -- "Upgrade items 10 times" quest support
    -- --------------------------------------------------------
    -- Same folder paths your main script already uses for equips
    -- (ReplicatedStorage.PlayerEquips[you].Primary/Offhand/Armor) and the
    -- exact same upgrade-loop logic you gave me for "Upgrade Equipped
    -- Items" - just pointed at whatever random equippable item we found
    -- in your inventory instead of always the currently-equipped one.
    -- No place teleport happens for this quest, so a plain local table
    -- is fine here (doesn't need getgenv() persistence).
    -- ========================================================
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

    -- Exact loop from your "Upgrade Equipped Items" button, just reused
    -- on whatever item we hand it - upgrades until maxed, or until 2
    -- seconds pass with no gold spent (means it's stuck/capped).
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
                rs.ItemUpgrade_Upgrade:FireServer(item)
                if goldValue.Value ~= oldGold then
                    oldGold = goldValue.Value
                    timer = tick()
                end
                if tick() - timer >= 2 then break end
            end
        end
    end

    -- Any weapon or armor in your inventory that still has upgrade room
    -- left - doesn't have to be the best one, just any equippable item
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

    -- CustomEvent -> Objective args = {eventKey}. Keyed by that key.
    local CustomEventHandlers = {}

    CustomEventHandlers["UpgradeCompleted"] = function(questData, amount)
        if UpgradeState.running then return end
        UpgradeState.running = true

        -- remember what's currently equipped so it can go back on after
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
                rs.Inventory_EquipItem:FireServer(item, targetFolder)
                task.wait(0.5) -- give the equip a moment to register

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
                rs.Pets_BuyEgg:FireServer("StarEgg", "Gold")
                task.wait(0.3) -- small gap between buys so the server has time to process each one
            end
        end)
    end
    -- CustomEventHandlers["DuelCompleted"] = function(questData, amount)
    --     -- TODO: your script goes here
    -- end
    CustomEventHandlers["CompletedInfiniteTowerFloor"] = function(questData, amount)
        FireRaidIfNeeded(38, nil)
    end

    -- DoDungeonWithClass -> Objective args = {classTier}. Need to be playing
    -- a class of that tier when clearing ANY dungeon - any dungeon counts,
    -- so we just use World 1's (the simplest/fastest one) rather than
    -- needing to be in any specific world first.
    -- Fill in more tiers as you figure out which class belongs to each.
    --
    -- IMPORTANT: entering a dungeon fully restarts this script (it's a real
    -- place teleport), so a plain local variable can't survive long enough
    -- to remember your original class by the time the quest finishes and
    -- we need to switch back. getgenv() persists across that restart (your
    -- main script already relies on this elsewhere), so we store state
    -- there instead.
    local TierToClass = {
        [2] = "IcefireMage",
        [4] = "Archer",
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

        -- Staged flow, since teleporting to World 3 is a REAL place
        -- teleport that fully restarts this script mid-function - code
        -- after it in the SAME call would never run. Each stage is
        -- gated by its own Persist(getgenv) flag so it only fires once,
        -- and RunLoop calls this handler on every pass for this quest
        -- type specifically (see the `alwaysReinvoke` check there) so
        -- the NEXT script instance (after the restart) can pick up and
        -- advance to the next stage.
        if not Persist.tierClassHubSent then
            Persist.tierClassHubSent = true
            rs.Teleport_TeleportToHub:FireServer(20) -- World 3 hub
            return -- script restarts here; next call continues below
        end

        if not Persist.tierClassSwitched then
            Persist.tierClassSwitched = true
            rs.Profile_SwitchClass:FireServer(className)
            task.wait(1) -- give the switch a moment to register before entering a dungeon
        end

        FireRaidIfNeeded(1, 5) -- World 1's dungeon - simplest, any dungeon counts for this quest type
    end

    local DungeonWithClassHandlers = {}
    DungeonWithClassHandlers[2] = function(questData, amount)
        DungeonWithClassHandler(questData, amount, 2)
    end
    DungeonWithClassHandlers[4] = function(questData, amount)
        DungeonWithClassHandler(questData, amount, 4)
    end

    -- DoDungeonWithWorldAndDifficulty -> "Complete N Challenge Dungeons in World X"
    -- Objective args = {requiredDifficulty}. Reuses the same dungeon id as
    -- DoDungeonInWorld for that world, just fired with the SPECIFIC
    -- difficulty this quest asks for instead of the world's default one -
    -- works for any world already listed in DungeonWorldRaid above without
    -- needing a separate entry per world.
    local function DungeonWorldWithDifficultyHandler(questData, amount, difficulty)
        local raid = questData.LinkedWorld and DungeonWorldRaid[questData.LinkedWorld]
        if raid then
            FireRaidIfNeeded(raid[1], difficulty)
        end
    end

    -- DoRandomDungeonWithDifficulty -> "Complete any Dungeon from the
    -- Nightmare Portals". These are the 3 rotating Nightmare Dungeon ids
    -- from your main script's Nightmare Dungeons buttons - any one of
    -- them counts, so just pick one at random.
    local NightmareDungeonIds = {1005, 1006, 1007}
    local function RandomDungeonHandler(questData, amount, difficulty)
        local randomId = NightmareDungeonIds[math.random(1, #NightmareDungeonIds)]
        FireRaidIfNeeded(randomId, difficulty)
    end

    -- ========================================================
    -- CanHandle — a "dry run" check: does this quest's content
    -- have a handler written for it? Used to pick which quest to
    -- work on next (see GetNextIncompleteQuest below).
    -- ========================================================
    local function CanHandle(questData, objective)
        local objType = objective[1]
        local args = objective[3] or {}

        if objType == "KillMob" or objType == "KillMobInWorld" or objType == "KillAnyMob" then
            return true -- always covered, falls back to Infinite Tower
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
        end

        return false
    end

    -- ========================================================
    -- DISPATCHER — routes each quest to the right handler above
    -- based on its Objective type + content. You shouldn't need
    -- to touch this, just fill in the *Handlers/*Raid tables above.
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
        end

        return false
    end

    -- Called once a quest is finished — turn off whatever your
    -- handler turned on here (e.g. your mob farm toggle)
    local function StopCurrentAction(questId, questData)
        if questData.Objective[1] == "DoDungeonWithClass" then
            -- Restore whatever class you were playing before this quest
            -- switched it. Read through Persist (getgenv()) since this can
            -- run in a freshly-restarted script after the dungeon teleport.
            -- No hub teleport needed - leaving the dungeon already returns
            -- you to a hub on its own.
            if Persist.classBeforeSwitch then
                rs.Profile_SwitchClass:FireServer(Persist.classBeforeSwitch)
                Persist.classBeforeSwitch = nil
            end
            -- reset the staged flow so the NEXT Tier-class quest (this
            -- one again later, or a different tier) starts fresh
            Persist.tierClassHubSent = nil
            Persist.tierClassSwitched = nil
        elseif questData.Objective[1] == "CustomEvent" and questData.Objective[3] and questData.Objective[3][1] == "UpgradeCompleted" then
            -- Stop the upgrade loop and put your original gear back on
            UpgradeState.running = false
            if UpgradeState.savedPrimary then rs.Inventory_EquipItem:FireServer(UpgradeState.savedPrimary, EquipPrimary) end
            if UpgradeState.savedOffhand then rs.Inventory_EquipItem:FireServer(UpgradeState.savedOffhand, EquipOffhand) end
            if UpgradeState.savedArmor then rs.Inventory_EquipItem:FireServer(UpgradeState.savedArmor, EquipArmor) end
        end
    end

    -- Grabs the first quest in the list that isn't finished yet AND has a
    -- real handler for its content. Quests with no handler (still a TODO)
    -- get skipped so the bot doesn't get stuck waiting on them forever -
    -- it keeps looking further down the list instead of retrying the
    -- same unhandled quest over and over.
    -- Along the way it also claims anything that's already done but
    -- hasn't been claimed yet (in case it finished on its own).
    local function GetNextIncompleteQuest(questIds, isWeekly, weeklyData)
        local skippedNames = {}
        for _, questId in ipairs(questIds) do
            if not claimedQuestIds[questId] then
                local questData = GetQuestData(questId)
                if questData and not questData.Disabled then
                    -- check VIP-gating explicitly here so it shows up as a
                    -- clear, named skip reason instead of silently vanishing
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
                            -- status unknown this tick (e.g. weekly data fetch failed) -
                            -- don't guess, just skip it for this pass
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

    -- ========================================================
    -- PERSISTENT STATUS NOTIFICATION
    -- --------------------------------------------------------
    -- One single notification (Persist = true) that stays on screen
    -- and updates its text live via :ChangeDescription() as progress
    -- changes - instead of a stream of separate toast popups that each
    -- fade away on their own. Recreated fresh each time a mode toggle
    -- starts (since the whole GUI - including any open notification -
    -- gets rebuilt from scratch if the script restarts from a dungeon
    -- teleport), and destroyed when quests are stopped.
    -- ========================================================
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
            statusNotification = nil -- stale reference, fall through and recreate
        end
        local ok, result = pcall(function()
            return Library:Notify({
                Title = 'Quests',
                Description = text,
                Persist = true,
            })
        end)
        if ok then
            statusNotification = result
        end
    end

    -- Persisted via getgenv() so this survives a dungeon-forced script
    -- restart - otherwise a quest whose handler already fired (e.g. it
    -- already switched class and entered a dungeon) would look "not
    -- fired yet" again after the restart and re-run its whole start
    -- sequence while you're still mid-dungeon.
    Persist.firedQuestIds = Persist.firedQuestIds or {}
    local firedQuestIds = Persist.firedQuestIds
    local currentRunningMode = nil -- 'Daily' | 'Weekly' | 'Both' | nil

    -- Picks the next quest to work on. In 'Both' mode, BOTH pools get
    -- scanned every cycle (so completed Weekly quests get claimed even
    -- while Daily is still in progress, and vice versa) - Daily just
    -- gets priority for what to actively WORK ON when both have
    -- something available.
    local function PickQuest(mode)
        if mode == 'Both' then
            local dIds = GetActiveDailyQuestIds()
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
            local ids = GetActiveDailyQuestIds()
            local qId, qData, cur, skipped = GetNextIncompleteQuest(ids, false)
            return qId, qData, cur, skipped, mode
        else -- 'Weekly'
            local weeklyData = GetWeeklyData()
            local ids = GetActiveWeeklyQuestIds(weeklyData)
            local qId, qData, cur, skipped = GetNextIncompleteQuest(ids, true, weeklyData)
            return qId, qData, cur, skipped, mode
        end
    end

    local function RunLoop(mode)
        runToken += 1
        local myToken = runToken
        Running = true
        currentRunningMode = mode
        -- NOT resetting firedQuestIds here anymore - it's persisted via
        -- Persist (getgenv()) so it survives dungeon-forced restarts. If
        -- we reset it every RunLoop start, that protection would be
        -- pointless (a restart also re-triggers this function).

        while Running and myToken == runToken do
            local questId, questData, current, skippedNames, activeSubMode = PickQuest(mode)

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

                -- DoDungeonWithClass manages its own staged, restart-safe
                -- firing internally (via Persist/getgenv flags per step),
                -- so it needs to be called on every pass to advance to the
                -- next stage after a script restart - it can't rely on the
                -- one-shot firedQuestIds gate like other handlers do.
                local alwaysReinvoke = (objective[1] == "DoDungeonWithClass")
                local isFirstTime = not firedQuestIds[questId]

                if alwaysReinvoke or isFirstTime then
                    -- Note: for raid quests, FireRaidIfNeeded ALSO checks
                    -- game.PlaceId itself, so even a fresh script restart
                    -- (after being teleported into the dungeon's own Place)
                    -- won't re-fire once you're actually there - this flag
                    -- is just an extra safety net for non-raid handlers
                    -- (like egg hatching) within one run.
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

                    -- bail out cleanly if we were stopped during the wait below,
                    -- without firing any "quest complete" side effects
                    if not Running or myToken ~= runToken then break end

                    if newCurrent == nil then
                        -- status unknown this tick (e.g. weekly fetch failed) -
                        -- don't treat this as "not done", just wait and retry
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
    -- Quests Tab — Both first (recommended default), then a divider,
    -- then Daily and Weekly for running them individually.
    -- ========================================================

    -- Check/claim Daily Login rewards passively in the background,
    -- regardless of which quest toggle (if any) is on.
    task.spawn(function()
        while true do
            pcall(TryClaimDailyLogin)
            task.wait(60)
        end
    end)

    QuestsMainTab:AddToggle('autoBothQuests', {
        Text = 'Complete All',
        Tooltip = 'Works through your Daily quests first, then automatically moves on to Weekly once Daily is done',
        Default = false,
        Callback = function(value)
            if value then
                if currentRunningMode == 'Both' then return end -- already running, ignore duplicate click
                if Toggles.autoDailyQuests and Toggles.autoDailyQuests.Value then Toggles.autoDailyQuests:SetValue(false) end
                if Toggles.autoWeeklyQuests and Toggles.autoWeeklyQuests.Value then Toggles.autoWeeklyQuests:SetValue(false) end
                task.spawn(RunLoop, 'Both')
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
                task.spawn(RunLoop, 'Daily')
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
                task.spawn(RunLoop, 'Weekly')
            else
                if currentRunningMode == 'Weekly' then StopQuests() end
            end
        end,
    })
end)()
