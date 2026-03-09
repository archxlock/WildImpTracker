-- Imp Tracker Reskin v6.2.0
-- Compact vertical-bar imp tracker for Demonology Warlock
-- Simulated imp tracker with support for:
--   * Hand of Gul'dan spawning 3 imps
--   * Imp Gang Boss talent (1250768)
--   * Implosion removing the 6 imps with the least remaining duration
--   * To Hell and Back talent (1281511) spawning boss imps from Implosion
--   * Bar fill representing remaining casts/fireballs instead of remaining duration

local ADDON_NAME = ...

local HAND_OF_GULDAN_SPELL_ID = 105174
local IMPLOSION_SPELL_ID = 196277
local IMP_GANG_BOSS_TALENT_ID = 1250768
local TO_HELL_AND_BACK_TALENT_ID = 1281511

local IMP_DURATION = 40
local START_ENERGY = 100
local DECAY_BASE = 7.5
local MAX_IMPS = 40
local MAX_CASTS_NORMAL = 6
local MAX_CASTS_BOSS = 6

local defaults = {
    x = 0,
    y = -150,
    scale = 1.0,
    alpha = 0.90,
    locked = false,
    barWidth = 30,
    barHeight = 60,
    barGap = 2,
    anchor = "TOPLEFT",
    showBackground = true,
}

local db
local activeImps = {}
local displayOrder = {}
local barFrames = {}
local lastUpdate = GetTime()

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function EnsureDB()
    ImpTrackerReskinDBShortBars = ImpTrackerReskinDBShortBars or {}
    CopyDefaults(defaults, ImpTrackerReskinDBShortBars)
    db = ImpTrackerReskinDBShortBars
    db.barHeight = 60
    db.barWidth = 20
    db.barGap = 2
    db.barHeight = 60
    db.barWidth = 20
    db.barGap = 2
    db.barHeight = 60
end

local function IsSpellKnownSafe(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID)
    end
    if IsPlayerSpell then
        return IsPlayerSpell(spellID)
    end
    return false
end

local function HasImpGangBossTalent()
    return IsSpellKnownSafe(IMP_GANG_BOSS_TALENT_ID)
end

local function HasToHellAndBackTalent()
    return IsSpellKnownSafe(TO_HELL_AND_BACK_TALENT_ID)
end

local function RemainingTime(imp, now)
    now = now or GetTime()
    return math.max(0, IMP_DURATION - (now - imp.spawn))
end

local function GetMaxCasts(imp)
    if imp and imp.isBoss then
        return MAX_CASTS_BOSS
    end
    return MAX_CASTS_NORMAL
end

local function RemainingCasts(imp)
    local maxCasts = GetMaxCasts(imp)
    local casts = math.ceil((imp.energy or 0) / (START_ENERGY / maxCasts))
    return math.max(0, math.min(maxCasts, casts))
end

local function AddImp(isBoss)
    table.insert(activeImps, {
        spawn = GetTime(),
        energy = START_ENERGY,
        isBoss = isBoss and true or false,
    })
    while #activeImps > MAX_IMPS do
        table.remove(activeImps, 1)
    end
end

local function AddHandOfGuldanImps()
    local hasIGB = HasImpGangBossTalent()
    local madeBoss = false

    for _ = 1, 3 do
        local isBoss = false
        if hasIGB and not madeBoss then
            isBoss = true
            madeBoss = true
        end
        AddImp(isBoss)
    end
end

local function SortImpIndicesByRemainingDurationAscending(now)
    wipe(displayOrder)
    for i = 1, #activeImps do
        displayOrder[i] = i
    end

    table.sort(displayOrder, function(a, b)
        local ra = RemainingTime(activeImps[a], now)
        local rb = RemainingTime(activeImps[b], now)
        if math.abs(ra - rb) > 0.001 then
            return ra < rb
        end
        return activeImps[a].spawn < activeImps[b].spawn
    end)
end

