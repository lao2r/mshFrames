local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")
local dispelOverlayPreviewState = setmetatable({}, { __mode = "k" })
local knownDispelTypes = { "Magic", "Curse", "Disease", "Poison" }
local defaultDispelColors = {
    Magic = { r = 0.20, g = 0.60, b = 1.00, a = 0.95 },
    Curse = { r = 0.60, g = 0.00, b = 1.00, a = 0.95 },
    Disease = { r = 0.75, g = 0.55, b = 0.20, a = 0.95 },
    Poison = { r = 0.00, g = 0.85, b = 0.20, a = 0.95 },
}
local dispelOverlaySides = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
local pixelGlowLayers = {
    { alpha = 0.85 },
    { alpha = 0.35 },
    { alpha = 0.15 },
}
local pixelGlowKey = "mshDispel"

local function EnsureTextLayer(frame)
    if not frame or frame.mshTextLayer then
        return
    end

    frame.mshTextLayer = CreateFrame("Frame", nil, frame)
    frame.mshTextLayer:SetFrameStrata(frame:GetFrameStrata())
    frame.mshTextLayer:SetFrameLevel((frame.healthBar and frame.healthBar:GetFrameLevel() or frame:GetFrameLevel()) + 10)
    frame.mshTextLayer:SetAllPoints(frame)
end

local function SafeEquals(left, right)
    local ok, matches = pcall(function()
        return left == right
    end)

    return ok and matches
end

local function NormalizeDispelType(value)
    if not value then
        return nil
    end

    for _, dispelType in ipairs(knownDispelTypes) do
        if SafeEquals(value, dispelType) then
            return dispelType
        end
    end

    return nil
end

local function CreateOverlayTexture(parent, subLevel)
    local texture = parent:CreateTexture(nil, "OVERLAY", nil, subLevel or 0)
    texture:SetTexture("Interface\\Buttons\\White8x8")
    texture:Hide()
    return texture
end

local function GetCustomGlowLib()
    if not LibStub then
        return nil
    end

    return LibStub("LibCustomGlow-1.0", true)
end

local function EnsureDispelOverlay(frame)
    if not frame or not frame.healthBar or frame.mshDispelOverlayFrame then
        return
    end

    EnsureTextLayer(frame)

    local overlay = CreateFrame("Frame", nil, frame.mshTextLayer or frame)
    overlay:SetFrameStrata((frame.mshTextLayer and frame.mshTextLayer:GetFrameStrata()) or frame:GetFrameStrata())
    overlay:SetFrameLevel((frame.mshTextLayer and frame.mshTextLayer:GetFrameLevel()) or frame:GetFrameLevel() + 2)
    overlay:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT")
    overlay:Hide()

    overlay.solidEdges = {}
    for _, side in ipairs(dispelOverlaySides) do
        overlay.solidEdges[side] = CreateOverlayTexture(overlay, 1)
    end

    overlay.pixelEdges = {}
    for layerIndex = 1, #pixelGlowLayers do
        local edges = {}
        for _, side in ipairs(dispelOverlaySides) do
            edges[side] = CreateOverlayTexture(overlay, 1 + layerIndex)
        end
        overlay.pixelEdges[layerIndex] = edges
    end

    frame.mshDispelOverlayFrame = overlay
end

local function HideEdgeSet(edges)
    if not edges then
        return
    end

    for _, texture in pairs(edges) do
        texture:Hide()
    end
end

local function SetEdgeSetBlendMode(edges, mode)
    if not edges then
        return
    end

    for _, texture in pairs(edges) do
        texture:SetBlendMode(mode)
    end
end

local function HideDispelOverlay(frame)
    if frame and frame.mshDispelOverlayFrame then
        local customGlow = GetCustomGlowLib()
        if customGlow and customGlow.PixelGlow_Stop then
            customGlow.PixelGlow_Stop(frame.mshDispelOverlayFrame, pixelGlowKey)
        end

        frame.mshDispelOverlayFrame:Hide()
        HideEdgeSet(frame.mshDispelOverlayFrame.solidEdges)

        for _, edges in ipairs(frame.mshDispelOverlayFrame.pixelEdges or {}) do
            HideEdgeSet(edges)
        end
    end

    if frame and frame.DispelOverlay and frame.DispelOverlay.SetAlpha then
        if frame.DispelOverlay.mshOriginalAlpha == nil and frame.DispelOverlay.GetAlpha then
            frame.DispelOverlay.mshOriginalAlpha = frame.DispelOverlay:GetAlpha()
        end

        frame.DispelOverlay:SetAlpha(frame.DispelOverlay.mshOriginalAlpha or 1)
    end
