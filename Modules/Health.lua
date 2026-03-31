local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")

local isUpdating = false

function msh.CreateHealthLayers(frame)
    if not msh.db or not msh.db.profile then return end
    local cfg = msh.GetConfigForFrame(frame)
    if frame.mshHealthCreated then return end

    frame.mshHP = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

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

    isUpdating = false
end
