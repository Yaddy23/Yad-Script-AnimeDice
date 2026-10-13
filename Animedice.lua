--[[
    ==============================================================================
    YadScript — ANIME DICE
    Features:
      - Auto Roll with server debounce synchronization
      - Auto Collect Plot Balance with configurable interval (seconds)
      - Auto Equip Best Units with configurable interval (seconds)
      - Auto Level Up Slots with precondition cost checks
      - Auto Buy Upgrades with Multi-Category Focus Dropdown & Priority Purchasing
      - Auto Rebirth with cost validation
      - Auto Buy New Dice
      - Auto Claim Freebies (Daily, Offline, Spins, Group if joined)
      - Movement Hacks (WalkSpeed, JumpPower, InfJump, Noclip)
      - Live Theme Switcher (2K Frost, Aqua, Light, Dark)
    ==============================================================================
]]

-- ── 1. STRICT AUTO-CLEANUP ───────────────────────────────────────────────────────
if _G.AnimeDiceCleanup then pcall(_G.AnimeDiceCleanup) end
if _G.AnimeDiceWindow and _G.AnimeDiceWindow.Destroy then pcall(function() _G.AnimeDiceWindow:Destroy() end) end
if _G.AnimeDiceMinGui then pcall(function() _G.AnimeDiceMinGui:Destroy() end) end
_G.AnimeDiceRunning = false

local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local thisRunId         = HttpService:GenerateGUID(false)
_G.AnimeDiceRunId       = thisRunId
_G.AnimeDiceRunning     = true

local _conns = {}
_G.AnimeDiceCleanup = function()
    _G.AnimeDiceRunning = false
    _G.AnimeDiceRunId   = nil
    for _, c in ipairs(_conns) do pcall(function() c:Disconnect() end) end
    table.clear(_conns)
    if _G.AnimeDiceWindow and _G.AnimeDiceWindow.Destroy then
        pcall(function() _G.AnimeDiceWindow:Destroy() end)
        _G.AnimeDiceWindow = nil
    end
    if _G.AnimeDiceMinGui then
        pcall(function() _G.AnimeDiceMinGui:Destroy() end)
        _G.AnimeDiceMinGui = nil
    end
end

-- ── 2. SERVICES & NETWORK REMOTES ────────────────────────────────────────────────
local LP = Players.LocalPlayer
local network = RS:WaitForChild("Network")
local VirtualUser = game:GetService("VirtualUser")

local RollService            = network:WaitForChild("RollService")
local PlotService            = network:WaitForChild("PlotService")
local RebirthService         = network:WaitForChild("RebirthService")
local DiceShopService        = network:WaitForChild("DiceShopService")
local DailyRewardService     = network:WaitForChild("DailyRewardService")
local GroupRewardService     = network:WaitForChild("GroupRewardService")
local OfflineEarningsService = network:WaitForChild("OfflineEarningsService")
local SpinService            = network:WaitForChild("SpinService")
local UpgradeServiceRE       = network:WaitForChild("RE"):WaitForChild("BuyUpgrade")

-- Towers Network Remotes
local TowerNetwork           = network:FindFirstChild("Towers")
local EquipBestTowerTeamRE   = TowerNetwork and TowerNetwork:FindFirstChild("RE") and TowerNetwork.RE:FindFirstChild("EquipBestTowerTeam")
local PlayTowerRF            = TowerNetwork and TowerNetwork:FindFirstChild("RF") and TowerNetwork.RF:FindFirstChild("PlayTower")
local CancelTowerRF          = TowerNetwork and TowerNetwork:FindFirstChild("RF") and TowerNetwork.RF:FindFirstChild("CancelTower")

-- Grade Network Remotes
local GradeNetwork           = network:FindFirstChild("GradeService")
local SetGradeProtectedRE    = GradeNetwork and GradeNetwork:FindFirstChild("RE") and GradeNetwork.RE:FindFirstChild("SetGradeProtected")
local RollGradeRE            = GradeNetwork and GradeNetwork:FindFirstChild("RE") and GradeNetwork.RE:FindFirstChild("Roll")

-- Sell Network Remotes
local SellNetwork            = network:FindFirstChild("SellService")
local SellInventoryRF        = SellNetwork and SellNetwork:FindFirstChild("RF") and SellNetwork.RF:FindFirstChild("SellInventory")
local SellEquippedRF         = SellNetwork and SellNetwork:FindFirstChild("RF") and SellNetwork.RF:FindFirstChild("SellEquipped")
local UpdateAutoSellRE       = SellNetwork and SellNetwork:FindFirstChild("RE") and SellNetwork.RE:FindFirstChild("UpdateAutoSell")

local DataController         = require(RS.Framework.Features.Data.DataController)
local BuffController         = require(RS.Framework.Features.Buffs.BuffController)
local UnitUtil               = require(RS.Framework.Features.Inventory.Kinds.Unit.UnitUtil)
local EntryRegistry          = require(RS.Framework.Features.Inventory.EntryRegistry)
local GradesModule           = require(RS.Framework.Features.Grades.Grades)
local TreeStructure          = require(RS.Framework.Features.Upgrades.TreeStructure)
local RebirthsModule         = require(RS.Framework.Features.Rebirth.Rebirths)
local UpgradesModule         = require(RS.Framework.Features.Upgrades.Upgrades)
local DiceModule             = require(RS.Framework.Features.Rolling.Dice)
local GroupRewardConfig      = require(RS.Framework.Features.Rewards.GroupRewardConfig)
local NumberFormatter        = require(RS.Packages.NumberFormatter)

local httpRequest            = (request or http_request or (syn and syn.request) or (http and http.request))

local TowerController        = nil
pcall(function()
    TowerController = require(RS.Framework.Features.Towers.TowerController)
end)
local UIReferences           = nil
pcall(function()
    UIReferences = require(RS.Framework.Features.UI.UIReferences)
end)
local TowersModule           = nil
pcall(function()
    TowersModule = require(RS.Framework.Features.Towers.Towers)
end)

-- ── 3. UPGRADE CATEGORIES & TOWER MAPPING ────────────────────────────────────────
local UpgradeCategories = {
    ["Luck & Fortune"]      = {"Luck", "Fortune"},
    ["Roll Speed"]          = {"Roll Speed"},
    ["Money"]               = {"Money"},
    ["Unit Storage"]        = {"Unit Storage"},
    ["Damage"]              = {"Damage"},
    ["Health"]              = {"Health"},
    ["Walkspeed"]           = {"Walkspeed"},
    ["Sell"]                = {"Sell"},
}