end

local function LayoutOverlayEdge(texture, overlay, side, offset, thickness)
    texture:ClearAllPoints()

    if side == "TOP" then
        texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", -offset, offset)
        texture:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", offset, offset)
        texture:SetHeight(thickness)
    elseif side == "BOTTOM" then
        texture:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -offset, -offset)
        texture:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", offset, -offset)
        texture:SetHeight(thickness)
    elseif side == "LEFT" then
        texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", -offset, offset)
        texture:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -offset, -offset)
        texture:SetWidth(thickness)
    else
        texture:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", offset, offset)
        texture:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", offset, -offset)
        texture:SetWidth(thickness)
    end
end

local function GetDispelOverlayColor(cfg, dispelType)
    local field, fallback

    if dispelType == "Curse" then
        field = "dispelOverlayCurseColor"
        fallback = defaultDispelColors.Curse
    elseif dispelType == "Disease" then
        field = "dispelOverlayDiseaseColor"
        fallback = defaultDispelColors.Disease
    elseif dispelType == "Poison" then
        field = "dispelOverlayPoisonColor"
        fallback = defaultDispelColors.Poison
    else
        field = "dispelOverlayMagicColor"
        fallback = defaultDispelColors.Magic
    end

    local color = cfg and cfg[field]
    if type(color) ~= "table" then
        return fallback.r, fallback.g, fallback.b, fallback.a
    end

    return color.r or fallback.r, color.g or fallback.g, color.b or fallback.b, color.a or fallback.a
end

local function GetBlizzardDispelReferenceColor(dispelType)
    local color = DebuffTypeColor and DebuffTypeColor[dispelType]
    if type(color) ~= "table" then
        return nil
    end

    return color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4] or 1
end

local function FindVisibleTextureColor(regionOwner)
    if not regionOwner then
        return false, nil, nil, nil, nil
    end

    local regions = { regionOwner:GetRegions() }
    for _, region in ipairs(regions) do
        if region and region.IsObjectType and region:IsObjectType("Texture") and region:IsShown() then
            local r, g, b, a = region:GetVertexColor()
            return true, r, g, b, a
        end
    end

    local children = { regionOwner:GetChildren() }
    for _, child in ipairs(children) do
        local found, r, g, b, a = FindVisibleTextureColor(child)
        if found then
            return true, r, g, b, a
        end
    end

    return false, nil, nil, nil, nil
end

local function GuessDispelTypeFromColor(r, g, b)
    if not r or not g or not b then
        return nil
    end

    local bestType
    local bestDistance

    for _, dispelType in ipairs(knownDispelTypes) do
        local refR, refG, refB = GetBlizzardDispelReferenceColor(dispelType)
        if refR and refG and refB then
            local distance = ((r - refR) * (r - refR)) + ((g - refG) * (g - refG)) + ((b - refB) * (b - refB))
            if not bestDistance or distance < bestDistance then
                bestDistance = distance
                bestType = dispelType
            end
        end
    end

    return bestType
end

local function GetNativeDispelVisual(frame, activeDispelIcon)
    local shown = false
    local r, g, b, a

    if activeDispelIcon then
        shown = activeDispelIcon:IsShown()

        local border = activeDispelIcon.border or activeDispelIcon.Border or activeDispelIcon.IconBorder
        if border and border.GetVertexColor then
            r, g, b, a = border:GetVertexColor()
        end
    end

    if frame and frame.DispelOverlay then
        shown = shown or frame.DispelOverlay:IsShown()
        local foundTexture, texR, texG, texB, texA = FindVisibleTextureColor(frame.DispelOverlay)
        if foundTexture and (not r or not g or not b) then
            r, g, b, a = texR, texG, texB, texA
        end
    end

    return shown, r, g, b, a
end

local function ApplySolidDispelOverlay(frame, r, g, b, a, thickness)
    local overlay = frame and frame.mshDispelOverlayFrame
    if not overlay then
        return
    end

    overlay:Show()
    local customGlow = GetCustomGlowLib()
    if customGlow and customGlow.PixelGlow_Stop then
        customGlow.PixelGlow_Stop(overlay, pixelGlowKey)
    end

    for _, edges in ipairs(overlay.pixelEdges or {}) do
        SetEdgeSetBlendMode(edges, "BLEND")
        HideEdgeSet(edges)
    end

    for side, texture in pairs(overlay.solidEdges or {}) do
        LayoutOverlayEdge(texture, overlay, side, 0, thickness)
        texture:SetBlendMode("BLEND")
        texture:SetVertexColor(r, g, b, a)
        texture:Show()
    end
