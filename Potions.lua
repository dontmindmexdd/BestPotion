local _, ns = ...

local CONSUMABLE_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or _G.LE_ITEM_CLASS_CONSUMABLE or 0
local POTION_SUBCLASS_ID = (Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Potion) or 1
local GENERIC_SUBCLASS_ID = 0
local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

-- Curated Classic / WoW Forever potions used as fast-path metadata and locale fallback.
-- Live client tooltips still take precedence whenever available so Forever rebalances
-- or custom potions work automatically.
ns.KNOWN_POTIONS = {
    -- Healing
    [118]   = { name = "Minor Healing Potion",       heal = 80,   reqLevel = 1 },
    [858]   = { name = "Lesser Healing Potion",      heal = 160,  reqLevel = 3 },
    [4596]  = { name = "Discolored Healing Potion",  heal = 160,  reqLevel = 5 },
    [929]   = { name = "Healing Potion",             heal = 320,  reqLevel = 12 },
    [1710]  = { name = "Greater Healing Potion",     heal = 520,  reqLevel = 21 },
    [3928]  = { name = "Superior Healing Potion",    heal = 800,  reqLevel = 35 },
    [18839] = { name = "Combat Healing Potion",      heal = 800,  reqLevel = 35 },
    [13446] = { name = "Major Healing Potion",       heal = 1400, reqLevel = 45 },
    [17349] = { name = "Superior Healing Draught",   heal = 640,  reqLevel = 35, bgOnly = true },
    [17348] = { name = "Major Healing Draught",      heal = 1120, reqLevel = 45, bgOnly = true },

    -- Mana
    [2455]  = { name = "Minor Mana Potion",          mana = 160,  reqLevel = 5 },
    [3385]  = { name = "Lesser Mana Potion",         mana = 320,  reqLevel = 14 },
    [3827]  = { name = "Mana Potion",                mana = 520,  reqLevel = 22 },
    [6149]  = { name = "Greater Mana Potion",        mana = 800,  reqLevel = 31 },
    [13443] = { name = "Superior Mana Potion",       mana = 1200, reqLevel = 41 },
    [18841] = { name = "Combat Mana Potion",         mana = 1200, reqLevel = 41 },
    [13444] = { name = "Major Mana Potion",          mana = 1800, reqLevel = 49 },
    [17352] = { name = "Superior Mana Draught",      mana = 640,  reqLevel = 35, bgOnly = true },
    [17351] = { name = "Major Mana Draught",         mana = 1120, reqLevel = 45, bgOnly = true },

    -- Rejuvenation (both)
    [2456]  = { name = "Minor Rejuvenation Potion",  heal = 120,  mana = 120,  reqLevel = 5 },
    [18253] = { name = "Major Rejuvenation Potion",  heal = 1600, mana = 1600, reqLevel = 50 },
}

-- Explicitly excluded non-instant / sleep / health-cost / RNG consumables.
ns.EXCLUDED_POTIONS = {
    [12190] = true, -- Dreamless Sleep Potion
    [20002] = true, -- Greater Dreamless Sleep Potion
    [9144]  = true, -- Wildvine Potion
    [20520] = true, -- Dark Rune
    [12662] = true, -- Demonic Rune
}