local function getCategoryOfKey(key)
    for catName, prefixes in pairs(UpgradeCategories) do
        for _, p in ipairs(prefixes) do
            if key:sub(1, #p) == p then
                return catName
            end
        end
    end
    return "Other"
end

-- Tower display mappings
local TowerDisplayNameMap = {
    ["Dragon Tower (Easy - 100 Floors)"]           = "Dragon Tower",
    ["Cursed Tower (Medium - 100 Floors)"]         = "Cursed Tower",
    ["Pirate Tower (Hard - 100 Floors)"]           = "Pirate Tower",
    ["Hidden Leaf Tower (Extreme - 100 Floors)"]   = "Hidden Leaf Tower",
    ["Infinity Tower (Infinity - Endless)"]        = "Infinity Tower",
}

local TowerDisplayOptions = {
    "Dragon Tower (Easy - 100 Floors)",
    "Cursed Tower (Medium - 100 Floors)",
    "Pirate Tower (Hard - 100 Floors)",
    "Hidden Leaf Tower (Extreme - 100 Floors)",
    "Infinity Tower (Infinity - Endless)",
}

-- Grade, Rarity & Rebirth mappings
local GradeOrder = {
    ["D"] = 1,
    ["C"] = 2,
    ["B"] = 3,
    ["A"] = 4,
    ["A+"] = 5,
    ["S"] = 6,
    ["S+"] = 7,
    ["Z"] = 8,
    ["Z+"] = 9,
    ["God"] = 10
}

local RarityOrder = {
    ["Common"] = 1,
    ["Uncommon"] = 2,
    ["Rare"] = 3,
    ["Epic"] = 4,
    ["Legendary"] = 5,
    ["Mythical"] = 6,
    ["Secret I"] = 7,
    ["Secret"] = 7,
    ["Exotic"] = 8,
    ["Celestial"] = 9,
    ["Divine"] = 10,
    ["Exclusive"] = 11
}

local RebirthDisplayOptions = {
    "Rebirth 1",
    "Rebirth 2",
    "Rebirth 3",
    "Rebirth 4",
    "Rebirth 5",
    "Rebirth 6",
    "Rebirth 7",
    "Rebirth 8",
    "Rebirth 9",
    "Rebirth 10",
    "Rebirth 11",
    "Rebirth 12 (MAX)",
    "Unlimited / Always Max"
}

-- ── 4. STATE & SETTINGS (all features start disabled by default) ────────────────
local State = {
    -- Anti-AFK (100% Safe Client-Side - enabled by default)
    AntiAFK                  = true,

    -- Auto Farming (ALL FALSE BY DEFAULT)
    AutoRoll                 = false,
    AutoCollect              = false,
    CollectInterval          = 0.5,
    AutoEquipBest            = false,
    EquipInterval            = 3.0,
    AutoLevelSlots           = false,
    TargetUnitLevel          = 30,
    AutoRebirth              = false,
    TargetRebirth            = 12,
    AutoUpgrades             = false,
    OnlySelectedUpgrades     = false,
    SelectedUpgradeCategories = {
        ["Luck & Fortune"] = true,
        ["Roll Speed"]     = true,
        ["Money"]          = true,
    },
    AutoBuyDice              = false,
    AutoClaim                = false,

    -- Auto Sell Units (ALL FALSE / SAFE BY DEFAULT)
    AutoSellUnits            = false,
    SellInterval             = 5,
    InGameAutoSellThreshold  = 100000000, -- 100m (1 in 100,000,000)
    InGameAutoSellInput      = "100m",
    SellBelowChance          = false,     -- Include 1 in X chance check in inventory sweeping
    SelectedSellRarities     = {
        ["Common"] = true,
        ["Uncommon"] = true,
        ["Rare"] = true,
    },
    ProtectPlottedUnits      = true,
    ProtectGradeSPlus        = true,
    ProtectLockedUnits       = true,

    -- Grade System (ALL FALSE BY DEFAULT)
    AutoRerollGrade          = false,
    TargetGradeUnitKey       = "",
    TargetGrade              = "S",
    GradeRollDelay           = 0.35,

    -- Discord Webhook
    WebhookURL               = "",
    WebhookEnabled           = false,
    WebhookNotifyRolls       = true,
    WebhookMinRarity         = "Mythical",
    WebhookNotifyRebirth     = true,
    WebhookNotifyGrade       = true,
    WebhookPeriodicSummary   = false,
    WebhookSummaryInterval   = 15,

    -- Auto Tower (ALL FALSE BY DEFAULT)
    AutoTower                = false,
    SelectedTower            = "Dragon Tower",
    AutoEquipBestTowerTeam   = true,
    HideTowerScreen          = true,

    -- Movement (ALL FALSE BY DEFAULT)
    WalkSpeed                = 16,
    JumpPower                = 50,
    InfJump                  = false,
    Noclip                   = false,
}

-- ── 5. CORE AUTOMATION ENGINE ────────────────────────────────────────────────────

-- 1. Auto Collect Money from all 13 Plot Slots
local function collectAllSlots()
    pcall(function()
        for slot = 1, 13 do
            PlotService.RE.CollectBalance:FireServer(slot)
        end
    end)
end

-- 2. Auto Equip Best Anime Units
local function equipBestUnits()
    pcall(function()
        PlotService.RE.EquipBest:FireServer()
    end)
end

-- 3. Auto Level Up Slots with Precondition Check
local function levelUpAllSlots()
    pcall(function()
        local curMoney = DataController.Money()
        if not curMoney or curMoney <= 0 then return end
        local targetLvl = tonumber(State.TargetUnitLevel) or 30
        for slot = 1, 13 do
            local slotData = DataController.Slots[tostring(slot)] and DataController.Slots[tostring(slot)]()
            if slotData and slotData.unitId then
                local unitData = DataController.Inventory[slotData.unitId] and DataController.Inventory[slotData.unitId]()
                if unitData then
                    local currentLvl = (unitData.attributes and unitData.attributes.level) or 1
                    if currentLvl < targetLvl then
                        local price = UnitUtil.GetLevelPrice(unitData.name, unitData.attributes)
                        if price and curMoney >= price then
                            curMoney = curMoney - price
                            PlotService.RE.LevelUpSlot:FireServer(slot)
                        end
                    end
                end
            end
        end
    end)
end

-- Discord Webhook Helper Engine
local function sendDiscordWebhook(title, description, color, fields)
    if not State.WebhookEnabled or not State.WebhookURL or State.WebhookURL == "" or not httpRequest then return end
    task.spawn(function()
        pcall(function()
            local payload = {
                username = "Yad Script | Anime Dice",
                avatar_url = "",
                embeds = {
                    {
                        title = title,
                        description = description,
                        color = color or 0x00FFE0,
                        fields = fields or {},
                        footer = {
                            text = "Yad Script • Anime Dice Automation • " .. os.date("%X")
                        },
                        timestamp = DateTime.now():ToIsoDate()
                    }
                }
            }
            httpRequest({
                Url = State.WebhookURL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode(payload)
            })
        end)
    end)
end

-- 4. Auto Rebirth with Precondition & Target Limit Check
local function checkAndRebirth()
    pcall(function()
        local curRebirth = DataController.Rebirth()
        local targetRebirth = tonumber(State.TargetRebirth) or 12
        if curRebirth >= targetRebirth then return end

        local curMoney = DataController.Money()
        local nextData = RebirthsModule.GetNext(curRebirth)
        if nextData and nextData.cost and curMoney >= nextData.cost then
            RebirthService.RE.Rebirth:FireServer()
            if State.WebhookEnabled and State.WebhookNotifyRebirth then
                local newLvl = curRebirth + 1
                sendDiscordWebhook(
                    "Rebirth Complete! (Rebirth " .. tostring(newLvl) .. ")",
                    "Player **" .. LP.DisplayName .. "** has successfully rebirthed to the next tier.",
                    0xFFD700,
                    {
                        {name = "New Rebirth Level", value = "Rebirth " .. tostring(newLvl), inline = true},
                        {name = "Money Multiplier", value = "x" .. tostring(nextData.moneyMultiplier or "?"), inline = true},
                        {name = "Luck Multiplier", value = "x" .. tostring(nextData.luckMultiplier or "?"), inline = true}
                    }
                )
            end
        end
    end)
end

-- 4.1 Selectable Auto Sell Engine
local function sellSelectedUnits()
    local soldCount = 0
    local earned = 0
    pcall(function()
        if not SellInventoryRF then return end
        local inv = DataController.Inventory and DataController.Inventory()
        if not inv then return end

        local plotted = {}
        for slot = 1, 13 do
            local sData = DataController.Slots[tostring(slot)] and DataController.Slots[tostring(slot)]()
            if sData and sData.unitId then
                plotted[sData.unitId] = true
            end
        end

        local towerTeam = {}
        if DataController.TowerTeam then
            local tt = DataController.TowerTeam()
            if type(tt) == "table" then
                for _, uid in pairs(tt) do
                    if type(uid) == "string" then towerTeam[uid] = true end
                end
            end
        end

        local toSell = {}
        for id, unit in pairs(inv) do
            if type(unit) == "table" and unit.name and unit.attributes then
                local isPlotted = plotted[id] == true
                local isTower = towerTeam[id] == true
                local isLocked = unit.attributes and unit.attributes.locked == true

                local canSell = true
                if State.ProtectPlottedUnits and (isPlotted or isTower) then
                    canSell = false
                end
                if State.ProtectLockedUnits and isLocked then
                    canSell = false
                end
                if State.ProtectGradeSPlus and unit.attributes and unit.attributes.grade then
                    local gOrder = GradeOrder[unit.attributes.grade] or 0
                    if gOrder >= 6 then
                        canSell = false
                    end
                end

                if canSell then
                    local cfg = EntryRegistry.getEntryConfig(unit.name)
                    local rarity = (cfg and cfg.rarity) or "Unknown"
                    local match = false
                    for selName, isSelected in pairs(State.SelectedSellRarities) do
                        if isSelected and (selName == rarity or string.find(selName, rarity, 1, true)) then
                            match = true
                            break
                        end
                    end

                    if match then
                        table.insert(toSell, id)
                        if #toSell >= 50 then
                            break
                        end
                    elseif State.SellBelowChance and cfg and cfg.chance then
                        local ch = cfg.chance()
                        if ch and ch > 0 and ch < (State.InGameAutoSellThreshold or 0) then
                            table.insert(toSell, id)
                            if #toSell >= 50 then
                                break
                            end
                        end
                    end
                end
            end
        end

        if #toSell > 0 then
            local res1, res2 = SellInventoryRF:InvokeServer(toSell)
            earned = res1 or 0
            soldCount = res2 or #toSell
        end
    end)
    return soldCount, earned
end

-- 4.2 Auto Roll Grade Engine
local function rollGradeForSelectedUnit()
    local success = false
    pcall(function()
        if not RollGradeRE or not State.TargetGradeUnitKey or State.TargetGradeUnitKey == "" then return end
        local inv = DataController.Inventory
        if not inv then return end

        local unit = inv[State.TargetGradeUnitKey] and inv[State.TargetGradeUnitKey]()
        if not unit or not unit.attributes then return end

        local curGrade = unit.attributes.grade or "D"
        local curOrder = GradeOrder[curGrade] or 1
        local targetOrder = GradeOrder[State.TargetGrade] or 6

        if curOrder >= targetOrder then
            return -- Already at or above target grade
        end

        local gemData = inv.Gems and inv.Gems()
        if not gemData or (gemData.amount or 0) <= 0 then
            return -- No gems left
        end

        RollGradeRE:FireServer(State.TargetGradeUnitKey, true)
        success = true

        -- Check if rolled new grade and notify
        task.delay(0.2, function()
            pcall(function()
                local updatedUnit = inv[State.TargetGradeUnitKey] and inv[State.TargetGradeUnitKey]()
                if updatedUnit and updatedUnit.attributes and updatedUnit.attributes.grade then
                    local newGrade = updatedUnit.attributes.grade
                    local newOrder = GradeOrder[newGrade] or 1
                    if newOrder >= 6 and State.WebhookEnabled and State.WebhookNotifyGrade then
                        sendDiscordWebhook(
                            "High Grade Rolled! (Grade " .. newGrade .. ")",
                            "Unit **" .. updatedUnit.name .. "** received a high grade from rerolling.",
                            0x9B59B6,
                            {
                                {name = "Unit", value = updatedUnit.name, inline = true},
                                {name = "Grade Obtained", value = newGrade, inline = true},
                                {name = "Gems Remaining", value = tostring(inv.Gems and inv.Gems().amount or 0), inline = true}
                            }
                        )
                    end
                end
            end)
        end)
    end)
    return success
end

-- 5. Auto Buy Upgrades with Dropdown Category Prioritization
local function buyPrioritizedUpgrades()
    pcall(function()
        if not UpgradesModule or not TreeStructure then return end
        local curMoney = DataController.Money()
        if not curMoney or curMoney <= 0 then return end

        local unownedAvailable = {}
        for key, data in pairs(UpgradesModule) do
            local isOwned = DataController.Upgrades[key] and DataController.Upgrades[key]()
            if not isOwned then
                local parent = TreeStructure.GetParent(key)
                local parentUnlocked = (not parent or parent == "Start") or (DataController.Upgrades[parent] and DataController.Upgrades[parent]())
                if parentUnlocked and data.price and curMoney >= data.price then
                    table.insert(unownedAvailable, {
                        key = key,
                        price = data.price,
                        category = getCategoryOfKey(key)
                    })
                end
            end
        end

        if #unownedAvailable == 0 then return end

        local focusedList = {}
        local otherList = {}

        for _, item in ipairs(unownedAvailable) do
            if State.SelectedUpgradeCategories[item.category] then
                table.insert(focusedList, item)
            else
                table.insert(otherList, item)
            end
        end

        table.sort(focusedList, function(a, b) return a.price < b.price end)
        table.sort(otherList, function(a, b) return a.price < b.price end)

        -- Buy selected categories first
        for _, item in ipairs(focusedList) do
            if curMoney >= item.price then
                curMoney = curMoney - item.price
                UpgradeServiceRE:FireServer(item.key)
                task.wait(0.12)
            end
        end

        -- If not restricted to only-selected, buy remaining categories too
        if not State.OnlySelectedUpgrades then
            for _, item in ipairs(otherList) do
                if curMoney >= item.price then
                    curMoney = curMoney - item.price
                    UpgradeServiceRE:FireServer(item.key)
                    task.wait(0.12)
                end
            end
        end
    end)
end

-- 6. Auto Buy Affordable Unowned Dice
local function buyAffordableDice()
    pcall(function()
        if not DiceModule then return end
        local allDice = DiceModule.GetAll()
        local curMoney = DataController.Money()
        for name, data in pairs(allDice) do
            local isOwned = DataController.OwnedDice[name] and DataController.OwnedDice[name]()
            if not isOwned and data.price and data.price <= curMoney then
                DiceShopService.RE.BuyDice:FireServer(name)
                task.wait(0.4)
            end
        end
    end)
end

-- 7. Auto Claim Free Rewards (checks group first to avoid duplicate alerts)
local function claimAllFreebies()
    pcall(function()
        DailyRewardService.RE.Claim:FireServer()
        OfflineEarningsService.RE.Claim:FireServer()
        SpinService.RE.Use:FireServer()

        -- Claim group reward only if player is in the group and hasn't claimed yet
        if GroupRewardConfig and GroupRewardConfig.GroupId then
            local inGroup = false
            pcall(function()
                inGroup = LP:IsInGroup(GroupRewardConfig.GroupId)
            end)
            if inGroup and DataController.ClaimedGroupReward and not DataController.ClaimedGroupReward() then
                GroupRewardService.RE.Claim:FireServer()
            end
        end
    end)
end

-- 8. Auto Tower Automation Handler
local function handleAutoTower()
    pcall(function()
        if not State.AutoTower then return end

        local screen = UIReferences and UIReferences.Root and UIReferences.Root.Tower and UIReferences.Root.Tower.Screen
        local hidden = screen and screen.Parent and screen.Parent:FindFirstChild("Hidden")
        local inTower = (hidden and hidden.Visible == true) or (screen and screen.Visible == true)

        if inTower then
            -- Hide tower battle screen if option enabled
            if State.HideTowerScreen and screen and screen.Visible and hidden then
                pcall(function()
                    if firesignal then
                        firesignal(hidden.Activated)
                    end
                end)
            end

            -- Check and press in-game Auto button to keep animation and next floor flowing
            if screen and screen:FindFirstChild("Buttons") and screen.Buttons:FindFirstChild("Auto") then
                local autoBtn = screen.Buttons.Auto
                local grad = autoBtn:FindFirstChildOfClass("UIGradient")
                local isGreen = grad and tostring(grad.Color):find("0.298")
                if not isGreen and firesignal then
                    pcall(function() firesignal(autoBtn.Activated) end)
                end
            end
        else
            -- Not in tower: equip best team and start selected tower immediately
            if State.AutoEquipBestTowerTeam and EquipBestTowerTeamRE then
                pcall(function() EquipBestTowerTeamRE:FireServer() end)
                task.wait(0.3)
            end

            local towerTarget = State.SelectedTower or "Dragon Tower"
            local started = false
            if TowerController and TowerController.startTower then
                started = TowerController.startTower(towerTarget)
            end
            if not started and PlayTowerRF then
                PlayTowerRF:InvokeServer(towerTarget)
            end
            task.wait(1.2)

            -- Hide screen right after start if enabled
            if State.HideTowerScreen and screen and screen.Visible and hidden and firesignal then
                pcall(function() firesignal(hidden.Activated) end)
            end
        end
    end)
end

-- ── 5.1 ANTI-AFK & ANTI-KICK DEFENSE ENGINE (TRIPLE-LAYER ZERO-DISCONNECT) ────────

local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = nil
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

-- Layer 1: Destroy the game's 19-minute AFK script immediately
local function neutralizeGameAFK()
    pcall(function()
        local afkScript = LP.PlayerScripts:FindFirstChild("AFK")
        if afkScript then
            afkScript.Disabled = true
            afkScript:Destroy()
        end
    end)
end
neutralizeGameAFK()

table.insert(_conns, LP.PlayerScripts.ChildAdded:Connect(function(child)
    if child.Name == "AFK" and child:IsA("LocalScript") then
        pcall(function()
            child.Disabled = true
            child:Destroy()
        end)
    end
end))

-- Layer 2: Intercept Teleport calls that kick the player due to AFK script
pcall(function()
    if hookfunction then
        local oldTeleport
        oldTeleport = hookfunction(TeleportService.Teleport, function(self, placeId, player, ...)
            if State.AntiAFK then
                local trace = debug.traceback()
                if string.find(trace, "AFK") or string.find(trace, "scheduleTeleport") then
                    return
                end
            end
            return oldTeleport(self, placeId, player, ...)
        end)
    end
end)

pcall(function()
    if hookmetamethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if State.AntiAFK and (method == "Teleport" or method == "teleport") and self == TeleportService then
                local trace = debug.traceback()
                if string.find(trace, "AFK") or string.find(trace, "scheduleTeleport") then
                    return
                end
            end
            return oldNamecall(self, ...)
        end)
    end
end)

