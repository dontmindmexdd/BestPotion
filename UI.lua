local _, ns = ...

local frame = nil
local buttons = {}

local function formatCandidateLine(cand, kind)
    local statLabel = (kind == "heal") and "HP" or "Mana"
    local amount = math.floor((cand.score or 0) + 0.5)
    return string.format("%s (%d %s, x%d)", cand.name, amount, statLabel, cand.count or 0)
end

local function updateButton(kind)
    local btn = buttons[kind]
    if not btn then
        return
    end
    local cand = ns.state and ns.state[kind]
    if cand then
        btn.icon:SetTexture(cand.icon or ns.GetFallbackIcon(kind))
        btn.icon:SetDesaturated(false)
        btn.icon:SetVertexColor(1, 1, 1)
        btn.count:SetText((cand.count and cand.count > 0) and tostring(cand.count) or "")
        btn.itemLabel:SetText(cand.name)
        btn.itemLabel:SetTextColor(1, 1, 1)
    else
        btn.icon:SetTexture(ns.GetFallbackIcon(kind))
        btn.icon:SetDesaturated(true)
        btn.icon:SetVertexColor(0.55, 0.55, 0.55)
        btn.count:SetText("")
        btn.itemLabel:SetText("None")
        btn.itemLabel:SetTextColor(0.55, 0.55, 0.55)
    end
end

function ns.RefreshUI()
    if not frame then
        return
    end
    updateButton("heal")
    updateButton("mana")
end

