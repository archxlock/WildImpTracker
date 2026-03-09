local ADDON_NAME = ...

local function IsDemonology()
    local spec = GetSpecialization()
    return spec == 2
end


local HAND_OF_GULDAN_SPELL_ID = 105174
local IMPLOSION_SPELL_ID = 196277
local IMP_GANG_BOSS_TALENT_ID = 1250768
local TO_HELL_AND_BACK_TALENT_ID = 1281511

local IMP_DURATION = 40
local START_ENERGY = 100
local DECAY_BASE = 7.5
local MAX_GROUPS = 20
local MAX_CASTS_NORMAL = 6
local MAX_CASTS_BOSS = 6

local FRAME_BG_DEFAULT = { r = 0, g = 0, b = 0, a = 0.55 }
local TOTAL_TEXT_DEFAULT = { r = 0.75, g = 0.85, b = 1.0, a = 1 }
local LABEL_TEXT_DEFAULT = { r = 0.78, g = 0.88, b = 1.0, a = 1 }
local TIMER_TEXT_DEFAULT = { r = 1, g = 1, b = 1, a = 1 }
local CAST_TEXT_DEFAULT = { r = 1, g = 0.95, b = 0.85, a = 1 }
local NORMAL_FILL_DEFAULT = { r = 0.15, g = 1.00, b = 0.18, a = 1 }
local NORMAL_BORDER_DEFAULT = { r = 0.35, g = 0.85, b = 0.35, a = 1 }
local BOSS_FILL_DEFAULT = { r = 1.00, g = 0.45, b = 0.00, a = 1 }
local BOSS_BORDER_DEFAULT = { r = 1.00, g = 0.60, b = 0.10, a = 1 }

local defaults = {
    x = 0,
    y = -150,
    scale = 1.0,
    alpha = 0.90,
    locked = false,
    barWidth = 25,
    barHeight = 56,
    barGap = 1,
    anchor = "TOPLEFT",
    showBackground = true,

    bgColor = FRAME_BG_DEFAULT,
    totalTextColor = TOTAL_TEXT_DEFAULT,
    labelTextColor = LABEL_TEXT_DEFAULT,
    timerTextColor = TIMER_TEXT_DEFAULT,
    castTextColor = CAST_TEXT_DEFAULT,
    normalFillColor = NORMAL_FILL_DEFAULT,
    normalBorderColor = NORMAL_BORDER_DEFAULT,
    bossFillColor = BOSS_FILL_DEFAULT,
    bossBorderColor = BOSS_BORDER_DEFAULT,

    totalFontSize = 34,
    timerFontSize = 15,
    castFontSize = 12,
    labelFontSize = 12,
}

local db
local activeGroups = {}
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
    db.barHeight = db.barHeight or 56
    db.barWidth = db.barWidth or 25
    db.barGap = db.barGap or 2
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

local function RemainingTime(group, now)
    now = now or GetTime()
    return math.max(0, IMP_DURATION - (now - group.spawn))
end

local function GetMaxCasts(group)
    if group and group.isBoss then
        return MAX_CASTS_BOSS
    end
    return MAX_CASTS_NORMAL
end

local function RemainingCasts(group)
    local maxCasts = GetMaxCasts(group)
    local casts = math.ceil((group.energy or 0) / (START_ENERGY / maxCasts))
    return math.max(0, math.min(maxCasts, casts))
end

local function AddGroup(count, isBoss)
    if not count or count <= 0 then return end

    table.insert(activeGroups, {
        spawn = GetTime(),
        energy = START_ENERGY,
        count = count,
        isBoss = isBoss and true or false,
    })

    while #activeGroups > MAX_GROUPS do
        table.remove(activeGroups, 1)
    end
end

local function AddHandOfGuldanGroup()
    AddGroup(3, false)
end

local function SortGroupIndicesByRemainingDurationAscending(now)
    wipe(displayOrder)
    for i = 1, #activeGroups do
        displayOrder[i] = i
    end

    table.sort(displayOrder, function(a, b)
        local ra = RemainingTime(activeGroups[a], now)
        local rb = RemainingTime(activeGroups[b], now)
        if math.abs(ra - rb) > 0.001 then
            return ra < rb
        end
        return activeGroups[a].spawn < activeGroups[b].spawn
    end)
end