-- Layer 3: Block Roblox Engine 20-minute kick (LP.Idled)
pcall(function()
    if getconnections then
        for _, c in ipairs(getconnections(LP.Idled)) do
            pcall(function() c:Disable() end)
        end
    end
end)

table.insert(_conns, LP.Idled:Connect(function()
    if not State.AntiAFK then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end))

-- Layer 4: Virtual Input Heartbeat Loop every 40 seconds, 100% disconnect prevention
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(40)
        if State.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
            pcall(function()
                if VirtualInputManager then
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
                    task.wait(0.03)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
                end
            end)
            neutralizeGameAFK()
        end
    end
end)

-- ── 6. ASYNC AUTOMATION THREADS ──────────────────────────────────────────────────

-- Thread 1: Auto Collect Money (configurable interval)
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        if State.AutoCollect then
            collectAllSlots()
        end
        local delaySec = tonumber(State.CollectInterval) or 0.5
        if delaySec < 0.1 then delaySec = 0.1 end
        task.wait(delaySec)
    end
end)

-- Thread 2: Auto Equip Best Units (configurable interval)
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        if State.AutoEquipBest then
            equipBestUnits()
        end
        local delaySec = tonumber(State.EquipInterval) or 3.0
        if delaySec < 1.0 then delaySec = 1.0 end
        task.wait(delaySec)
    end
end)

-- Thread 3: Slot Level Ups
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(0.7)
        if State.AutoLevelSlots then
            levelUpAllSlots()
        end
    end
end)

-- Thread 4: Precise Roll Loop (synced with server debounce)
task.spawn(function()
    local lastRollTime = 0
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(0.1)
        if State.AutoRoll then
            pcall(function()
                if not DataController.AutoRoll() then
                    RollService.RE.SetAutoRoll:FireServer(true)
                end
            end)

            local duration = 1.9
            pcall(function()
                local d = BuffController.GetBuff("Roll Duration")
                if type(d) == "number" and d > 0 then
                    duration = d
                end
            end)

            if os.clock() - lastRollTime >= (duration + 0.1) then
                lastRollTime = os.clock()
                pcall(function()
                    RollService.RF.RollDice:InvokeServer()
                end)
            end
        else
            pcall(function()
                if DataController.AutoRoll() then
                    RollService.RE.SetAutoRoll:FireServer(false)
                end
            end)
        end
    end
end)

-- Thread 5: Upgrades, Rebirth, Dice & Claims
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(1.5)
        if State.AutoRebirth then
            checkAndRebirth()
        end
        if State.AutoUpgrades then
            buyPrioritizedUpgrades()
        end
        if State.AutoBuyDice then
            buyAffordableDice()
        end
        if State.AutoClaim then
            claimAllFreebies()
        end
    end
end)

-- Thread 6: Auto Tower Loop
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(1.5)
        if State.AutoTower then
            handleAutoTower()
        end
    end
end)

-- Thread 7: Anti-AFK Background Heartbeat
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        if State.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end
        task.wait(45)
    end
end)

-- Thread 8: Selectable Auto Sell Units Loop
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        local interval = tonumber(State.SellInterval) or 5
        if interval < 1 then interval = 1 end
        task.wait(interval)
        if State.AutoSellUnits then
            pcall(sellSelectedUnits)
        end
    end
end)

-- Thread 9: Auto Roll Grade Loop
task.spawn(function()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(State.GradeRollDelay or 0.35)
        if State.AutoRerollGrade then
            local ok = rollGradeForSelectedUnit()
            if not ok then
                State.AutoRerollGrade = false
            end
        end
    end
end)

-- Thread 10: Webhook High-Tier Rolls Watcher
task.spawn(function()
    local knownUnits = {}
    pcall(function()
        local inv = DataController.Inventory and DataController.Inventory()
        if inv then
            for id, _ in pairs(inv) do knownUnits[id] = true end
        end
    end)

    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(0.6)
        pcall(function()
            local inv = DataController.Inventory and DataController.Inventory()
            if not inv then return end

            for id, unit in pairs(inv) do
                if not knownUnits[id] and type(unit) == "table" and unit.name and unit.attributes then
                    knownUnits[id] = true

                    local cfg = EntryRegistry.getEntryConfig(unit.name)
                    local rarity = (cfg and cfg.rarity) or "Unknown"
                    local rarityRank = RarityOrder[rarity] or 0
                    local minRank = RarityOrder[State.WebhookMinRarity] or 6

                    if State.WebhookEnabled and State.WebhookNotifyRolls and rarityRank >= minRank then
                        local grade = unit.attributes.grade or "D"
                        local trait = unit.attributes.trait or "None"
                        local mutation = unit.attributes.mutation or "None"
                        sendDiscordWebhook(
                            "High-Tier Unit Rolled! (" .. rarity .. ")",
                            "Player **" .. LP.DisplayName .. "** obtained a new unit from rolling.",
                            0x00FFE0,
                            {
                                {name = "Unit", value = unit.name, inline = true},
                                {name = "Rarity", value = rarity, inline = true},
                                {name = "Grade", value = grade, inline = true},
                                {name = "Trait", value = trait, inline = true},
                                {name = "Mutation", value = mutation, inline = true},
                                {name = "Rebirth", value = "Rebirth " .. tostring(DataController.Rebirth()), inline = true}
                            }
                        )
                    end
                end
            end
        end)
    end
end)

-- Thread 11: Webhook Periodic Stats Summary
task.spawn(function()
    local lastSummaryTime = os.clock()
    while _G.AnimeDiceRunning and _G.AnimeDiceRunId == thisRunId do
        task.wait(10)
        if State.WebhookEnabled and State.WebhookPeriodicSummary then
            local intervalSec = (tonumber(State.WebhookSummaryInterval) or 15) * 60
            if os.clock() - lastSummaryTime >= intervalSec then
                lastSummaryTime = os.clock()
                pcall(function()
                    local moneyStr = NumberFormatter.FormatCompact(DataController.Money() or 0)
                    local rebirthLvl = tostring(DataController.Rebirth() or 0)
                    local diceName = tostring(DataController.Dice() or "Default")
                    local invCount = 0
                    local inv = DataController.Inventory and DataController.Inventory()
                    if inv then
                        for _, u in pairs(inv) do
                            if type(u) == "table" and u.name then invCount = invCount + 1 end
                        end
                    end

                    sendDiscordWebhook(
                        "Periodic Player Status Summary",
                        "Progress summary for **" .. LP.DisplayName .. "** (@" .. LP.Name .. ")",
                        0x4287F5,
                        {
                            {name = "Balance", value = "$" .. moneyStr, inline = true},
                            {name = "Rebirth Level", value = "Rebirth " .. rebirthLvl, inline = true},
                            {name = "Equipped Dice", value = diceName, inline = true},
                            {name = "Inventory Units", value = tostring(invCount) .. " units", inline = true},
                            {name = "Farming Tower", value = State.SelectedTower or "None", inline = true},
                            {name = "Session Duration", value = string.format("%.1f minutes", (os.clock()) / 60), inline = true}
                        }
                    )
                end)
            end
        end
    end
end)

-- ── 7. MOVEMENT ENHANCEMENTS ─────────────────────────────────────────────────────
table.insert(_conns, RunService.Stepped:Connect(function()
    if not _G.AnimeDiceRunning or _G.AnimeDiceRunId ~= thisRunId then return end
    local char = LP.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        if hum.WalkSpeed ~= State.WalkSpeed and State.WalkSpeed > 16 then
            hum.WalkSpeed = State.WalkSpeed
        end
        if hum.JumpPower ~= State.JumpPower and State.JumpPower > 50 then
            hum.JumpPower = State.JumpPower
        end
    end

    if State.Noclip then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end))

table.insert(_conns, UserInputService.JumpRequest:Connect(function()
    if State.InfJump and LP.Character then
        local hum = LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end))

-- ── 8. PERSISTENT 2K MINI BUTTON (HIGH-END CYBER LOGO) ───────────────────────────
local function getGuiContainer()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    if CoreGui then
        local ok, cg = pcall(function() return CoreGui end)
        if ok and cg then return cg end
    end
    return LP:WaitForChild("PlayerGui")
end

local minGui = Instance.new("ScreenGui")
minGui.Name = "YadMiniButton"
minGui.ResetOnSpawn = false
minGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
minGui.Parent = getGuiContainer()
_G.AnimeDiceMinGui = minGui

local minBtn = Instance.new("TextButton")
minBtn.Name = "MiniPill"
minBtn.Size = UDim2.fromOffset(52, 46)
minBtn.Position = UDim2.new(0, 14, 0.5, -23)
minBtn.BackgroundColor3 = Color3.fromRGB(10, 16, 28)
minBtn.BorderSizePixel = 0
minBtn.Text = ""
minBtn.AutoButtonColor = false
minBtn.Active = true
minBtn.Draggable = true
minBtn.Parent = minGui

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 14)
minCorner.Parent = minBtn

local minBgGrad = Instance.new("UIGradient")
minBgGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 40, 68)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 20, 36)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 10, 18))
})
minBgGrad.Rotation = 45
minBgGrad.Parent = minBtn

-- Liquid Neon Rotating Stroke
local minStroke = Instance.new("UIStroke")
minStroke.Color = Color3.fromRGB(255, 255, 255)
minStroke.Thickness = 2.4
minStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
minStroke.Parent = minBtn

local strokeGrad = Instance.new("UIGradient")
strokeGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 220, 255)),
    ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.7, Color3.fromRGB(0, 140, 230)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 240, 255))
})
strokeGrad.Parent = minStroke

-- Smooth 60fps liquid neon rotation
table.insert(_conns, RunService.RenderStepped:Connect(function()
    if not _G.AnimeDiceRunning or _G.AnimeDiceRunId ~= thisRunId then return end
    if strokeGrad and strokeGrad.Parent then
        strokeGrad.Rotation = (strokeGrad.Rotation + 2.5) % 360
    end
end))

-- Top Glass Reflection
local glass = Instance.new("Frame")
glass.Name = "GlassShine"
glass.Size = UDim2.new(1, -4, 0.46, 0)
glass.Position = UDim2.new(0, 2, 0, 2)
glass.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
glass.BackgroundTransparency = 0.82
glass.BorderSizePixel = 0
glass.Parent = minBtn

local glassCorner = Instance.new("UICorner")
glassCorner.CornerRadius = UDim.new(0, 14)
glassCorner.Parent = glass

local glassGrad = Instance.new("UIGradient")
glassGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.2),
    NumberSequenceKeypoint.new(1, 1)
})
glassGrad.Rotation = 90
glassGrad.Parent = glass