local function buildPattern(fmt, fallback)
    local source = (type(fmt) == "string" and fmt ~= "") and fmt or fallback
    local order = {}
    local pattern = source:gsub("%%(%d?)%$?([sd])", function(pos, kind)
        order[#order + 1] = tonumber(pos) or (#order + 1)
        return kind == "s" and "\1" or "\2"
    end)
    pattern = pattern:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    pattern = "^" .. pattern:gsub("\1", "(.+)"):gsub("\2", "(%%d+)") .. "$"
    return pattern, order
end

local function matchFormat(text, pattern, order)
    if not pattern then
        return nil
    end
    local captures = { text:match(pattern) }
    if not captures[1] then
        return nil
    end
    local unpackFn = _G.unpack or table.unpack
    local out = {}
    for i, pos in ipairs(order) do
        out[pos] = captures[i]
    end
    return unpackFn(out, 1, #order)
end

local MIN_LEVEL_PATTERN, MIN_LEVEL_ORDER = buildPattern(_G.ITEM_MIN_LEVEL, "Requires Level %d")
local CLASSES_PATTERN, CLASSES_ORDER = buildPattern(_G.ITEM_CLASSES_ALLOWED, "Classes: %s")
local FALLBACK_MIN_LEVEL_PATTERN = "^[Rr]equires [Ll]evel (%d+)$"
local FALLBACK_CLASSES_PATTERN = "^Classes:%s*(.+)$"

local function parseNumber(str)
    if type(str) ~= "string" then
        return nil
    end
    local cleaned = str:gsub(",", "")
    if not cleaned:match("^%d+%.?%d*$") and not cleaned:match("^%d*%.%d+$") then
        return nil
    end
    return tonumber(cleaned)
end

local EXCLUDED_SUBSTRINGS = {
    "sleep",
    "incapacitat",
    "must remain seated",
    "at the cost of",
    "drains",
    "sacrific",
    "friendly target",
    "maximum health",
    "maximum mana",
}

local EXCLUDED_PATTERNS = {
    "%f[%a]pet%f[%A]",
    "over %d[%d,%.]* sec",
    "every %d[%d,%.]* sec",
    "per %d[%d,%.]* sec",
    "for %d[%d,%.]* min",
    "for %d[%d,%.]* hour",
    "increases .* health",
    "increases .* mana",
}

local function isExcludedLine(lowerText)
    for _, sub in ipairs(EXCLUDED_SUBSTRINGS) do
        if lowerText:find(sub, 1, true) then
            return true
        end
    end
    for _, pat in ipairs(EXCLUDED_PATTERNS) do
        if lowerText:match(pat) then
            return true
        end
    end
    return false
end

local function isBattlegroundText(lowerText)
    return lowerText:find("battleground", 1, true) ~= nil
        or lowerText:find("alterac valley", 1, true) ~= nil
        or lowerText:find("warsong gulch", 1, true) ~= nil
        or lowerText:find("arathi basin", 1, true) ~= nil
end

local function extractRestrictedZone(text)
    local zone = text:match("[Oo]nly usable inside ([^%.]+)")
        or text:match("[Oo]nly usable in ([^%.]+)")
        or text:match("[Cc]an only be used inside ([^%.]+)")
        or text:match("[Cc]an only be used in ([^%.]+)")
    if not zone then
        return nil, false
    end
    zone = zone:gsub("^%s+", ""):gsub("%s+$", "")
    if zone == "" then
        return nil, false
    end
    if isBattlegroundText(zone:lower()) then
        return nil, true
    end
    return zone, false
end

local function isOnUseLine(text)
    local prefix = ns.Plain(_G.ITEM_SPELL_TRIGGER_ONUSE)
    if type(prefix) == "string" and prefix ~= "" and text:sub(1, #prefix) == prefix then
        return true
    end
    return text:sub(1, 4) == "Use:"
end

local function parseResourceValue(lowerUse, kind)
    -- Range: "1,050 to 1,750 health" or "1050-1750 health"
    local loStr, hiStr = lowerUse:match("([%d,]+)%s+to%s+([%d,]+)%s+" .. kind)
    if not loStr then
        loStr, hiStr = lowerUse:match("([%d,]+)%s*%-%s*([%d,]+)%s+" .. kind)
    end
    if loStr and hiStr then
        local lo, hi = parseNumber(loStr), parseNumber(hiStr)
        if lo and hi then
            return (lo + hi) / 2, nil
        end
    end

    -- Flat: "1,400 health"
    local flatStr = lowerUse:match("([%d,]+)%s+" .. kind)
    if flatStr then
        local val = parseNumber(flatStr)
        if val then
            return val, nil
        end
    end

    -- Percent: "50% of your health" or "50% health"
    local pctStr = lowerUse:match("([%d%.]+)%%%s+of%s+[%a%s]-" .. kind)
        or lowerUse:match("([%d%.]+)%%%s+" .. kind)
    if pctStr then
        local pct = tonumber(pctStr)
        if pct and pct > 0 then
            return nil, pct
        end
    end

    return nil, nil
end

function ns.ParsePotionTooltipLines(lines, maxHealth, maxMana)
    local result = {
        hasLines = false,
        reqLevel = nil,
        classes = nil,
        bgOnly = false,
        restrictedZone = nil,
        excluded = false,
        heal = nil,
        mana = nil,
        healPct = nil,
        manaPct = nil,
    }
    if type(lines) ~= "table" or #lines == 0 then
        return result
    end

    local useLines = {}
    for _, rawLine in ipairs(lines) do
        local text = ns.Plain(rawLine)
        if type(text) == "string" then
            text = text:gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" then
                result.hasLines = true
                local lowerText = text:lower()

                local lvl = matchFormat(text, MIN_LEVEL_PATTERN, MIN_LEVEL_ORDER)
                    or text:match(FALLBACK_MIN_LEVEL_PATTERN)
                local numLvl = lvl and tonumber(lvl)
                if numLvl and (not result.reqLevel or numLvl > result.reqLevel) then
                    result.reqLevel = numLvl
                end

                local classesStr = matchFormat(text, CLASSES_PATTERN, CLASSES_ORDER)
                    or text:match(FALLBACK_CLASSES_PATTERN)
                if classesStr then
                    result.classes = {}
                    for cls in classesStr:gmatch("[^,]+") do
                        local trimmed = cls:gsub("^%s+", ""):gsub("%s+$", "")
                        if trimmed ~= "" then
                            result.classes[#result.classes + 1] = trimmed
                        end
                    end
                end

                local zone, zoneIsBG = extractRestrictedZone(text)
                if zoneIsBG then
                    result.bgOnly = true
                elseif zone then
                    result.restrictedZone = zone
                elseif isBattlegroundText(lowerText) and (lowerText:find("only", 1, true) or lowerText:find("usable in", 1, true)) then
                    result.bgOnly = true
                end

                if isExcludedLine(lowerText) then
                    result.excluded = true
                end

                if isOnUseLine(text) then
                    useLines[#useLines + 1] = lowerText
                end
            end
        end
    end

    if result.excluded then
        return result
    end

    for _, lowerUse in ipairs(useLines) do
        -- Combined dual restore ("1,200 to 1,800 health and mana" / "mana and health")
        local loStr, hiStr = lowerUse:match("([%d,]+)%s+to%s+([%d,]+)%s+health%s+and%s+mana")
        if not loStr then
            loStr, hiStr = lowerUse:match("([%d,]+)%s+to%s+([%d,]+)%s+mana%s+and%s+health")
        end
        if loStr and hiStr then
            local lo, hi = parseNumber(loStr), parseNumber(hiStr)
            if lo and hi then
                local avg = (lo + hi) / 2
                result.heal = result.heal or avg
                result.mana = result.mana or avg
            end
        end

        if not result.heal and not result.mana then
            local flatBoth = lowerUse:match("([%d,]+)%s+health%s+and%s+mana")
                or lowerUse:match("([%d,]+)%s+mana%s+and%s+health")
            local bothVal = flatBoth and parseNumber(flatBoth)
            if bothVal then
                result.heal = bothVal
                result.mana = bothVal
            end
        end

        if not result.heal and not result.mana and not result.healPct and not result.manaPct then
            local pctBoth = lowerUse:match("([%d%.]+)%%%s+of%s+[%a%s]-health%s+and%s+mana")
                or lowerUse:match("([%d%.]+)%%%s+of%s+[%a%s]-mana%s+and%s+health")
                or lowerUse:match("([%d%.]+)%%%s+health%s+and%s+mana")
                or lowerUse:match("([%d%.]+)%%%s+mana%s+and%s+health")
            local pctVal = pctBoth and tonumber(pctBoth)
            if pctVal and pctVal > 0 then
                result.healPct = pctVal
                result.manaPct = pctVal
            end
        end

        if not result.heal and not result.healPct then
            local hVal, hPct = parseResourceValue(lowerUse, "health")
            result.heal = hVal
            result.healPct = hPct
        end

        if not result.mana and not result.manaPct then
            local mVal, mPct = parseResourceValue(lowerUse, "mana")
            result.mana = mVal
            result.manaPct = mPct
        end
    end

    if not result.heal and result.healPct and type(maxHealth) == "number" and maxHealth > 0 then
        result.heal = maxHealth * (result.healPct / 100)
    end
    if not result.mana and result.manaPct and type(maxMana) == "number" and maxMana > 0 then
        result.mana = maxMana * (result.manaPct / 100)
    end

    return result
end

local tooltipCache = {}
local scannerTooltip = nil
local SCANNER_NAME = "BestPotionScanTooltip"

function ns.ClearTooltipCache()
    for k in pairs(tooltipCache) do
        tooltipCache[k] = nil
    end
end

local function readTooltipLines(itemID)
    if C_TooltipInfo and type(C_TooltipInfo.GetItemByID) == "function" then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        data = ok and ns.Plain(data) or nil
        if type(data) == "table" and type(data.lines) == "table" and #data.lines > 0 then
            local lines = {}
            for i = 1, #data.lines do
                local line = data.lines[i]
                local text = type(line) == "table" and ns.Plain(line.leftText) or nil
                if type(text) == "string" and text ~= "" then
                    lines[#lines + 1] = text
                end
            end
            if #lines > 0 then
                return lines
            end
        end
    end

    if type(_G.CreateFrame) == "function" and _G.WorldFrame then
        if not scannerTooltip then
            local ok, tip = pcall(_G.CreateFrame, "GameTooltip", SCANNER_NAME, nil, "GameTooltipTemplate")
            if ok and tip then
                scannerTooltip = tip
                pcall(scannerTooltip.SetOwner, scannerTooltip, _G.WorldFrame, "ANCHOR_NONE")
            end
        end
        if scannerTooltip and scannerTooltip.SetHyperlink then
            scannerTooltip:ClearLines()
            local ok = pcall(scannerTooltip.SetHyperlink, scannerTooltip, "item:" .. itemID)
            if ok then
                local numLines = tonumber(ns.Plain(scannerTooltip:NumLines())) or 0
                if numLines > 0 then
                    local lines = {}
                    for i = 1, numLines do
                        local left = _G[SCANNER_NAME .. "TextLeft" .. i]
                        local text = left and left.GetText and ns.Plain(left:GetText())
                        if type(text) == "string" and text ~= "" then
                            lines[#lines + 1] = text
                        end
                    end
                    if #lines > 0 then
                        return lines
                    end
                end
            end
        end
    end

    return nil
end

local function getParsedTooltip(itemID, isLoaded)
    local cached = tooltipCache[itemID]
    if cached then
        return cached
    end
    local lines = readTooltipLines(itemID)
    if not lines or #lines == 0 then
        return nil
    end
    local parsed = ns.ParsePotionTooltipLines(lines)
    if isLoaded and parsed.hasLines then
        tooltipCache[itemID] = parsed
    end
    return parsed
end

local function excludesPlayer(classes)
    if not classes or #classes == 0 then
        return false
    end
    if type(_G.UnitClass) ~= "function" then
        return false
    end
    local playerClass, classFile = _G.UnitClass("player")
    playerClass = ns.Plain(playerClass)
    classFile = ns.Plain(classFile)
    if not playerClass and not classFile then
        return false
    end
    local male = classFile and _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[classFile]
    local female = classFile and _G.LOCALIZED_CLASS_NAMES_FEMALE and _G.LOCALIZED_CLASS_NAMES_FEMALE[classFile]
    for _, name in ipairs(classes) do
        if name == playerClass or name == male or name == female or (classFile and name:upper() == classFile) then
            return false
        end
    end
    return true
end

local function isInBattleground(context)
    if context and context.inBG ~= nil then
        return context.inBG == true
    end
    if type(_G.IsInInstance) == "function" then
        local inInstance, instanceType = _G.IsInInstance()
        if ns.Plain(inInstance) and ns.Plain(instanceType) == "pvp" then
            return true
        end
    end
    if _G.C_PvP and type(_G.C_PvP.IsBattleground) == "function" then
        local ok, isBG = pcall(_G.C_PvP.IsBattleground)
        if ok and ns.Plain(isBG) == true then
            return true
        end
    end
    return false
end

local function normalizeZone(z)
    if type(z) ~= "string" then
        return ""
    end
    z = z:lower():gsub("^%s+", ""):gsub("%s+$", "")
    z = z:gsub("^the%s+", "")
    return z
end

local function isInRestrictedZone(restrictedZone, context)
    local target = normalizeZone(restrictedZone)
    if target == "" then
        return true
    end
    local candidates = {}
    if context and type(context.zone) == "string" then
        candidates[#candidates + 1] = context.zone
    end
    if type(_G.GetZoneText) == "function" then
        candidates[#candidates + 1] = ns.Plain(_G.GetZoneText())
    end
    if type(_G.GetRealZoneText) == "function" then
        candidates[#candidates + 1] = ns.Plain(_G.GetRealZoneText())
    end
    if type(_G.GetSubZoneText) == "function" then
        candidates[#candidates + 1] = ns.Plain(_G.GetSubZoneText())
    end
    if type(_G.GetInstanceInfo) == "function" then
        candidates[#candidates + 1] = ns.Plain((_G.GetInstanceInfo()))
    end
    for _, current in ipairs(candidates) do
        local norm = normalizeZone(current)
        if norm ~= "" and (norm == target or target:find(norm, 1, true) or norm:find(target, 1, true)) then
            return true
        end
    end
    return false
end

local function getPlayerMaxHealth(context)
    if context and type(context.maxHealth) == "number" then
        return context.maxHealth
    end
    if type(_G.UnitHealthMax) == "function" then
        local hp = tonumber(ns.Plain(_G.UnitHealthMax("player")))
        if hp and hp > 0 then
            return hp
        end
    end
    return nil
end

local function getPlayerMaxMana(context)
    if context and type(context.maxMana) == "number" then
        return context.maxMana
    end
    if type(_G.UnitPowerMax) == "function" then
        local mp = tonumber(ns.Plain(_G.UnitPowerMax("player", MANA_POWER_TYPE)))
        if mp and mp > 0 then
            return mp
        end
    end
    return nil
end

function ns.CompareCandidates(a, b)
    if a.score ~= b.score then
        return a.score > b.score
    end
    if a.isPure ~= b.isPure then
        return a.isPure
    end
    if a.reqLevel ~= b.reqLevel then
        return a.reqLevel > b.reqLevel
    end
    return a.itemID > b.itemID
end

function ns.ClassifyPotion(itemID, playerLevel, count, iconFromBag, linkFromBag, context)
    if not itemID or ns.EXCLUDED_POTIONS[itemID] then
        return nil, false
    end

    local known = ns.KNOWN_POTIONS[itemID]
    local _, _, _, _, iconInstant, instantClassID, instantSubClassID = ns.GetItemInfoInstant(itemID)
    iconInstant = ns.Plain(iconInstant)
    instantClassID = tonumber(ns.Plain(instantClassID))
    instantSubClassID = tonumber(ns.Plain(instantSubClassID))

    if not known then
        if instantClassID ~= nil and instantClassID ~= CONSUMABLE_CLASS_ID then
            return nil, false
        end
        if instantSubClassID ~= nil and instantSubClassID ~= POTION_SUBCLASS_ID and instantSubClassID ~= GENERIC_SUBCLASS_ID then
            return nil, false
        end
    end

    local itemName, itemLink, _, _, apiMinLevel, _, _, _, _, itemTexture, _, itemClassID, itemSubClassID = ns.GetItemInfo(itemID)
    itemName = ns.Plain(itemName)
    itemLink = ns.Plain(itemLink)
    apiMinLevel = tonumber(ns.Plain(apiMinLevel))
    itemTexture = ns.Plain(itemTexture)
    itemClassID = tonumber(ns.Plain(itemClassID))
    itemSubClassID = tonumber(ns.Plain(itemSubClassID))

    local loaded = type(itemName) == "string" and itemName ~= ""
    local classID = itemClassID or instantClassID
    local subClassID = itemSubClassID or instantSubClassID

    if not loaded then
        ns.RequestLoadItemDataByID(itemID)
        if not known then
            return nil, true
        end

        local reqLevel = known.reqLevel or 0
        local skipReason = nil
        if reqLevel > playerLevel then
            skipReason = "Requires Level " .. reqLevel
        elseif known.bgOnly and not isInBattleground(context) then
            skipReason = "Battlegrounds only"
        end

        return {
            itemID = itemID,
            name = known.name or ("Item #" .. itemID),
            link = linkFromBag,
            icon = iconFromBag or iconInstant,
            count = count or 0,
            reqLevel = reqLevel,
            heal = known.heal or 0,
            mana = known.mana or 0,
            usable = (skipReason == nil),
            skipReason = skipReason,
        }, true
    end

    if not known then
        if classID ~= CONSUMABLE_CLASS_ID then
            return nil, false
        end
        if subClassID ~= POTION_SUBCLASS_ID then
            if subClassID ~= GENERIC_SUBCLASS_ID then
                return nil, false
            end
            local lowerName = itemName:lower()
            if not lowerName:find("potion", 1, true) and not lowerName:find("draught", 1, true) then
                return nil, false
            end
        end
    end

    local parsed = getParsedTooltip(itemID, true)
    if parsed and parsed.excluded then
        return nil, false
    end

    if not parsed and not known then
        return nil, true
    end

    local maxHealth = getPlayerMaxHealth(context)
    local maxMana = getPlayerMaxMana(context)

    local heal = nil
    local mana = nil
    if parsed then
        heal = parsed.heal or (parsed.healPct and maxHealth and (maxHealth * parsed.healPct / 100) or nil)
        mana = parsed.mana or (parsed.manaPct and maxMana and (maxMana * parsed.manaPct / 100) or nil)
    end
    if not heal and known then
        heal = known.heal
    end
    if not mana and known then
        mana = known.mana
    end

    if (not heal or heal <= 0) and (not mana or mana <= 0) then
        return nil, false
    end

    local reqLevel = math.max(apiMinLevel or 0, (parsed and parsed.reqLevel) or 0)
    if reqLevel == 0 and (not parsed or not parsed.hasLines) and known and known.reqLevel then
        reqLevel = known.reqLevel
    end

    local skipReason = nil
    if reqLevel > playerLevel then
        skipReason = "Requires Level " .. reqLevel
    elseif parsed and excludesPlayer(parsed.classes) then
        skipReason = "Wrong class"
    elseif (parsed and parsed.bgOnly) or (known and known.bgOnly) then
        if not isInBattleground(context) then
            skipReason = "Battlegrounds only"
        end
    elseif parsed and parsed.restrictedZone and not isInRestrictedZone(parsed.restrictedZone, context) then
        skipReason = "Only usable in " .. parsed.restrictedZone
    end

    return {
        itemID = itemID,
        name = itemName,
        link = linkFromBag or itemLink,
        icon = iconFromBag or itemTexture or iconInstant,
        count = count or 0,
        reqLevel = reqLevel,
        heal = heal or 0,
        mana = mana or 0,
        usable = (skipReason == nil),
        skipReason = skipReason,
    }, false
end

local function makeCandidate(entry, kind)
    local isHeal = (kind == "heal")
    return {
        itemID = entry.itemID,
        name = entry.name,
        link = entry.link,
        icon = entry.icon,
        count = entry.count,
        reqLevel = entry.reqLevel,
        heal = entry.heal,
        mana = entry.mana,
        score = isHeal and entry.heal or entry.mana,
        isPure = isHeal and (entry.mana == 0) or (entry.heal == 0),
        usable = entry.usable,
        skipReason = entry.skipReason,
    }
end

function ns.ScanBestPotions(overrideLevel, context)
    local unitLevel = (type(_G.UnitLevel) == "function") and tonumber(ns.Plain(_G.UnitLevel("player"))) or 1
    if unitLevel and ns.recentLevelUp and unitLevel >= ns.recentLevelUp then
        ns.recentLevelUp = nil
    end
    local playerLevel = math.max(unitLevel or 1, tonumber(overrideLevel) or 1, tonumber(ns.recentLevelUp) or 1)

    local byItemID = {}
    local itemOrder = {}
    local lastBag = _G.NUM_BAG_SLOTS or 4

    for bag = 0, lastBag do
        local numSlots = ns.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = ns.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local existing = byItemID[info.itemID]
                if existing then
                    existing.count = existing.count + (info.stackCount or 1)
                    existing.link = existing.link or info.hyperlink
                    existing.icon = existing.icon or info.iconFileID
                else
                    byItemID[info.itemID] = {
                        itemID = info.itemID,
                        count = info.stackCount or 1,
                        link = info.hyperlink,
                        icon = info.iconFileID,
                    }
                    itemOrder[#itemOrder + 1] = info.itemID
                end
            end
        end
    end

    local healCandidates = {}
    local manaCandidates = {}
    local skippedHeal = {}
    local skippedMana = {}
    local hasUncached = false

    for _, itemID in ipairs(itemOrder) do
        local bagItem = byItemID[itemID]
        local entry, uncached = ns.ClassifyPotion(itemID, playerLevel, bagItem.count, bagItem.icon, bagItem.link, context)
        if uncached then
            hasUncached = true
        end
        if entry then
            if entry.heal > 0 then
                local cand = makeCandidate(entry, "heal")
                if entry.usable then
                    healCandidates[#healCandidates + 1] = cand
                else
                    skippedHeal[#skippedHeal + 1] = cand
                end
            end
            if entry.mana > 0 then
                local cand = makeCandidate(entry, "mana")
                if entry.usable then
                    manaCandidates[#manaCandidates + 1] = cand
                else
                    skippedMana[#skippedMana + 1] = cand
                end
            end
        end
    end

    table.sort(healCandidates, ns.CompareCandidates)
    table.sort(manaCandidates, ns.CompareCandidates)
    table.sort(skippedHeal, ns.CompareCandidates)
    table.sort(skippedMana, ns.CompareCandidates)

    ns.state.playerLevel = playerLevel
    ns.state.hasUncached = hasUncached
    ns.state.healCandidates = healCandidates
    ns.state.manaCandidates = manaCandidates
    ns.state.heal = healCandidates[1] or nil
    ns.state.mana = manaCandidates[1] or nil
    ns.state.skipped.heal = skippedHeal
    ns.state.skipped.mana = skippedMana

    return ns.state
end