end

local function ApplyPixelDispelOverlay(frame, r, g, b, a, thickness)
    local overlay = frame and frame.mshDispelOverlayFrame
    if not overlay then
        return
    end

    overlay:Show()
    HideEdgeSet(overlay.solidEdges)

    local customGlow = GetCustomGlowLib()
    if customGlow and customGlow.PixelGlow_Start then
        for _, edges in ipairs(overlay.pixelEdges or {}) do
            HideEdgeSet(edges)
        end

        customGlow.PixelGlow_Start(
            overlay,
            { r, g, b, a },
            8,
            0.25,
            nil,
            math.max(1, thickness),
            0,
            0,
            false,
            pixelGlowKey,
            1
        )
        return
    end

    for index, layerData in ipairs(pixelGlowLayers) do
        local glowOffset = (index - 1) * math.max(1, thickness)
        local edges = overlay.pixelEdges and overlay.pixelEdges[index]

        if edges then
            for side, texture in pairs(edges) do
                LayoutOverlayEdge(texture, overlay, side, glowOffset, 1)
                texture:SetBlendMode("ADD")
                texture:SetVertexColor(r, g, b, a * layerData.alpha)
                texture:Show()
            end
        end
    end
end

local function GetActiveDispelIcon(frame, cfg)
    if not frame or not frame.dispelDebuffFrames then
        return nil
    end

    local hadShownDispel = false

    for i = 1, #frame.dispelDebuffFrames do
        local dispelFrame = frame.dispelDebuffFrames[i]
        if dispelFrame and dispelFrame:IsShown() then
            hadShownDispel = true
            local spellID = msh.GetAuraSpellID and msh.GetAuraSpellID(dispelFrame)
            local isExcluded = msh.IsExcludedSpell and msh.IsExcludedSpell(cfg, "excludedDebuffSpellIDs", spellID)

            if isExcluded then
                dispelFrame:SetAlpha(0)
            else
                return dispelFrame, true
            end
        end
    end

    return nil, hadShownDispel
end

local function GetDispelTypeForIcon(icon)
    if not icon then
        return nil
    end

    return NormalizeDispelType(
        (msh.GetAuraDispelType and msh.GetAuraDispelType(icon)) or icon.mshDispelType or icon.dispelName or icon.dispelType or
        icon.debuffType
    )
end

function msh.IsDispelOverlayPreviewEnabled(cfg)
    return cfg and dispelOverlayPreviewState[cfg] == true or false
end

function msh.ToggleDispelOverlayPreview(cfg)
    if not cfg then
        return
    end

    dispelOverlayPreviewState[cfg] = not dispelOverlayPreviewState[cfg]
end

local function UpdateDispelOverlay(frame, cfg, activeDispelIcon, globalMode, hadShownDispel)
    local previewEnabled = msh.IsDispelOverlayPreviewEnabled and msh.IsDispelOverlayPreviewEnabled(cfg)
    local nativeShown, nativeR, nativeG, nativeB, nativeA = GetNativeDispelVisual(frame, activeDispelIcon)
    HideDispelOverlay(frame)

    if not previewEnabled then
        if cfg.dispelIndicatorOverlay == false or globalMode == "0" or not nativeShown or (not activeDispelIcon and hadShownDispel) then
            return
        end
    end

    local dispelType
    local r, g, b, a

    if previewEnabled then
        dispelType = NormalizeDispelType(cfg.dispelOverlayPreviewType or "Magic") or "Magic"
        r, g, b, a = GetDispelOverlayColor(cfg, dispelType)
    else
        dispelType = GetDispelTypeForIcon(activeDispelIcon) or GuessDispelTypeFromColor(nativeR, nativeG, nativeB)
        if dispelType then
            r, g, b, a = GetDispelOverlayColor(cfg, dispelType)
        else
            r = nativeR
            g = nativeG
            b = nativeB
            a = nativeA
        end
    end

    if not r or not g or not b then
        return
    end

    EnsureDispelOverlay(frame)

    local thickness = math.max(1, math.floor(cfg.dispelOverlayThickness or 2))
    local style = cfg.dispelOverlayStyle or "SOLID"
    a = a or 0.95

    if frame.DispelOverlay and frame.DispelOverlay.SetAlpha then
        if frame.DispelOverlay.mshOriginalAlpha == nil and frame.DispelOverlay.GetAlpha then
            frame.DispelOverlay.mshOriginalAlpha = frame.DispelOverlay:GetAlpha()
        end

        frame.DispelOverlay:SetAlpha(0)
    end

    if style == "PIXEL" then
        ApplyPixelDispelOverlay(frame, r, g, b, a, thickness)
    else
        ApplySolidDispelOverlay(frame, r, g, b, a, thickness)
    end