-- Text Glow Underlayer
local textGlow = Instance.new("TextLabel")
textGlow.Name = "TextGlow"
textGlow.Size = UDim2.new(1, 0, 1, 0)
textGlow.Position = UDim2.new(0, 0, 0, 1)
textGlow.BackgroundTransparency = 1
textGlow.Text = "YAD"
textGlow.TextColor3 = Color3.fromRGB(0, 210, 255)
textGlow.TextTransparency = 0.45
textGlow.TextSize = 23
textGlow.Font = Enum.Font.GothamBlack
textGlow.ZIndex = 2
textGlow.Parent = minBtn

-- Main High-Impact Typography
local textMain = Instance.new("TextLabel")
textMain.Name = "TextMain"
textMain.Size = UDim2.new(1, 0, 1, 0)
textMain.BackgroundTransparency = 1
textMain.RichText = true
textMain.Text = '<font color="#FFFFFF">Y</font><font color="#00E5FF">A</font><font color="#00E5FF">D</font>'
textMain.TextSize = 23
textMain.Font = Enum.Font.GothamBlack
textMain.ZIndex = 3
textMain.Parent = minBtn

-- Pulsing Cyber LED Dot
local dot = Instance.new("Frame")
dot.Name = "LedDot"
dot.Size = UDim2.fromOffset(6, 6)
dot.Position = UDim2.new(1, -11, 0, 6)
dot.BackgroundColor3 = Color3.fromRGB(0, 255, 200)
dot.BorderSizePixel = 0
dot.ZIndex = 4
dot.Parent = minBtn

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot

local dotStroke = Instance.new("UIStroke")
dotStroke.Thickness = 1
dotStroke.Color = Color3.fromRGB(0, 255, 230)
dotStroke.Transparency = 0.3
dotStroke.Parent = dot

-- Hover Micro-Animation
local hoverIn = TweenService:Create(minBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    Size = UDim2.fromOffset(57, 50)
})
local hoverOut = TweenService:Create(minBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    Size = UDim2.fromOffset(52, 46)
})

minBtn.MouseEnter:Connect(function() hoverIn:Play() end)
minBtn.MouseLeave:Connect(function() hoverOut:Play() end)

-- ── 9. FLUENT UI & CUSTOM FROST THEME ────────────────────────────────────────────
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
_G.AnimeDiceFluent = Fluent

-- Register Custom YadScript_Dark Theme
local uv = debug.getupvalues(Fluent.SetTheme)
local creator = uv[2]
local uvTheme = debug.getupvalues(creator.GetThemeProperty)
local themeTable = uvTheme[1]

-- Hook Creator to make all typography bolder, punchier, and more legible
local origNew = creator.New
creator.New = function(className, properties, children)
    if className == "TextLabel" or className == "TextBox" or className == "TextButton" then
        if properties then
            properties.Font = Enum.Font.GothamBold
            properties.FontFace = Font.fromEnum(Enum.Font.GothamBold)
            if properties.TextSize and properties.TextSize <= 12 then
                properties.TextSize = 13
            end
            if properties.TextTransparency and properties.TextTransparency > 0.25 then
                properties.TextTransparency = 0.15
            end
        end
    end
    return origNew(className, properties, children)
end

themeTable["YadScript_Dark"] = {
    Name = "YadScript_Dark",
    Accent = Color3.fromRGB(0, 205, 255),               -- Vivid Electric Sky Cyan
    AcrylicMain = Color3.fromRGB(11, 19, 32),            -- Deep frosted navy
    AcrylicBorder = Color3.fromRGB(80, 185, 250),        -- Ice cyan border
    AcrylicGradient = ColorSequence.new(
        Color3.fromRGB(16, 28, 48),
        Color3.fromRGB(8, 14, 24)
    ),
    AcrylicNoise = 0.94,
    Element = Color3.fromRGB(22, 36, 56),                -- Sleek frost container
    ElementBorder = Color3.fromRGB(60, 135, 210),        -- Ice border
    InElementBorder = Color3.fromRGB(85, 175, 250),      -- Inner glow
    ElementTransparency = 0.72,
    ToggleSlider = Color3.fromRGB(0, 215, 255),          -- Bright cyan slider
    ToggleToggled = Color3.fromRGB(255, 255, 255),       -- Pure white knob
    SliderRail = Color3.fromRGB(0, 195, 255),            -- Cyan slider bar
    DropdownHolder = Color3.fromRGB(16, 28, 46),
    DropdownBorder = Color3.fromRGB(75, 160, 240),
    DropdownOption = Color3.fromRGB(28, 50, 78),
    DropdownFrame = Color3.fromRGB(140, 215, 255),
    Input = Color3.fromRGB(24, 40, 64),
    InputFocused = Color3.fromRGB(38, 65, 100),
    InputIndicator = Color3.fromRGB(180, 230, 255),
    Dialog = Color3.fromRGB(16, 28, 46),
    DialogHolder = Color3.fromRGB(12, 20, 32),
    DialogHolderLine = Color3.fromRGB(60, 130, 210),
    DialogBorder = Color3.fromRGB(75, 160, 240),
    DialogButton = Color3.fromRGB(26, 46, 72),
    DialogButtonBorder = Color3.fromRGB(75, 160, 240),
    DialogInput = Color3.fromRGB(22, 38, 60),
    DialogInputLine = Color3.fromRGB(85, 175, 250),
    TitleBarLine = Color3.fromRGB(70, 165, 245),
    Text = Color3.fromRGB(255, 255, 255),               -- Pure crisp white text
    SubText = Color3.fromRGB(205, 235, 255),            -- Crisp ice-cyan subtext
    Hover = Color3.fromRGB(45, 75, 120),
    HoverChange = 0.05,
    Keybind = Color3.fromRGB(35, 60, 94),
    Tab = Color3.fromRGB(150, 215, 255)                 -- Ice cyan tab text
}
if not table.find(Fluent.Themes, "YadScript_Dark") then
    table.insert(Fluent.Themes, "YadScript_Dark")
end

local Window = Fluent:CreateWindow({
    Title       = "Yad Script",
    SubTitle    = "Anime Dice",
    TabWidth    = 125,
    Size        = UDim2.fromOffset(480, 360),
    Acrylic     = true,
    Theme       = "YadScript_Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})
_G.AnimeDiceWindow = Window

-- Prevent Maximize button from expanding to fullscreen
pcall(function()
    if Window.TitleBar and Window.TitleBar.MaxButton and Window.TitleBar.MaxButton.Frame then
        Window.TitleBar.MaxButton.Frame.Visible = false
    end
end)

local defaultWindowSize = UDim2.fromOffset(480, 360)

-- Toggle Window Visibility via Mini 2K Button
local function toggleUI()
    pcall(function()
        -- Ensure the ScreenGui holding the window is enabled
        local gui = Window.Root
        while gui and not gui:IsA("ScreenGui") do
            gui = gui.Parent
        end
        if gui then gui.Enabled = true end

        -- Window is considered "hidden" if it's invisible OR minimized
        local isHidden = (Window.Root.Visible == false) or (Window.Minimized == true)

        if isHidden then
            -- ── RESTORE / POP UP ────────────────────────────────
            -- 1) Un-minimize if currently minimized (Fluent's Minimize toggles)
            if Window.Minimized then
                pcall(function()
                    if type(Window.Minimize) == "function" then
                        Window:Minimize()   -- toggles back to expanded
                    end
                end)
            end

            -- 2) Un-maximize if it was maximized
            if Window.Maximized then
                pcall(function() Window:Maximize() end)
            end

            -- 3) Make visible and reset size
            Window.Root.Visible = true
            Window.Root.Size = defaultWindowSize

        else
            -- ── HIDE ────────────────────────────────────────────
            Window.Root.Visible = false
        end
    end)
end

minBtn.Activated:Connect(toggleUI)


-- Tabs
local Tabs = {
    Main     = Window:AddTab({Title = "Main Farm",     Icon = "zap"}),
    Tower    = Window:AddTab({Title = "Towers",        Icon = "shield"}),
    Plot     = Window:AddTab({Title = "Plots",         Icon = "home"}),
    AutoSell = Window:AddTab({Title = "Auto Sell",     Icon = "trash-2"}),
    Grades   = Window:AddTab({Title = "Grades",        Icon = "award"}),
    Upgrades = Window:AddTab({Title = "Upgrades",      Icon = "arrow-up-circle"}),
    Webhook  = Window:AddTab({Title = "Webhook",       Icon = "send"}),
    Move     = Window:AddTab({Title = "Movement",      Icon = "move"}),
    Settings = Window:AddTab({Title = "Settings",      Icon = "palette"}),
}

-- ── TAB 1: MAIN FARM (MAIN AUTOMATION) ───────────────────────────────────────────
local secRoll = Tabs.Main:AddSection("Rolling")

secRoll:AddToggle("TogAutoRoll", {
    Title       = "Auto Roll",
    Description = "Continuously rolls based on server speed.",
    Default     = false,
    Callback    = function(v)
        State.AutoRoll = v
        Fluent:Notify({Title = "Yad Script", Content = v and "Auto Roll enabled" or "Auto Roll disabled", Duration = 2})
    end
})

local secProg = Tabs.Main:AddSection("Rebirth & Claims")

secProg:AddToggle("TogAutoRebirth", {
    Title       = "Auto Rebirth",
    Description = "Checks money before firing, no spam alerts.",
    Default     = false,
    Callback    = function(v) State.AutoRebirth = v end
})

local slideRebirthRef = nil

local dropTargetRebirth = secProg:AddDropdown("DropTargetRebirth", {
    Title       = "Target Rebirth",
    Description = "Stop rebirthing once selected level is reached.",
    Values      = RebirthDisplayOptions,
    Default     = "Rebirth 12 (MAX)",
    Callback    = function(val)
        if val == "Unlimited / Always Max" then
            State.TargetRebirth = 999
        else
            local num = tonumber(string.match(val or "", "%d+"))
            if num then
                State.TargetRebirth = num
                if slideRebirthRef and slideRebirthRef.SetValue then
                    pcall(function() slideRebirthRef:SetValue(num) end)
                end
            end
        end
    end
})

slideRebirthRef = secProg:AddSlider("SlideTargetRebirth", {
    Title       = "Rebirth Cap (1 - 12)",
    Description = "Adjust max rebirth level to target.",
    Min         = 1,
    Max         = 12,
    Default     = 12,
    Rounding    = 0,
    Callback    = function(v)
        State.TargetRebirth = v
    end
})

secProg:AddButton({
    Title       = "Rebirth Now",
    Description = "Trigger a rebirth immediately when money is enough.",
    Callback    = function()
        checkAndRebirth()
        Fluent:Notify({Title = "Yad Script", Content = "Rebirth check and fire complete", Duration = 2})
    end
})

secProg:AddToggle("TogAutoClaim", {
    Title       = "Auto Claim Freebies",
    Description = "Claim daily, spin, and offline rewards.",
    Default     = false,
    Callback    = function(v) State.AutoClaim = v end
})

local secAfk = Tabs.Main:AddSection("Anti-AFK")

secAfk:AddToggle("TogAntiAFK", {
    Title       = "Anti-AFK 24/7",
    Description = "Prevents disconnects and kicks while idle.",
    Default     = true,
    Callback    = function(v) State.AntiAFK = v end
})

-- ── TAB: TOWERS (TOWERS AUTOMATION) ──────────────────────────────────────────────
local secTower = Tabs.Tower:AddSection("Auto Tower")

secTower:AddDropdown("DropSelectTower", {
    Title       = "Select Tower",
    Description = "Choose the tower difficulty you want to farm.",
    Values      = TowerDisplayOptions,
    Default     = 1,
    Callback    = function(v)
        State.SelectedTower = TowerDisplayNameMap[v] or "Dragon Tower"
    end
})

secTower:AddToggle("TogAutoTower", {
    Title       = "Auto Tower",
    Description = "Continuous tower farming, restarts on win or loss.",
    Default     = false,
    Callback    = function(v)
        State.AutoTower = v
        Fluent:Notify({
            Title = "Yad Script",
            Content = v and ("Auto Tower started: " .. State.SelectedTower) or "Auto Tower disabled",
            Duration = 2.5
        })
    end
})

secTower:AddToggle("TogAutoEquipTowerTeam", {
    Title       = "Equip Best Team",
    Description = "Equips highest damage and health units to tower team.",
    Default     = true,
    Callback    = function(v)
        State.AutoEquipBestTowerTeam = v
    end
})

