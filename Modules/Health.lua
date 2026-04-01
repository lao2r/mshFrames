local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")

local isUpdating = false
local predictionPreviewState = setmetatable({}, { __mode = "k" })
local defaultHealAbsorbColor = { r = 0.45, g = 0.12, b = 0.12, a = 0.9 }
local defaultShieldColor = { r = 0.18, g = 0.62, b = 0.85, a = 0.9 }

local function GetPredictionColor(cfg, field, fallback)
    local color = cfg and cfg[field]
    if type(color) ~= "table" then
        return fallback.r, fallback.g, fallback.b, fallback.a
    end

    return color.r or fallback.r, color.g or fallback.g, color.b or fallback.b, color.a or fallback.a
end

local function StylePredictionTexture(texture, texturePath, r, g, b, a)
    if not texture then return end

    texture:SetTexture(texturePath)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(r, g, b, a)
end

local function SetElementSuppressed(element, suppressed)
    if not element then
        return
    end

    if element.mshOriginalAlpha == nil and element.GetAlpha then
        element.mshOriginalAlpha = element:GetAlpha()
    end

    if element.SetAlpha then
        element:SetAlpha(suppressed and 0 or (element.mshOriginalAlpha or 1))
    end
end

local function SetPredictionDecorationsSuppressed(frame, suppressed)
    SetElementSuppressed(frame.totalAbsorbOverlay, suppressed)
    SetElementSuppressed(frame.overAbsorbGlow, suppressed)
    SetElementSuppressed(frame.overHealAbsorbGlow, suppressed)
    SetElementSuppressed(frame.myHealAbsorbOverlay, suppressed)
    SetElementSuppressed(frame.myHealAbsorbLeftShadow, suppressed)
    SetElementSuppressed(frame.myHealAbsorbRightShadow, suppressed)
end

local function EnsureTextLayer(frame)
    if not frame or frame.mshTextLayer then
        return
    end

    frame.mshTextLayer = CreateFrame("Frame", nil, frame)
    frame.mshTextLayer:SetFrameStrata(frame:GetFrameStrata())
    frame.mshTextLayer:SetFrameLevel((frame.healthBar and frame.healthBar:GetFrameLevel() or frame:GetFrameLevel()) + 10)
    frame.mshTextLayer:SetAllPoints(frame)
end

local function ReparentPredictionElement(element, parent)
    if element and parent and element.SetParent then
        element:SetParent(parent)
    end
end

local function EnsurePredictionOverlays(frame)
    if not frame or not frame.healthBar or frame.mshPredictionCreated then
        return
    end

    frame.mshPredictionClip = CreateFrame("Frame", nil, frame)
    frame.mshPredictionClip:SetFrameStrata(frame:GetFrameStrata())
    frame.mshPredictionClip:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
    frame.mshPredictionClip:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT")
    frame.mshPredictionClip:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT")
    if frame.mshPredictionClip.SetClipsChildren then
        frame.mshPredictionClip:SetClipsChildren(true)
    end

    ReparentPredictionElement(frame.myHealPrediction, frame.mshPredictionClip)
    ReparentPredictionElement(frame.otherHealPrediction, frame.mshPredictionClip)

    frame.mshShieldBar = CreateFrame("StatusBar", nil, frame.mshPredictionClip)
    frame.mshShieldBar:SetFrameStrata(frame:GetFrameStrata())
    frame.mshShieldBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
    frame.mshShieldBar:SetAllPoints(frame.mshPredictionClip)
    frame.mshShieldBar:Hide()

    frame.mshHealAbsorbBar = CreateFrame("StatusBar", nil, frame.mshPredictionClip)
    frame.mshHealAbsorbBar:SetFrameStrata(frame:GetFrameStrata())
    frame.mshHealAbsorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
    frame.mshHealAbsorbBar:SetAllPoints(frame.mshPredictionClip)
    frame.mshHealAbsorbBar:Hide()

    frame.mshPredictionCreated = true
end

function msh.IsPredictionPreviewEnabled(cfg)
    return cfg and predictionPreviewState[cfg] == true or false
end

function msh.TogglePredictionPreview(cfg)
    if not cfg then
        return
    end

    predictionPreviewState[cfg] = not predictionPreviewState[cfg]
end

