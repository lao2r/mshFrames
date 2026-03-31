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

local function StylePredictionTexture(texture, texturePath, r, g, b, a, subLevel)
    if not texture then return end

    texture:SetTexture(texturePath)
    texture:SetVertexColor(r, g, b, a)

    if texture.SetDrawLayer then
        texture:SetDrawLayer("ARTWORK", subLevel or 1)
    end
end

local function SetPredictionDrawLayer(texture, layer, subLevel)
    if texture and texture.SetDrawLayer then
        texture:SetDrawLayer(layer, subLevel or 1)
    end
end

local function ApplyHealAbsorbSide(frame, side)
    local bar = frame and frame.myHealAbsorb
    local healthTexture = frame and frame.healthBar and frame.healthBar:GetStatusBarTexture()

    if not bar or not bar:IsShown() or not healthTexture then
        return
    end

    bar:ClearAllPoints()

    if side == "RIGHT" then
        bar:SetPoint("TOPLEFT", healthTexture, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", healthTexture, "BOTTOMLEFT", 0, 0)
    else
        bar:SetPoint("TOPRIGHT", healthTexture, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", healthTexture, "BOTTOMRIGHT", 0, 0)
    end
end

local function ApplyShieldSide(frame, side)
    local bar = frame and frame.totalAbsorb

    if not bar or not bar:IsShown() then
        return
    end

    local _, relativeTo = bar:GetPoint(1)
    if not relativeTo then
        return
    end

    bar:ClearAllPoints()

    if side == "LEFT" then
        bar:SetPoint("TOPRIGHT", relativeTo, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", relativeTo, "BOTTOMLEFT", 0, 0)
    else
        bar:SetPoint("TOPLEFT", relativeTo, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", relativeTo, "BOTTOMRIGHT", 0, 0)
    end
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

    frame.mshHealthCreated = true
end

function msh.UpdateHealthPredictionDisplay(frame)
    if not frame or frame:IsForbidden() then return end

    local cfg = msh.GetConfigForFrame(frame)
    if not cfg then return end

    local healAbsorbTexture = LSM:Fetch("statusbar", cfg.healAbsorbTexture or cfg.texture or "Solid")
    local shieldTexture = LSM:Fetch("statusbar", cfg.shieldTexture or cfg.texture or "Solid")
    local healR, healG, healB, healA = GetPredictionColor(cfg, "healAbsorbColor", defaultHealAbsorbColor)
    local shieldR, shieldG, shieldB, shieldA = GetPredictionColor(cfg, "shieldColor", defaultShieldColor)

    StylePredictionTexture(frame.myHealAbsorb, healAbsorbTexture, healR, healG, healB, healA, 2)
    StylePredictionTexture(frame.totalAbsorb, shieldTexture, shieldR, shieldG, shieldB, shieldA, 2)

    SetPredictionDrawLayer(frame.totalAbsorbOverlay, "ARTWORK", 3)
    SetPredictionDrawLayer(frame.overAbsorbGlow, "ARTWORK", 4)
    SetPredictionDrawLayer(frame.overHealAbsorbGlow, "ARTWORK", 4)
    SetPredictionDrawLayer(frame.myHealAbsorbLeftShadow, "ARTWORK", 3)
    SetPredictionDrawLayer(frame.myHealAbsorbRightShadow, "ARTWORK", 3)

    ApplyHealAbsorbSide(frame, cfg.healAbsorbSide or "LEFT")
    ApplyShieldSide(frame, cfg.shieldSide or "RIGHT")
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