secTower:AddToggle("TogHideTowerScreen", {
    Title       = "Hide Screen",
    Description = "Minimizes the tower screen for smoother performance.",
    Default     = true,
    Callback    = function(v)
        State.HideTowerScreen = v
    end
})

local secTowerActions = Tabs.Tower:AddSection("Manual Controls")

secTowerActions:AddButton({
    Title       = "Play Tower Now",
    Description = "Start the current tower run once.",
    Callback    = function()
        pcall(function()
            if State.AutoEquipBestTowerTeam and EquipBestTowerTeamRE then
                EquipBestTowerTeamRE:FireServer()
                task.wait(0.3)
            end
            local towerName = State.SelectedTower or "Dragon Tower"
            if TowerController and TowerController.startTower then
                TowerController.startTower(towerName)
            elseif PlayTowerRF then
                PlayTowerRF:InvokeServer(towerName)
            end
            Fluent:Notify({Title = "Yad Script", Content = "Started " .. towerName, Duration = 2})
        end)
    end
})

secTowerActions:AddButton({
    Title       = "Exit Tower",
    Description = "Leave the tower immediately.",
    Callback    = function()
        pcall(function()
            if CancelTowerRF then
                CancelTowerRF:InvokeServer()
            end
            Fluent:Notify({Title = "Yad Script", Content = "Exited tower successfully", Duration = 2})
        end)
    end
})

-- ── TAB 2: PLOTS & UNITS ─────────────────────────────────────────────────────────
local secCollect = Tabs.Plot:AddSection("Collect Balance")

secCollect:AddToggle("TogAutoCollect", {
    Title       = "Auto Collect",
    Description = "Collects from all plots on the configured interval.",
    Default     = false,
    Callback    = function(v) State.AutoCollect = v end
})

secCollect:AddSlider("SlideCollectInterval", {
    Title    = "Collect Interval (seconds)",
    Description = "Adjust the collect loop interval (recommended 0.3s - 0.5s).",
    Min      = 0.1,
    Max      = 5.0,
    Default  = State.CollectInterval,
    Rounding = 1,
    Callback = function(v)
        State.CollectInterval = v
    end
})

secCollect:AddButton({
    Title       = "Collect Now",
    Description = "Collect from all plots immediately.",
    Callback    = function()
        collectAllSlots()
        Fluent:Notify({Title = "Yad Script", Content = "Collected from all plots", Duration = 2})
    end
})

local secUnits = Tabs.Plot:AddSection("Anime Units")

secUnits:AddToggle("TogAutoEquip", {
    Title       = "Auto Equip Best",
    Description = "Keeps the best units equipped on plots at all times.",
    Default     = false,
    Callback    = function(v) State.AutoEquipBest = v end
})

secUnits:AddSlider("SlideEquipInterval", {
    Title    = "Equip Interval (seconds)",
    Description = "Adjust the interval for checking and equipping units.",
    Min      = 1,
    Max      = 30,
    Default  = State.EquipInterval,
    Rounding = 0,
    Callback = function(v)
        State.EquipInterval = v
    end
})

secUnits:AddButton({
    Title       = "Equip Best Now",
    Callback    = function()
        equipBestUnits()
        Fluent:Notify({Title = "Yad Script", Content = "Best units equipped", Duration = 2})
    end
})

local secSlots = Tabs.Plot:AddSection("Level Up Units")

secSlots:AddToggle("TogAutoLevelSlots", {
    Title       = "Auto Level Up",
    Description = "Calculates money and levels up plot units when affordable.",
    Default     = false,
    Callback    = function(v) State.AutoLevelSlots = v end
})

local levelPresetOptions = {
    "Level 20",
    "Level 30",
    "Level 40",
    "Level 50",
    "Level 60",
    "Level 70",
    "Level 80",
    "Level 90",
    "Level 100",
    "Max (By Money)",
}

local slideLevelRef = nil

local dropTargetLvl = secSlots:AddDropdown("DropTargetLevel", {
    Title       = "Preset Level",
    Description = "Choose the level you want to reach.",
    Values      = levelPresetOptions,
    Default     = "Level 30",
    Callback    = function(val)
        if val == "Max (By Money)" then
            State.TargetUnitLevel = 999999
        else
            local num = tonumber(string.match(val or "", "%d+"))
            if num then
                State.TargetUnitLevel = num
                if slideLevelRef and slideLevelRef.SetValue then
                    pcall(function() slideLevelRef:SetValue(num) end)
                end
            end
        end
    end
})

slideLevelRef = secSlots:AddSlider("SlideTargetUnitLevel", {
    Title       = "Level Cap (10 - 150)",
    Description = "Adjust max level cap.",
    Min         = 10,
    Max         = 150,
    Default     = 30,
    Rounding    = 0,
    Callback    = function(v)
        State.TargetUnitLevel = v
    end
})

secSlots:AddButton({
    Title       = "Level Up Now",
    Description = "Level up plot units immediately, one cycle.",
    Callback    = function()
        levelUpAllSlots()
        Fluent:Notify({
            Title   = "Yad Script",
            Content = "Queued upgrades for units below level " .. tostring(State.TargetUnitLevel),
            Duration = 2.5
        })
    end
})

-- ── TAB: AUTO SELL UNITS ─────────────────────────────────────────────────────────
local secInGameSell = Tabs.AutoSell:AddSection("Server-Side Auto Sell (1 in X)")

secInGameSell:AddParagraph({
    Title   = "In-Game Auto Sell (1 in X)",
    Content = "Automatically sells units on the server immediately if their roll chance is below 1 in X.\n(Sold units never enter your inventory.)"
})

local inGameSellPresets = {
    "1 in 100 (100)",
    "1 in 1,000 (1k)",
    "1 in 10,000 (10k)",
    "1 in 100,000 (100k)",
    "1 in 1,000,000 (1m)",
    "1 in 10,000,000 (10m)",
    "1 in 50,000,000 (50m)",
    "1 in 100,000,000 (100m)",
    "1 in 500,000,000 (500m)",
    "1 in 1,000,000,000 (1b)",
    "1 in 10,000,000,000 (10b)",
    "1 in 100,000,000,000 (100b)",
    "Disable (0)"
}

local inputAutoSellThresholdRef = nil

secInGameSell:AddDropdown("DropInGameSellPreset", {
    Title       = "Chance Presets",
    Description = "Select a roll rate threshold for auto-sell.",
    Values      = inGameSellPresets,
    Default     = "1 in 100,000,000 (100m)",
    Callback    = function(val)
        if val == "Disable (0)" then
            State.InGameAutoSellThreshold = 0
            State.InGameAutoSellInput = "0"
            if inputAutoSellThresholdRef and inputAutoSellThresholdRef.SetValue then
                pcall(function() inputAutoSellThresholdRef:SetValue("0") end)
            end
            if UpdateAutoSellRE then
                UpdateAutoSellRE:FireServer(0)
            end
            Fluent:Notify({Title = "Yad Script", Content = "In-game auto-sell disabled", Duration = 2.5})
        else
            local compactStr = string.match(val, "%(([%w]+)%)") or "100m"
            local parsedNum = NumberFormatter.ParseCompact(compactStr) or tonumber(compactStr) or 100000000
            State.InGameAutoSellThreshold = parsedNum
            State.InGameAutoSellInput = compactStr
            if inputAutoSellThresholdRef and inputAutoSellThresholdRef.SetValue then
                pcall(function() inputAutoSellThresholdRef:SetValue(compactStr) end)
            end
            if UpdateAutoSellRE then
                UpdateAutoSellRE:FireServer(parsedNum)
            end
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Auto Sell 1 in " .. compactStr .. " set on server",
                Duration = 2.5
            })
        end
    end
})

inputAutoSellThresholdRef = secInGameSell:AddInput("InputInGameSellCustom", {
    Title       = "Custom Threshold",
    Description = "Enter a number like 100m, 1b, 500k.",
    Default     = State.InGameAutoSellInput,
    Placeholder = "e.g. 100m, 1b",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        State.InGameAutoSellInput = string.gsub(val or "", "%s+", "")
    end
})

secInGameSell:AddButton({
    Title       = "Apply to Game",
    Description = "Send the threshold value to the game server.",
    Callback    = function()
        local raw = string.gsub(State.InGameAutoSellInput or "", "%s+", "")
        local parsed = tonumber(raw) or NumberFormatter.ParseCompact(raw)
        if not parsed or parsed < 0 then
            Fluent:Notify({Title = "Yad Script", Content = "Please enter a valid threshold such as 100m or 1b", Duration = 3})
            return
        end
        State.InGameAutoSellThreshold = parsed
        if UpdateAutoSellRE then
            UpdateAutoSellRE:FireServer(parsed)
        end
        Fluent:Notify({
            Title   = "Yad Script",
            Content = "Sent Auto Sell 1 in " .. NumberFormatter.FormatCompact(parsed) .. " to server",
            Duration = 3
        })
    end
})

secInGameSell:AddButton({
    Title       = "Disable",
    Description = "Reset value to 0 to disable auto sell.",
    Callback    = function()
        State.InGameAutoSellThreshold = 0
        State.InGameAutoSellInput = "0"
        if inputAutoSellThresholdRef and inputAutoSellThresholdRef.SetValue then
            pcall(function() inputAutoSellThresholdRef:SetValue("0") end)
        end
        if UpdateAutoSellRE then
            UpdateAutoSellRE:FireServer(0)
        end
        Fluent:Notify({Title = "Yad Script", Content = "In-game auto sell disabled (value = 0)", Duration = 2.5})
    end
})

secInGameSell:AddToggle("TogSellBelowChanceInInv", {
    Title       = "Check 1 in X in Inventory Sweep",
    Description = "Also sells inventory units whose roll chance is below the threshold.",
    Default     = false,
    Callback    = function(v) State.SellBelowChance = v end
})

local secSell = Tabs.AutoSell:AddSection("Inventory Sell")

secSell:AddToggle("TogAutoSellUnits", {
    Title       = "Auto Sell",
    Description = "Scans and sells units based on selected tiers.",
    Default     = false,
    Callback    = function(v)
        State.AutoSellUnits = v
        Fluent:Notify({
            Title   = "Yad Script",
            Content = v and "Auto Sell enabled" or "Auto Sell disabled",
            Duration = 2.5
        })
    end
})

secSell:AddSlider("SlideSellInterval", {
    Title       = "Scan Interval (seconds)",
    Description = "Interval to scan and sell units.",
    Min         = 1,
    Max         = 30,
    Default     = State.SellInterval,
    Rounding    = 0,
    Callback    = function(v)
        State.SellInterval = v
    end
})

local sellRarityOptions = {
    "Common",
    "Uncommon",
    "Rare",
    "Epic",
    "Legendary",
    "Mythical"
}

local defaultSellRarities = {
    "Common",
    "Uncommon",
    "Rare"
}

secSell:AddDropdown("DropSellRarities", {
    Title       = "Rarities to Sell",
    Description = "Only sell units within the selected rarities.",
    Values      = sellRarityOptions,
    Multi       = true,
    Default     = defaultSellRarities,
    Callback    = function(val)
        table.clear(State.SelectedSellRarities)
        if type(val) == "table" then
            for k, v in pairs(val) do
                if v == true then
                    State.SelectedSellRarities[k] = true
                elseif type(k) == "number" and type(v) == "string" then
                    State.SelectedSellRarities[v] = true
                end
            end
        end
    end
})

local secSellSafety = Tabs.AutoSell:AddSection("Safety Lock")

secSellSafety:AddToggle("TogProtectPlot", {
    Title       = "Protect Equipped Units",
    Description = "Do not sell units on plots or tower teams.",
    Default     = true,
    Callback    = function(v) State.ProtectPlottedUnits = v end
})

secSellSafety:AddToggle("TogProtectGradeS", {
    Title       = "Protect Grade S+ and Above",
    Description = "Do not sell units graded S, S+, Z, Z+, or God.",
    Default     = true,
    Callback    = function(v) State.ProtectGradeSPlus = v end
})

secSellSafety:AddToggle("TogProtectLocked", {
    Title       = "Protect Locked Units",
    Description = "Do not sell units locked in your inventory.",
    Default     = true,
    Callback    = function(v) State.ProtectLockedUnits = v end
})