local function ImplodeGroups()
    local impsToRemove = 6
    if impsToRemove <= 0 or #activeGroups == 0 then
        return
    end

    local now = GetTime()
    local totalRemoved = 0
    SortGroupIndicesByRemainingDurationAscending(now)

    for _, groupIndex in ipairs(displayOrder) do
        local group = activeGroups[groupIndex]
        if group and impsToRemove > 0 then
            local removeCount = math.min(impsToRemove, group.count)
            group.count = group.count - removeCount
            impsToRemove = impsToRemove - removeCount
            totalRemoved = totalRemoved + removeCount
        end
        if impsToRemove <= 0 then
            break
        end
    end

    for i = #activeGroups, 1, -1 do
        if activeGroups[i].count <= 0 then
            table.remove(activeGroups, i)
        end
    end

    if HasToHellAndBackTalent() and totalRemoved > 0 then
        local bossCount = math.floor(totalRemoved / 2)
        if bossCount > 0 then
            AddGroup(bossCount, true)
        end
    end
end

local function GetTotalImpCount()
    local total = 0
    for i = 1, #activeGroups do
        total = total + (activeGroups[i].count or 0)
    end
    return total
end

local mainFrame = CreateFrame("Frame", "WildImpTrackerMainFrame", UIParent, "BackdropTemplate")
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

local function UpdateBackdrop()
    if db.showBackground then
        mainFrame:SetBackdropColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a)
        mainFrame:SetBackdropBorderColor(0.45, 0.3, 0.8, 0.95)
    else
        mainFrame:SetBackdropColor(0, 0, 0, 0)
        mainFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

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
totalCountText:SetText("0")

local totalLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totalLabel:SetText("Imps")

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
    f.fill:SetColorTexture(0.15, 1.0, 0.18, 1)

    f.topText = f:CreateFontString(nil, "OVERLAY")
    f.topText:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    f.topText:SetPoint("BOTTOM", f, "TOP", 0, 2)
    f.topText:SetTextColor(1, 1, 1)

    f.bottomText = f:CreateFontString(nil, "OVERLAY")
    f.bottomText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    f.bottomText:SetWidth((db and db.barWidth or 25) - 4)
    f.bottomText:SetJustifyH("CENTER")
    f.bottomText:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    f.bottomText:SetTextColor(1, 0.95, 0.85)

    barFrames[index] = f
    return f
end

local function GetBar(index)
    return barFrames[index] or CreateBar(index)
end

local function UpdateContainerSize()
    local oldLeft = mainFrame:GetLeft()
    local oldTop = mainFrame:GetTop()

    local visibleBars = math.max(#activeGroups, 1)
    local barsWidth = (visibleBars * db.barWidth) + ((visibleBars - 1) * db.barGap)
    local leftColumnWidth = 64
    local totalWidth = leftColumnWidth + barsWidth + 20
    local totalHeight = math.max(174, db.barHeight + 72)

    barsAnchor:SetSize(barsWidth, db.barHeight)
    barsAnchor:ClearAllPoints()
    barsAnchor:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", leftColumnWidth, -40)

    totalCountText:SetFont("Fonts\\FRIZQT__.TTF", db.totalFontSize or 34, "OUTLINE")
    totalCountText:SetTextColor(db.totalTextColor.r, db.totalTextColor.g, db.totalTextColor.b, db.totalTextColor.a)
    totalCountText:ClearAllPoints()
    totalCountText:SetPoint("RIGHT", barsAnchor, "LEFT", -14, 0)

    totalLabel:SetFont("Fonts\\FRIZQT__.TTF", db.labelFontSize or 12, "OUTLINE")
    totalLabel:SetTextColor(db.labelTextColor.r, db.labelTextColor.g, db.labelTextColor.b, db.labelTextColor.a)
    totalLabel:ClearAllPoints()
    totalLabel:SetPoint("TOP", totalCountText, "BOTTOM", 0, -2)

    mainFrame:SetSize(totalWidth, totalHeight)
    mainFrame:SetScale(db.scale)
    mainFrame:SetAlpha(db.alpha)

    if oldLeft and oldTop then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", oldLeft, oldTop)
    end

    UpdateBackdrop()
    mainFrame:EnableMouse(not db.locked)
end

local function LayoutBars()
    for i = 1, math.max(#activeGroups, #barFrames) do
        local bar = GetBar(i)
        bar:SetSize(db.barWidth, db.barHeight)
        if bar.topText then
            bar.topText:SetFont("Fonts\\FRIZQT__.TTF", db.timerFontSize or 15, "OUTLINE")
            bar.topText:SetTextColor(db.timerTextColor.r, db.timerTextColor.g, db.timerTextColor.b, db.timerTextColor.a)
        end
        if bar.bottomText then
            bar.bottomText:SetFont("Fonts\\FRIZQT__.TTF", db.castFontSize or 12, "OUTLINE")
            bar.bottomText:SetTextColor(db.castTextColor.r, db.castTextColor.g, db.castTextColor.b, db.castTextColor.a)
            bar.bottomText:SetWidth(db.barWidth - 4)
        end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", (i - 1) * (db.barWidth + db.barGap), 0)
    end
end

local function ApplyBarColors(bar, group)
    if group and group.isBoss then
        bar.fill:SetColorTexture(db.bossFillColor.r, db.bossFillColor.g, db.bossFillColor.b, db.bossFillColor.a)
        bar:SetBackdropBorderColor(db.bossBorderColor.r, db.bossBorderColor.g, db.bossBorderColor.b, db.bossBorderColor.a)
    else
        bar.fill:SetColorTexture(db.normalFillColor.r, db.normalFillColor.g, db.normalFillColor.b, db.normalFillColor.a)
        bar:SetBackdropBorderColor(db.normalBorderColor.r, db.normalBorderColor.g, db.normalBorderColor.b, db.normalBorderColor.a)
    end
end

local function RefreshDisplay()
    local now = GetTime()
    totalCountText:SetText(tostring(GetTotalImpCount()))

    SortGroupIndicesByRemainingDurationAscending(now)
    UpdateContainerSize()
    LayoutBars()

    for i = 1, #barFrames do
        barFrames[i]:Hide()
    end

    for visualIndex, groupIndex in ipairs(displayOrder) do
        local group = activeGroups[groupIndex]
        local bar = GetBar(visualIndex)
        local remaining = RemainingTime(group, now)
        local casts = RemainingCasts(group)
        local maxCasts = GetMaxCasts(group)
        local fillHeight = 1

        if maxCasts > 0 then
            fillHeight = math.max(1, math.floor((casts / maxCasts) * (db.barHeight - 6)))
        end

        ApplyBarColors(bar, group)
        bar.fill:SetHeight(fillHeight)
        bar.topText:SetText(string.format("%d", math.ceil(remaining)))
        bar.bottomText:SetText(string.format("%d", casts))
        bar:Show()
    end
end

local function RevertToDefaults()
    wipe(db)
    CopyDefaults(defaults, db)
    print("|cff9d7dffWild Imp Tracker:|r All settings reverted to defaults.")
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -150)
    SaveFramePosition()
    UpdateContainerSize()
    RefreshDisplay()
end

local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)