end

function msh.CreateUnitLayers(frame)
    if frame.mshLayersCreated then return end

    EnsureTextLayer(frame)

    frame.mshName = frame.mshTextLayer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall", 8)
    if frame.name then frame.name:SetAlpha(0) end

    frame.mshRole = frame.mshTextLayer:CreateTexture(nil, "OVERLAY", nil, 5)
    frame.mshRaidIcon = frame.mshTextLayer:CreateTexture(nil, "OVERLAY", nil, 5)
    frame.mshLeader = frame.mshTextLayer:CreateTexture(nil, "OVERLAY", nil, 5)
    frame.mshDispelIndicator = frame.mshTextLayer:CreateTexture(nil, "OVERLAY", nil, 5)

    if frame.roleIcon then
        frame.roleIcon:SetParent(frame.mshTextLayer)
        frame.roleIcon:SetDrawLayer("OVERLAY", 5)
    end

    if frame.DispelOverlay then
        frame.DispelOverlay:SetParent(frame.mshTextLayer)
        frame.DispelOverlay:SetFrameStrata(frame.mshTextLayer:GetFrameStrata())
        frame.DispelOverlay:SetFrameLevel(frame.mshTextLayer:GetFrameLevel() + 1)
        frame.DispelOverlay:ClearAllPoints()
        frame.DispelOverlay:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT")
        frame.DispelOverlay:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT")
    end

    if frame.leaderIcon then frame.leaderIcon:SetAlpha(0) end

    EnsureDispelOverlay(frame)

    frame.mshLayersCreated = true
end