local secSellManual = Tabs.AutoSell:AddSection("Manual Actions")

secSellManual:AddButton({
    Title       = "Sell Now",
    Description = "Scan and sell units once (up to 50).",
    Callback    = function()
        local count, earned = sellSelectedUnits()
        if count > 0 then
            Fluent:Notify({
                Title   = "Yad Script",
                Content = string.format("Sold %d units for $%s", count, NumberFormatter.FormatCompact(earned)),
                Duration = 3.5
            })
        else
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "No matching units found or all protected.",
                Duration = 2.5
            })
        end
    end
})

-- ── TAB: UNIT GRADE SYSTEM ───────────────────────────────────────────────────────
local function getInventoryUnitOptions()
    local opts = {}
    local map = {}
    pcall(function()
        local inv = DataController.Inventory and DataController.Inventory()
        if not inv then return end
        for id, item in pairs(inv) do
            if type(item) == "table" and item.name then
                local cfg = EntryRegistry.getEntryConfig(item.name)
                if cfg and cfg.kind == "Unit" then
                    local grade = (item.attributes and item.attributes.grade) or "D"
                    local lvl = (item.attributes and item.attributes.level) or 1
                    local label = string.format("%s [Lv.%s | %s] (ID: %s...)", item.name, tostring(lvl), grade, string.sub(id, 1, 8))
                    table.insert(opts, label)
                    map[label] = id
                end
            end
        end
    end)
    if #opts == 0 then
        table.insert(opts, "No units in inventory")
    end
    return opts, map
end

local unitLabels, unitIdMap = getInventoryUnitOptions()
if unitLabels[1] and unitIdMap[unitLabels[1]] then
    State.TargetGradeUnitKey = unitIdMap[unitLabels[1]]
end

local secGrade = Tabs.Grades:AddSection("Auto Reroll")

secGrade:AddParagraph({
    Title   = "Grade System Tips",
    Content = "Uses 1 Gem per roll. System stops when target grade is reached or Gems run out."
})

local dropSelectUnitRef = nil

dropSelectUnitRef = secGrade:AddDropdown("DropGradeUnit", {
    Title       = "Select Unit",
    Description = "Choose a unit from your inventory to reroll.",
    Values      = unitLabels,
    Default     = unitLabels[1] or "",
    Callback    = function(val)
        local uId = unitIdMap[val]
        if uId then
            State.TargetGradeUnitKey = uId
        end
    end
})

secGrade:AddButton({
    Title       = "Refresh Units",
    Description = "Update the list and latest grades in inventory.",
    Callback    = function()
        local newOpts, newMap = getInventoryUnitOptions()
        unitLabels = newOpts
        unitIdMap = newMap
        if dropSelectUnitRef and dropSelectUnitRef.SetValues then
            dropSelectUnitRef:SetValues(newOpts)
        end
        Fluent:Notify({Title = "Yad Script", Content = "Unit list refreshed", Duration = 2})
    end
})

local gradeTargetOptions = {
    "A",
    "A+",
    "S",
    "S+",
    "Z",
    "Z+",
    "God"
}

secGrade:AddDropdown("DropTargetGrade", {
    Title       = "Target Grade",
    Description = "Reroll until this grade or higher is obtained.",
    Values      = gradeTargetOptions,
    Default     = "S",
    Callback    = function(v)
        local cleanGrade = string.match(v, "^[^%s]+") or v
        State.TargetGrade = cleanGrade
    end
})

secGrade:AddSlider("SlideGradeDelay", {
    Title       = "Reroll Speed (seconds)",
    Description = "Recommended 0.25s - 0.40s to avoid server throttling.",
    Min         = 0.15,
    Max         = 1.0,
    Default     = State.GradeRollDelay,
    Rounding    = 2,
    Callback    = function(v)
        State.GradeRollDelay = v
    end
})

secGrade:AddToggle("TogAutoRerollGrade", {
    Title       = "Auto Reroll",
    Description = "Continuously rerolls the unit until target grade is reached.",
    Default     = false,
    Callback    = function(v)
        State.AutoRerollGrade = v
        Fluent:Notify({
            Title   = "Yad Script",
            Content = v and "Auto Reroll started" or "Auto Reroll disabled",
            Duration = 2
        })
    end
})

local secGradeManual = Tabs.Grades:AddSection("Manual Reroll")

secGradeManual:AddButton({
    Title       = "Reroll 1x",
    Description = "Reroll the selected unit once (uses 1 Gem).",
    Callback    = function()
        if not State.TargetGradeUnitKey or State.TargetGradeUnitKey == "" then
            Fluent:Notify({Title = "Yad Script", Content = "Please select a unit to reroll first", Duration = 2.5})
            return
        end
        local ok = rollGradeForSelectedUnit()
        if ok then
            Fluent:Notify({Title = "Yad Script", Content = "Reroll triggered once", Duration = 2})
        else
            Fluent:Notify({Title = "Yad Script", Content = "Cannot reroll (no Gems or unit already at target)", Duration = 2.5})
        end
    end
})

local secGradeServerProtect = Tabs.Grades:AddSection("Server Lock")

local serverProtectList = {"S", "S+", "Z", "Z+", "God"}
for _, g in ipairs(serverProtectList) do
    secGradeServerProtect:AddToggle("TogServerProt_" .. g, {
        Title       = "Lock " .. g,
        Description = "Protect grade " .. g .. " on the server.",
        Default     = true,
        Callback    = function(val)
            pcall(function()
                if SetGradeProtectedRE then
                    SetGradeProtectedRE:FireServer(g, val)
                end
            end)
        end
    })
end

-- ── TAB 3: UPGRADES & DICE ───────────────────────────────────────────────────────
local secUpgrades = Tabs.Upgrades:AddSection("Upgrades")

secUpgrades:AddToggle("TogAutoUpgrades", {
    Title       = "Auto Upgrades",
    Description = "Purchases upgrades from selected categories when affordable.",
    Default     = false,
    Callback    = function(v) State.AutoUpgrades = v end
})

local upgradeOptions = {
    "Luck & Fortune",
    "Roll Speed",
    "Money",
    "Unit Storage",
    "Damage",
    "Health",
    "Walkspeed",
    "Sell"
}

local defaultSelections = {
    "Luck & Fortune",
    "Roll Speed",
    "Money"
}

local dropUpgradeFocus = secUpgrades:AddDropdown("DropUpgradeFocus", {
    Title       = "Focus Categories",
    Description = "Categories that will always be purchased first.",
    Values      = upgradeOptions,
    Multi       = true,
    Default     = defaultSelections,
    Callback    = function(val)
        table.clear(State.SelectedUpgradeCategories)
        if type(val) == "table" then
            for k, v in pairs(val) do
                if v == true then
                    State.SelectedUpgradeCategories[k] = true
                elseif type(k) == "number" and type(v) == "string" then
                    State.SelectedUpgradeCategories[v] = true
                end
            end
        end
    end
})

secUpgrades:AddToggle("TogOnlySelected", {
    Title       = "Only Selected",
    Description = "Do not purchase other categories even if money is leftover.",
    Default     = false,
    Callback    = function(v) State.OnlySelectedUpgrades = v end
})

secUpgrades:AddButton({
    Title       = "Buy Upgrades Now",
    Callback    = function()
        buyPrioritizedUpgrades()
        Fluent:Notify({Title = "Yad Script", Content = "Purchased selected upgrade categories", Duration = 2})
    end
})

local secDice = Tabs.Upgrades:AddSection("Dice Shop")

secDice:AddToggle("TogAutoBuyDice", {
    Title       = "Auto Buy Dice",
    Description = "Buy unowned dice when you can afford them.",
    Default     = false,
    Callback    = function(v) State.AutoBuyDice = v end
})

secDice:AddButton({
    Title       = "Buy Available Dice",
    Callback    = function()
        buyAffordableDice()
        Fluent:Notify({Title = "Yad Script", Content = "Purchased all affordable dice", Duration = 2})
    end
})

-- ── TAB: DISCORD WEBHOOK INTEGRATION ─────────────────────────────────────────────
local secWebhook = Tabs.Webhook:AddSection("Discord Webhook Setup")

secWebhook:AddParagraph({
    Title   = "Discord Notification System",
    Content = "Enter a Discord Webhook URL to receive real-time notifications, such as high-tier rolls or periodic stats."
})

local inputWebhookRef = nil

inputWebhookRef = secWebhook:AddInput("InputWebhookUrl", {
    Title       = "Discord Webhook URL",
    Description = "Paste your Discord Webhook link here.",
    Default     = State.WebhookURL,
    Placeholder = "https://discord.com/api/webhooks/...",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        State.WebhookURL = string.gsub(val or "", "%s+", "")
    end
})

secWebhook:AddButton({
    Title       = "Confirm URL",
    Description = "Save and verify the URL immediately (mobile-friendly).",
    Callback    = function()
        local currentVal = (inputWebhookRef and inputWebhookRef.Value) or (Fluent.Options and Fluent.Options.InputWebhookUrl and Fluent.Options.InputWebhookUrl.Value) or State.WebhookURL
        local clean = string.gsub(currentVal or "", "%s+", "")
        if clean == "" then
            Fluent:Notify({Title = "Yad Script", Content = "Please enter or paste a Webhook URL before confirming", Duration = 3})
            return
        end
        State.WebhookURL = clean
        if clean:find("discord.com/api/webhooks") or clean:find("discordapp.com/api/webhooks") then
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Webhook URL saved and verified. Ready to use!",
                Duration = 3.5
            })
        else
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Saved (warning: URL does not match standard Discord format)",
                Duration = 4
            })
        end
    end
})

secWebhook:AddButton({
    Title       = "Paste Clipboard",
    Description = "Fetch URL from clipboard instantly.",
    Callback    = function()
        local pasteFn = getclipboard or (Clipboard and Clipboard.get)
        if pasteFn then
            local ok, clip = pcall(pasteFn)
            if ok and clip and type(clip) == "string" and #clip > 0 then
                local clean = string.gsub(clip, "%s+", "")
                State.WebhookURL = clean
                if inputWebhookRef and inputWebhookRef.SetValue then
                    pcall(function() inputWebhookRef:SetValue(clean) end)
                end
                Fluent:Notify({
                    Title   = "Yad Script",
                    Content = "Webhook URL pasted from clipboard!",
                    Duration = 3
                })
                return
            end
        end
        Fluent:Notify({
            Title   = "Yad Script",
            Content = "Unable to read clipboard. Please paste directly into the field.",
            Duration = 3
        })
    end
})

secWebhook:AddToggle("TogWebhookEnabled", {
    Title       = "Enable Webhook",
    Description = "Send notifications to Discord.",
    Default     = false,
    Callback    = function(v)
        State.WebhookEnabled = v
        Fluent:Notify({
            Title   = "Yad Script",
            Content = v and "Discord Webhook enabled" or "Webhook notifications disabled",
            Duration = 2.5
        })
    end
})

secWebhook:AddButton({
    Title       = "Test Webhook",
    Description = "Send a test message to Discord.",
    Callback    = function()
        if not State.WebhookURL or State.WebhookURL == "" then
            Fluent:Notify({Title = "Yad Script", Content = "Please enter a Webhook URL first", Duration = 2.5})
            return
        end
        local ok = sendDiscordWebhook(
            "Webhook connection test successful!",
            "The **Yad Script - Anime Dice** notification system has connected to your Discord successfully.",
            0x00FF88,
            {
                {name = "Player", value = LP.DisplayName .. " (@" .. LP.Name .. ")", inline = true},
                {name = "Status", value = "Fully Operational", inline = true},
                {name = "Time", value = os.date("%H:%M:%S - %d/%m/%Y"), inline = true}
            }
        )
        Fluent:Notify({
            Title   = "Yad Script",
            Content = ok and "Test message sent to Discord successfully!" or "Failed to send Webhook (check URL or network)",
            Duration = 3.5
        })
    end
})

local secWebhookEvents = Tabs.Webhook:AddSection("Event Alerts")

secWebhookEvents:AddToggle("TogNotifRolls", {
    Title       = "High Rolls",
    Description = "Sends unit name, grade, and trait to Discord.",
    Default     = true,
    Callback    = function(v) State.WebhookNotifyRolls = v end
})