local function GetOptionsTable()
    return {
        type = "group",
        name = "Wild Imp Tracker",
        args = {
            basicGroup = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 10,
                args = {
                    locked = {
                        type = "toggle", name = "Lock Frame",
                        get = function() return db.locked end,
                        set = function(_, v) db.locked = v; mainFrame:EnableMouse(not v); UpdateContainerSize() end,
                        order = 1,
                    },
                    showBackground = {
                        type = "toggle", name = "Show Background",
                        get = function() return db.showBackground end,
                        set = function(_, v) db.showBackground = v; UpdateBackdrop() end,
                        order = 2,
                    },
                    bgColor = {
                        type = "color", name = "Background Color", hasAlpha = true,
                        get = function() return db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a end,
                        set = function(_, r, g, b, a) db.bgColor = { r = r, g = g, b = b, a = a }; UpdateBackdrop() end,
                        order = 3,
                    },
                    scale = {
                        type = "range", name = "Scale", min = 0.4, max = 3.0, step = 0.05,
                        get = function() return db.scale end,
                        set = function(_, v) db.scale = v; UpdateContainerSize(); RefreshDisplay() end,
                        order = 4,
                    },
                    alpha = {
                        type = "range", name = "Alpha", min = 0.1, max = 1.0, step = 0.01,
                        get = function() return db.alpha end,
                        set = function(_, v) db.alpha = v; UpdateContainerSize() end,
                        order = 5,
                    },
                },
            },
            barsGroup = {
                type = "group",
                name = "Bars",
                inline = true,
                order = 20,
                args = {
                    barWidth = {
                        type = "range", name = "Bar Width", min = 16, max = 80, step = 1,
                        get = function() return db.barWidth end,
                        set = function(_, v) db.barWidth = v; RefreshDisplay() end,
                        order = 1,
                    },
                    barHeight = {
                        type = "range", name = "Bar Height", min = 50, max = 180, step = 1,
                        get = function() return db.barHeight end,
                        set = function(_, v) db.barHeight = v; RefreshDisplay() end,
                        order = 2,
                    },
                    barGap = {
                        type = "range", name = "Bar Gap", min = 0, max = 20, step = 1,
                        get = function() return db.barGap end,
                        set = function(_, v) db.barGap = v; RefreshDisplay() end,
                        order = 3,
                    },
                    normalFillColor = {
                        type = "color", name = "Normal Imp Fill", hasAlpha = true,
                        get = function() return db.normalFillColor.r, db.normalFillColor.g, db.normalFillColor.b, db.normalFillColor.a end,
                        set = function(_, r, g, b, a) db.normalFillColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 4,
                    },
                    normalBorderColor = {
                        type = "color", name = "Normal Imp Border", hasAlpha = true,
                        get = function() return db.normalBorderColor.r, db.normalBorderColor.g, db.normalBorderColor.b, db.normalBorderColor.a end,
                        set = function(_, r, g, b, a) db.normalBorderColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 5,
                    },
                    bossFillColor = {
                        type = "color", name = "Imp Gang Boss Fill", hasAlpha = true,
                        get = function() return db.bossFillColor.r, db.bossFillColor.g, db.bossFillColor.b, db.bossFillColor.a end,
                        set = function(_, r, g, b, a) db.bossFillColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 6,
                    },
                    bossBorderColor = {
                        type = "color", name = "Imp Gang Boss Border", hasAlpha = true,
                        get = function() return db.bossBorderColor.r, db.bossBorderColor.g, db.bossBorderColor.b, db.bossBorderColor.a end,
                        set = function(_, r, g, b, a) db.bossBorderColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 7,
                    },
                },
            },
            textGroup = {
                type = "group",
                name = "Text",
                inline = true,
                order = 30,
                args = {
                    totalFontSize = {
                        type = "range", name = "Total Imps Font Size", min = 18, max = 60, step = 1,
                        get = function() return db.totalFontSize end,
                        set = function(_, v) db.totalFontSize = v; RefreshDisplay() end,
                        order = 1,
                    },
                    timerFontSize = {
                        type = "range", name = "Duration Font Size", min = 8, max = 30, step = 1,
                        get = function() return db.timerFontSize end,
                        set = function(_, v) db.timerFontSize = v; RefreshDisplay() end,
                        order = 2,
                    },
                    castFontSize = {
                        type = "range", name = "Casts Font Size", min = 8, max = 30, step = 1,
                        get = function() return db.castFontSize end,
                        set = function(_, v) db.castFontSize = v; RefreshDisplay() end,
                        order = 3,
                    },
                    labelFontSize = {
                        type = "range", name = "Label Font Size", min = 8, max = 30, step = 1,
                        get = function() return db.labelFontSize end,
                        set = function(_, v) db.labelFontSize = v; RefreshDisplay() end,
                        order = 4,
                    },
                    totalTextColor = {
                        type = "color", name = "Total Imps Color", hasAlpha = true,
                        get = function() return db.totalTextColor.r, db.totalTextColor.g, db.totalTextColor.b, db.totalTextColor.a end,
                        set = function(_, r, g, b, a) db.totalTextColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 5,
                    },
                    labelTextColor = {
                        type = "color", name = "Label Color", hasAlpha = true,
                        get = function() return db.labelTextColor.r, db.labelTextColor.g, db.labelTextColor.b, db.labelTextColor.a end,
                        set = function(_, r, g, b, a) db.labelTextColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 6,
                    },
                    timerTextColor = {
                        type = "color", name = "Duration Text Color", hasAlpha = true,
                        get = function() return db.timerTextColor.r, db.timerTextColor.g, db.timerTextColor.b, db.timerTextColor.a end,
                        set = function(_, r, g, b, a) db.timerTextColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 7,
                    },
                    castTextColor = {
                        type = "color", name = "Casts Text Color", hasAlpha = true,
                        get = function() return db.castTextColor.r, db.castTextColor.g, db.castTextColor.b, db.castTextColor.a end,
                        set = function(_, r, g, b, a) db.castTextColor = { r = r, g = g, b = b, a = a }; RefreshDisplay() end,
                        order = 8,
                    },
                },
            },
            profilesGroup = {
                type = "group",
                name = "Profiles",
                inline = true,
                order = 40,
                args = {
                    revert = {
                        type = "execute",
                        name = "Revert to Defaults",
                        desc = "Reset all settings to original default values.",
                        func = function()
                            StaticPopupDialogs["WILDIMPTRACKER_REVERT"] = {
                                text = "Revert all settings to defaults?\nThis cannot be undone.",
                                button1 = "Yes, Reset",
                                button2 = "Cancel",
                                OnAccept = function() RevertToDefaults() end,
                                showAlert = true,
                                preferredIndex = 3,
                                timeout = 0,
                                whileDead = true,
                                hideOnEscape = true,
                            }
                            StaticPopup_Show("WILDIMPTRACKER_REVERT")
                        end,
                        order = 1,
                    },
                },
            },
            testGroup = {
                type = "group",
                name = "Test Actions",
                inline = true,
                order = 50,
                args = {
                    testHog = {
                        type = "execute",
                        name = "Test Hand of Gul'dan",
                        func = function() AddHandOfGuldanGroup(); RefreshDisplay() end,
                        order = 1,
                    },
                    testImplode = {
                        type = "execute",
                        name = "Test Implosion",
                        func = function() ImplodeGroups(); RefreshDisplay() end,
                        order = 2,
                    },
                    clear = {
                        type = "execute",
                        name = "Clear Imps",
                        func = function() wipe(activeGroups); RefreshDisplay() end,
                        order = 3,
                    },
                },
            },
        },
    }
