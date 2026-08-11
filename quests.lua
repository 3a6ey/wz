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

    local function GetActiveWeeklyQuestIds(weeklyData)
        local ids = {}
        if weeklyData and weeklyData.quests then
            for _, q in ipairs(weeklyData.quests) do
                table.insert(ids, q.id)
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

    -- Tracks which questIds we've already claimed this session (whether we
    -- claimed them ourselves or they were already claimed by the time we
    -- checked - e.g. you claimed it manually in the UI). Once a quest is
    -- in here we never touch or notify about it again this session.
    local claimedQuestIds = {}

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
    local function GetNextIncompleteQuest(questIds, isWeekly, weeklyData)
        local skippedNames = {}
        for _, questId in ipairs(questIds) do
            if not claimedQuestIds[questId] then
                local questData = GetQuestData(questId)
                if questData and not questData.Disabled then
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
                local lastRemaining = amount - (current or 0)

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
                    noti((questData.Name or tostring(questId)) .. ' — ' .. tostring(lastRemaining) .. ' left')
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
                            noti((questData.Name or tostring(questId)) .. ' — ' .. tostring(remaining) .. ' left')
                        end
                        task.wait(CheckInterval)
                    end
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
    -- Quests Tab — Both first (recommended default), then a divider,
    -- then Daily and Weekly for running them individually.
    -- ========================================================
    QuestsMainTab:AddToggle('autoBothQuests', {
        Text = 'Auto Complete Daily, then Weekly',
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

    QuestsMainTab:AddToggle('autoWeeklyQuests', {
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
end)()
