local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")

local isUpdating = false
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

local function HideTexture(texture)
    if texture then
        texture:Hide()
    end
end

local function HidePredictionDecorations(frame)
    HideTexture(frame.totalAbsorbOverlay)
    HideTexture(frame.overAbsorbGlow)
    HideTexture(frame.overHealAbsorbGlow)
    HideTexture(frame.myHealAbsorbOverlay)
    HideTexture(frame.myHealAbsorbLeftShadow)
    HideTexture(frame.myHealAbsorbRightShadow)
end

local function EnsurePredictionOverlays(frame)
    if not frame or not frame.healthBar or frame.mshPredictionCreated then
        return
    end

    frame.mshShieldBar = CreateFrame("StatusBar", nil, frame)
    frame.mshShieldBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
    frame.mshShieldBar:SetAllPoints(frame.healthBar)
    frame.mshShieldBar:Hide()

    frame.mshHealAbsorbBar = CreateFrame("StatusBar", nil, frame)
    frame.mshHealAbsorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
    frame.mshHealAbsorbBar:SetAllPoints(frame.healthBar)
    frame.mshHealAbsorbBar:Hide()

    frame.mshPredictionCreated = true
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

function msh.CreateHealthLayers(frame)
    if not msh.db or not msh.db.profile then return end
    if frame.mshHealthCreated then return end

    frame.mshHP = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    local showHealAbsorb = (frame.myHealAbsorb and frame.myHealAbsorb:IsShown()) or (frame.overHealAbsorbGlow and frame.overHealAbsorbGlow:IsShown())
    local showShield = (frame.totalAbsorb and frame.totalAbsorb:IsShown()) or (frame.overAbsorbGlow and frame.overAbsorbGlow:IsShown())

    StylePredictionTexture(frame.myHealAbsorb, healAbsorbTexture, healR, healG, healB, healA)
    StylePredictionTexture(frame.totalAbsorb, shieldTexture, shieldR, shieldG, shieldB, shieldA)

    ConfigurePredictionBar(frame.mshHealAbsorbBar, healAbsorbTexture, healR, healG, healB, healA, cfg.healAbsorbSide or "LEFT")
    ConfigurePredictionBar(frame.mshShieldBar, shieldTexture, shieldR, shieldG, shieldB, shieldA, cfg.shieldSide or "RIGHT")

    HidePredictionDecorations(frame)
    HideTexture(frame.myHealAbsorb)
    HideTexture(frame.totalAbsorb)

    if not unit then
        frame.mshHealAbsorbBar:Hide()
        frame.mshShieldBar:Hide()
        return
    end

    UpdatePredictionBar(frame, frame.mshHealAbsorbBar, UnitGetTotalHealAbsorbs(unit), showHealAbsorb)
    UpdatePredictionBar(frame, frame.mshShieldBar, UnitGetTotalAbsorbs(unit), showShield)
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