local function ImplodeImps()
    local now = GetTime()
    SortImpIndicesByRemainingDurationAscending(now)

    local toRemove = math.min(6, #displayOrder)
    if toRemove <= 0 then
        return
    end

    local removeMap = {}
    for n = 1, toRemove do
        removeMap[displayOrder[n]] = true
    end

    for i = #activeImps, 1, -1 do
        if removeMap[i] then
            table.remove(activeImps, i)
        end
    end

    if HasToHellAndBackTalent() then
        local bossesToSpawn = math.floor(toRemove / 2)
        for _ = 1, bossesToSpawn do
            AddImp(true)
        end
    end
end

local mainFrame = CreateFrame("Frame", "ImpTrackerReskinMainFrame", UIParent, "BackdropTemplate")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:SetClampedToScreen(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
mainFrame:SetBackdropColor(0, 0, 0, 0.55)
mainFrame:SetBackdropBorderColor(0.45, 0.3, 0.8, 0.95)

local function SaveFramePosition()
    local left = mainFrame:GetLeft()
    local top = mainFrame:GetTop()
    if left and top then
        db.anchor = "TOPLEFT"
        db.x = left
        db.y = top
    end
end

mainFrame:SetScript("OnDragStart", function(self)
    if db and not db.locked then
        self:StartMoving()
    end
end)

mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveFramePosition()
end)




local totalCountText = mainFrame:CreateFontString(nil, "OVERLAY")
totalCountText:SetFont("Fonts\\FRIZQT__.TTF", 34, "OUTLINE")
totalCountText:SetJustifyH("CENTER")
totalCountText:SetTextColor(0.75, 0.85, 1.0)
totalCountText:SetText("0")

local totalLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totalLabel:SetText("Imps")
totalLabel:SetTextColor(0.78, 0.88, 1)

local barsAnchor = CreateFrame("Frame", nil, mainFrame)
local function CreateBar(index)
    local f = CreateFrame("Frame", nil, barsAnchor, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
    f:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetPoint("BOTTOMLEFT", 3, 3)
    f.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    f.fill:SetHeight(1)
    f.fill:SetColorTexture(0.55, 0.2, 0.95, 1)

    f.topText = f:CreateFontString(nil, "OVERLAY")
    f.topText:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    f.topText:SetPoint("BOTTOM", f, "TOP", 0, 2)
    f.topText:SetTextColor(1, 1, 1)

    f.bottomText = f:CreateFontString(nil, "OVERLAY")
    f.bottomText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    f.bottomText:SetWidth(db.barWidth - 6)
    f.bottomText:SetJustifyH("CENTER")
    f.bottomText:SetPoint("BOTTOM", 0, 8)
    f.bottomText:SetTextColor(1, 0.95, 0.85)

    f.index = index
    barFrames[index] = f
    return f
end

local function GetBar(index)
    return barFrames[index] or CreateBar(index)
end

local function UpdateContainerSize()
    local oldLeft = mainFrame:GetLeft()
    local oldTop = mainFrame:GetTop()

    local visibleBars = math.max(#activeImps, 1)
    local barsWidth = (visibleBars * db.barWidth) + ((visibleBars - 1) * db.barGap)
    local leftColumnWidth = 64
    local totalWidth = leftColumnWidth + barsWidth + 20
    local totalHeight = math.max(174, db.barHeight + 72)

    barsAnchor:SetSize(barsWidth, db.barHeight)
    barsAnchor:ClearAllPoints()
    barsAnchor:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", leftColumnWidth, -40)

    totalCountText:ClearAllPoints()
    totalCountText:SetPoint("RIGHT", barsAnchor, "LEFT", -14, 0)

    totalLabel:ClearAllPoints()
    totalLabel:SetPoint("TOP", totalCountText, "BOTTOM", 0, -2)

    mainFrame:SetSize(totalWidth, totalHeight)
    mainFrame:SetScale(db.scale)
    mainFrame:SetAlpha(db.alpha)

    if oldLeft and oldTop then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", oldLeft, oldTop)
    end

    if db.showBackground then
        mainFrame:SetBackdropColor(0, 0, 0, 0.55)
        mainFrame:SetBackdropBorderColor(0.45, 0.3, 0.8, 0.95)
    else
        mainFrame:SetBackdropColor(0, 0, 0, 0)
        mainFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    mainFrame:EnableMouse(not db.locked)
end

local function LayoutBars()
    for i = 1, math.max(#activeImps, #barFrames) do
        local bar = GetBar(i)
        bar:SetSize(db.barWidth, db.barHeight)
        if bar.bottomText then
            bar.bottomText:SetWidth(db.barWidth - 6)
        end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", (i - 1) * (db.barWidth + db.barGap), 0)
    end
end

local function RefreshDisplay()
    local now = GetTime()
    totalCountText:SetText(tostring(#activeImps))

    SortImpIndicesByRemainingDurationAscending(now)
    UpdateContainerSize()
    LayoutBars()

    for i = 1, #barFrames do
        barFrames[i]:Hide()
    end

    for visualIndex, impIndex in ipairs(displayOrder) do
        local imp = activeImps[impIndex]
        local bar = GetBar(visualIndex)
        local remaining = RemainingTime(imp, now)
        local casts = RemainingCasts(imp)
        local maxCasts = GetMaxCasts(imp)
        local fillHeight = 1

        if maxCasts > 0 then
            fillHeight = math.max(1, math.floor((casts / maxCasts) * (db.barHeight - 6)))
        end

        if imp.isBoss then
            bar.fill:SetColorTexture(1.0, 0.18, 0.05, 1)
            bar:SetBackdropBorderColor(1.0, 0.42, 0.12, 1)
        else
            bar.fill:SetColorTexture(0.15, 1.0, 0.18, 1)
            bar:SetBackdropBorderColor(0.35, 0.85, 0.35, 1)
        end

        bar.fill:SetHeight(fillHeight)
        bar.topText:SetText(string.format("%d", math.ceil(remaining)))
        bar.bottomText:SetText(string.format("%d", casts))
        bar:Show()
    end
end

local function PrintHelp()
    print("|cff9d7dffImp Tracker Reskin:|r /wit lock | unlock | scale <n> | alpha <n> | width <n> | height <n> | gap <n>")
    print("|cff9d7dffImp Tracker Reskin:|r /wit talent | test | implode | clear | bg on | bg off")
end

SLASH_WILDIMPTRACKER1 = "/wit"
SLASH_WILDIMPTRACKER2 = "/itr"
SlashCmdList["WILDIMPTRACKER"] = function(msg)
    EnsureDB()
    local cmd, arg1, arg2 = msg:match("^(%S*)%s*(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")
    arg1 = string.lower(arg1 or "")

    if cmd == "lock" then
        db.locked = true
        UpdateContainerSize()
        print("|cff9d7dffImp Tracker Reskin:|r Locked.")
    elseif cmd == "unlock" then
        db.locked = false
        UpdateContainerSize()
        print("|cff9d7dffImp Tracker Reskin:|r Unlocked.")
    elseif cmd == "scale" then
        local n = tonumber(arg1)
        if n then
            db.scale = math.max(0.4, math.min(3, n))
            UpdateContainerSize()
            RefreshDisplay()
        end
    elseif cmd == "alpha" then
        local n = tonumber(arg1)
        if n then
            db.alpha = math.max(0.1, math.min(1, n))
            UpdateContainerSize()
        end
    elseif cmd == "width" then
        local n = tonumber(arg1)
        if n then
            db.barWidth = math.max(16, math.min(80, math.floor(n)))
            RefreshDisplay()
        end
    elseif cmd == "height" then
        local n = tonumber(arg1)
        if n then
            db.barHeight = math.max(50, math.min(180, math.floor(n)))
            RefreshDisplay()
        end
    elseif cmd == "gap" then
        local n = tonumber(arg1)
        if n then
            db.barGap = math.max(0, math.min(20, math.floor(n)))
            RefreshDisplay()
        end
    elseif cmd == "bg" then
        if arg1 == "on" then
            db.showBackground = true
            UpdateContainerSize()
        elseif arg1 == "off" then
            db.showBackground = false
            UpdateContainerSize()
        end
    elseif cmd == "talent" then
        print("|cff9d7dffImp Tracker Reskin:|r Imp Gang Boss = " .. tostring(HasImpGangBossTalent()))
        print("|cff9d7dffImp Tracker Reskin:|r To Hell and Back = " .. tostring(HasToHellAndBackTalent()))
    elseif cmd == "test" then
        AddHandOfGuldanImps()
        RefreshDisplay()
        print("|cff9d7dffImp Tracker Reskin:|r Added test Hand of Gul'dan imps.")
    elseif cmd == "implode" then
        ImplodeImps()
        RefreshDisplay()
        print("|cff9d7dffImp Tracker Reskin:|r Simulated Implosion.")
    elseif cmd == "clear" then
        wipe(activeImps)
        RefreshDisplay()
        print("|cff9d7dffImp Tracker Reskin:|r Cleared active imps.")
    else
        PrintHelp()
    end
end

mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("PLAYER_LOGOUT")
mainFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
mainFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
mainFrame:RegisterEvent("PLAYER_TALENT_UPDATE")

mainFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        EnsureDB()
        mainFrame:ClearAllPoints()
        if db.anchor == "TOPLEFT" then
            mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.x or 0, db.y or -150)
        else
            mainFrame:SetPoint(db.anchor or "CENTER", UIParent, db.anchor or "CENTER", db.x or 0, db.y or 150)
            SaveFramePosition()
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.x or 0, db.y or -150)
        end
        UpdateContainerSize()
        RefreshDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnsureDB()
        lastUpdate = GetTime()
        RefreshDisplay()
    elseif event == "PLAYER_LOGOUT" then
        EnsureDB()
        SaveFramePosition()
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
        RefreshDisplay()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        if spellID == HAND_OF_GULDAN_SPELL_ID then
            AddHandOfGuldanImps()
            RefreshDisplay()
        elseif spellID == IMPLOSION_SPELL_ID then
            ImplodeImps()
            RefreshDisplay()
        end
    end
end)

C_Timer.NewTicker(0.05, function()
    if not db then return end

    local now = GetTime()
    local dt = now - lastUpdate
    lastUpdate = now

    local haste = 1 + ((GetHaste() or 0) / 100)

    for i = #activeImps, 1, -1 do
        local imp = activeImps[i]
        if UnitAffectingCombat("player") then
            imp.energy = imp.energy - (DECAY_BASE * haste * dt)
        end
        if RemainingTime(imp, now) <= 0 or imp.energy <= 0 then
            table.remove(activeImps, i)
        end
    end

    RefreshDisplay()
end)