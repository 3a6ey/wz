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
local BothQuestsTab = QuestsTabbox:AddTab('Both')
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
    -- Daily Login auto-claim
    -- --------------------------------------------------------
    -- Separate from quest rewards - this is the "log in today"
    -- bonus. GetDailyLogin checks your current status, then
    -- AwardDailyLogin claims it. We don't know the exact shape of
    -- what GetDailyLogin returns, so this dumps it to the console
    -- once so we can refine the "already claimed" check together
    -- if needed - for now it just tries to award every time this
    -- runs, which should be harmless even if already claimed.
    -- ========================================================
    local dailyLoginTried = false
    local function TryClaimDailyLogin()
        if dailyLoginTried then return end
        dailyLoginTried = true

        local ok, info = pcall(function()
            return rs.Profile_GetDailyLogin:InvokeServer()
        end)
        if ok then
            local dump = info
            if typeof(info) == 'table' then
                pcall(function() dump = game:GetService('HttpService'):JSONEncode(info) end)
            end
            warn('[Quests] DailyLogin status: ' .. tostring(dump))
        else
            warn('[Quests] Failed to check DailyLogin status: ' .. tostring(info))
        end

        local ok2, err2 = pcall(function()
            rs.Profile_AwardDailyLogin:FireServer()
        end)
        if ok2 then
            noti('Daily login reward claimed!')
        else
            warn('[Quests] Failed to award DailyLogin (probably already claimed): ' .. tostring(err2))
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

    -- Fires StartRaid(raidId, difficulty), but ONLY if you're not
    -- already sitting on that dungeon's Place. This is what makes
    -- re-toggling / script restarts safe - no duplicate teleports.
    local function FireRaidIfNeeded(raidId, difficulty)
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
    MobRaid["GrassCobra"] = {1, 5}
    MobRaid["PoisonCobra"] = {1, 5}
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
    -- Objective args = {dungeonId}. Keyed by dungeon id -> difficulty.
    local DungeonIdHandlers = {}
    -- DungeonIdHandlers[11] = 5  -- Temple of Ruin (World 2)
    -- DungeonIdHandlers[26] = 5  -- The Underworld (World 7)
    -- DungeonIdHandlers[14] = 1  -- Mountain Pass (World 3)

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
        FireRaidIfNeeded(2, 5)
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
        FireRaidIfNeeded(38, nil)
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
            return questData.LinkedWorld ~= nil and DungeonWorldDifficultyHandlers[questData.LinkedWorld] ~= nil
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
    -- get skipped so the bot doesn't get stuck waiting on them forever -
    -- it keeps looking further down the list instead of retrying the
    -- same unhandled quest over and over.
    -- Along the way it also claims anything that's already done but
    -- hasn't been claimed yet (in case it finished on its own).
    local function GetNextIncompleteQuest(questIds)
        local skippedNames = {}
        for _, questId in ipairs(questIds) do
            local questData = GetQuestData(questId)
            if questData and not questData.Disabled then
                local current, completed = GetProgress(questId)
                if completed then
                    ClaimQuest(questId)
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
    local firedQuestIds = {} -- hard guarantee: each questId's handler fires AT MOST once per run
    local currentRunningMode = nil -- 'Daily' | 'Weekly' | 'Both' | nil

    -- Picks the next quest to work on. In 'Both' mode, Daily always takes
    -- priority - Weekly only gets picked once there's nothing left to do
    -- in Daily (all completed or all still TODO).
    local function PickQuest(mode)
        if mode == 'Both' then
            local dIds = GetActiveDailyQuestIds()
            if #dIds > 0 then
                local qId, qData, cur, skipped = GetNextIncompleteQuest(dIds)
                if qId then return qId, qData, cur, skipped, 'Daily' end
            end
            local wIds = GetActiveWeeklyQuestIds()
            local qId, qData, cur, skipped = GetNextIncompleteQuest(wIds)
            return qId, qData, cur, skipped, 'Weekly'
        else
            local ids = (mode == 'Daily') and GetActiveDailyQuestIds() or GetActiveWeeklyQuestIds()
            local qId, qData, cur, skipped = GetNextIncompleteQuest(ids)
            return qId, qData, cur, skipped, mode
        end
    end

    local function RunLoop(mode)
        runToken += 1
        local myToken = runToken
        Running = true
        currentRunningMode = mode
        firedQuestIds = {}

        while Running and myToken == runToken do
            local questId, questData, current, skippedNames, activeSubMode = PickQuest(mode)

            if not questId then
                if skippedNames and #skippedNames > 0 then
                    local key = table.concat(skippedNames, ', ')
                    if key ~= lastSkippedKey then
                        warn('[Quests] No handler yet for: ' .. key)
                        lastSkippedKey = key
                    end
                else
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

                if not firedQuestIds[questId] then
                    -- Not fired yet this session - kick off the handler.
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
                    local remaining = amount - (current or 0)
                    noti((questData.Name or tostring(questId)) .. ' — ' .. tostring(remaining) .. ' left')
                end

                local lastRemaining = nil
                while Running and myToken == runToken do
                    local newCurrent, completed = GetProgress(questId)

                    -- bail out cleanly if we were stopped during the wait below,
                    -- without firing any "quest complete" side effects
                    if not Running or myToken ~= runToken then break end

                    if completed then
                        pcall(StopCurrentAction, questId, questData)
                        ClaimQuest(questId)
                        if Running and myToken == runToken then
                            noti((questData.Name or tostring(questId)) .. ' — complete!')
                        end
                        break
                    end

                    local remaining = amount - (newCurrent or 0)
                    if remaining ~= lastRemaining then
                        lastRemaining = remaining
                        noti((questData.Name or tostring(questId)) .. ' — ' .. tostring(remaining) .. ' left')
                    end
                    task.wait(CheckInterval)
                end
            end
        end

        if myToken == runToken then
            Running = false
            currentRunningMode = nil
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
    end

    -- ========================================================
    -- Both Tab — does all Daily first, then automatically moves on
    -- to Weekly. This is the recommended default, so it comes first.
    -- ========================================================
    BothQuestsTab:AddToggle('autoBothQuests', {
        Text = 'Auto Complete Daily, then Weekly',
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
    BothQuestsTab:AddDivider()
    BothQuestsTab:AddButton({
        Text = 'Stop All',
        Func = function()
            StopQuests()
            if Toggles.autoDailyQuests then Toggles.autoDailyQuests:SetValue(false) end
            if Toggles.autoWeeklyQuests then Toggles.autoWeeklyQuests:SetValue(false) end
            if Toggles.autoBothQuests then Toggles.autoBothQuests:SetValue(false) end
        end,
        DoubleClick = true,
    })

    -- ========================================================
    -- Daily Tab
    -- ========================================================
    DailyQuestsTab:AddToggle('autoDailyQuests', {
        Text = 'Auto Complete Daily Quests',
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

    -- ========================================================
    -- Weekly Tab
    -- ========================================================
    WeeklyQuestsTab:AddToggle('autoWeeklyQuests', {
        Text = 'Auto Complete Weekly Quests',
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

    -- Try to claim the daily login bonus once, shortly after the module loads
    task.spawn(function()
        task.wait(2)
        pcall(TryClaimDailyLogin)
    end)
end)()