local function ConfigurePredictionBar(bar, texturePath, r, g, b, a, side)
    if not bar then return end

    bar:SetStatusBarTexture(texturePath)
    bar:SetStatusBarColor(r, g, b, a)

    local texture = bar:GetStatusBarTexture()
    if texture then
        texture:SetDrawLayer("ARTWORK", 0)
        texture:SetHorizTile(true)
        texture:SetVertTile(true)
    end

    if bar.SetFillStyle and Enum and Enum.StatusBarFillStyle then
        bar:SetFillStyle(side == "RIGHT" and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
    elseif bar.SetReverseFill then
        bar:SetReverseFill(side == "RIGHT")
    end
end

local function UpdatePredictionBar(frame, bar, value, shouldShow)
    if not frame or not frame.healthBar or not bar then return end

    if not shouldShow or value == nil then
        bar:Hide()
        return
    end

    local minHealth, maxHealth = frame.healthBar:GetMinMaxValues()
    bar:SetMinMaxValues(minHealth, maxHealth)
    bar:SetValue(value)
    bar:Show()
end

local function UpdatePreviewPredictionBar(frame, bar, side, value)
    if not frame or not frame.healthBar or not bar then return end

    bar:ClearAllPoints()
    bar:SetAllPoints(frame.mshPredictionClip or frame.healthBar)

    if bar.SetFillStyle and Enum and Enum.StatusBarFillStyle then
        bar:SetFillStyle(side == "RIGHT" and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
    elseif bar.SetReverseFill then
        bar:SetReverseFill(side == "RIGHT")
    end

    bar:SetMinMaxValues(0, 100)
    bar:SetValue(value)
    bar:Show()
end

function msh.CreateHealthLayers(frame)
    if not msh.db or not msh.db.profile then return end
    if frame.mshHealthCreated then return end

    EnsureTextLayer(frame)

    frame.mshHP = frame.mshTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.mshHP:SetDrawLayer("OVERLAY", 7)

    if not frame.mshHoverTex then
        frame.mshHoverTex = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        frame.mshHoverTex:SetAllPoints(frame.healthBar)
        frame.mshHoverTex:SetTexture("Interface\\Buttons\\White8x8")
        frame.mshHoverTex:SetBlendMode("ADD")
        frame.mshHoverTex:Hide()

        frame:HookScript("OnEnter", function(self)
            if self.mshHoverTex then
                local isRaidFrame = self:GetName():find("Raid")
                local db = isRaidFrame and msh.db.profile.raid or msh.db.profile.party

                local alpha = db.hoverAlpha or 0.2
                self.mshHoverTex:SetVertexColor(1, 1, 1, alpha)
                self.mshHoverTex:Show()
            end
        end)

        frame:HookScript("OnLeave", function(self)
            if self.mshHoverTex then self.mshHoverTex:Hide() end
        end)
    end

    if frame.statusText then frame.statusText:SetAlpha(0) end
    if frame.name and frame.name.SetDrawLayer then
        frame.name:SetDrawLayer("OVERLAY", 6)
    end

    EnsurePredictionOverlays(frame)

    frame.mshHealthCreated = true
end

function msh.UpdateHealthPredictionDisplay(frame)
    if not frame or frame:IsForbidden() then return end
    EnsurePredictionOverlays(frame)

    local cfg = msh.GetConfigForFrame(frame)
    if not cfg then return end

    local healAbsorbTexture = LSM:Fetch("statusbar", cfg.healAbsorbTexture or cfg.texture or "Solid")
    local shieldTexture = LSM:Fetch("statusbar", cfg.shieldTexture or cfg.texture or "Solid")
    local healR, healG, healB, healA = GetPredictionColor(cfg, "healAbsorbColor", defaultHealAbsorbColor)
    local shieldR, shieldG, shieldB, shieldA = GetPredictionColor(cfg, "shieldColor", defaultShieldColor)
    local unit = frame.displayedUnit or frame.unit
    local healAbsorbAmount = unit and UnitGetTotalHealAbsorbs(unit) or nil
    local shieldAmount = unit and UnitGetTotalAbsorbs(unit) or nil
    local showHealAbsorb =
        (frame.myHealAbsorb and frame.myHealAbsorb:IsShown()) or
        (frame.overHealAbsorbGlow and frame.overHealAbsorbGlow:IsShown()) or
        (frame.myHealAbsorbOverlay and frame.myHealAbsorbOverlay:IsShown()) or
        (frame.myHealAbsorbLeftShadow and frame.myHealAbsorbLeftShadow:IsShown()) or
        (frame.myHealAbsorbRightShadow and frame.myHealAbsorbRightShadow:IsShown())
    local showShield =
        (frame.totalAbsorb and frame.totalAbsorb:IsShown()) or
        (frame.overAbsorbGlow and frame.overAbsorbGlow:IsShown()) or
        (frame.totalAbsorbOverlay and frame.totalAbsorbOverlay:IsShown())

    StylePredictionTexture(frame.myHealAbsorb, healAbsorbTexture, healR, healG, healB, healA)
    StylePredictionTexture(frame.totalAbsorb, shieldTexture, shieldR, shieldG, shieldB, shieldA)

    ConfigurePredictionBar(frame.mshHealAbsorbBar, healAbsorbTexture, healR, healG, healB, healA, cfg.healAbsorbSide or "LEFT")
    ConfigurePredictionBar(frame.mshShieldBar, shieldTexture, shieldR, shieldG, shieldB, shieldA, cfg.shieldSide or "RIGHT")

    if msh.IsPredictionPreviewEnabled(cfg) then
        UpdatePreviewPredictionBar(frame, frame.mshHealAbsorbBar, cfg.healAbsorbSide or "LEFT", 22)
        UpdatePreviewPredictionBar(frame, frame.mshShieldBar, cfg.shieldSide or "RIGHT", 36)
        SetPredictionDecorationsSuppressed(frame, true)
        SetElementSuppressed(frame.myHealAbsorb, true)
        SetElementSuppressed(frame.totalAbsorb, true)
        return
    end

    if not unit then
        frame.mshHealAbsorbBar:Hide()
        frame.mshShieldBar:Hide()
        SetPredictionDecorationsSuppressed(frame, false)
        SetElementSuppressed(frame.myHealAbsorb, false)
        SetElementSuppressed(frame.totalAbsorb, false)
        return
    end

    UpdatePredictionBar(frame, frame.mshHealAbsorbBar, healAbsorbAmount, showHealAbsorb)
    UpdatePredictionBar(frame, frame.mshShieldBar, shieldAmount, showShield)

    local customHealShown = frame.mshHealAbsorbBar and frame.mshHealAbsorbBar:IsShown()
    local customShieldShown = frame.mshShieldBar and frame.mshShieldBar:IsShown()
    SetPredictionDecorationsSuppressed(frame, customHealShown or customShieldShown)
    SetElementSuppressed(frame.myHealAbsorb, customHealShown)
    SetElementSuppressed(frame.totalAbsorb, customShieldShown)
end

function msh.UpdateHealthDisplay(frame)
    if isUpdating or not frame or frame:IsForbidden() then return end

    local cfg = msh.GetConfigForFrame(frame)
    if not cfg or not frame.healthBar then return end

    if not frame.mshHealthCreated then
        msh.CreateHealthLayers(frame)
    end

    local globalFont = msh.db.profile.global.globalFontName
    local localFont = cfg.fontStatus

    local activeFont
    if localFont and localFont ~= "Default" and localFont ~= "" then
        activeFont = localFont
    else
        activeFont = (globalFont and globalFont ~= "") and globalFont or "Friz Quadrata TT"
    end

    local fontPath = LSM:Fetch("font", activeFont)

    isUpdating = true

    local texturePath = LSM:Fetch("statusbar", cfg.texture)
    if frame.healthBar:GetStatusBarTexture():GetTexture() ~= texturePath then
        frame.healthBar:SetStatusBarTexture(texturePath)
    end
    local blizzText = frame.statusText and frame.statusText:GetText() or ""
    local unit = frame.displayedUnit or frame.unit

    if msh.db.profile.global.hpMode == "NONE" then
        local isDead = unit and UnitExists(unit) and UnitIsDeadOrGhost(unit)
        local isConnected = unit and UnitIsConnected(unit)

        if isDead or not isConnected then
            frame.mshHP:SetFont(fontPath, cfg.fontSizeStatus, cfg.statusOutline)
            frame.mshHP:ClearAllPoints()
            frame.mshHP:SetPoint(cfg.statusPoint or "TOP", frame, cfg.statusX or 0, cfg.statusY or 0)
            frame.mshHP:SetText(blizzText)
            frame.mshHP:Show()
        else
            frame.mshHP:SetText("")
            frame.mshHP:Hide()
        end
    else
        frame.mshHP:SetFont(fontPath, cfg.fontSizeStatus, cfg.statusOutline)
        frame.mshHP:ClearAllPoints()
        frame.mshHP:SetPoint(cfg.statusPoint or "TOP", frame, cfg.statusX or 0, cfg.statusY or 0)
        frame.mshHP:SetText(blizzText)
        frame.mshHP:Show()
    end

    msh.UpdateHealthPredictionDisplay(frame)

    isUpdating = false
end

hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
    if msh.UpdateHealthPredictionDisplay then
        msh.UpdateHealthPredictionDisplay(frame)
    end
end)
