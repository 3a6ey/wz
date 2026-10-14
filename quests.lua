

local plr, rs, Window, Tabs, Toggles, noti, Library = ...

local RepStorage = game:GetService('ReplicatedStorage')
local HttpService = game:GetService('HttpService')
local MarketplaceService = game:GetService('MarketplaceService')

local Quests = require(RepStorage.Shared.Quests)
local Profile = require(RepStorage.Shared.Profile)
local Items = require(RepStorage.Shared.Items)
local Options = Library and Library.Options or {}

if not Library then
    warn('[Quests] Library не передан (7-й аргумент loadstring) - статус-уведомление работать не будет.')
end

local QuestListModule
do
    local ok, mod = pcall(function()
        return require(RepStorage:WaitForChild('WorldModules', 5):WaitForChild('QuestList', 5))
    end)
    if ok and type(mod) == 'table' then QuestListModule = mod end
end

Tabs.Quests = Window:AddTab('Quests', 'scroll-text')
local QuestsTabbox = Tabs.Quests:AddLeftTabbox('questsBox')
local QuestsMainTab = QuestsTabbox:AddTab('Quests')

;(function()
    -- ========================================================
    -- Сохранение состояния (файл + getgenv)
    -- ========================================================
    local STATE_FILE = 'Infinite/World Zero/quests_state.json'

    local function LoadState()
        local ok, data = pcall(function()
            if isfile and isfile(STATE_FILE) then
                return HttpService:JSONDecode(readfile(STATE_FILE))
            end
        end)
        if ok and type(data) == 'table' then return data end
        return {}
    end

    getgenv().QuestsPersist = getgenv().QuestsPersist or LoadState()
    local Persist = getgenv().QuestsPersist
    Persist.firedQuestIds = nil -- старый формат (числовые ключи ломают JSON)
    Persist.fired = Persist.fired or {}
    Persist.learnedMobs = Persist.learnedMobs or {}
    Persist.trials = Persist.trials or {}

    local function SaveState()
        pcall(function()
            if writefile then
                writefile(STATE_FILE, HttpService:JSONEncode(Persist))
            end
        end)
    end

    -- ========================================================
    -- Базовые обёртки
    -- ========================================================
    local function GetMyProfile()
        return Profile:GetProfile(plr)
    end

    local function GetQuestData(questId)
        local ok, data = pcall(function() return Quests:GetQuestDataFromID(questId) end)
        if ok and data then return data end
        if QuestListModule then
            return QuestListModule[questId] or QuestListModule[tostring(questId)]
        end
        return nil
    end

    -- 2-е значение = "награда уже забрана" (не "квест выполнен")
    local function GetProgress(questId)
        return Quests:GetQuestProgress(plr, questId)
    end

    local function StartRaidRemote(raidId, difficulty)
        rs:WaitForChild('Teleport_StartRaid'):FireServer(raidId, difficulty)
    end

    -- Hot-квесты = слоты 1-3 (в GUI у них стоит огонёк)
    local function IsOnlyHot()
        return Toggles.questsOnlyHot and Toggles.questsOnlyHot.Value or false
    end

    local function GetActiveDailyQuestIds(onlyHot)
        local profile = GetMyProfile()
        if not profile then return {} end
        local raw = Quests:GetDailyQuests(profile)
        local ids = {}
        local maxSlot = onlyHot and 3 or 10
        for slot = 1, maxSlot do
            if raw[slot] then table.insert(ids, raw[slot]) end
        end
        return ids
    end

    -- ========================================================
    -- VIP
    -- ========================================================
    local VIP_GAMEPASS_ID = 8136226
    local HasVIP
    do
        local ok, owns = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, VIP_GAMEPASS_ID)
        end)
        HasVIP = ok and owns or false
    end

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
                if not (q.isVIP and not HasVIP) then
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

    local claimedQuestIds = {}

    -- ========================================================
    -- Daily Login (левая колонка тиров)
    -- ========================================================
    local function TryClaimDailyLogin()
        for _ = 1, 5 do
            local ok, current, claimedUpTo = pcall(function()
                return Profile:GetCurrentDailyLogin(plr)
            end)
            if not ok then return end
            if not (current and claimedUpTo and claimedUpTo < current) then break end
            local ok2, err2 = pcall(function() Profile:AwardDailyLoginReward(plr) end)
            if ok2 then
                noti('Daily login reward claimed!')
            else
                warn('[Quests] Daily Login claim failed: ' .. tostring(err2))
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
            if not entry then return nil, nil, nil end
            if entry.isVIP and not HasVIP then return nil, nil, nil end
            current = entry.value or 0
            claimed = entry.claimed or false
        else
            local c, cl = GetProgress(questId)
            current = c or 0
            claimed = cl or false
        end

        if claimed then claimedQuestIds[questId] = true end
        return current, (current >= required), claimed
    end

    local function ClaimQuest(questId, isWeekly, questName)
        if claimedQuestIds[questId] then return end
        claimedQuestIds[questId] = true
        Persist.fired[tostring(questId)] = nil

        rs.Quests_ClaimQuest:FireServer(questId)
        noti((questName or tostring(questId)) .. ' — claimed!')

        if isWeekly then
            pcall(function() rs.Quests_ClaimWeeklyReward:FireServer() end)
        end
    end

    -- ========================================================
    -- Данжи / рейды
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
    local PlaceIdSet = {}
    for _, pid in pairs(DungeonPlaceIds) do PlaceIdSet[tostring(pid)] = true end

    local HUB_WORLD1 = 13 -- хаб World 1 (id из WorldData главного скрипта)
    local RAID_FIRE_COOLDOWN = 20 -- сек между StartRaid, чтобы не спамить
    local TRIAL_SECONDS = 360 -- сколько ждём прогресса в данже при поиске моба

    local function CurrentMissionId()
        local ok, v = pcall(function() return workspace:GetAttribute('MissionId') end)
        if ok then return v end
        return nil
    end

    local function InMission()
        return CurrentMissionId() ~= nil or PlaceIdSet[tostring(game.PlaceId)] == true
    end

    -- Стартует рейд только если мы не в нём уже и не спамим
    local function FireRaidIfNeeded(raidId, difficulty)
        local cur = CurrentMissionId()
        if cur ~= nil and tostring(cur) == tostring(raidId) then return false end

        local target = DungeonPlaceIds[raidId]
        if target and tostring(game.PlaceId) == tostring(target) then return false end

        if os.time() - (Persist.lastRaidFire or 0) < RAID_FIRE_COOLDOWN then return false end
        Persist.lastRaidFire = os.time()
        SaveState()
        StartRaidRemote(raidId, difficulty)
        return true
    end

    -- true = телепорт в хаб отправлен/идёт, вызывающий должен подождать
    local function GoToHubIfInMission()
        if InMission() then
            if os.time() - (Persist.lastHubFire or 0) > 15 then
                Persist.lastHubFire = os.time()
                SaveState()
                rs.Teleport_TeleportToHub:FireServer(HUB_WORLD1)
            end
            return true
        end
        return false
    end

    -- ========================================================
    -- Моб -> {данж, сложность}. Неизвестных мобов скрипт ищет сам
    -- (см. MobHandler) и запоминает в Persist.learnedMobs.
    -- ========================================================
    local MobRaid = {}
    MobRaid["Boarwolf"] = {2, 5}
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

    -- Данжи по мирам (для поиска мобов перебором)
    local WorldDungeonIds = {
        [1] = {1, 3, 2, 4, 6},
        [2] = {11, 12, 13, 7},
        [3] = {14, 15, 16},
        [4] = {20, 19, 18},
        [5] = {24, 35},
        [6] = {25, 36},
        [7] = {26, 37},
        [8] = {30, 31},
        [9] = {32, 33},
        [10] = {41, 42},
    }

    local function WorldCandidates(linkedWorld)
        if linkedWorld and WorldDungeonIds[linkedWorld] then
            return WorldDungeonIds[linkedWorld]
        end
        local all = {}
        for w = 1, 10 do
            for _, id in ipairs(WorldDungeonIds[w]) do table.insert(all, id) end
        end
        return all
    end

    -- ctx = {questId, isWeekly, current}
    local function MobHandler(mobName, questData, ctx)
        if not mobName then
            FireRaidIfNeeded(38, nil) -- KillAnyMob: любой моб, Infinite Tower
            return
        end

        local raid = MobRaid[mobName] or Persist.learnedMobs[mobName]
        if raid then
            FireRaidIfNeeded(raid[1], raid[2])
            return
        end

        -- Моб неизвестен: перебираем данжи его мира, ждём прогресса
        local cands = WorldCandidates(questData.LinkedWorld)
        local t = Persist.trials[mobName]
        if not t then
            t = { idx = 1, since = os.time(), base = ctx.current }
            Persist.trials[mobName] = t
            SaveState()
        end
        if t.idx > #cands then t.idx = 1 end

        if ctx.current > t.base then
            Persist.learnedMobs[mobName] = { cands[t.idx], 1 }
            Persist.trials[mobName] = nil
            SaveState()
            noti('Нашёл где живёт ' .. mobName .. ' (данж ' .. tostring(cands[t.idx]) .. ')')
            FireRaidIfNeeded(cands[t.idx], 1)
            return
        end

        if os.time() - t.since > TRIAL_SECONDS then
            t.idx = (t.idx % #cands) + 1
            t.since = os.time()
            t.base = ctx.current
            SaveState()
        end
        FireRaidIfNeeded(cands[t.idx], 1)
    end

    -- "Пройти любой данж в мире X"
    local DungeonWorldRaid = {
        [1] = {1, 5},
        [2] = {11, 5},
        [3] = {15, 1},
        [4] = {18, 5},
        [5] = {35, 5},
        [6] = {36, 5},
        [7] = {37, 5},
        [8] = {31, 5},
        [9] = {33, 5},
        [10] = {41, 5},
    }

    -- "Defeat dungeon 'X' at any difficulty"
    local DungeonIdHandlers = {}
    for _, id in ipairs({1, 3, 2, 4, 6, 11, 12, 13, 7, 14, 15, 16, 20, 19, 18,
        24, 35, 25, 36, 26, 37, 30, 31, 32, 33, 41, 42}) do
        DungeonIdHandlers[id] = 5
    end

    -- Миры-ивенты пока пропускаем (по просьбе)
    local WorldEventHandlers = {}

    local function TimeInWorldHandler(questData, amount, hubId)
        if hubId then rs.Teleport_TeleportToHub:FireServer(hubId) end
    end

    -- ========================================================
    -- Отключение продажи на время квеста "Upgrade"
    -- ========================================================
    local SELL_TOGGLES = {
        'sellAll_Weapon', 'sellAll_Armor', 'sellAll_Pet',
        'smartPerkSell_Weapon', 'smartPerkSell_Armor', 'smartPerkSell_Pet',
        'autoSellEggs',
    }
    local SELL_DROPDOWNS = { 'sellTiers_Weapon', 'sellTiers_Armor', 'sellTiers_Pet' }

    local function DisableSelling(questId)
        local bk = Persist.sellBackup
        if not bk then
            bk = { questId = questId, toggles = {}, tiers = {} }
            for _, name in ipairs(SELL_TOGGLES) do
                local t = Toggles[name]
                if t then bk.toggles[name] = t.Value and true or false end
            end
            for _, name in ipairs(SELL_DROPDOWNS) do
                local o = Options[name]
                if o then
                    local arr = {}
                    for k, v in pairs(o.Value or {}) do
                        if v then table.insert(arr, k) end
                    end
                    bk.tiers[name] = arr
                end
            end
            Persist.sellBackup = bk
            SaveState()
        end
        bk.questId = questId

        -- принудительно держим выключенным (конфиг мог перезагрузить значения)
        for _, name in ipairs(SELL_TOGGLES) do
            local t = Toggles[name]
            if t and t.Value then t:SetValue(false) end
        end
        for _, name in ipairs(SELL_DROPDOWNS) do
            local o = Options[name]
            if o and next(o.Value or {}) ~= nil then o:SetValue({}) end
        end
    end

    local function RestoreSelling()
        local bk = Persist.sellBackup
        if not bk then return end
        Persist.sellBackup = nil
        SaveState()
        for name, val in pairs(bk.toggles or {}) do
            local t = Toggles[name]
            if t and t.Value ~= val then t:SetValue(val) end
        end
        for name, arr in pairs(bk.tiers or {}) do
            local o = Options[name]
            if o then
                local set = {}
                for _, tierNum in ipairs(arr) do set[tierNum] = true end
                o:SetValue(set)
            end
        end
        noti('Автопродажа возвращена')
    end

    -- ========================================================
    -- Квест "Upgrade items N times"
    -- 1-1 -> копим броню (продажа выключена) -> надеть -> макс апгрейд ->
    -- вернуть старую -> продать прокачанную
    -- ========================================================
    local PlayerEquips = RepStorage:WaitForChild('PlayerEquips'):WaitForChild(plr.Name)
    local EquipArmor = PlayerEquips:WaitForChild('Armor')

    local UpgradeState = { running = false, busy = false }

    local function ItemId(item)
        local v = item and item:FindFirstChild('ID')
        return v and v.Value or nil
    end

    local function FindInventoryItemById(id)
        if not id then return nil end
        local profile = GetMyProfile()
        if not profile then return nil end
        for _, item in ipairs(profile.Inventory.Items:GetChildren()) do
            if ItemId(item) == id then return item end
        end
        return nil
    end

    local function FindUpgradeableArmor()
        local profile = GetMyProfile()
        if not profile then return nil end
        for _, item in ipairs(profile.Inventory.Items:GetChildren()) do
            local data = Items[item.Name]
            if data and data.Type == 'Armor' and not item:FindFirstChild('Locked') then
                local limit = item:FindFirstChild('UpgradeLimit')
                local cur = item:FindFirstChild('Upgrade')
                if limit and limit.Value > 0 and ((cur and cur.Value or 0) < limit.Value) then
                    return item
                end
            end
        end
        return nil
    end

    local function EquipArmorItem(item)
        if not item then return false end
        local id = ItemId(item)
        local cur = EquipArmor:GetChildren()[1]
        if cur and ItemId(cur) == id then return true end
        rs.Inventory_EquipItem:FireServer(item, EquipArmor)
        local t = tick()
        while tick() - t < 5 do
            task.wait(0.25)
            local c = EquipArmor:GetChildren()[1]
            if c and ItemId(c) == id then return true end
        end
        return false
    end

    -- Тот же цикл, что в кнопке "Upgrade Equipped Items", + выход по условию
    local function UpgradeItemToLimit(item, shouldContinue)
        if not (item and item:FindFirstChild('UpgradeLimit') and item.UpgradeLimit.Value ~= 0) then return end
        local profile = GetMyProfile()
        local goldValue = profile.Currency.Gold
        local oldGold = goldValue.Value
        local timer = tick()
        while task.wait(0.1) do
            if not shouldContinue() or not item.Parent then break end
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

    local function UpgradeLoop()
        while UpgradeState.running do
            local cur = EquipArmor:GetChildren()[1]
            local origId = Persist.upgradeOrigArmorId
            local work

            -- продолжение после рестарта: на нас рабочая броня, старая запомнена
            if origId and cur and (origId == 'NONE' or ItemId(cur) ~= origId) then
                work = cur
            end

            if not work then
                Persist.upgradeOrigArmorId = nil
                local cand = FindUpgradeableArmor()
                if not cand then
                    task.wait(3) -- ждём дропов (фармим 1-1)
                else
                    Persist.upgradeOrigArmorId = ItemId(cur) or 'NONE'
                    SaveState()
                    if EquipArmorItem(cand) then
                        work = cand
                    else
                        Persist.upgradeOrigArmorId = nil
                        SaveState()
                        task.wait(2)
                    end
                end
            end

            if work then
                UpgradeItemToLimit(work, function() return UpgradeState.running end)
                local workId = ItemId(work)
                local origId2 = Persist.upgradeOrigArmorId

                if origId2 and origId2 ~= 'NONE' then
                    local orig = FindInventoryItemById(origId2)
                    if orig then EquipArmorItem(orig) end
                end

                local sellItem = workId and FindInventoryItemById(workId)
                if sellItem and ItemId(sellItem) ~= origId2 and not sellItem:FindFirstChild('Locked') then
                    pcall(function() rs.Drops_SellItems:InvokeServer({ sellItem }) end)
                end
                Persist.upgradeOrigArmorId = nil
                SaveState()
            end
            task.wait(0.5)
        end
        UpgradeState.busy = false
        RestoreSelling()
    end

    -- ========================================================
    -- Квесты с классом (Tier 2/3/4)
    -- ========================================================
    local ClassNames = {
        'None', 'Assassin', 'MageOfLight', 'Warlord', 'Paladin', 'Berserker', 'Guardian',
        'Demon', 'Swordmaster', 'Mage', 'Defender', 'DualWielder', 'IcefireMage',
        'Dragoon', 'Leviathan', 'Archer', 'Summoner', 'Necromancer', 'MageOfShadows',
        'Hunter', 'Stormcaller', 'Starbreaker',
    }
    local DefaultTierClass = { [2] = 'IcefireMage', [3] = 'None', [4] = 'Archer' }

    local function ClassForTier(tier)
        local opt = Options['questTier' .. tostring(tier) .. 'Class']
        local v = opt and opt.Value
        if v and v ~= 'None' then return v end
        return nil
    end

    local function GetCurrentClass()
        local ok, c = pcall(function()
            local p = Profile:GetProfile(plr)
            return p and p.Class and p.Class.Value
        end)
        if ok then return c end
        return nil
    end

    local function SwitchClassVerified(className)
        for _ = 1, 3 do
            if GetCurrentClass() == className then return true end
            rs.Profile_SwitchClass:FireServer(className)
            local t = tick()
            while tick() - t < 8 do
                task.wait(0.5)
                if GetCurrentClass() == className then
                    task.wait(1)
                    return true
                end
            end
        end
        return GetCurrentClass() == className
    end

    -- true = всё вернули. false = ещё в процессе (телепорт в хаб / смена класса)
    local function RestoreClass()
        local cq = Persist.classQuest
        if not cq then return true end
        if cq.saved and GetCurrentClass() ~= cq.saved then
            if GoToHubIfInMission() then return false end
            if not SwitchClassVerified(cq.saved) then return false end
        end
        Persist.classQuest = nil
        SaveState()
        if cq.saved then noti('Класс возвращён: ' .. tostring(cq.saved)) end
        return true
    end

    local function DungeonWithClassHandler(questData, amount, tier, ctx)
        local className = ClassForTier(tier)
        if not className then return end

        local cq = Persist.classQuest
        if cq and cq.questId ~= ctx.questId then
            if not RestoreClass() then return end
            cq = nil
        end
        if not cq then
            cq = {
                questId = ctx.questId,
                isWeekly = ctx.isWeekly,
                target = className,
                saved = GetCurrentClass(), -- запоминаем текущий класс
                stage = 'switch',
            }
            Persist.classQuest = cq
            SaveState()
        end

        if cq.stage == 'switch' then
            if GetCurrentClass() ~= className then
                -- в данже класс не меняем: сначала в хаб
                if GoToHubIfInMission() then return end
                if not SwitchClassVerified(className) then
                    warn('[Quests] Не удалось сменить класс на ' .. className)
                    return
                end
            end
            cq.stage = 'run'
            SaveState()
        end

        -- фармим любой данж (1-1 самый простой), пока квест не выполнится
        FireRaidIfNeeded(1, 5)
    end

    -- ========================================================
    -- Остальные обработчики
    -- ========================================================
    local CustomEventHandlers = {}

    CustomEventHandlers["UpgradeCompleted"] = function(questData, amount, ctx)
        DisableSelling(ctx.questId) -- сначала выключаем продажу
        FireRaidIfNeeded(1, 5) -- World 1, данж 1: фарм брони
        if UpgradeState.running then return end
        UpgradeState.running = true
        UpgradeState.busy = true
        task.spawn(UpgradeLoop)
    end

    CustomEventHandlers["CollectEquipmentInDungeon"] = function() FireRaidIfNeeded(2, 5) end
    CustomEventHandlers["CompletedInfiniteTowerFloor"] = function() FireRaidIfNeeded(38, nil) end
    CustomEventHandlers["HatchPetEgg"] = function(questData, amount)
        task.spawn(function()
            for _ = 1, amount do
                rs.Pets_BuyEgg:FireServer("StarEgg", "Gold")
                task.wait(0.3)
            end
        end)
    end

    local DungeonWithClassHandlers = {}
    for _, tier in ipairs({2, 3, 4}) do
        DungeonWithClassHandlers[tier] = function(questData, amount, ctx)
            DungeonWithClassHandler(questData, amount, tier, ctx)
        end
    end

    local NightmareDungeonIds = {1005, 1006, 1007}
    local NightmareSet = { [1005] = true, [1006] = true, [1007] = true }
    local function RandomDungeonHandler(questData, amount, difficulty)
        local cur = CurrentMissionId()
        if cur ~= nil and NightmareSet[tonumber(cur)] then return end -- уже в Nightmare-данже
        local randomId = NightmareDungeonIds[math.random(1, #NightmareDungeonIds)]
        FireRaidIfNeeded(randomId, difficulty)
    end

    -- ========================================================
    -- CanHandle: есть ли обработчик для этого квеста
    -- ========================================================
    local function CanHandle(questData, objective)
        local objType = objective[1]
        local args = objective[3] or {}

        if objType == "KillMob" or objType == "KillMobInWorld" or objType == "KillAnyMob" then
            return true
        elseif objType == "DoDungeonInWorld" then
            return questData.LinkedWorld ~= nil and DungeonWorldRaid[questData.LinkedWorld] ~= nil
        elseif objType == "DoDungeon" then
            return args[1] ~= nil and DungeonIdHandlers[args[1]] ~= nil
        elseif objType == "DoDungeonWithDifficulty" then
            return args[1] ~= nil and DungeonPlaceIds[args[1]] ~= nil
        elseif objType == "CompleteWorldEvent" then
            return questData.LinkedWorld ~= nil and WorldEventHandlers[questData.LinkedWorld] ~= nil
        elseif objType == "TimeInWorld" then
            return true
        elseif objType == "CustomEvent" then
            return args[1] ~= nil and CustomEventHandlers[args[1]] ~= nil
        elseif objType == "DoDungeonWithClass" then
            return args[1] ~= nil and DungeonWithClassHandlers[args[1]] ~= nil and ClassForTier(args[1]) ~= nil
        elseif objType == "DoDungeonWithWorldAndDifficulty" then
            return questData.LinkedWorld ~= nil and DungeonWorldRaid[questData.LinkedWorld] ~= nil
        elseif objType == "DoRandomDungeonWithDifficulty" then
            return true
        end
        return false
    end

    -- Эти типы вызываются на каждом тике (идемпотентно), остальные - один раз
    local ReinvokeTypes = {
        KillMob = true, KillMobInWorld = true, KillAnyMob = true,
        DoDungeon = true, DoDungeonInWorld = true, DoDungeonWithDifficulty = true,
        DoDungeonWithWorldAndDifficulty = true, DoRandomDungeonWithDifficulty = true,
        DoDungeonWithClass = true,
    }
    local ReinvokeEvents = {
        UpgradeCompleted = true, CollectEquipmentInDungeon = true, CompletedInfiniteTowerFloor = true,
    }
    local function ShouldReinvoke(objective)
        if ReinvokeTypes[objective[1]] then return true end
        if objective[1] == "CustomEvent" then
            local key = objective[3] and objective[3][1]
            return key ~= nil and ReinvokeEvents[key] == true
        end
        return false
    end

    -- ========================================================
    -- Диспетчер
    -- ========================================================
    local function RunHandlerFor(questData, objective, amount, ctx)
        local objType = objective[1]
        local args = objective[3] or {}

        if objType == "KillMob" or objType == "KillMobInWorld" then
            return true, pcall(MobHandler, args[1], questData, ctx)

        elseif objType == "KillAnyMob" then
            return true, pcall(MobHandler, nil, questData, ctx)

        elseif objType == "DoDungeonInWorld" then
            local raid = questData.LinkedWorld and DungeonWorldRaid[questData.LinkedWorld]
            if raid then return true, pcall(FireRaidIfNeeded, raid[1], raid[2]) end
            return false

        elseif objType == "DoDungeon" then
            local diff = args[1] and DungeonIdHandlers[args[1]]
            if diff then return true, pcall(FireRaidIfNeeded, args[1], diff) end
            return false

        elseif objType == "DoDungeonWithDifficulty" then
            -- Objective args = {dungeonId, difficulty}
            if args[1] and DungeonPlaceIds[args[1]] then
                return true, pcall(FireRaidIfNeeded, args[1], args[2] or 5)
            end
            return false

        elseif objType == "TimeInWorld" then
            return true, pcall(TimeInWorldHandler, questData, amount, args[1])

        elseif objType == "CustomEvent" then
            local handler = args[1] and CustomEventHandlers[args[1]]
            if handler then return true, pcall(handler, questData, amount, ctx) end
            return false

        elseif objType == "DoDungeonWithClass" then
            local handler = args[1] and DungeonWithClassHandlers[args[1]]
            if handler then return true, pcall(handler, questData, amount, ctx) end
            return false

        elseif objType == "DoDungeonWithWorldAndDifficulty" then
            local raid = questData.LinkedWorld and DungeonWorldRaid[questData.LinkedWorld]
            if raid then return true, pcall(FireRaidIfNeeded, raid[1], args[1] or raid[2]) end
            return false

        elseif objType == "DoRandomDungeonWithDifficulty" then
            return true, pcall(RandomDungeonHandler, questData, amount, args[1])
        end

        return false
    end

    local function StopCurrentAction(questId, questData)
        if questData.Objective[1] == "CustomEvent" and questData.Objective[3]
            and questData.Objective[3][1] == "UpgradeCompleted" then
            -- цикл сам доделает итерацию, вернёт броню, продаст и вернёт автопродажу
            UpgradeState.running = false
        end
        -- Класс возвращается через ReconcilePending (см. RunLoop) - так он
        -- переживает рестарт скрипта после телепорта.
    end

    -- ========================================================
    -- Выбор следующего квеста
    -- ========================================================
    local function GetNextIncompleteQuest(questIds, isWeekly, weeklyData)
        local skippedNames = {}
        for _, questId in ipairs(questIds) do
            if not claimedQuestIds[questId] then
                local questData = GetQuestData(questId)
                if questData and not questData.Disabled then
                    local vipBlocked = false
                    if isWeekly then
                        local entry = GetWeeklyQuestEntry(weeklyData, questId)
                        if entry and entry.isVIP and not HasVIP then vipBlocked = true end
                    end

                    if vipBlocked then
                        table.insert(skippedNames, (questData.Name or tostring(questId)) .. ' (VIP required)')
                    else
                        local current, isDone, claimed = GetQuestStatus(questId, questData, isWeekly, weeklyData)
                        if current == nil then
                            -- статус неизвестен в этот тик
                        elseif isDone then
                            if not claimed then ClaimQuest(questId, isWeekly, questData.Name) end
                        else
                            if CanHandle(questData, questData.Objective) then
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
    -- Состояние / статус
    -- ========================================================
    local runToken = 0
    local Running = false
    local CurrentQuestId = nil
    local CheckInterval = 2
    local lastSkippedKey = nil
    local lastErrKey = nil
    local currentRunningMode = nil -- 'Daily' | 'Weekly' | 'Both' | nil

    local statusNotification = nil

    local function DestroyStatusNotification()
        if statusNotification then
            pcall(function() statusNotification:Destroy() end)
            statusNotification = nil
        end
    end

    local function SetStatus(text)
        if statusNotification then
            local ok = pcall(function() statusNotification:ChangeDescription(text) end)
            if ok then return end
            statusNotification = nil
        end
        if not Library then return end
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

    local function StatusLine(questData, questId, remaining)
        local line = (questData.Name or tostring(questId)) .. ' — ' .. tostring(remaining) .. ' left'
        local cq = Persist.classQuest
        if cq and cq.questId == questId then
            line = line .. ' [' .. tostring(cq.target) .. ']'
        end
        return line
    end

    -- Возврат класса / автопродажи, если текущий квест уже не тот, ради которого
    -- они менялись. false = ещё в процессе, надо подождать.
    local function ReconcilePending(questId)
        local cq = Persist.classQuest
        if cq and cq.questId ~= questId then
            if not RestoreClass() then return false end
        end
        local bk = Persist.sellBackup
        if bk and bk.questId ~= questId and not UpgradeState.busy then
            RestoreSelling()
        end
        return true
    end

    -- Подбирает следующий квест. В 'Both' оба пула сканируются (чтобы всё
    -- выполненное клеймилось), работать приоритетно начинаем с Daily.
    local function PickQuest(mode)
        local onlyHot = IsOnlyHot()
        if mode == 'Both' then
            local dIds = GetActiveDailyQuestIds(onlyHot)
            local weeklyData = GetWeeklyData()
            local wIds = GetActiveWeeklyQuestIds(weeklyData)

            local dQ, dData, dCur, dSkip
            if #dIds > 0 then dQ, dData, dCur, dSkip = GetNextIncompleteQuest(dIds, false) end
            dSkip = dSkip or {}

            local wQ, wData, wCur, wSkip
            if #wIds > 0 then wQ, wData, wCur, wSkip = GetNextIncompleteQuest(wIds, true, weeklyData) end
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
        else
            local weeklyData = GetWeeklyData()
            local ids = GetActiveWeeklyQuestIds(weeklyData)
            local qId, qData, cur, skipped = GetNextIncompleteQuest(ids, true, weeklyData)
            return qId, qData, cur, skipped, mode
        end
    end

    -- Клеймит всё остальное выполненное, пока работаем над текущим квестом
    local function SweepClaims(mode, currentId, weeklyData)
        if mode == 'Daily' or mode == 'Both' then
            for _, otherId in ipairs(GetActiveDailyQuestIds(false)) do
                if otherId ~= currentId and not claimedQuestIds[otherId] then
                    local od = GetQuestData(otherId)
                    if od and not od.Disabled then
                        local _, oDone, oClaimed = GetQuestStatus(otherId, od, false, nil)
                        if oDone and not oClaimed then ClaimQuest(otherId, false, od.Name) end
                    end
                end
            end
        end
        if mode == 'Weekly' or mode == 'Both' then
            local wData = weeklyData or GetWeeklyData()
            for _, otherId in ipairs(GetActiveWeeklyQuestIds(wData)) do
                if otherId ~= currentId and not claimedQuestIds[otherId] then
                    local od = GetQuestData(otherId)
                    if od and not od.Disabled then
                        local _, oDone, oClaimed = GetQuestStatus(otherId, od, true, wData)
                        if oDone and not oClaimed then ClaimQuest(otherId, true, od.Name) end
                    end
                end
            end
        end
    end

    -- ========================================================
    -- MAIN LOOP
    -- ========================================================
    local function RunLoop(mode)
        runToken += 1
        local myToken = runToken
        Running = true
        currentRunningMode = mode

        SetStatus('Starting ' .. mode .. ' quests...')

        while Running and myToken == runToken do
            local questId, questData, current, skippedNames, activeSubMode = PickQuest(mode)

            if not ReconcilePending(questId) then
                SetStatus('Возвращаю класс / настройки...')
                task.wait(3)

            elseif not questId then
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
                local isWeekly = (activeSubMode == 'Weekly')

                CurrentQuestId = questId
                local lastRemaining = amount - (current or 0)
                SetStatus(StatusLine(questData, questId, lastRemaining))

                local ctx = { questId = questId, isWeekly = isWeekly, current = current or 0 }
                local reinvoke = ShouldReinvoke(objective)
                local firedKey = tostring(questId)

                while Running and myToken == runToken do
                    local weeklyData = isWeekly and GetWeeklyData() or nil
                    local newCurrent, isDone, claimed = GetQuestStatus(questId, questData, isWeekly, weeklyData)

                    if not Running or myToken ~= runToken then break end

                    SweepClaims(mode, questId, weeklyData)

                    if newCurrent == nil then
                        task.wait(CheckInterval)
                    elseif isDone then
                        pcall(StopCurrentAction, questId, questData)
                        if not claimed then ClaimQuest(questId, isWeekly, questData.Name) end
                        break
                    else
                        ctx.current = newCurrent

                        if reinvoke or not Persist.fired[firedKey] then
                            if not reinvoke then
                                Persist.fired[firedKey] = true
                                SaveState()
                            end
                            local handled, ok, err = RunHandlerFor(questData, objective, amount, ctx)
                            if handled and not ok then
                                local ek = firedKey .. tostring(err)
                                if ek ~= lastErrKey then
                                    lastErrKey = ek
                                    warn('[Quests] Handler error "' .. tostring(questData.Name) .. '": ' .. tostring(err))
                                end
                            end
                        end

                        local remaining = amount - newCurrent
                        if remaining ~= lastRemaining then
                            lastRemaining = remaining
                            SetStatus(StatusLine(questData, questId, remaining))
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
            if questData then pcall(StopCurrentAction, CurrentQuestId, questData) end
        end
        CurrentQuestId = nil
        DestroyStatusNotification()

        -- если остановили посреди класс-квеста: вернуть класс
        if Persist.classQuest then
            task.spawn(function()
                for _ = 1, 6 do
                    if RestoreClass() then break end
                    task.wait(5)
                end
            end)
        end
    end

    -- ========================================================
    -- Вкладка Quests
    -- ========================================================
    task.spawn(function()
        while true do
            pcall(TryClaimDailyLogin)
            task.wait(60)
        end
    end)

    QuestsMainTab:AddToggle('autoBothQuests', {
        Text = 'Complete All',
        Tooltip = 'Daily сначала, потом Weekly',
        Default = false,
        Callback = function(value)
            if value then
                if currentRunningMode == 'Both' then return end
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

    QuestsMainTab:AddDivider()

    QuestsMainTab:AddToggle('questsOnlyHot', {
        Text = 'Daily: only Hot quests',
        Tooltip = 'Делать только 3 горящих (🔥) daily-квеста - те, что идут в прогресс тиров. Остальные 7 слотов пропускаются (но если они уже выполнены - заклеймятся).',
        Default = false,
    })

    QuestsMainTab:AddDivider()
    QuestsMainTab:AddLabel('Класс для квестов "Dungeons with Tier X class". None = квест пропускается.', true)

    for _, tier in ipairs({2, 3, 4}) do
        QuestsMainTab:AddDropdown('questTier' .. tier .. 'Class', {
            Text = 'Tier ' .. tier .. ' class',
            Values = ClassNames,
            Default = DefaultTierClass[tier] or 'None',
            Multi = false,
        })
    end
end)()
