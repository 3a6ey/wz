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
--
-- IMPORTANT: the game hands out quests from a big pool of random
-- numeric IDs (not a fixed set), so quests are matched by their
-- CONTENT (mob name / world / dungeon id / event key) instead of
-- by their numeric ID. That's what all the *Handlers tables below
-- are for.
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

    -- ========================================================
    -- HANDLERS — THIS IS WHERE YOU PUT YOUR OWN CODE
    -- --------------------------------------------------------
    -- Quests are matched by CONTENT, not by their numeric ID
    -- (the game randomly assigns IDs from a big pool, so a fixed
    -- id -> handler map doesn't work). Each table below is keyed
    -- by whatever actually identifies the quest: mob name, world
    -- number, dungeon id, or custom event key.
    -- ========================================================

    -- KillMob / KillMobInWorld / KillAnyMob
    -- Objective args = list of mob names that count (usually 1).
    -- Keyed by mob name -> function(questData, amount)
    local MobHandlers = {}

    MobHandlers["Boarwolf"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(2, 5, nil)
    end
    MobHandlers["EliteBoarwolf"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(2, 5, nil)
    end
    MobHandlers["Toucan"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(3, 5, nil)
    end
    MobHandlers["EarthCrab"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(4, 5, nil)
    end
    MobHandlers["ElectricCrab"] = MobHandlers["EarthCrab"]
    MobHandlers["FireCrab"] = MobHandlers["EarthCrab"]
    MobHandlers["GrassCobra"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(1, 5, nil)
    end
    MobHandlers["PoisonCobra"] = MobHandlers["GrassCobra"]
    MobHandlers["Quillodile"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(12, 1, nil)
    end
    MobHandlers["GoblinSpear"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(13, 1, nil)
    end
    MobHandlers["GoblinSlingshot"] = MobHandlers["GoblinSpear"]
    MobHandlers["GoblinGatekeeper"] = MobHandlers["GoblinSpear"]
    MobHandlers["RedGoblinSpear"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(13, 1, nil)
    end
    MobHandlers["RedGoblinSlingshot"] = MobHandlers["RedGoblinSpear"]
    MobHandlers["RedGoblinGatekeeper"] = MobHandlers["RedGoblinSpear"]
    MobHandlers["IcyGoo"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(15, 1, nil)
    end
    MobHandlers["SnowRaptor"] = MobHandlers["IcyGoo"]
    MobHandlers["FrostGolem"] = MobHandlers["IcyGoo"]
    MobHandlers["HappyCactus"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(18, 5, nil)
    end
    MobHandlers["GoldCobra"] = MobHandlers["HappyCactus"]
    MobHandlers["RockGolem"] = MobHandlers["HappyCactus"]
    MobHandlers["PinkBoarwolf"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(24, 5, nil)
    end
    MobHandlers["BlueGoblinSlingshot"] = MobHandlers["PinkBoarwolf"]
    MobHandlers["BlueGoblinElite"] = MobHandlers["PinkBoarwolf"]
    MobHandlers["BlueGoblinGatekeeper"] = MobHandlers["PinkBoarwolf"]
    MobHandlers["BlossomTree"] = MobHandlers["PinkBoarwolf"]
    MobHandlers["SeaSerpent"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(36, 5, nil)
    end
    MobHandlers["JellyfishSlime"] = MobHandlers["SeaSerpent"]
    MobHandlers["Parrot"] = MobHandlers["SeaSerpent"]
    MobHandlers["GoblinGladiator"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(37, 5, nil)
    end
    MobHandlers["GoblinSpartan"] = MobHandlers["GoblinGladiator"]
    MobHandlers["Kirin"] = MobHandlers["GoblinGladiator"]
    MobHandlers["ScorpionGold"] = MobHandlers["GoblinGladiator"]
    MobHandlers["Gargoyle"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(26, 5, nil)
    end
    MobHandlers["GargoyleGrey"] = MobHandlers["Gargoyle"]
    MobHandlers["RuinGuardian"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(30, 5, nil)
    end
    MobHandlers["Alligator"] = MobHandlers["RuinGuardian"]
    MobHandlers["Rapigator"] = MobHandlers["RuinGuardian"]

    -- Used for KillAnyMob (no specific mob name given) and as a
    -- fallback if a mob isn't in MobHandlers above
    local function DefaultMobHandler(questData, amount, mobName)
        rs.Teleport_StartRaid:FireServer(38, nil, nil) -- Infinite Tower, counts any kill
    end

    -- DoDungeonInWorld -> "finish any dungeon in World X"
    -- Keyed by LinkedWorld -> function(questData, amount)
    local DungeonWorldHandlers = {}
    DungeonWorldHandlers[1] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(1, 5, nil)
    end
    DungeonWorldHandlers[2] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(11, 5, nil)
    end
    DungeonWorldHandlers[3] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(15, 1, nil)
    end
    DungeonWorldHandlers[4] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(18, 5, nil)
    end
    -- TODO: add 5,6,7,8,9,10 etc as you go

    -- DoDungeon -> "defeat dungeon '<Name>' at any difficulty"
    -- Objective args = {dungeonId}. Keyed by dungeon id.
    local DungeonIdHandlers = {}
    -- DungeonIdHandlers[11] = function(questData, amount) -- Temple of Ruin (World 2)
    --     -- TODO: your script goes here
    -- end
    -- DungeonIdHandlers[26] = function(questData, amount) -- The Underworld (World 7)
    --     -- TODO: your script goes here
    -- end
    -- DungeonIdHandlers[14] = function(questData, amount) -- Mountain Pass (World 3)
    --     -- TODO: your script goes here
    -- end

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

    -- CustomEvent -> Objective args = {eventKey}. Keyed by that key.
    local CustomEventHandlers = {}
    -- CustomEventHandlers["UpgradeCompleted"] = function(questData, amount)
    --     -- TODO: your script goes here
    -- end
    CustomEventHandlers["CollectEquipmentInDungeon"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(2, 5, nil)
    end
    CustomEventHandlers["HatchPetEgg"] = function(questData, amount)
        for i = 1, amount do
            rs.Pets_BuyEgg:FireServer("StarEgg", "Gold")
        end
    end
    -- CustomEventHandlers["DuelCompleted"] = function(questData, amount)
    --     -- TODO: your script goes here
    -- end
    CustomEventHandlers["CompletedInfiniteTowerFloor"] = function(questData, amount)
        rs.Teleport_StartRaid:FireServer(38, nil, nil)
    end

    -- DoDungeonWithClass -> Objective args = {classTier}. TODO if you want
    -- to switch classes automatically; otherwise it'll just be skipped.
    local DungeonWithClassHandlers = {}
    -- DungeonWithClassHandlers[2] = function(questData, amount) -- TODO end
    -- DungeonWithClassHandlers[4] = function(questData, amount) -- TODO end

    -- DoDungeonWithWorldAndDifficulty -> keyed by LinkedWorld (args = {difficulty})
    local DungeonWorldDifficultyHandlers = {}
    -- DungeonWorldDifficultyHandlers[2] = function(questData, amount, difficulty) -- TODO end
    -- DungeonWorldDifficultyHandlers[6] = function(questData, amount, difficulty) -- TODO end

    -- DoRandomDungeonWithDifficulty -> Objective args = {difficulty}
    local function RandomDungeonHandler(questData, amount, difficulty)
        -- TODO: your script goes here (Nightmare Portal)
    end

    -- ========================================================
    -- DISPATCHER — routes each quest to the right handler above
    -- based on its Objective type + content. You shouldn't need
    -- to touch this, just fill in the *Handlers tables above.
    -- ========================================================
    local function RunHandlerFor(questData, objective, amount)
        local objType = objective[1]
        local args = objective[3] or {}

        if objType == "KillMob" or objType == "KillMobInWorld" then
            local mobName = args[1]
            local handler = mobName and MobHandlers[mobName]
            if handler then
                return true, pcall(handler, questData, amount)
            else
                return true, pcall(DefaultMobHandler, questData, amount, mobName)
            end

        elseif objType == "KillAnyMob" then
            return true, pcall(DefaultMobHandler, questData, amount, nil)

        elseif objType == "DoDungeonInWorld" then
            local handler = questData.LinkedWorld and DungeonWorldHandlers[questData.LinkedWorld]
            if handler then
                return true, pcall(handler, questData, amount)
            end
            return false

        elseif objType == "DoDungeon" then
            local dungeonId = args[1]
            local handler = dungeonId and DungeonIdHandlers[dungeonId]
            if handler then
                return true, pcall(handler, questData, amount)
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
            local handler = questData.LinkedWorld and DungeonWorldDifficultyHandlers[questData.LinkedWorld]
            if handler then
                return true, pcall(handler, questData, amount, args[1])
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
        -- TODO (optional, only needed if you want to stop something
        -- between quests)

    end

    -- Grabs the first quest in the list that isn't finished yet AND has a
    -- real handler for its content. Quests with no handler (still a TODO)
    -- get skipped so the bot doesn't get stuck waiting on them forever.
    -- Along the way it also claims anything that's already done but
    -- hasn't been claimed yet (in case it finished on its own).
    local function GetNextIncompleteQuest(questIds)
        local sawUnhandled = false
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
        return nil, nil, nil, sawUnhandled
    end

    -- ========================================================
    -- MAIN LOOP
    -- ========================================================

    local runToken = 0
    local Running = false
    local CurrentQuestId = nil
    local CheckInterval = 2
    local StatusText = 'Idle'

    local dailyStatusLabel, weeklyStatusLabel

    local function RunLoop(mode)
        runToken += 1
        local myToken = runToken
        Running = true

        while Running and myToken == runToken do
            local questIds = (mode == 'Daily') and GetActiveDailyQuestIds() or GetActiveWeeklyQuestIds()

            if #questIds == 0 then
                StatusText = 'No active ' .. mode .. ' quests found'
                warn('[Quests] ' .. mode .. ': GetActive' .. mode .. 'QuestIds returned an EMPTY list.')
                task.wait(5)
            else
                local questId, questData, current = GetNextIncompleteQuest(questIds)

                if not questId then
                    StatusText = 'All ' .. mode .. ' quests done!'
                    noti(mode .. ' Quests: all done!')
                    task.wait(5)
                else
                    local objective = questData.Objective
                    local amount = objective[2]

                    CurrentQuestId = questId
                    local handled, ok, err = RunHandlerFor(questData, objective, amount)

                    if handled then
                        if not ok then
                            warn('[Quests] Error running handler for "' .. tostring(questData.Name) .. '": ' .. tostring(err))
                        end

                        StatusText = (questData.Name or tostring(questId)) .. ' (0/' .. tostring(amount) .. ')'

                        while Running and myToken == runToken do
                            local newCurrent, completed = GetProgress(questId)
                            StatusText = (questData.Name or tostring(questId)) .. ' (' .. tostring(newCurrent or 0) .. '/' .. tostring(amount) .. ')'
                            if completed then
                                pcall(StopCurrentAction, questId, questData)
                                ClaimQuest(questId)
                                break
                            end
                            task.wait(CheckInterval)
                        end
                    else
                        -- No handler written for this quest's content yet -
                        -- skip it and move to the next one instead of hanging
                        warn('[Quests] No handler for: "' .. tostring(questData.Name) .. '" (ID ' .. tostring(questId) .. ', Objective: ' .. objective[1] .. ')')
                        task.wait(1)
                    end
                end
            end
        end

        if myToken == runToken then
            Running = false
            StatusText = 'Idle'
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

    DailyQuestsTab:AddDivider()
    dailyStatusLabel = DailyQuestsTab:AddLabel('Status: Idle')

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

    WeeklyQuestsTab:AddDivider()
    weeklyStatusLabel = WeeklyQuestsTab:AddLabel('Status: Idle')

    -- Keeps the status label on the active tab updated
    task.spawn(function()
        while true do
            if Running and CurrentQuestId then
                local label = (Toggles.autoDailyQuests and Toggles.autoDailyQuests.Value) and dailyStatusLabel or weeklyStatusLabel
                if label and label.SetText then
                    label:SetText('Status: ' .. StatusText)
                end
            else
                if dailyStatusLabel and dailyStatusLabel.SetText then dailyStatusLabel:SetText('Status: Idle') end
                if weeklyStatusLabel and weeklyStatusLabel.SetText then weeklyStatusLabel:SetText('Status: Idle') end
            end
            task.wait(1)
        end
    end)
end)()
