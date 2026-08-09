-- ============================================================
-- QUESTS MODULE
-- ============================================================
-- Load this separately from your main script, e.g.:
--   loadstring(game:HttpGet('YOUR_RAW_URL_HERE'))(plr, rs, Window, Tabs, Toggles, noti)
--
-- It's loaded as its own chunk so it doesn't add to your main
-- script's local variable count (avoids "Out of local registers").
-- This module creates its own Tabs.Quests tab and tabbox - you
-- don't need to declare anything for it in your main script.
-- ============================================================

local plr, rs, Window, Tabs, Toggles, noti = ...

local Quests = require(game.ReplicatedStorage.Shared.Quests)
local Profile = require(game.ReplicatedStorage.Shared.Profile)

Tabs.Quests = Window:AddTab('Quests', 'scroll-text')
local QuestsTabbox = Tabs.Quests:AddLeftTabbox('questsBox')
local DailyQuestsTab = QuestsTabbox:AddTab('Daily')
local WeeklyQuestsTab = QuestsTabbox:AddTab('Weekly')

-- Quests Tab
;(function()
    local function GetMyProfile()
        return Profile:GetProfile(plr)
    end

    local function GetQuestData(questId)
        return Quests:GetQuestDataFromID(questId)
    end

    -- current, isCompleted
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

    -- {questId, questId, ...} in the order returned by GetWeeklyQuestData
    local function GetActiveWeeklyQuestIds()
        local data = rs.Quests_GetWeeklyQuestData:InvokeServer()
        local ids = {}
        if data and data.quests then
            for _, q in ipairs(data.quests) do
                table.insert(ids, q.id)
            end
        end
        return ids
    end

    -- Claims the reward for a finished quest
    local function ClaimQuest(questId)
        rs.Quests_ClaimQuest:FireServer(questId)
    end

    -- Grabs the first quest in the list that isn't finished yet.
    -- Along the way it also claims anything that's already done but
    -- hasn't been claimed yet (in case it finished on its own).
    local function GetNextIncompleteQuest(questIds)
        for _, questId in ipairs(questIds) do
            local questData = GetQuestData(questId)
            if questData and not questData.Disabled then
                local current, completed = GetProgress(questId)
                if completed then
                    ClaimQuest(questId)
                else
                    return questId, questData, current
                end
            end
        end
        return nil
    end

    -- ========================================================
    -- QUEST HANDLERS — THIS IS WHERE YOU PUT YOUR OWN CODE
    -- --------------------------------------------------------
    -- One questId = one block. Everything below is every quest
    -- that can actually show up in Daily / Weekly (checked
    -- against QuestList). Just drop your script inside the
    -- matching QuestHandlers["quest_id"] = function(questData, amount) ... end
    --
    -- questData -- the full quest table (Name, LinkedWorld, Objective...)
    -- amount    -- how much is needed (e.g. 30 cobras, 600 seconds, etc)
    --
    -- The function should just KICK OFF the action and return
    -- (e.g. flip on your farm toggle, teleport, whatever) - it should
    -- NOT block. The loop below handles waiting for progress and
    -- claiming the reward once GetQuestProgress says it's completed.
    -- ========================================================

    local QuestHandlers = {}

    -- ============================================================
    -- DAILY QUESTS
    -- ============================================================

    -- [daily_boarwolves] Defeat 30 Boarwolves in World 1
    -- Type: KillMob | Amount: 30 | Args: Boarwolf | World: 1
    QuestHandlers["daily_boarwolves"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(2, 5, nil)
    end

    -- [daily_w1we] Complete 1 World Event in World 1
    -- Type: CompleteWorldEvent | Amount: 1 | World: 1
    QuestHandlers["daily_w1we"] = function(questData, amount)
        -- TODO: your script goes here (world events - doing later)

    end

    -- [daily_toucans] Defeat 30 Toucans in World 1
    -- Type: KillMob | Amount: 30 | Args: Toucan | World: 1
    QuestHandlers["daily_toucans"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(3, 5, nil)
    end

    -- [daily_earthcrabs] Defeat 30 Crabs in World 1
    -- Type: KillMob | Amount: 30 | Args: EarthCrab, ElectricCrab, FireCrab | World: 1
    QuestHandlers["daily_earthcrabs"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(4, 5, nil)
    end

    -- [daily_cobras] Defeat 30 Cobras in World 1
    -- Type: KillMob | Amount: 30 | Args: GrassCobra, PoisonCobra | World: 1
    QuestHandlers["daily_cobras"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(1, 5, nil)
    end

    -- [daily_eliteboarwolves] Defeat 30 Alpha Boarwolves in World 1
    -- Type: KillMob | Amount: 30 | Args: EliteBoarwolf | World: 1
    QuestHandlers["daily_eliteboarwolves"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(2, 5, nil)
    end

    -- [daily_missionw1] Finish any dungeon in World 1
    -- Type: DoDungeonInWorld | Amount: 1 | World: 1
    QuestHandlers["daily_missionw1"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(1, 5, nil)
    end

    -- [daily_w2we] Complete 1 World Event in World 2
    -- Type: CompleteWorldEvent | Amount: 1 | World: 2
    QuestHandlers["daily_w2we"] = function(questData, amount)
        -- TODO: your script goes here (world events - doing later)

    end

    -- [daily_quillodiles] Defeat 30 Quillodiles in World 2
    -- Type: KillMob | Amount: 30 | Args: Quillodile | World: 2
    QuestHandlers["daily_quillodiles"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(12, 1, nil)
    end

    -- [daily_goblins] Defeat 30 Green Goblins in World 2
    -- Type: KillMob | Amount: 30 | Args: GoblinSpear, GoblinSlingshot, GoblinGatekeeper | World: 2
    QuestHandlers["daily_goblins"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(13, 1, nil)
    end

    -- [daily_redgoblins] Defeat 30 Red Goblins in World 2
    -- Type: KillMob | Amount: 30 | Args: RedGoblinSpear, RedGoblinSlingshot, RedGoblinGatekeeper | World: 2
    QuestHandlers["daily_redgoblins"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(13, 1, nil)
    end

    -- [daily_missionw2] Finish any dungeon in World 2
    -- Type: DoDungeonInWorld | Amount: 1 | World: 2
    QuestHandlers["daily_missionw2"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(11, 5, nil)
    end

    -- [daily_w3we] Complete 1 World Event in World 3
    -- Type: CompleteWorldEvent | Amount: 1 | World: 3
    QuestHandlers["daily_w3we"] = function(questData, amount)
        -- TODO: your script goes here (world events - doing later)

    end

    -- [daily_icygoos] Defeat 30 Icy Goos in World 3
    -- Type: KillMob | Amount: 30 | Args: IcyGoo | World: 3
    QuestHandlers["daily_icygoos"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(15, 1, nil)
    end

    -- [daily_snowraptors] Defeat 30 Snow Raptors in World 3
    -- Type: KillMob | Amount: 30 | Args: SnowRaptor | World: 3
    QuestHandlers["daily_snowraptors"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(15, 1, nil)
    end

    -- [daily_frostgolems] Defeat 20 Frost Golems in World 3
    -- Type: KillMob | Amount: 20 | Args: FrostGolem | World: 3
    QuestHandlers["daily_frostgolems"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(15, 1, nil)
    end

    -- [daily_missionw3] Finish any dungeon in World 3
    -- Type: DoDungeonInWorld | Amount: 1 | World: 3
    QuestHandlers["daily_missionw3"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(15, 1, nil)
    end

    -- [daily_w4we] Complete 1 World Event in World 4
    -- Type: CompleteWorldEvent | Amount: 1 | World: 4
    QuestHandlers["daily_w4we"] = function(questData, amount)
        -- TODO: your script goes here (world events - doing later)

    end

    -- [daily_happycactuses] Defeat 30 Happy Cacti in World 4
    -- Type: KillMob | Amount: 30 | Args: HappyCactus | World: 4
    QuestHandlers["daily_happycactuses"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(18, 5, nil)
    end

    -- [daily_goldensnakes] Defeat 30 Golden Cobras in World 4
    -- Type: KillMob | Amount: 30 | Args: GoldCobra | World: 4
    QuestHandlers["daily_goldensnakes"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(18, 5, nil)
    end

    -- [daily_rockgolems] Defeat 20 Rock Golems in World 4
    -- Type: KillMob | Amount: 20 | Args: RockGolem | World: 4
    QuestHandlers["daily_rockgolems"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(18, 5, nil)
    end

    -- [daily_missionw4] Finish any dungeon in World 4
    -- Type: DoDungeonInWorld | Amount: 1 | World: 4
    QuestHandlers["daily_missionw4"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(18, 5, nil)
    end

    -- [daily_w5we] Complete 1 World Event in World 5
    -- Type: CompleteWorldEvent | Amount: 1 | World: 5
    QuestHandlers["daily_w5we"] = function(questData, amount)
        -- TODO: your script goes here (world events - doing later)

    end

    -- [daily_pinkboarwolves] Defeat 30 Charged Boarwolves in World 5
    -- Type: KillMob | Amount: 30 | Args: PinkBoarwolf | World: 5
    QuestHandlers["daily_pinkboarwolves"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(24, 5, nil)
    end

    -- [daily_bluegoblins] Defeat 30 Blue Goblins in World 5
    -- Type: KillMob | Amount: 30 | Args: BlueGoblinSlingshot, BlueGoblinElite, BlueGoblinGatekeeper | World: 5
    QuestHandlers["daily_bluegoblins"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(24, 5, nil)
    end

    -- [daily_blossomtrees] Defeat 30 Blossom Trees in World 5
    -- Type: KillMob | Amount: 30 | Args: BlossomTree | World: 5
    QuestHandlers["daily_blossomtrees"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(24, 5, nil)
    end

    -- [daily_seaserpent] Defeat Sea Serpents in World 6
    -- Type: KillMob | Amount: 30 | Args: SeaSerpent | World: 6
    QuestHandlers["daily_seaserpent"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(36, 5, nil)
    end

    -- [daily_jellyfishslime] Defeat Jellyfish Slime in World 6
    -- Type: KillMob | Amount: 30 | Args: JellyfishSlime | World: 6
    QuestHandlers["daily_jellyfishslime"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(36, 5, nil)
    end

    -- [daily_parrot] Defeat Parrots in World 6
    -- Type: KillMob | Amount: 30 | Args: Parrot | World: 6
    QuestHandlers["daily_parrot"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(36, 5, nil)
    end

    -- [daily_goblingladiator] Defeat Gladiator Goblins in World 7
    -- Type: KillMob | Amount: 30 | Args: GoblinGladiator | World: 7
    QuestHandlers["daily_goblingladiator"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(37, 5, nil)
    end

    -- [daily_goblinspartan] Defeat Armored Goblins in World 7
    -- Type: KillMob | Amount: 25 | Args: GoblinSpartan | World: 7
    QuestHandlers["daily_goblinspartan"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(37, 5, nil)
    end

    -- [daily_kirin] Defeat Ki-Rins in World 7
    -- Type: KillMob | Amount: 30 | Args: Kirin | World: 7
    QuestHandlers["daily_kirin"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(37, 5, nil)
    end

    -- [daily_scorpiongold] Defeat Gilded Scorpions in World 7
    -- Type: KillMob | Amount: 30 | Args: ScorpionGold | World: 7
    QuestHandlers["daily_scorpiongold"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(37, 5, nil)
    end

    -- [daily_gargoyle] Defeat Red Gargoyles in World 7
    -- Type: KillMob | Amount: 30 | Args: Gargoyle | World: 7
    QuestHandlers["daily_gargoyle"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(26, 5, nil)
    end

    -- [daily_gargoyle2] Defeat Flaming Gargoyles in World 7
    -- Type: KillMob | Amount: 30 | Args: GargoyleGrey | World: 7
    QuestHandlers["daily_gargoyle2"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(26, 5, nil)
    end

    -- [daily_ruinguardian] Defeat Ruin Guardians in World 8
    -- Type: KillMob | Amount: 3 | Args: RuinGuardian | World: 8
    QuestHandlers["daily_ruinguardian"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(30, 5, nil)
    end

    -- [daily_alligator] Defeat Alligators in World 8
    -- Type: KillMob | Amount: 30 | Args: Alligator, Rapigator | World: 8
    QuestHandlers["daily_alligator"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(30, 5, nil)
    end

    -- [daily_w9we] Complete 1 World Event in World 9
    -- Type: CompleteWorldEvent | Amount: 1 | World: 9
    QuestHandlers["daily_w9we"] = function(questData, amount)
        -- TODO: your script goes here (world events - doing later)

    end

    -- [daily_dungeonPortal] Complete any Dungeon from the Nightmare Portals
    -- Type: DoRandomDungeonWithDifficulty | Amount: 1 | Args: difficulty 1
    QuestHandlers["daily_dungeonPortal"] = function(questData, amount)
        -- TODO: your script goes here

    end

    -- [daily_infiniteTower] Defeat 100 monsters in the Infinite Tower
    -- Type: KillAnyMob | Amount: 100
    QuestHandlers["daily_infiniteTower"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(38, nil, nil)
    end

    -- ============================================================
    -- WEEKLY QUESTS
    -- ============================================================

    -- [weekly_upgradeItem] Upgrade items 10 times
    -- Type: CustomEvent | Amount: 10 | Args: UpgradeCompleted
    QuestHandlers["weekly_upgradeItem"] = function(questData, amount)
        -- TODO: your script goes here

    end

    -- [weekly_collectArmor] Collect Equipment items from dungeons 15 times
    -- Type: CustomEvent | Amount: 15 | Args: CollectEquipmentInDungeon
    QuestHandlers["weekly_collectArmor"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(2, 5, nil)
    end

    -- [weekly_worldEvent] Complete any world event 5 times
    -- Type: CompleteWorldEvent | Amount: 5
    QuestHandlers["weekly_worldEvent"] = function(questData, amount)
        -- TODO: your script goes here (world events - doing later)

    end

    -- [weekly_hatchPet] Hatch 5 pet eggs
    -- Type: CustomEvent | Amount: 5 | Args: HatchPetEgg
    QuestHandlers["weekly_hatchPet"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Pets_BuyEgg
        for i = 1, 5 do
            Event:FireServer("StarEgg", "Gold")
        end
    end

    -- [weekly_doDungeons] Complete 10 dungeons of any difficulty
    -- Type: DoDungeonInWorld | Amount: 10
    QuestHandlers["weekly_doDungeons"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(1, 5, nil)
    end

    -- [weekly_anyMob] Defeat 2800 monsters in any world
    -- Type: KillAnyMob | Amount: 2800
    QuestHandlers["weekly_anyMob"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(38, nil, nil)
    end

    -- [weekly_duels] Participate in 5 duels
    -- Type: CustomEvent | Amount: 5 | Args: DuelCompleted
    QuestHandlers["weekly_duels"] = function(questData, amount)
        -- TODO: your script goes here

    end

    -- [weekly_pvpArenaTime] Fight in the PvP Arena for 10 minutes
    -- Type: TimeInWorld | Amount: 600 (seconds) | World: 103 (PvP arena)
    QuestHandlers["weekly_pvpArenaTime"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_TeleportToHub
        Event:FireServer(39)
    end

    -- [weekly_infiniteTower] Clear 30 floors of the Infinite Tower
    -- Type: CustomEvent | Amount: 30 | Args: CompletedInfiniteTowerFloor
    QuestHandlers["weekly_infiniteTower"] = function(questData, amount)
        local Event = game:GetService("ReplicatedStorage").rs.Teleport_StartRaid
        Event:FireServer(38, nil, nil)
    end

    -- ========================================================
    -- Fallback if the current quest doesn't have a handler above
    -- (e.g. a new quest got added to the game and this list wasn't
    -- updated yet)
    -- ========================================================
    local function DefaultHandler(questId, questData, amount)
        warn('[Quests] No handler for quest: ' .. tostring(questId) .. ' (' .. tostring(questData.Name) .. ')')
    end

    -- Called once a quest is finished — turn off whatever your
    -- handler turned on here (e.g. your mob farm toggle)
    local function StopCurrentAction(questId, questData)
        -- TODO (optional, only needed if you want to stop something
        -- between quests)

    end

    -- ========================================================
    -- MAIN LOOP
    -- ========================================================

    local runToken = 0
    local Running = false
    local CurrentQuestId = nil
    local CheckInterval = 2

    local function RunLoop(mode)
        runToken += 1
        local myToken = runToken
        Running = true

        while Running and myToken == runToken do
            local questIds = (mode == 'Daily') and GetActiveDailyQuestIds() or GetActiveWeeklyQuestIds()
            local questId, questData, current = GetNextIncompleteQuest(questIds)

            if not questId then
                noti(mode .. ' Quests: all done!')
                task.wait(5)
            else
                local objective = questData.Objective
                local amount = objective[2]

                CurrentQuestId = questId
                local handler = QuestHandlers[questId]

                if handler then
                    local ok, err = pcall(handler, questData, amount)
                    if not ok then
                        warn('[Quests] Error in handler for ' .. questId .. ': ' .. tostring(err))
                    end
                else
                    DefaultHandler(questId, questData, amount)
                end

                while Running and myToken == runToken do
                    local newCurrent, completed = GetProgress(questId)
                    if completed then
                        if handler then
                            pcall(StopCurrentAction, questId, questData)
                        end
                        ClaimQuest(questId)
                        break
                    end
                    task.wait(CheckInterval)
                end
            end
        end

        if myToken == runToken then
            Running = false
        end
    end

    local function StopQuests()
        Running = false
        runToken += 1
        if CurrentQuestId then
            local questData = GetQuestData(CurrentQuestId)
            if questData then
                pcall(StopCurrentAction, CurrentQuestId, questData)
            end
        end
        CurrentQuestId = nil
    end

    -- ========================================================
    -- Daily Tab
    -- ========================================================
    DailyQuestsTab:AddToggle('autoDailyQuests', {
        Text = 'Auto Complete Daily Quests',
        Default = false,
        Callback = function(value)
            if value then
                if Toggles.autoWeeklyQuests and Toggles.autoWeeklyQuests.Value then
                    Toggles.autoWeeklyQuests:SetValue(false)
                end
                task.spawn(RunLoop, 'Daily')
            else
                StopQuests()
            end
        end,
    })

    -- ========================================================
    -- Weekly Tab
    -- ========================================================
    WeeklyQuestsTab:AddToggle('autoWeeklyQuests', {
        Text = 'Auto Complete Weekly Quests',
        Default = false,
        Callback = function(value)
            if value then
                if Toggles.autoDailyQuests and Toggles.autoDailyQuests.Value then
                    Toggles.autoDailyQuests:SetValue(false)
                end
                task.spawn(RunLoop, 'Weekly')
            else
                StopQuests()
            end
        end,
    })
end)()
