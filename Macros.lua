local _, ns = ...

local QUESTION_MARK_ICON = 134400

ns.MACRO_SPECS = {
    heal = {
        name = "BestHealPot",
        marker = "# BestPotion:Heal",
        fallbackItemID = 13446,
        fallbackIcon = "INV_Potion_54",
        emptyComment = "# No usable heal potion in bags",
    },
    mana = {
        name = "BestManaPot",
        marker = "# BestPotion:Mana",
        fallbackItemID = 13444,
        fallbackIcon = "INV_Potion_76",
        emptyComment = "# No usable mana potion in bags",
    },
}

local warnedCollision = {}
local warnedFull = false

local function canonicalBody(body)
    if type(body) ~= "string" then
        return nil
    end
    return (body:gsub("[\r\n]+$", ""))
end

local function iconsMatch(curIcon, desiredIcon)
    if curIcon == desiredIcon then
        return true
    end
    if tostring(curIcon) == tostring(desiredIcon) then
        return true
    end
    if desiredIcon == QUESTION_MARK_ICON and type(curIcon) == "string" and curIcon:lower():find("inv_misc_questionmark", 1, true) then
        return true
    end
    return false
end

function ns.GetFallbackIcon(kind)
    local spec = ns.MACRO_SPECS[kind]
    if not spec then
        return QUESTION_MARK_ICON
    end
    if spec.fallbackItemID then
        local _, _, _, _, iconFileID = ns.GetItemInfoInstant(spec.fallbackItemID)
        iconFileID = ns.Plain(iconFileID)
        if iconFileID then
            return iconFileID
        end
    end
    return spec.fallbackIcon or QUESTION_MARK_ICON
end

function ns.BuildMacroContent(kind, itemID)
    local spec = ns.MACRO_SPECS[kind]
    if not spec then
        return "", QUESTION_MARK_ICON
    end
    if itemID then
        local body = "#showtooltip\n" .. spec.marker .. "\n/use item:" .. tostring(itemID)
        return body, QUESTION_MARK_ICON
    end
    local body = spec.marker .. "\n" .. spec.emptyComment
    return body, ns.GetFallbackIcon(kind)
end

function ns.IsManagedMacroBody(kind, body)
    local spec = ns.MACRO_SPECS[kind]
    if not spec or type(body) ~= "string" then
        return false
    end
    if canonicalBody(body) == "" then
        return true
    end
    return body:find(spec.marker, 1, true) ~= nil
end

local function inCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown() == true) or false
end

function ns.SyncMacro(kind, allowCreate)
    local spec = ns.MACRO_SPECS[kind]
    if not spec then
        return nil, "invalid"
    end

    if inCombat() then
        ns.pendingMacroSync = true
        ns.pendingAllowCreate = ns.pendingAllowCreate or (allowCreate == true)
        return nil, "combat"
    end

    if type(_G.GetMacroIndexByName) ~= "function" or type(_G.GetMacroInfo) ~= "function" then
        return nil, "api_missing"
    end

    local okLookup, macroID = pcall(_G.GetMacroIndexByName, spec.name)
    macroID = okLookup and tonumber(ns.Plain(macroID)) or 0

    local curIcon, curBody
    if macroID and macroID > 0 then
        local okInfo, foundName, icon, body = pcall(_G.GetMacroInfo, macroID)
        foundName = okInfo and ns.Plain(foundName) or nil
        if foundName ~= spec.name then
            return nil, "lookup_mismatch"
        end
        curIcon = ns.Plain(icon)
        curBody = ns.Plain(body) or ""
        if not ns.IsManagedMacroBody(kind, curBody) then
            if not warnedCollision[kind] then
                warnedCollision[kind] = true
                ns.Print("Macro '" .. spec.name .. "' already exists and is not managed by BestPotion; leaving it untouched.")
            end
            return nil, "collision"
        end
    else
        macroID = 0
    end

    local candidate = ns.state and ns.state[kind]
    local desiredBody, desiredIcon = ns.BuildMacroContent(kind, candidate and candidate.itemID)

    if macroID == 0 then
        if not allowCreate then
            return nil, "missing"
        end
        if type(_G.CreateMacro) ~= "function" then
            return nil, "api_missing"
        end

        local numGlobal, numChar = 0, 0
        if type(_G.GetNumMacros) == "function" then
            local okNum, g, c = pcall(_G.GetNumMacros)
            if okNum then
                numGlobal = tonumber(ns.Plain(g)) or 0
                numChar = tonumber(ns.Plain(c)) or 0
            end
        end

        local maxGlobal = _G.MAX_ACCOUNT_MACROS or 120
        local maxChar = _G.MAX_CHARACTER_MACROS or 30
        local perChar
        if numChar < maxChar then
            perChar = true
        elseif numGlobal < maxGlobal then
            perChar = false
        else
            if not warnedFull then
                warnedFull = true
                ns.Print("Cannot create macro '" .. spec.name .. "': both character and general macro slots are full.")
            end
            return nil, "full"
        end

        ns.isEditingMacros = true
        local okCreate, created = pcall(_G.CreateMacro, spec.name, desiredIcon, desiredBody, perChar)
        ns.isEditingMacros = false

        local newID = okCreate and tonumber(ns.Plain(created)) or nil
        if not newID or newID <= 0 then
            local okFind, found = pcall(_G.GetMacroIndexByName, spec.name)
            newID = okFind and tonumber(ns.Plain(found)) or nil
        end
        if not newID or newID <= 0 then
            return nil, "create_failed"
        end
        return newID, "created"
    end

    if canonicalBody(curBody) == canonicalBody(desiredBody) and iconsMatch(curIcon, desiredIcon) then
        return macroID, "unchanged"
    end

    if type(_G.EditMacro) ~= "function" then
        return macroID, "edit_unavailable"
    end

    ns.isEditingMacros = true
    local okEdit, edited = pcall(_G.EditMacro, macroID, spec.name, desiredIcon, desiredBody)
    ns.isEditingMacros = false

    if not okEdit or edited == false then
        return macroID, "edit_failed"
    end
    return macroID, "updated"
end

function ns.SyncMacros(allowCreate)
    local healID, healStatus = ns.SyncMacro("heal", allowCreate)
    local manaID, manaStatus = ns.SyncMacro("mana", allowCreate)
    return {
        heal = { id = healID, status = healStatus },
        mana = { id = manaID, status = manaStatus },
    }
end

function ns.PickupPotionMacro(kind)
    if inCombat() then
        ns.Print("Cannot pick up shortcut while in combat.")
        return false
    end

    ns.RefreshNow(nil, true)
    local macroID, status = ns.SyncMacro(kind, true)
    if not macroID or macroID <= 0 then
        if status == "full" then
            ns.Print("Free a macro slot (/macro) so BestPotion can create its shortcut.")
        elseif status == "collision" then
            ns.Print("Rename or delete your existing '" .. (ns.MACRO_SPECS[kind] and ns.MACRO_SPECS[kind].name or "") .. "' macro first.")
        end
        return false
    end

    if type(_G.PickupMacro) ~= "function" then
        return false
    end
    local ok = pcall(_G.PickupMacro, macroID)
    return ok == true
end