end

local function PrintHelp()
    print("|cff9d7dffWild Imp Tracker:|r /wit opens options. Commands: lock | unlock | scale <n> | alpha <n> | width <n> | height <n> | gap <n>")
    print("|cff9d7dffWild Imp Tracker:|r /wit talent | test | implode | clear | bg on | bg off")
end

SLASH_WILDIMPTRACKER1 = "/wit"
SLASH_WILDIMPTRACKER2 = "/itr"
SlashCmdList["WILDIMPTRACKER"] = function(msg)
    EnsureDB()
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        if AceConfigDialog then
            AceConfigDialog:Open(ADDON_NAME)
        else
            PrintHelp()
            print("|cff9d7dffWild Imp Tracker:|r Options panel requires Ace3.")
        end
        return
    end

    local cmd, arg1 = msg:match("^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")
    arg1 = string.lower(arg1 or "")

    if cmd == "lock" then
        db.locked = true
        UpdateContainerSize()
        print("|cff9d7dffWild Imp Tracker:|r Locked.")
    elseif cmd == "unlock" then
        db.locked = false
        UpdateContainerSize()
        print("|cff9d7dffWild Imp Tracker:|r Unlocked.")
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
        print("|cff9d7dffWild Imp Tracker:|r Imp Gang Boss = " .. tostring(HasImpGangBossTalent()))
        print("|cff9d7dffWild Imp Tracker:|r To Hell and Back = " .. tostring(HasToHellAndBackTalent()))
    elseif cmd == "test" then
        AddHandOfGuldanGroup()
        RefreshDisplay()
        print("|cff9d7dffWild Imp Tracker:|r Added grouped Hand of Gul'dan imps.")
    elseif cmd == "implode" then
        ImplodeGroups()
        RefreshDisplay()
        print("|cff9d7dffWild Imp Tracker:|r Simulated Implosion.")
    elseif cmd == "clear" then
        wipe(activeGroups)
        RefreshDisplay()
        print("|cff9d7dffWild Imp Tracker:|r Cleared active imp groups.")
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
mainFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

mainFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        EnsureDB()

        if AceConfig then
            AceConfig:RegisterOptionsTable(ADDON_NAME, GetOptionsTable)
            if AceConfigDialog then
                AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Wild Imp Tracker")
            end
        end

        mainFrame:ClearAllPoints()
        if db.anchor == "TOPLEFT" then
            mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.x or 0, db.y or -150)
        else
            mainFrame:SetPoint(db.anchor or "CENTER", UIParent, db.anchor or "CENTER", db.x or 0, db.y or 150)
            SaveFramePosition()
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.x or 0, db.y or -150)
        end
        UpdateBackdrop()
        UpdateContainerSize()
        RefreshDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnsureDB()
        if not IsDemonology() then
            mainFrame:Hide()
            return
        else
            mainFrame:Show()
        end
        lastUpdate = GetTime()
        RefreshDisplay()
    elseif event == "PLAYER_LOGOUT" then
        EnsureDB()
        SaveFramePosition()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if IsDemonology() then
            mainFrame:Show()
            RefreshDisplay()
        else
            mainFrame:Hide()
        end
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
        RefreshDisplay()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        if spellID == HAND_OF_GULDAN_SPELL_ID then
            AddHandOfGuldanGroup()
            RefreshDisplay()
        elseif spellID == IMPLOSION_SPELL_ID then
            ImplodeGroups()
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

    for i = #activeGroups, 1, -1 do
        local group = activeGroups[i]
        if UnitAffectingCombat("player") then
            group.energy = group.energy - (DECAY_BASE * haste * dt)
        end
        if RemainingTime(group, now) <= 0 or group.energy <= 0 or group.count <= 0 then
            table.remove(activeGroups, i)
        end
    end

    RefreshDisplay()
end)
