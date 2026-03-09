-- WildImpTracker v5.1
-- Fixes: nil value width error on initialization
-- Features: Position, Scale, Width, Transparency, Locking

local activeImps = {}
local MAX_IMPS = 18
local IMP_DURATION = 40
local START_ENERGY = 100
local DECAY_BASE = 7.5

-- Default Settings (Safety fallback)
local defaults = { x = 0, y = 150, alpha = 0.8, locked = false, scale = 1.0, width = 230 }

-- ============================================================
-- UI SETUP & SAVED VARIABLES
-- ============================================================
local mainFrame = CreateFrame("Frame", "WITMainFrame", UIParent)
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:SetClampedToScreen(true)

local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.8)

local title = mainFrame:CreateFontString(nil, "OVERLAY")
title:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
title:SetPoint("TOPLEFT", 5, -5)
title:SetText("WILD IMPS")

local bars = {}

local function UpdateLayout()
    if not WildImpTrackerDB then return end
    local db = WildImpTrackerDB
    
    mainFrame:SetSize(db.width or 230, 40)
    mainFrame:SetScale(db.scale or 1.0)
    bg:SetAlpha(db.locked and 0 or (db.alpha or 0.8))
    mainFrame:EnableMouse(not db.locked)
    
    for _, f in ipairs(bars) do
        f:SetWidth((db.width or 230) - 10)
        if f.energy then f.energy:SetWidth((db.width or 230) - 10) end
        if f.hp then f.hp:SetWidth((db.width or 230) - 10) end
    end
end

mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "WildImpTracker" then
        -- Initialize Database if missing
        if not WildImpTrackerDB then WildImpTrackerDB = {} end
        for k, v in pairs(defaults) do
            if WildImpTrackerDB[k] == nil then WildImpTrackerDB[k] = v end
        end
        
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", WildImpTrackerDB.x, WildImpTrackerDB.y)
        UpdateLayout()
    end
end)

mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    if WildImpTrackerDB then
        WildImpTrackerDB.x = x
        WildImpTrackerDB.y = y
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================
SLASH_WILDIMP1 = "/wit"
SlashCmdList["WILDIMP"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    arg = tonumber(arg)
    
    if cmd == "unlock" then
        WildImpTrackerDB.locked = false
        UpdateLayout()
        print("|cff8844ffWIT:|r Unlocked.")
    elseif cmd == "lock" then
        WildImpTrackerDB.locked = true
        UpdateLayout()
        print("|cff8844ffWIT:|r Locked.")
    elseif cmd == "alpha" and arg then
        WildImpTrackerDB.alpha = arg
        UpdateLayout()
    elseif cmd == "scale" and arg then
        WildImpTrackerDB.scale = arg
        UpdateLayout()
    elseif cmd == "width" and arg then
        WildImpTrackerDB.width = arg
        UpdateLayout()
    else
        print("|cff8844ffWIT Commands:|r /wit [lock/unlock/alpha/scale/width]")
    end
end

-- ============================================================
-- CORE ENGINE
-- ============================================================
local function GetBar(i)
    if not bars[i] then
        local w = (WildImpTrackerDB and WildImpTrackerDB.width) or 230
        local f = CreateFrame("Frame", nil, mainFrame)
        f:SetSize(w - 10, 22)
        
        f.energy = CreateFrame("StatusBar", nil, f)
        f.energy:SetSize(w - 10, 12)
        f.energy:SetPoint("TOP")
        f.energy:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        f.energy:SetMinMaxValues(0, 100)
        
        f.hp = CreateFrame("StatusBar", nil, f)
        f.hp:SetSize(w - 10, 4)
        f.hp:SetPoint("TOP", f.energy, "BOTTOM", 0, -1)
        f.hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        f.hp:SetStatusBarColor(0.2, 0.8, 0.2)
        
        f.text = f.energy:CreateFontString(nil, "OVERLAY")
        f.text:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        f.text:SetPoint("CENTER", 0, 0)
        bars[i] = f
    end
    return bars[i]
end

hooksecurefunc("UseAction", function(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" then
        local now = GetTime()
        if id == 196277 then
            local sacrificed = math.min(#activeImps, 6)
            table.wipe(activeImps)
            if sacrificed >= 2 then
                for i = 1, math.floor(sacrificed / 2) do
                    table.insert(activeImps, { spawn = now, energy = START_ENERGY, isBoss = true })
                end
            end
        elseif id == 264130 then
            if #activeImps >= 2 then
                table.remove(activeImps, 1) table.remove(activeImps, 1)
                table.insert(activeImps, { spawn = now, energy = START_ENERGY, isBoss = true })
            end
        end
    end
end)

local lastUpdate, wasCasting = GetTime(), false
C_Timer.NewTicker(0.05, function()
    -- Wait until DB is initialized
    if not WildImpTrackerDB then return end
    
    local now = GetTime()
    local dt, haste = now - lastUpdate, 1 + (GetHaste() / 100)
    lastUpdate = now
    
    local _, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
    if wasCasting and not (spellID == 105174) and GetUnitSpeed("player") == 0 then
        for i = 1, 3 do table.insert(activeImps, { spawn = now, energy = START_ENERGY }) end
    end
    wasCasting = (spellID == 105174)

    for i = #activeImps, 1, -1 do
        local imp = activeImps[i]
        if UnitAffectingCombat("player") then imp.energy = imp.energy - (DECAY_BASE * haste * dt) end
        if (now - imp.spawn) >= IMP_DURATION or imp.energy <= 0 then table.remove(activeImps, i) end
    end

    title:SetText("WILD IMPS: " .. #activeImps)
    for _, b in ipairs(bars) do b:Hide() end
    for i, imp in ipairs(activeImps) do
        local b = GetBar(i)
        b:SetPoint("TOP", 0, -20 - (i-1) * 26)
        b.energy:SetStatusBarColor(imp.isBoss and 1 or 0.6, imp.isBoss and 0.4 or 0.2, imp.isBoss and 0 or 0.9)
        b.energy:SetValue(imp.energy)
        b.text:SetText(string.format("%s: %.1fs | %d%%", imp.isBoss and "BOSS" or "Imp", math.max(0, IMP_DURATION - (now - imp.spawn)), math.floor(imp.energy)))
        b:Show()
    end
    mainFrame:SetHeight(math.max(40, 25 + (#activeImps * 26)))
end)

mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)