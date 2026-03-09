-- WildImpTracker v4.8
-- Talent Sync: To Hell and Back (1281511)
-- Zero Forbidden Calls / Zero RegisterEvent

local activeImps = {}
local MAX_IMPS = 18
local IMP_DURATION = 40
local START_ENERGY = 100
local DECAY_BASE = 7.5 -- Base energy loss per second

-- ============================================================
-- UI SETUP
-- ============================================================
local mainFrame = CreateFrame("Frame", nil, UIParent)
mainFrame:SetSize(230, 40)
mainFrame:SetPoint("CENTER", 0, 150)
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:SetClampedToScreen(true)

local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.8)

local title = mainFrame:CreateFontString(nil, "OVERLAY")
title:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
title:SetPoint("TOPLEFT", 5, -5)
title:SetText("WILD IMPS: 0")

local bars = {}
local function GetBar(i)
    if not bars[i] then
        local f = CreateFrame("Frame", nil, mainFrame)
        f:SetSize(220, 22)
        f.energy = CreateFrame("StatusBar", nil, f)
        f.energy:SetSize(220, 12)
        f.energy:SetPoint("TOP")
        f.energy:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        f.energy:SetStatusBarColor(0.6, 0.2, 0.9)
        f.energy:SetMinMaxValues(0, 100)
        f.hp = CreateFrame("StatusBar", nil, f)
        f.hp:SetSize(220, 4)
        f.hp:SetPoint("TOP", f.energy, "BOTTOM", 0, -1)
        f.hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        f.hp:SetStatusBarColor(0.2, 0.8, 0.2)
        f.hp:SetMinMaxValues(0, 100)
        f.text = f.energy:CreateFontString(nil, "OVERLAY")
        f.text:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        f.text:SetPoint("CENTER", 0, 0)
        bars[i] = f
    end
    return bars[i]
end

-- ============================================================
-- TALENT LOGIC (To Hell and Back Simulation)
-- ============================================================
hooksecurefunc("UseAction", function(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" then
        local now = GetTime()
        
        -- 1. IMPLOSION (Summon 1 Boss per 2 Imps, max 3 Bosses)
        if id == 196277 then 
            local impsSacrificed = math.min(#activeImps, 6)
            table.wipe(activeImps)
            
            if impsSacrificed >= 2 then
                local bossesToSpawn = math.floor(impsSacrificed / 2)
                for i = 1, bossesToSpawn do
                    -- Imp Gang Bosses have the same duration/energy logic for tracking
                    table.insert(activeImps, { spawn = now, energy = START_ENERGY, isBoss = true })
                end
            end
            
        -- 2. POWER SIPHON (Sacrifice 2, Summon 1 Boss)
        elseif id == 264130 then
            if #activeImps >= 2 then
                table.remove(activeImps, 1)
                table.remove(activeImps, 1)
                table.insert(activeImps, { spawn = now, energy = START_ENERGY, isBoss = true })
            end
        end
    end
end)

-- ============================================================
-- THE UPDATE LOOP
-- ============================================================
local lastUpdate = GetTime()
local wasCasting = false

C_Timer.NewTicker(0.05, function()
    local now = GetTime()
    local dt = now - lastUpdate
    lastUpdate = now

    local inCombat = UnitAffectingCombat("player")
    local hasteMultiplier = 1 + (GetHaste() / 100)
    local currentDecay = DECAY_BASE * hasteMultiplier

    -- DETECT HAND OF GUL'DAN
    local _, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
    local isCasting = (spellID == 105174)
    if wasCasting and not isCasting and GetUnitSpeed("player") == 0 then
        for i = 1, 3 do table.insert(activeImps, { spawn = now, energy = START_ENERGY }) end
    end
    wasCasting = isCasting

    -- UPDATE AND CLEANUP
    for i = #activeImps, 1, -1 do
        local imp = activeImps[i]
        if inCombat then
            imp.energy = imp.energy - (currentDecay * dt)
        end
        if (now - imp.spawn) >= IMP_DURATION or imp.energy <= 0 then
            table.remove(activeImps, i)
        end
    end

    -- REFRESH UI
    title:SetText("WILD IMPS: " .. #activeImps)
    for _, b in ipairs(bars) do b:Hide() end
    for i, imp in ipairs(activeImps) do
        local b = GetBar(i)
        b:SetPoint("TOP", 0, -20 - (i-1) * 26)
        b.energy:SetValue(imp.energy)
        b.hp:SetValue(100)
        
        -- Visual distinction for Gang Bosses
        if imp.isBoss then
            b.energy:SetStatusBarColor(1, 0.4, 0) -- Orange for Bosses
        else
            b.energy:SetStatusBarColor(0.6, 0.2, 0.9) -- Purple for standard
        end

        local timeLeft = math.max(0, IMP_DURATION - (now - imp.spawn))
        b.text:SetText(string.format("%s %d: %.1fs | %d%%", imp.isBoss and "BOSS" or "Imp", i, timeLeft, math.floor(imp.energy)))
        b:Show()
    end
    mainFrame:SetHeight(math.max(40, 25 + (#activeImps * 26)))
end)

mainFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
mainFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

print("|cff8844ffWildImpTracker v4.8:|r To Hell and Back Talent Synced.")