local function showButtonTooltip(self)
    if not _G.GameTooltip then
        return
    end
    local kind = self.kind
    local title = (kind == "heal") and "Best Heal Potion Shortcut" or "Best Mana Potion Shortcut"
    local statLabel = (kind == "heal") and "HP" or "Mana"
    local active = ns.state and ns.state[kind]
    local backups = ns.state and (kind == "heal" and ns.state.healCandidates or ns.state.manaCandidates) or {}
    local skipped = ns.state and ns.state.skipped and ns.state.skipped[kind] or {}

    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(title, 1, 1, 1)

    if active then
        _G.GameTooltip:AddLine("Active: " .. active.name, 0.25, 0.90, 0.45)
        _G.GameTooltip:AddLine(string.format("Restores ~%d %s (x%d in bags)", math.floor(active.score + 0.5), statLabel, active.count or 0), 0.85, 0.85, 0.85)
    else
        _G.GameTooltip:AddLine("No usable potion in bags", 0.70, 0.70, 0.70)
    end

    if #backups > 1 then
        _G.GameTooltip:AddLine(" ")
        _G.GameTooltip:AddLine("Backups in bags:", 1, 0.82, 0)
        local limit = math.min(#backups, 4)
        for i = 2, limit do
            _G.GameTooltip:AddLine("  " .. formatCandidateLine(backups[i], kind), 0.80, 0.80, 0.80)
        end
    end

    if #skipped > 0 then
        _G.GameTooltip:AddLine(" ")
        _G.GameTooltip:AddLine("Skipped (unusable):", 1, 0.45, 0.45)
        local limit = math.min(#skipped, 4)
        for i = 1, limit do
            local s = skipped[i]
            _G.GameTooltip:AddLine(string.format("  %s - %s", s.name, s.skipReason or "Unusable"), 0.95, 0.55, 0.55)
        end
    end

    _G.GameTooltip:AddLine(" ")
    _G.GameTooltip:AddLine("Click or drag onto an action bar", 0.22, 0.74, 0.97)
    _G.GameTooltip:Show()
end

local function createButton(parent, kind, titleText, xOffset)
    local btn = CreateFrame("Button", "BestPotionBtn_" .. kind, parent)
    btn:SetSize(44, 44)
    btn:SetPoint("TOP", parent, "TOP", xOffset, -54)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn.kind = kind

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetSize(76, 76)
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.border = border

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints(icon)

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    count:SetJustifyH("RIGHT")
    btn.count = count

    local titleLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleLabel:SetPoint("TOP", btn, "BOTTOM", 0, -6)
    titleLabel:SetText(titleText)
    btn.titleLabel = titleLabel

    local itemLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemLabel:SetWidth(96)
    itemLabel:SetWordWrap(false)
    itemLabel:SetJustifyH("CENTER")
    itemLabel:SetPoint("TOP", titleLabel, "BOTTOM", 0, -2)
    btn.itemLabel = itemLabel

    btn:SetScript("OnClick", function(self)
        ns.PickupPotionMacro(self.kind)
    end)
    btn:SetScript("OnDragStart", function(self)
        ns.PickupPotionMacro(self.kind)
    end)
    btn:SetScript("OnEnter", showButtonTooltip)
    btn:SetScript("OnLeave", function()
        if _G.GameTooltip then
            _G.GameTooltip:Hide()
        end
    end)

    buttons[kind] = btn
    return btn
end

local function createMainFrame()
    if frame then
        return frame
    end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "BestPotionFrame", _G.UIParent, template)
    frame:SetSize(224, 152)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end

    local db = ns.GetDB()
    frame:ClearAllPoints()
    if db.point and db.relPoint and db.x ~= nil and db.y ~= nil then
        frame:SetPoint(db.point, _G.UIParent, db.relPoint, db.x, db.y)
    else
        frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    end

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point and relPoint then
            local saved = ns.GetDB()
            saved.point = point
            saved.relPoint = relPoint
            saved.x = math.floor(x + 0.5)
            saved.y = math.floor(y + 0.5)
        end
    end)
    frame:SetScript("OnShow", function()
        ns.RefreshNow(nil, true)
    end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("BestPotion")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetTextColor(0.75, 0.75, 0.75)
    subtitle:SetText("Drag or click to add to action bar")

    createButton(frame, "heal", "Heal", -50)
    createButton(frame, "mana", "Mana", 50)

    if type(_G.UISpecialFrames) == "table" then
        local listed = false
        for _, name in ipairs(_G.UISpecialFrames) do
            if name == "BestPotionFrame" then
                listed = true
                break
            end
        end
        if not listed then
            table.insert(_G.UISpecialFrames, "BestPotionFrame")
        end
    end

    ns.frame = frame
    return frame
end

function ns.ShowUI()
    local f = createMainFrame()
    ns.RefreshNow(nil, true)
    f:Show()
end

function ns.HideUI()
    if frame then
        frame:Hide()
    end
end

function ns.ToggleUI()
    local f = createMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        ns.RefreshNow(nil, true)
        f:Show()
    end
end

function ns.ResetUIPosition()
    local db = ns.GetDB()
    db.point = nil
    db.relPoint = nil
    db.x = nil
    db.y = nil
    db.minimap.hide = false
    db.minimap.minimapPos = 235
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    end
    if ns.UpdateMinimapButton then
        ns.UpdateMinimapButton()
    end
    ns.Print("Window and minimap button positions reset.")
end

function ns.PrintStatus()
    local state = ns.state
    local healText = state.heal and formatCandidateLine(state.heal, "heal") or "None"
    local manaText = state.mana and formatCandidateLine(state.mana, "mana") or "None"
    ns.Print(string.format("Level %d | Heal: %s | Mana: %s", state.playerLevel or 1, healText, manaText))

    if state.healCandidates and #state.healCandidates > 1 then
        local names = {}
        for i = 2, #state.healCandidates do
            names[#names + 1] = state.healCandidates[i].name
        end
        ns.Print("  Heal backups: " .. table.concat(names, ", "))
    end
    if state.manaCandidates and #state.manaCandidates > 1 then
        local names = {}
        for i = 2, #state.manaCandidates do
            names[#names + 1] = state.manaCandidates[i].name
        end
        ns.Print("  Mana backups: " .. table.concat(names, ", "))
    end
    for _, kind in ipairs({ "heal", "mana" }) do
        local list = state.skipped and state.skipped[kind]
        if list and #list > 0 then
            local parts = {}
            for _, item in ipairs(list) do
                parts[#parts + 1] = item.name .. " (" .. (item.skipReason or "unusable") .. ")"
            end
            ns.Print("  Skipped " .. kind .. ": " .. table.concat(parts, ", "))
        end
    end
end

function BestPotion_OnAddonCompartmentClick()
    ns.ToggleUI()
end

local function handleSlash(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()
    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.ToggleUI()
    elseif cmd == "hide" then
        ns.HideUI()
    elseif cmd == "heal" then
        if ns.PickupPotionMacro("heal") then
            ns.Print("Picked up Heal potion shortcut — click an action bar slot to place it.")
        end
    elseif cmd == "mana" then
        if ns.PickupPotionMacro("mana") then
            ns.Print("Picked up Mana potion shortcut — click an action bar slot to place it.")
        end
    elseif cmd == "status" then
        ns.PrintStatus()
    elseif cmd == "refresh" then
        ns.RefreshNow(nil, true)
        ns.PrintStatus()
    elseif cmd == "reset" then
        ns.ResetUIPosition()
    elseif cmd == "minimap" then
        if ns.ToggleMinimapButton then
            ns.ToggleMinimapButton()
        end
    else
        ns.Print("Commands: /bp [show | hide | heal | mana | status | refresh | reset | minimap]")
    end
end

SLASH_BESTPOTION1 = "/bestpot"
SLASH_BESTPOTION2 = "/bp"
SlashCmdList["BESTPOTION"] = handleSlash
