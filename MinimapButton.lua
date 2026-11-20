local _, ns = ...

local BUTTON_NAME = "BestPotion"
local TITLE = "BestPotion"
local ICON_PATH = "Interface\\AddOns\\BestPotion\\Icon"

local function addTooltip(tooltip)
    if not tooltip or not tooltip.AddLine then
        return
    end
    local state = ns.state or {}
    local heal = state.heal
    local mana = state.mana
    local skippedHeal = (state.skipped and state.skipped.heal and #state.skipped.heal) or 0
    local skippedMana = (state.skipped and state.skipped.mana and #state.skipped.mana) or 0
    local totalSkipped = skippedHeal + skippedMana

    tooltip:AddLine(TITLE, 1, 1, 1)

    if heal then
        tooltip:AddLine(string.format("Heal: %s (x%d)", heal.name, heal.count or 0), 0.25, 0.90, 0.45)
    else
        tooltip:AddLine("Heal: None", 0.70, 0.70, 0.70)
    end

    if mana then
        tooltip:AddLine(string.format("Mana: %s (x%d)", mana.name, mana.count or 0), 0.35, 0.75, 1.0)
    else
        tooltip:AddLine("Mana: None", 0.70, 0.70, 0.70)
    end

    if totalSkipped > 0 then
        tooltip:AddLine(string.format("Skipped (unusable): %d", totalSkipped), 1.0, 0.55, 0.55)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Left-click: Toggle shortcut window", 1, 1, 1)
    tooltip:AddLine("Right-click: Refresh & print status", 1, 1, 1)
    tooltip:AddLine("Drag: Move button", 0.65, 0.65, 0.65)
end

local function onClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.RefreshNow(nil, true)
        ns.PrintStatus()
    else
        ns.ToggleUI()
    end
end

function ns.UpdateMinimapButton()
    local db = ns.GetDB()
    local LibStub = _G.LibStub
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    local libIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (ldb and libIcon) then
        return
    end

    local launcher = (ldb.GetDataObjectByName and ldb:GetDataObjectByName(BUTTON_NAME))
        or ldb:NewDataObject(BUTTON_NAME, {
            type = "launcher",
            text = TITLE,
            icon = ICON_PATH,
            OnClick = onClick,
            OnTooltipShow = addTooltip,
        })

    if not libIcon:IsRegistered(BUTTON_NAME) then
        libIcon:Register(BUTTON_NAME, launcher, db.minimap)
    else
        libIcon:Refresh(BUTTON_NAME, db.minimap)
    end

    if db.minimap.hide then
        libIcon:Hide(BUTTON_NAME)
    else
        libIcon:Show(BUTTON_NAME)
    end
end

function ns.ToggleMinimapButton()
    local db = ns.GetDB()
    db.minimap.hide = not db.minimap.hide
    ns.UpdateMinimapButton()
    if db.minimap.hide then
        ns.Print("Minimap button hidden.")
    else
        ns.Print("Minimap button shown.")
    end
end