function msh.UpdateUnitDisplay(frame)
    if not frame or frame:IsForbidden() then return end

    local unit = frame.displayedUnit or frame.unit

    if not unit or not UnitExists(unit) then return end

    local cfg = msh.GetConfigForFrame(frame)

    if not frame.mshLayersCreated then
        msh.CreateUnitLayers(frame)
    end

    if not cfg then return end

    local fontName = cfg.fontName or "Friz Quadrata TT"
    local fontPath = LSM:Fetch("font", fontName)
    local fontSize = cfg.fontSizeName or 10
    local fontOutline = cfg.nameOutline or "OUTLINE"

    local maxChars = cfg.nameLength or 10
    local displayName = msh.GetShortName(unit, maxChars)
    frame.mshName:SetText(displayName)


    frame.mshName:ClearAllPoints()
    frame.mshName:SetPoint(cfg.namePoint or "CENTER", frame, cfg.nameX or 0, cfg.nameY or 0)

    frame.mshName:SetFont(fontPath, fontSize, fontOutline)
    frame.mshName:SetTextColor(1, 1, 1)

    if frame.name then frame.name:SetAlpha(0) end
    frame.mshName:Show()

    local index = GetRaidTargetIndex(unit)
    if index and cfg.showRaidMark then
        frame.mshRaidIcon:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
        frame.mshRaidIcon:SetSize(cfg.raidMarkSize or 14, cfg.raidMarkSize or 14)
        frame.mshRaidIcon:SetAlpha(cfg.raidMarkAlpha or 1)
        frame.mshRaidIcon:ClearAllPoints()
        frame.mshRaidIcon:SetPoint(cfg.raidMarkPoint or "CENTER", frame, cfg.raidMarkX or 0, cfg.raidMarkY or 0)
        SetRaidTargetIconTexture(frame.mshRaidIcon, index)
        frame.mshRaidIcon:Show()
    else
        frame.mshRaidIcon:Hide()
    end

    if frame.mshLeader then
        local isLeader = UnitIsGroupLeader(unit)
        local isAssistant = UnitIsGroupAssistant(unit)


        if (isLeader or isAssistant) and (cfg.showLeaderIcon ~= false) then
            frame.mshLeader:SetAtlas(isLeader and "GO-icon-Lead-Applied" or "GO-icon-Assist-Applied")
            frame.mshLeader:SetDrawLayer("OVERLAY", 1)

            local size = cfg.leaderIconSize or 12
            frame.mshLeader:SetSize(size, size)
            frame.mshLeader:SetAlpha(cfg.leaderIconAlpha or 1)
            frame.mshLeader:ClearAllPoints()

            frame.mshLeader:SetPoint(
                cfg.leaderIconPoint or "TOPLEFT",
                frame,
                cfg.leaderIconX or 0,
                cfg.leaderIconY or 0
            )
            frame.mshLeader:Show()
        else
            frame.mshLeader:Hide()
        end
    end

    if frame.mshDispelIndicator then
        local globalMode = "0"
        if msh.db and msh.db.profile and msh.db.profile.global then
            globalMode = msh.db.profile.global.dispelIndicatorMode or "0"
        end

        if frame.dispelDebuffFrames then
            for i = 1, #frame.dispelDebuffFrames do
                local dispelFrame = frame.dispelDebuffFrames[i]
                if dispelFrame then
                    dispelFrame:SetAlpha(1)
                end
            end
        end

        local blizzIcon, hadShownDispel = GetActiveDispelIcon(frame, cfg)
        UpdateDispelOverlay(frame, cfg, blizzIcon, globalMode, hadShownDispel)

        if globalMode == "0" then
            frame.mshDispelIndicator:Hide()
        else
            if blizzIcon and blizzIcon:IsShown() and blizzIcon.icon then
                local atlasName = blizzIcon.icon.GetAtlas and blizzIcon.icon:GetAtlas()
                if atlasName then
                    frame.mshDispelIndicator:SetAtlas(atlasName)
                else
                    frame.mshDispelIndicator:SetTexture(blizzIcon.icon:GetTexture())
                end

                local size = cfg.dispelIndicatorSize or 18
                frame.mshDispelIndicator:SetSize(size, size)
                frame.mshDispelIndicator:SetAlpha(cfg.dispelIndicatorAlpha or 1)
                frame.mshDispelIndicator:ClearAllPoints()
                frame.mshDispelIndicator:SetPoint(cfg.dispelIndicatorPoint or "TOPRIGHT", frame,
                    cfg.dispelIndicatorX or 0, cfg.dispelIndicatorY or 0)

                frame.mshDispelIndicator:Show()
                blizzIcon:SetAlpha(0)
            else
                frame.mshDispelIndicator:Hide()
            end
        end
    end


    local role = UnitGroupRolesAssigned(unit)

    if cfg.useBlizzRole then
        if frame.mshRole then frame.mshRole:Hide() end

        if frame.roleIcon then
            frame.roleIcon:SetAlpha(1)
            frame.roleIcon:Show()
            CompactUnitFrame_UpdateRoleIcon(frame)
        end
    else
        if frame.roleIcon then
            frame.roleIcon:Hide()
            frame.roleIcon:SetAlpha(0)
        end

        local shouldShowCustom = false
        if cfg.showCustomRoleIcon then
            if role == "TANK" and cfg.showRoleTank then
                shouldShowCustom = true
            elseif role == "HEALER" and cfg.showRoleHeal then
                shouldShowCustom = true
            elseif role == "DAMAGER" and cfg.showRoleDamager then
                shouldShowCustom = true
            end
        end

        if shouldShowCustom and role and role ~= "NONE" then
            if frame.mshRole then
                local atlasName
                if role == "TANK" then
                    atlasName = "GO-icon-role-Header-Tank"
                elseif role == "HEALER" then
                    atlasName = "GO-icon-role-Header-Healer"
                elseif role == "DAMAGER" then
                    atlasName = "GO-icon-role-Header-DPS"
                end
                if atlasName then
                    frame.mshRole:SetAtlas(atlasName)
                    local size = cfg.roleIconSize or 12
                    frame.mshRole:SetSize(size, size)
                    frame.mshRole:SetAlpha(cfg.roleIconAlpha or 1)
                    frame.mshRole:ClearAllPoints()
                    frame.mshRole:SetPoint(cfg.roleIconPoint or "TOPLEFT", frame, cfg.roleIconX or 2, cfg.roleIconY or -2)
                    frame.mshRole:Show()
                end
            end
        else
            if frame.mshRole then frame.mshRole:Hide() end
        end
    end
end