local webhookRarityOptions = {
    "Epic",
    "Legendary",
    "Mythical",
    "Secret",
    "Exotic",
    "Celestial",
    "Divine"
}

secWebhookEvents:AddDropdown("DropMinRarity", {
    Title       = "Min Rarity",
    Description = "Minimum rarity threshold for alerts.",
    Values      = webhookRarityOptions,
    Default     = "Mythical",
    Callback    = function(v) State.WebhookMinRarity = v end
})

secWebhookEvents:AddToggle("TogNotifRebirth", {
    Title       = "Rebirth Alert",
    Description = "Sends new rebirth level and bonuses.",
    Default     = true,
    Callback    = function(v) State.WebhookNotifyRebirth = v end
})

secWebhookEvents:AddToggle("TogNotifGrade", {
    Title       = "High Grade",
    Description = "Sends alerts for grades S, S+, Z, Z+, God.",
    Default     = true,
    Callback    = function(v) State.WebhookNotifyGrade = v end
})

local secWebhookSummary = Tabs.Webhook:AddSection("Periodic Summary")

secWebhookSummary:AddToggle("TogWebhookSummary", {
    Title       = "Auto Summary",
    Description = "Sends a summary of money, rebirth, and units on a timer.",
    Default     = false,
    Callback    = function(v) State.WebhookPeriodicSummary = v end
})

secWebhookSummary:AddSlider("SlideSummaryInterval", {
    Title       = "Summary Interval (minutes)",
    Description = "Time between summary reports (5 - 60 minutes).",
    Min         = 5,
    Max         = 60,
    Default     = State.WebhookSummaryInterval,
    Rounding    = 0,
    Callback    = function(v) State.WebhookSummaryInterval = v end
})

secWebhookSummary:AddButton({
    Title       = "Send Summary Now",
    Description = "Send a current stat summary to Discord immediately.",
    Callback    = function()
        if not State.WebhookURL or State.WebhookURL == "" then
            Fluent:Notify({Title = "Yad Script", Content = "Please enter a Webhook URL first", Duration = 2.5})
            return
        end
        pcall(function()
            local moneyStr = NumberFormatter.FormatCompact(DataController.Money() or 0)
            local rebirthLvl = tostring(DataController.Rebirth() or 0)
            local diceName = tostring(DataController.Dice() or "Default")
            local invCount = 0
            local inv = DataController.Inventory and DataController.Inventory()
            if inv then
                for _, u in pairs(inv) do
                    if type(u) == "table" and u.name then invCount = invCount + 1 end
                end
            end

            local ok = sendDiscordWebhook(
                "Periodic Player Status Summary",
                "Progress summary for **" .. LP.DisplayName .. "** (@" .. LP.Name .. ")",
                0x4287F5,
                {
                    {name = "Balance", value = "$" .. moneyStr, inline = true},
                    {name = "Rebirth Level", value = "Rebirth " .. rebirthLvl, inline = true},
                    {name = "Equipped Dice", value = diceName, inline = true},
                    {name = "Inventory Units", value = tostring(invCount) .. " units", inline = true},
                    {name = "Farming Tower", value = State.SelectedTower or "None", inline = true},
                    {name = "Session Duration", value = string.format("%.1f minutes", (os.clock()) / 60), inline = true}
                }
            )
            Fluent:Notify({
                Title   = "Yad Script",
                Content = ok and "Summary sent to Discord successfully" or "Failed to send (check Webhook URL)",
                Duration = 3
            })
        end)
    end
})

-- ── TAB 4: MOVEMENT HACKS ────────────────────────────────────────────────────────
local secMove = Tabs.Move:AddSection("Movement")

secMove:AddSlider("SlideWalkSpeed", {
    Title    = "WalkSpeed",
    Min      = 16,
    Max      = 200,
    Default  = 16,
    Rounding = 0,
    Callback = function(v)
        State.WalkSpeed = v
        if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then
            LP.Character.Humanoid.WalkSpeed = v
        end
    end
})

secMove:AddSlider("SlideJumpPower", {
    Title    = "JumpPower",
    Min      = 50,
    Max      = 250,
    Default  = 50,
    Rounding = 0,
    Callback = function(v)
        State.JumpPower = v
        if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then
            LP.Character.Humanoid.JumpPower = v
        end
    end
})

secMove:AddToggle("TogInfJump", {
    Title       = "Infinite Jump",
    Description = "Jump repeatedly in mid-air at any time.",
    Default     = false,
    Callback    = function(v) State.InfJump = v end
})

secMove:AddToggle("TogNoclip", {
    Title       = "Noclip",
    Description = "Walk through walls and obstacles.",
    Default     = false,
    Callback    = function(v) State.Noclip = v end
})

-- ── TAB 5: SETTINGS & COMMUNITY ──────────────────────────────────────────────────
local secCommunity = Tabs.Settings:AddSection("Community & Support")

secCommunity:AddParagraph({
    Title = "Created by Yad Script",
})

-- ── CONFIG MANAGEMENT ENGINE ──────────────────────────────────────────────────
local ConfigFolder = "YadScript/AnimeDice"
local AutoloadFile = ConfigFolder .. "/autoload.txt"

local function ensureConfigFolder()
    pcall(function()
        if makefolder and isfolder then
            if not isfolder("YadScript") then
                makefolder("YadScript")
            end
            if not isfolder(ConfigFolder) then
                makefolder(ConfigFolder)
            end
        end
    end)
end

local function listConfigs()
    ensureConfigFolder()
    local list = {}
    pcall(function()
        if listfiles then
            local files = listfiles(ConfigFolder)
            for _, path in ipairs(files) do
                local filename = string.match(path, "([^/\\]+)%.json$")
                if filename and filename ~= "" then
                    table.insert(list, filename)
                end
            end
        end
    end)
    table.sort(list)
    if #list == 0 then
        table.insert(list, "No configs (empty)")
    end
    return list
end

local function getAutoloadConfigName()
    ensureConfigFolder()
    local autoName = nil
    pcall(function()
        if isfile and isfile(AutoloadFile) and readfile then
            local content = readfile(AutoloadFile)
            if content and #content > 0 then
                autoName = string.gsub(content, "%s+", "")
            end
        end
    end)
    return autoName
end

local function saveConfigFile(configName)
    ensureConfigFolder()
    if not configName or configName == "" or configName == "No configs (empty)" then
        return false, "Invalid config name"
    end
    local safeName = string.gsub(configName, "[^%w_%-]", "")
    if #safeName == 0 then
        return false, "Config name must contain letters or numbers"
    end

    local dataToSave = {
        Version = "1.0",
        Timestamp = os.time(),
        State = State
    }

    local success, encoded = pcall(function()
        return HttpService:JSONEncode(dataToSave)
    end)
    if not success or not encoded then
        return false, "Failed to encode JSON"
    end

    local filePath = ConfigFolder .. "/" .. safeName .. ".json"
    local writeOk = pcall(function()
        writefile(filePath, encoded)
    end)
    if not writeOk then
        return false, "Failed to write config file"
    end
    return true, safeName
end

local function loadConfigFile(configName)
    ensureConfigFolder()
    if not configName or configName == "" or configName == "No configs (empty)" then
        return false, "Please select a config to load"
    end
    local safeName = string.gsub(configName, "[^%w_%-]", "")
    local filePath = ConfigFolder .. "/" .. safeName .. ".json"
    if not isfile(filePath) then
        return false, "Config file not found: " .. safeName
    end

    local content
    local readOk = pcall(function()
        content = readfile(filePath)
    end)
    if not readOk or not content or #content == 0 then
        return false, "Failed to read config file"
    end

    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not decodeOk or type(decoded) ~= "table" then
        return false, "Config file structure is corrupted"
    end

    local loadedState = decoded.State or decoded
    if type(loadedState) ~= "table" then
        return false, "State data missing from config"
    end

    -- Update current State
    for k, v in pairs(loadedState) do
        if State[k] ~= nil then
            State[k] = v
        end
    end

    -- Sync Fluent UI widgets to loaded values
    pcall(function()
        local opt = Fluent.Options
        if not opt then return end

        -- Main Tab
        if opt.TogAutoRoll then opt.TogAutoRoll:SetValue(State.AutoRoll) end
        if opt.TogAutoRebirth then opt.TogAutoRebirth:SetValue(State.AutoRebirth) end
        if opt.SlideTargetRebirth then opt.SlideTargetRebirth:SetValue(State.TargetRebirth) end
        if opt.TogAutoClaim then opt.TogAutoClaim:SetValue(State.AutoClaim) end
        if opt.TogAntiAFK then opt.TogAntiAFK:SetValue(State.AntiAFK) end

        -- Tower Tab
        if opt.DropSelectTower and TowerDisplayNameMap then
            for dispName, realName in pairs(TowerDisplayNameMap) do
                if realName == State.SelectedTower then
                    opt.DropSelectTower:SetValue(dispName)
                    break
                end
            end
        end
        if opt.TogAutoTower then opt.TogAutoTower:SetValue(State.AutoTower) end
        if opt.TogAutoEquipTowerTeam then opt.TogAutoEquipTowerTeam:SetValue(State.AutoEquipBestTowerTeam) end
        if opt.TogHideTowerScreen then opt.TogHideTowerScreen:SetValue(State.HideTowerScreen) end

        -- Plot Tab
        if opt.TogAutoCollect then opt.TogAutoCollect:SetValue(State.AutoCollect) end
        if opt.SlideCollectInterval then opt.SlideCollectInterval:SetValue(State.CollectInterval) end
        if opt.TogAutoEquip then opt.TogAutoEquip:SetValue(State.AutoEquipBest) end
        if opt.SlideEquipInterval then opt.SlideEquipInterval:SetValue(State.EquipInterval) end
        if opt.TogAutoLevelSlots then opt.TogAutoLevelSlots:SetValue(State.AutoLevelSlots) end
        if opt.SlideTargetUnitLevel then opt.SlideTargetUnitLevel:SetValue(State.TargetUnitLevel) end

        -- Auto Sell Tab
        if opt.InputInGameSellCustom then opt.InputInGameSellCustom:SetValue(State.InGameAutoSellInput or "100m") end
        if opt.TogSellBelowChanceInInv then opt.TogSellBelowChanceInInv:SetValue(State.SellBelowChance) end
        if opt.TogAutoSellUnits then opt.TogAutoSellUnits:SetValue(State.AutoSellUnits) end
        if opt.SlideSellInterval then opt.SlideSellInterval:SetValue(State.SellInterval) end
        if opt.DropSellRarities then opt.DropSellRarities:SetValue(State.SelectedSellRarities) end
        if opt.TogProtectPlot then opt.TogProtectPlot:SetValue(State.ProtectPlottedUnits) end
        if opt.TogProtectGradeS then opt.TogProtectGradeS:SetValue(State.ProtectGradeSPlus) end
        if opt.TogProtectLocked then opt.TogProtectLocked:SetValue(State.ProtectLockedUnits) end

        -- Grades Tab
        if opt.DropTargetGrade then opt.DropTargetGrade:SetValue(State.TargetGrade) end
        if opt.SlideGradeDelay then opt.SlideGradeDelay:SetValue(State.GradeRollDelay) end
        if opt.TogAutoRerollGrade then opt.TogAutoRerollGrade:SetValue(State.AutoRerollGrade) end

        -- Upgrades Tab
        if opt.TogAutoUpgrades then opt.TogAutoUpgrades:SetValue(State.AutoUpgrades) end
        if opt.DropUpgradeFocus then opt.DropUpgradeFocus:SetValue(State.SelectedUpgradeCategories) end
        if opt.TogOnlySelected then opt.TogOnlySelected:SetValue(State.OnlySelectedUpgrades) end
        if opt.TogAutoBuyDice then opt.TogAutoBuyDice:SetValue(State.AutoBuyDice) end

        -- Webhook Tab
        if opt.InputWebhookUrl then opt.InputWebhookUrl:SetValue(State.WebhookURL) end
        if opt.TogWebhookEnabled then opt.TogWebhookEnabled:SetValue(State.WebhookEnabled) end
        if opt.TogNotifRolls then opt.TogNotifRolls:SetValue(State.WebhookNotifyRolls) end
        if opt.DropMinRarity then opt.DropMinRarity:SetValue(State.WebhookMinRarity) end
        if opt.TogNotifRebirth then opt.TogNotifRebirth:SetValue(State.WebhookNotifyRebirth) end
        if opt.TogNotifGrade then opt.TogNotifGrade:SetValue(State.WebhookNotifyGrade) end
        if opt.TogWebhookSummary then opt.TogWebhookSummary:SetValue(State.WebhookPeriodicSummary) end
        if opt.SlideSummaryInterval then opt.SlideSummaryInterval:SetValue(State.WebhookSummaryInterval) end

        -- Movement Tab
        if opt.SlideWalkSpeed then opt.SlideWalkSpeed:SetValue(State.WalkSpeed) end
        if opt.SlideJumpPower then opt.SlideJumpPower:SetValue(State.JumpPower) end
        if opt.TogInfJump then opt.TogInfJump:SetValue(State.InfJump) end
        if opt.TogNoclip then opt.TogNoclip:SetValue(State.Noclip) end
    end)

    return true, safeName
