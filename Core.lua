local ADDON_NAME, ns = ...
_G.BestPotion = ns

local issecretvalue = _G.issecretvalue

function ns.Plain(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

function ns.Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8BestPotion:|r " .. tostring(msg))
    end
end

function ns.GetContainerNumSlots(bag)
    local fn = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    if type(fn) ~= "function" then
        return 0
    end
    local ok, slots = pcall(fn, bag)
    slots = ok and tonumber(ns.Plain(slots)) or 0
    return slots or 0
end

function ns.GetContainerItemInfo(bag, slot)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        info = ok and ns.Plain(info) or nil
        if type(info) ~= "table" then
            return nil
        end
        local itemID = tonumber(ns.Plain(info.itemID))
        if not itemID then
            return nil
        end
        return {
            itemID = itemID,
            stackCount = tonumber(ns.Plain(info.stackCount)) or 1,
            hyperlink = ns.Plain(info.hyperlink),
            iconFileID = ns.Plain(info.iconFileID),
        }
    end

    if type(_G.GetContainerItemInfo) == "function" then
        local ok, icon, count, _, _, _, _, link, _, _, itemID = pcall(_G.GetContainerItemInfo, bag, slot)
        if not ok then
            return nil
        end
        itemID = tonumber(ns.Plain(itemID))
        if not itemID then
            return nil
        end
        return {
            itemID = itemID,
            stackCount = tonumber(ns.Plain(count)) or 1,
            hyperlink = ns.Plain(link),
            iconFileID = ns.Plain(icon),
        }
    end

    return nil
end

function ns.GetItemInfo(item)
    local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if type(fn) ~= "function" then
        return nil
    end
    return fn(item)
end

function ns.GetItemInfoInstant(item)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if type(fn) ~= "function" then
        return nil
    end
    return fn(item)
end

function ns.RequestLoadItemDataByID(itemID)
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local DEFAULTS = {
    welcomed = false,
}

function ns.GetDB()
    if type(BestPotionDB) ~= "table" then
        BestPotionDB = {}
    end
    for k, v in pairs(DEFAULTS) do
        if BestPotionDB[k] == nil then
            BestPotionDB[k] = v
        end
    end
    if type(BestPotionDB.minimap) ~= "table" then
        BestPotionDB.minimap = {}
    end
    if BestPotionDB.minimapButton ~= nil then
        if BestPotionDB.minimap.hide == nil then
            BestPotionDB.minimap.hide = (BestPotionDB.minimapButton == false)
        end
        BestPotionDB.minimapButton = nil
    end
    if BestPotionDB.minimapAngle ~= nil then
        if BestPotionDB.minimap.minimapPos == nil then
            BestPotionDB.minimap.minimapPos = BestPotionDB.minimapAngle
        end
        BestPotionDB.minimapAngle = nil
    end
    if BestPotionDB.minimap.hide == nil then
        BestPotionDB.minimap.hide = false
    end
    if BestPotionDB.minimap.minimapPos == nil then
        BestPotionDB.minimap.minimapPos = 235
    end
    return BestPotionDB
end

ns.state = {
    heal = nil,
    mana = nil,
    healCandidates = {},
    manaCandidates = {},
    skipped = {
        heal = {},
        mana = {},
    },
    hasUncached = false,
    playerLevel = 1,
}

ns.pendingMacroSync = false
ns.pendingAllowCreate = false
ns.isEditingMacros = false
ns.recentLevelUp = nil

local refreshPending = false
local pendingOverrideLevel = nil

function ns.RefreshNow(overrideLevel, allowCreateMacros)
    local level = overrideLevel
    if pendingOverrideLevel and (not level or pendingOverrideLevel > level) then
        level = pendingOverrideLevel
    end
    pendingOverrideLevel = nil

    if ns.ScanBestPotions then
        ns.ScanBestPotions(level)
    end
    if ns.SyncMacros then
        ns.SyncMacros(allowCreateMacros == true)
    end
    if ns.RefreshUI then
        ns.RefreshUI()
    end
end

function ns.ScheduleRefresh(delay, overrideLevel)
    if overrideLevel and (not pendingOverrideLevel or overrideLevel > pendingOverrideLevel) then
        pendingOverrideLevel = overrideLevel
    end
    if refreshPending then
        return
    end
    if not (C_Timer and type(C_Timer.After) == "function") then
        ns.RefreshNow(pendingOverrideLevel, false)
        return
    end
    refreshPending = true
    C_Timer.After(delay or 0.1, function()
        refreshPending = false
        local level = pendingOverrideLevel
        pendingOverrideLevel = nil
        ns.RefreshNow(level, false)
    end)
end

local eventFrame = CreateFrame("Frame")

local function RegisterSafeEvent(event)
    if C_EventUtils and type(C_EventUtils.IsEventValid) == "function" then
        if not C_EventUtils.IsEventValid(event) then
            return false
        end
    end
    return pcall(eventFrame.RegisterEvent, eventFrame, event)
end

RegisterSafeEvent("ADDON_LOADED")
RegisterSafeEvent("PLAYER_LOGIN")
RegisterSafeEvent("PLAYER_ENTERING_WORLD")
RegisterSafeEvent("BAG_UPDATE_DELAYED")
RegisterSafeEvent("PLAYER_LEVEL_UP")
RegisterSafeEvent("PLAYER_REGEN_ENABLED")
RegisterSafeEvent("ZONE_CHANGED_NEW_AREA")
RegisterSafeEvent("GET_ITEM_INFO_RECEIVED")
RegisterSafeEvent("ITEM_DATA_LOAD_RESULT")
RegisterSafeEvent("TOOLTIP_DATA_UPDATE")
RegisterSafeEvent("UPDATE_MACROS")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            ns.GetDB()
        end
    elseif event == "PLAYER_LOGIN" then
        local db = ns.GetDB()
        ns.RefreshNow(nil, true)
        if ns.UpdateMinimapButton then
            pcall(ns.UpdateMinimapButton)
        end
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(1.0, function()
                ns.RefreshNow(nil, true)
            end)
        end
        if not db.welcomed then
            ns.Print("Type /bp to drag Heal & Mana potion shortcuts onto your action bars.")
            db.welcomed = true
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.ScheduleRefresh(0.2)
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.ScheduleRefresh(0.1)
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = tonumber(ns.Plain(arg1))
        if newLevel and (not ns.recentLevelUp or newLevel > ns.recentLevelUp) then
            ns.recentLevelUp = newLevel
        end
        ns.RefreshNow(newLevel, false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.pendingMacroSync then
            local allowCreate = ns.pendingAllowCreate
            ns.pendingMacroSync = false
            ns.pendingAllowCreate = false
            if ns.SyncMacros then
                ns.SyncMacros(allowCreate)
            end
            if ns.RefreshUI then
                ns.RefreshUI()
            end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ns.ScheduleRefresh(0.2)
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if ns.state.hasUncached then
            ns.ScheduleRefresh(0.15)
        end
    elseif event == "TOOLTIP_DATA_UPDATE" then
        if ns.ClearTooltipCache then
            ns.ClearTooltipCache()
        end
        ns.ScheduleRefresh(0.15)
    elseif event == "UPDATE_MACROS" then
        if not ns.isEditingMacros and ns.RefreshUI then
            ns.RefreshUI()
        end
    end
end)