end

local function deleteConfigFile(configName)
    ensureConfigFolder()
    if not configName or configName == "" or configName == "No configs (empty)" then
        return false, "Please select a config to delete"
    end
    local safeName = string.gsub(configName, "[^%w_%-]", "")
    local filePath = ConfigFolder .. "/" .. safeName .. ".json"
    if not isfile(filePath) then
        return false, "Config file not found to delete"
    end
    local ok = pcall(function()
        delfile(filePath)
    end)
    if not ok then
        return false, "Failed to delete config file"
    end
    if getAutoloadConfigName() == safeName then
        pcall(function() delfile(AutoloadFile) end)
    end
    return true, safeName
end

local function setAutoloadConfig(configName)
    ensureConfigFolder()
    if not configName or configName == "" or configName == "No configs (empty)" then
        pcall(function() if isfile(AutoloadFile) then delfile(AutoloadFile) end end)
        return false, "AutoLoad cleared"
    end
    local safeName = string.gsub(configName, "[^%w_%-]", "")
    local filePath = ConfigFolder .. "/" .. safeName .. ".json"
    if not isfile(filePath) then
        return false, "Config file not found: " .. safeName
    end
    local ok = pcall(function()
        writefile(AutoloadFile, safeName)
    end)
    if not ok then
        return false, "Failed to save AutoLoad"
    end
    return true, safeName
end

local secConfig = Tabs.Settings:AddSection("Config Profiles")

secConfig:AddParagraph({
    Title   = "Config Manager",
    Content = "Save your settings to disk (folder YadScript/AnimeDice) and set an autoload config."
})

local selectedConfigName = ""
local newConfigInputName = "Default"
local configListValues = listConfigs()
local dropConfigListRef = nil
local paraAutoloadRef = nil

local function updateAutoloadStatusText()
    local autoName = getAutoloadConfigName()
    if autoName and autoName ~= "" then
        return "Current auto-load config: " .. autoName
    else
        return "Current auto-load config: not set (disabled)"
    end
end

paraAutoloadRef = secConfig:AddParagraph({
    Title   = "Current Auto-Load Status",
    Content = updateAutoloadStatusText()
})

local inputConfigNameRef = secConfig:AddInput("InputConfigName", {
    Title       = "New Config Name",
    Description = "Name your config, e.g. Farm_Main, Tower_Push.",
    Default     = "Default",
    Placeholder = "e.g. Default, Farm_Plot, Night_AFK",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        newConfigInputName = string.gsub(val or "", "%s+", "")
    end
})

secConfig:AddButton({
    Title       = "Create Config",
    Description = "Create and save current settings to a file.",
    Callback    = function()
        local nameToSave = newConfigInputName
        if not nameToSave or nameToSave == "" then
            nameToSave = (inputConfigNameRef and inputConfigNameRef.Value) or "Default"
        end
        local ok, msg = saveConfigFile(nameToSave)
        if ok then
            configListValues = listConfigs()
            selectedConfigName = msg
            if dropConfigListRef and dropConfigListRef.SetValues then
                dropConfigListRef:SetValues(configListValues)
                dropConfigListRef:SetValue(msg)
            end
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Config [" .. msg .. "] created and saved successfully!",
                Duration = 3.5
            })
        else
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Error: " .. tostring(msg),
                Duration = 3.5
            })
        end
    end
})

dropConfigListRef = secConfig:AddDropdown("DropConfigList", {
    Title       = "Select Config",
    Description = "Choose an existing config to load or delete.",
    Values      = configListValues,
    Default     = configListValues[1] or "No configs (empty)",
    Callback    = function(val)
        selectedConfigName = val
    end
})

if configListValues[1] and configListValues[1] ~= "No configs (empty)" then
    selectedConfigName = configListValues[1]
end

secConfig:AddButton({
    Title       = "Load Config",
    Description = "Load settings from the selected config immediately.",
    Callback    = function()
        if not selectedConfigName or selectedConfigName == "" or selectedConfigName == "No configs (empty)" then
            Fluent:Notify({Title = "Yad Script", Content = "Please select a config from the list first", Duration = 3})
            return
        end
        local ok, msg = loadConfigFile(selectedConfigName)
        if ok then
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Config [" .. msg .. "] loaded! Settings applied immediately.",
                Duration = 3.5
            })
        else
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Failed to load config: " .. tostring(msg),
                Duration = 3.5
            })
        end
    end
})

secConfig:AddButton({
    Title       = "Save Config",
    Description = "Save current settings over the selected config.",
    Callback    = function()
        if not selectedConfigName or selectedConfigName == "" or selectedConfigName == "No configs (empty)" then
            Fluent:Notify({Title = "Yad Script", Content = "Please select a config to overwrite", Duration = 3})
            return
        end
        local ok, msg = saveConfigFile(selectedConfigName)
        if ok then
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Config [" .. msg .. "] saved successfully!",
                Duration = 3.5
            })
        else
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Failed to save config: " .. tostring(msg),
                Duration = 3.5
            })
        end
    end
})

secConfig:AddButton({
    Title       = "Refresh List",
    Description = "Update the config dropdown list.",
    Callback    = function()
        configListValues = listConfigs()
        if dropConfigListRef and dropConfigListRef.SetValues then
            dropConfigListRef:SetValues(configListValues)
            if configListValues[1] then
                dropConfigListRef:SetValue(configListValues[1])
                selectedConfigName = configListValues[1]
            end
        end
        if paraAutoloadRef and paraAutoloadRef.SetDesc then
            pcall(function() paraAutoloadRef:SetDesc(updateAutoloadStatusText()) end)
        end
        Fluent:Notify({Title = "Yad Script", Content = "Config list refreshed", Duration = 2})
    end
})

secConfig:AddButton({
    Title       = "Set Auto-Load",
    Description = "Load this config automatically every time the script starts.",
    Callback    = function()
        if not selectedConfigName or selectedConfigName == "" or selectedConfigName == "No configs (empty)" then
            Fluent:Notify({Title = "Yad Script", Content = "Please select a config to set as Auto-Load", Duration = 3})
            return
        end
        local ok, msg = setAutoloadConfig(selectedConfigName)
        if ok then
            if paraAutoloadRef and paraAutoloadRef.SetDesc then
                pcall(function() paraAutoloadRef:SetDesc(updateAutoloadStatusText()) end)
            end
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Set [" .. msg .. "] as Auto-Load successfully!",
                Duration = 3.5
            })
        else
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Error: " .. tostring(msg),
                Duration = 3
            })
        end
    end
})

secConfig:AddButton({
    Title       = "Clear Auto-Load",
    Description = "Disable config autoloading.",
    Callback    = function()
        setAutoloadConfig(nil)
        if paraAutoloadRef and paraAutoloadRef.SetDesc then
            pcall(function() paraAutoloadRef:SetDesc(updateAutoloadStatusText()) end)
        end
        Fluent:Notify({Title = "Yad Script", Content = "Auto-Load cleared", Duration = 2.5})
    end
})

secConfig:AddButton({
    Title       = "Delete Config",
    Description = "Permanently delete the config file.",
    Callback    = function()
        if not selectedConfigName or selectedConfigName == "" or selectedConfigName == "No configs (empty)" then
            Fluent:Notify({Title = "Yad Script", Content = "Please select a config to delete", Duration = 3})
            return
        end
        local targetToDelete = selectedConfigName
        local ok, msg = deleteConfigFile(targetToDelete)
        if ok then
            configListValues = listConfigs()
            selectedConfigName = configListValues[1] or ""
            if dropConfigListRef and dropConfigListRef.SetValues then
                dropConfigListRef:SetValues(configListValues)
                dropConfigListRef:SetValue(configListValues[1] or "")
            end
            if paraAutoloadRef and paraAutoloadRef.SetDesc then
                pcall(function() paraAutoloadRef:SetDesc(updateAutoloadStatusText()) end)
            end
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Config [" .. msg .. "] deleted",
                Duration = 3
            })
        else
            Fluent:Notify({
                Title   = "Yad Script",
                Content = "Failed to delete config: " .. tostring(msg),
                Duration = 3
            })
        end
    end
})

local secUIScale = Tabs.Settings:AddSection("UI Controls")

secUIScale:AddDropdown("DropUISize", {
    Title       = "UI Size",
    Description = "Instantly switch between Small / Medium / Large.",
    Values      = {"Small", "Medium", "Large"},
    Default     = "Small",
    Callback    = function(v)
        local sizes = {
            ["Small"]  = UDim2.fromOffset(440, 330),
            ["Medium"] = UDim2.fromOffset(480, 360),
            ["Large"]  = UDim2.fromOffset(560, 420),
        }
        local target = sizes[v] or sizes["Small"]
        pcall(function()
            if Window.Root then
                Window.Root.Size = target
            end
        end)
    end
})

secUIScale:AddParagraph({
    Title = "Draggable Window",
    Content = "Drag the Yad Script title bar to move the window. The VF button toggles the window."
})

local secTheme = Tabs.Settings:AddSection("Theme Settings")

secTheme:AddDropdown("DropThemeSelect", {
    Title       = "Theme Color",
    Values      = {"YadScript_Dark", "Aqua", "Light", "Dark"},
    Default     = "YadScript_Dark",
    Callback    = function(themeName)
        pcall(function()
            Fluent:SetTheme(themeName)
        end)
    end
})

secTheme:AddButton({
    Title       = "Unload Script",
    Description = "Stop all systems and close the UI immediately.",
    Callback    = function()
        if _G.AnimeDiceCleanup then
            _G.AnimeDiceCleanup()
        end
    end
})

Window:SelectTab(1)

-- ── TYPOGRAPHY ENHANCEMENT (BOLD FONT ENGINE) ──────────────────────────────────
local function applyBoldTypography(inst)
    if inst:IsA("TextLabel") or inst:IsA("TextBox") or inst:IsA("TextButton") then
        inst.Font = Enum.Font.GothamBold
        inst.FontFace = Font.fromEnum(Enum.Font.GothamBold)
        if inst.TextSize <= 12 then
            inst.TextSize = 13
        end
        if inst.TextTransparency > 0.25 then
            inst.TextTransparency = 0.15
        end
    end
end

task.spawn(function()
    task.wait(0.1)
    pcall(function()
        local sg = Window.Root
        while sg and not sg:IsA("ScreenGui") do
            sg = sg.Parent
        end
        local target = sg or Window.Root
        for _, d in ipairs(target:GetDescendants()) do
            applyBoldTypography(d)
        end
        table.insert(_conns, target.DescendantAdded:Connect(applyBoldTypography))
    end)
end)

Fluent:Notify({
    Title   = "Yad Script",
    Content = "Anime Dice",
    Duration = 5
})

-- Auto-Load Config at Boot
task.spawn(function()
    task.wait(1.5)
    pcall(function()
        local autoConfig = getAutoloadConfigName()
        if autoConfig and autoConfig ~= "" and autoConfig ~= "No configs (empty)" then
            local ok, name = loadConfigFile(autoConfig)
            if ok then
                Fluent:Notify({
                    Title   = "Yad Script",
                    Content = "Auto-loaded config: " .. tostring(name),
                    Duration = 4
                })
            end
        end
    end)
end)
