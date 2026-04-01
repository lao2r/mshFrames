local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")
local dispelOverlayPreviewState = setmetatable({}, { __mode = "k" })
local aggroIndicatorPreviewState = setmetatable({}, { __mode = "k" })
local knownDispelTypes = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local dispelTypeAliases
local DEBUG_DISPEL = false
local dispelCurveCache = setmetatable({}, { __mode = "k" })
local dispelLookupCurve
local dispelEnumByType = {
    Magic = 1,
    Curse = 2,
    Disease = 3,
    Poison = 4,
    Bleed = 11,
}
local dispelLookupColorByType = {
    Magic = { 1, 0, 0, 1 },
    Curse = { 0, 1, 0, 1 },
    Disease = { 0, 0, 1, 1 },
    Poison = { 1, 1, 0, 1 },
    Bleed = { 1, 0, 1, 1 },
}
local dispelTypeByLookupColor = {
    ["1.000:0.000:0.000:1.000"] = "Magic",
    ["0.000:1.000:0.000:1.000"] = "Curse",
    ["0.000:0.000:1.000:1.000"] = "Disease",
    ["1.000:1.000:0.000:1.000"] = "Poison",
    ["1.000:0.000:1.000:1.000"] = "Bleed",
}
local defaultDispelColors = {
    Magic = { r = 0.20, g = 0.60, b = 1.00, a = 0.95 },
    Curse = { r = 0.60, g = 0.00, b = 1.00, a = 0.95 },
    Disease = { r = 0.75, g = 0.55, b = 0.20, a = 0.95 },
    Poison = { r = 0.00, g = 0.85, b = 0.20, a = 0.95 },
    Bleed = { r = 0.80, g = 0.10, b = 0.10, a = 0.95 },
}
local defaultAggroColor = { r = 1.00, g = 0.15, b = 0.15, a = 0.95 }
local aggroArrowAtlas = "minimal-scrollbar-arrow-bottom-down"
local aggroArrowRotationByDirection = {
    DOWN = 0,
    LEFT = math.pi * 0.5,
    UP = math.pi,
    RIGHT = math.pi * -0.5,
}
local dispelOverlaySides = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
local dashedSegmentsPerSide = 16
local function BuildDispelTypeAliases()
    local aliases = {
        Magic = { "Magic", "magic", 8 },
        Disease = { "Disease", "disease", 16 },
        Curse = { "Curse", "curse", 32 },
        Poison = { "Poison", "poison", 64 },
        Bleed = { "Bleed", "bleed" },
    }

    local localizedTypes = {
        Magic = _G and _G.DEBUFF_TYPE_MAGIC,
        Disease = _G and _G.DEBUFF_TYPE_DISEASE,
        Curse = _G and _G.DEBUFF_TYPE_CURSE,
        Poison = _G and _G.DEBUFF_TYPE_POISON,
        Bleed = _G and _G.DEBUFF_TYPE_BLEED,
    }

    for dispelType, localizedName in pairs(localizedTypes) do
        if type(localizedName) == "string" and localizedName ~= "" then
            table.insert(aliases[dispelType], localizedName)
            table.insert(aliases[dispelType], string.lower(localizedName))
        end
    end

    return aliases
end

dispelTypeAliases = BuildDispelTypeAliases()

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
    if value == nil then
        return nil
    end

    local ok, token = pcall(function()
        local textValue = tostring(value)
        if type(textValue) ~= "string" or textValue == "" then
            return nil
        end

        local plainValue = string.format("%s", textValue)
        if type(plainValue) ~= "string" or plainValue == "" then
            return nil
        end

        return string.lower(plainValue)
    end)

    if not ok or type(token) ~= "string" or token == "" then
        return nil
    end

    for _, dispelType in ipairs(knownDispelTypes) do
        local aliases = dispelTypeAliases[dispelType]
        if aliases then
            for _, alias in ipairs(aliases) do
                local aliasToken = string.lower(tostring(alias))
                local matched, containsAlias = pcall(function()
                    return string.find(token, aliasToken, 1, true) ~= nil
                end)
                if matched and containsAlias then
                    return dispelType
                end
            end
        end
    end

    return nil
end

local function GetConfiguredColor(cfg, field, fallback)
    local color = cfg and cfg[field]
    if type(color) ~= "table" then
        return fallback.r, fallback.g, fallback.b, fallback.a
    end

    return color.r or fallback.r, color.g or fallback.g, color.b or fallback.b, color.a or fallback.a
end

local function CreateOverlayTexture(parent, subLevel)
    local texture = parent:CreateTexture(nil, "OVERLAY", nil, subLevel or 0)
    texture:SetTexture("Interface\\Buttons\\White8x8")
    texture:Hide()
    return texture
end

local function GetStringToken(value)
    if value == nil then
        return nil
    end

    local ok, token = pcall(function()
        local textValue = string.format("%s", value)
        if type(textValue) ~= "string" or textValue == "" then
            return nil
        end

        return string.lower(textValue)
    end)

    if ok and type(token) == "string" and token ~= "" then
        return token
    end

    return nil
end

local function DebugDispelSource(frame, message)
    if not DEBUG_DISPEL then
        return
    end

    if not DEFAULT_CHAT_FRAME or not message then
        return
    end

    local frameName = frame and frame.GetName and frame:GetName() or "?"
    local fullMessage = string.format("mshFrames dispel source: frame=%s %s", tostring(frameName), tostring(message))
    DEFAULT_CHAT_FRAME:AddMessage(fullMessage)
end

local function SafeDebugValue(value)
    local ok, rawValue = pcall(tostring, value)
    if ok then
        return rawValue
    end

    return "<error>"
end

local function SafeAuraValue(value)
    if value == nil then
        return nil
    end

    if issecretvalue and issecretvalue(value) then
        if canaccessvalue and not canaccessvalue(value) then
            return nil
        end
    end

    return value
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
    if overlay.SetClipsChildren then
        overlay:SetClipsChildren(true)
    end
    overlay:Hide()

    overlay.solidEdges = {}
    for _, side in ipairs(dispelOverlaySides) do
        overlay.solidEdges[side] = CreateOverlayTexture(overlay, 1)
    end

    overlay.pixelEdges = {}
    for _, side in ipairs(dispelOverlaySides) do
        local edges = {}
        for index = 1, dashedSegmentsPerSide do
            edges[index] = CreateOverlayTexture(overlay, 2)
            edges[index]:SetBlendMode("BLEND")
        end
        overlay.pixelEdges[side] = edges
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

local function HideAllPixelEdges(overlay)
    if not overlay or not overlay.pixelEdges then
        return
    end

    for _, edges in pairs(overlay.pixelEdges) do
        HideEdgeSet(edges)
    end
end

local function LayoutDashedSide(textures, overlay, side, thickness, dashLength, dashGap)
    if not textures or not overlay then
        return
    end

    for index, texture in ipairs(textures) do
        texture:ClearAllPoints()

        local offset = (index - 1) * (dashLength + dashGap)

        if side == "TOP" then
            texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", offset, 0)
            texture:SetSize(dashLength, thickness)
            texture:Show()
        elseif side == "BOTTOM" then
            texture:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", offset, 0)
            texture:SetSize(dashLength, thickness)
            texture:Show()
        elseif side == "LEFT" then
            texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, -offset)
            texture:SetSize(thickness, dashLength)
            texture:Show()
        else
            texture:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, -offset)
            texture:SetSize(thickness, dashLength)
            texture:Show()
        end
    end
end

local function HideDispelOverlay(frame)
    if frame and frame.mshDispelOverlayFrame then
        frame.mshDispelOverlayFrame:Hide()
        HideEdgeSet(frame.mshDispelOverlayFrame.solidEdges)
        HideAllPixelEdges(frame.mshDispelOverlayFrame)
    end
end

local function SetNativeDispelOverlayAlpha(frame, alpha)
    if frame and frame.DispelOverlay and frame.DispelOverlay.SetAlpha then
        if frame.DispelOverlay.mshOriginalAlpha == nil and frame.DispelOverlay.GetAlpha then
            frame.DispelOverlay.mshOriginalAlpha = frame.DispelOverlay:GetAlpha()
        end

        frame.DispelOverlay:SetAlpha(alpha)
    end
end

local function SetNativeAggroHighlightAlpha(frame, alpha)
    if frame and frame.aggroHighlight and frame.aggroHighlight.SetAlpha then
        if frame.aggroHighlight.mshOriginalAlpha == nil and frame.aggroHighlight.GetAlpha then
            frame.aggroHighlight.mshOriginalAlpha = frame.aggroHighlight:GetAlpha()
        end

        frame.aggroHighlight:SetAlpha(alpha)
    end
end

local function EnsureAggroIndicator(frame)
    if not frame or not frame.healthBar or frame.mshAggroIndicator then
        return
    end

    EnsureTextLayer(frame)

    local holder = CreateFrame("Frame", nil, frame.mshTextLayer or frame)
    holder:SetFrameStrata((frame.mshTextLayer and frame.mshTextLayer:GetFrameStrata()) or frame:GetFrameStrata())
    holder:SetFrameLevel((frame.mshTextLayer and frame.mshTextLayer:GetFrameLevel()) or frame:GetFrameLevel() + 3)
    holder:Hide()

    holder.edges = {}
    for index = 1, 8 do
        holder.edges[index] = CreateOverlayTexture(holder, 3)
    end

    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.label:SetDrawLayer("OVERLAY", 7)
    holder.label:Hide()

    holder.arrow = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    if holder.arrow.SetAtlas then
        holder.arrow:SetAtlas(aggroArrowAtlas, false)
    else
        holder.arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    end
    holder.arrow:SetTexCoord(0, 1, 0, 1)
    holder.arrow:Hide()

    frame.mshAggroIndicator = holder
end

local function HideAggroIndicator(frame)
    local holder = frame and frame.mshAggroIndicator
    if not holder then
        return
    end

    for _, texture in ipairs(holder.edges or {}) do
        texture:Hide()
    end

    if holder.label then
        holder.label:Hide()
    end

    if holder.arrow then
        holder.arrow:Hide()
    end

    holder:Hide()
end

local function SetAggroEdge(texture, point, relativeTo, relativePoint, x, y, width, height, r, g, b, a)
    if not texture then
        return
    end

    texture:ClearAllPoints()
    texture:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    texture:SetSize(width, height)
    texture:SetVertexColor(r, g, b, a)
    texture:Show()
end

local function UpdateAggroBorder(holder, shape, width, height, thickness, r, g, b, a)
    local edges = holder and holder.edges
    if not edges then
        return
    end

    for _, texture in ipairs(edges) do
        texture:Hide()
    end

    local segment = math.max(thickness * 2, math.floor(math.min(width, height) * 0.3))

    if shape == "CORNERS" then
        SetAggroEdge(edges[1], "TOPLEFT", holder, "TOPLEFT", 0, 0, segment, thickness, r, g, b, a)
        SetAggroEdge(edges[2], "TOPLEFT", holder, "TOPLEFT", 0, 0, thickness, segment, r, g, b, a)
        SetAggroEdge(edges[3], "TOPRIGHT", holder, "TOPRIGHT", 0, 0, segment, thickness, r, g, b, a)
        SetAggroEdge(edges[4], "TOPRIGHT", holder, "TOPRIGHT", 0, 0, thickness, segment, r, g, b, a)
        SetAggroEdge(edges[5], "BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0, segment, thickness, r, g, b, a)
        SetAggroEdge(edges[6], "BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0, thickness, segment, r, g, b, a)
        SetAggroEdge(edges[7], "BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0, segment, thickness, r, g, b, a)
        SetAggroEdge(edges[8], "BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0, thickness, segment, r, g, b, a)
    elseif shape == "BRACKETS" then
        SetAggroEdge(edges[1], "TOPLEFT", holder, "TOPLEFT", 0, 0, thickness, height, r, g, b, a)
        SetAggroEdge(edges[2], "TOPLEFT", holder, "TOPLEFT", 0, 0, segment, thickness, r, g, b, a)
        SetAggroEdge(edges[3], "BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0, segment, thickness, r, g, b, a)
        SetAggroEdge(edges[4], "TOPRIGHT", holder, "TOPRIGHT", 0, 0, thickness, height, r, g, b, a)
        SetAggroEdge(edges[5], "TOPRIGHT", holder, "TOPRIGHT", 0, 0, segment, thickness, r, g, b, a)
        SetAggroEdge(edges[6], "BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0, segment, thickness, r, g, b, a)
    else
        SetAggroEdge(edges[1], "TOPLEFT", holder, "TOPLEFT", 0, 0, width, thickness, r, g, b, a)
        SetAggroEdge(edges[2], "BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0, width, thickness, r, g, b, a)
        SetAggroEdge(edges[3], "TOPLEFT", holder, "TOPLEFT", 0, 0, thickness, height, r, g, b, a)
        SetAggroEdge(edges[4], "TOPRIGHT", holder, "TOPRIGHT", 0, 0, thickness, height, r, g, b, a)
    end
end

local function UpdateAggroIndicator(frame, cfg)
    if not frame or not cfg or not frame.healthBar then
        return
    end

    EnsureAggroIndicator(frame)

    local previewEnabled = cfg and aggroIndicatorPreviewState[cfg] == true

    if cfg.showAggroIndicator == false then
        HideAggroIndicator(frame)
        SetNativeAggroHighlightAlpha(frame, frame.aggroHighlight and (frame.aggroHighlight.mshOriginalAlpha or 1) or 1)
        return
    end

    local unit = frame.displayedUnit or frame.unit
    local threatStatus = unit and UnitExists(unit) and UnitThreatSituation(unit) or nil
    local hasAggro = previewEnabled or (frame.aggroHighlight and frame.aggroHighlight:IsShown()) or (threatStatus and threatStatus > 1) or false

    if not hasAggro then
        HideAggroIndicator(frame)
        SetNativeAggroHighlightAlpha(frame, 0)
        return
    end

    local holder = frame.mshAggroIndicator
    local mode = cfg.aggroIndicatorMode or "BORDER"
    local shape = cfg.aggroBorderShape or "FRAME"
    local r, g, b, a = GetConfiguredColor(cfg, "aggroColor", defaultAggroColor)
    local baseWidth = (frame.healthBar.GetWidth and frame.healthBar:GetWidth()) or 0
    local baseHeight = (frame.healthBar.GetHeight and frame.healthBar:GetHeight()) or 0
    local offsetX = 0
    local offsetY = 0
    local width
    local height

    if mode == "BORDER" then
        width = math.max(4, baseWidth + (cfg.aggroWidth or 0))
        height = math.max(4, baseHeight + (cfg.aggroHeight or 0))
        offsetX = cfg.aggroX or 0
        offsetY = cfg.aggroY or 0
    elseif mode == "TEXT" then
        local fontSize = math.max(8, math.floor(cfg.aggroTextSize or 14))
        width = math.max(12, baseWidth)
        height = math.max(12, fontSize + 6)
        offsetX = cfg.aggroTextX or 0
        offsetY = cfg.aggroTextY or 0
    else
        width = math.max(8, math.floor(cfg.aggroArrowWidth or 18))
        height = math.max(8, math.floor(cfg.aggroArrowHeight or 18))
        offsetX = cfg.aggroArrowX or 0
        offsetY = cfg.aggroArrowY or 0
    end

    holder:ClearAllPoints()
    holder:SetSize(width, height)
    holder:SetPoint("CENTER", frame.healthBar, "CENTER", offsetX, offsetY)
    holder:Show()

    for _, texture in ipairs(holder.edges or {}) do
        texture:Hide()
    end
    holder.label:Hide()
    holder.arrow:Hide()

    if mode == "TEXT" then
        local aggroText = cfg.aggroText
        if type(aggroText) ~= "string" or aggroText == "" then
            aggroText = L["АГРО"]
        end

        local fontPath = LSM:Fetch("font", cfg.fontName or "Friz Quadrata TT")
        holder.label:SetFont(fontPath, math.max(8, math.floor(cfg.aggroTextSize or 14)), cfg.nameOutline or "OUTLINE")
        holder.label:SetText(aggroText)
        holder.label:SetTextColor(r, g, b, a)
        holder.label:ClearAllPoints()
        holder.label:SetPoint("CENTER", holder, "CENTER")
        holder.label:Show()
    elseif mode == "ARROW" then
        local direction = cfg.aggroArrowDirection or "DOWN"
        local rotation = aggroArrowRotationByDirection[direction] or 0
        holder.arrow:ClearAllPoints()
        holder.arrow:SetPoint("CENTER", holder, "CENTER")
        holder.arrow:SetSize(width, height)
        holder.arrow:SetVertexColor(r, g, b, a)
        if holder.arrow.SetAtlas then
            holder.arrow:SetAtlas(aggroArrowAtlas, false)
        end
        if holder.arrow.SetRotation then
            holder.arrow:SetRotation(rotation)
        end
        holder.arrow:Show()
    else
        local thickness = math.max(1, math.floor(cfg.aggroBorderThickness or 2))
        UpdateAggroBorder(holder, shape, width, height, thickness, r, g, b, a)
    end

    SetNativeAggroHighlightAlpha(frame, 0)
end

function msh.IsAggroIndicatorPreviewEnabled(cfg)
    return cfg and aggroIndicatorPreviewState[cfg] == true or false
end

function msh.ToggleAggroIndicatorPreview(cfg)
    if not cfg then
        return
    end

    aggroIndicatorPreviewState[cfg] = not aggroIndicatorPreviewState[cfg]
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
    local normalizedType = NormalizeDispelType(dispelType) or "Magic"
    local field, fallback

    if normalizedType == "Curse" then
        field = "dispelOverlayCurseColor"
        fallback = defaultDispelColors.Curse
    elseif normalizedType == "Disease" then
        field = "dispelOverlayDiseaseColor"
        fallback = defaultDispelColors.Disease
    elseif normalizedType == "Poison" then
        field = "dispelOverlayPoisonColor"
        fallback = defaultDispelColors.Poison
    elseif normalizedType == "Bleed" then
        field = nil
        fallback = defaultDispelColors.Bleed
    else
        field = "dispelOverlayMagicColor"
        fallback = defaultDispelColors.Magic
    end

    local color = field and cfg and cfg[field]
    if type(color) ~= "table" then
        return fallback.r, fallback.g, fallback.b, fallback.a
    end

    return color.r or fallback.r, color.g or fallback.g, color.b or fallback.b, color.a or fallback.a
end

local function GetDispelLookupSignature(r, g, b, a)
    return string.format("%.3f:%.3f:%.3f:%.3f", r or 0, g or 0, b or 0, a or 1)
end

local function CreateDispelColor(r, g, b, a)
    if not _G.CreateColor then
        return nil
    end

    return _G.CreateColor(r or 1, g or 1, b or 1, a or 1)
end

local function GetDispelCurveSignature(cfg)
    local parts = {}

    for _, dispelType in ipairs(knownDispelTypes) do
        local r, g, b, a = GetDispelOverlayColor(cfg, dispelType)
        parts[#parts + 1] = GetDispelLookupSignature(r, g, b, a)
    end

    return table.concat(parts, "|")
end

local function BuildDispelColorCurve(cfg)
    if not cfg or not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not _G.Enum or not _G.Enum.LuaCurveType then
        return nil
    end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(_G.Enum.LuaCurveType.Step)

    for _, dispelType in ipairs(knownDispelTypes) do
        local dispelEnum = dispelEnumByType[dispelType]
        local color = CreateDispelColor(GetDispelOverlayColor(cfg, dispelType))
        if dispelEnum and color then
            curve:AddPoint(dispelEnum, color)
        end
    end

    return curve
end

local function GetDispelColorCurve(cfg)
    if not cfg then
        return nil
    end

    local signature = GetDispelCurveSignature(cfg)
    local cached = dispelCurveCache[cfg]
    if cached and cached.signature == signature then
        return cached.curve
    end

    local curve = BuildDispelColorCurve(cfg)
    dispelCurveCache[cfg] = {
        signature = signature,
        curve = curve,
    }

    return curve
end

local function GetDispelLookupCurve()
    if dispelLookupCurve or not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not _G.Enum or not _G.Enum.LuaCurveType then
        return dispelLookupCurve
    end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(_G.Enum.LuaCurveType.Step)

    for _, dispelType in ipairs(knownDispelTypes) do
        local dispelEnum = dispelEnumByType[dispelType]
        local colorValues = dispelLookupColorByType[dispelType]
        local color = colorValues and CreateDispelColor(colorValues[1], colorValues[2], colorValues[3], colorValues[4])
        if dispelEnum and color then
            curve:AddPoint(dispelEnum, color)
        end
    end

    dispelLookupCurve = curve
    return dispelLookupCurve
end

local function GetActiveDispelAuraInstanceID(activeDispelIcon)
    if not activeDispelIcon then
        return nil
    end

    return activeDispelIcon.mshAuraInstanceID or activeDispelIcon.auraInstanceID
end

local function GetAuraDispelCurveColor(frame, activeDispelIcon, curve)
    local unit = frame and (frame.displayedUnit or frame.unit)
    local auraInstanceID = GetActiveDispelAuraInstanceID(activeDispelIcon)

    if not unit or not auraInstanceID or not C_UnitAuras or not C_UnitAuras.GetAuraDispelTypeColor or not curve then
        return nil, nil, nil, nil
    end

    local okColor, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, curve)
    if not okColor or not color or not color.GetRGBA then
        return nil, nil, nil, nil
    end

    local okRGBA, r, g, b, a = pcall(color.GetRGBA, color)
    if not okRGBA then
        return nil, nil, nil, nil
    end

    return r, g, b, a
end

local function GetAuraDispelTypeFromCurve(frame, activeDispelIcon)
    return nil
end

local function GetConfiguredDispelColor(frame, cfg, activeDispelIcon)
    return GetAuraDispelCurveColor(frame, activeDispelIcon, GetDispelColorCurve(cfg))
end

local function IsUsefulDispelColor(r, g, b)
    return r ~= nil and g ~= nil and b ~= nil
end

local function GetTextureDispelType(textureObject)
    if not textureObject then
        return nil
    end

    local atlasToken = textureObject.GetAtlas and GetStringToken(textureObject:GetAtlas()) or nil
    local dispelType = NormalizeDispelType(atlasToken)
    if dispelType then
        return dispelType
    end

    local textureToken = textureObject.GetTexture and GetStringToken(textureObject:GetTexture()) or nil
    return NormalizeDispelType(textureToken)
end

local function GetNamedDispelTexture(icon, suffix)
    if not icon or not icon.GetName then
        return nil
    end

    local name = icon:GetName()
    if not name or name == "" then
        return nil
    end

    local region = _G[name .. suffix]
    if region and region.IsObjectType and region:IsObjectType("Texture") then
        return region
    end

    return nil
end

local function GetNativeIconBorder(icon)
    if not icon then
        return nil
    end

    return icon.border or icon.Border or icon.IconBorder or GetNamedDispelTexture(icon, "Border") or
        GetNamedDispelTexture(icon, "IconBorder")
end

local function GetPreferredTextureColor(regionOwner)
    if not regionOwner then
        return nil, nil, nil, nil
    end

    if regionOwner.IsObjectType and regionOwner:IsObjectType("Texture") then
        local r, g, b, a = regionOwner:GetVertexColor()
        return r, g, b, a
    end

    if not regionOwner.GetRegions then
        return nil, nil, nil, nil
    end

    local bestR, bestG, bestB, bestA
    local bestScore = -1
    local regions = { regionOwner:GetRegions() }
    for _, region in ipairs(regions) do
        if region and region.IsObjectType and region:IsObjectType("Texture") and region:IsShown() then
            local r, g, b, a = region:GetVertexColor()
            local score = 0
            local regionName = region.GetName and GetStringToken(region:GetName()) or nil
            local atlasToken = region.GetAtlas and GetStringToken(region:GetAtlas()) or nil
            local textureToken = region.GetTexture and GetStringToken(region:GetTexture()) or nil

            if regionName and (string.find(regionName, "border", 1, true) or string.find(regionName, "glow", 1, true)) then
                score = score + 3
            end
            if atlasToken and (string.find(atlasToken, "border", 1, true) or string.find(atlasToken, "glow", 1, true)) then
                score = score + 2
            end
            if textureToken and string.find(textureToken, "border", 1, true) then
                score = score + 2
            end

            if score > bestScore then
                bestScore = score
                bestR, bestG, bestB, bestA = r, g, b, a
            end
        end
    end

    return bestR, bestG, bestB, bestA
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
    return nil
end

local function GetNativeDispelVisual(frame, activeDispelIcon)
    local shown = false
    local r, g, b, a

    if activeDispelIcon then
        shown = activeDispelIcon:IsShown()

        local border = GetNativeIconBorder(activeDispelIcon)
        if border and border.GetVertexColor then
            r, g, b, a = border:GetVertexColor()
        end

        if (not r or not g or not b) and border then
            local texR, texG, texB, texA = GetPreferredTextureColor(border)
            if texR and texG and texB then
                r, g, b, a = texR, texG, texB, texA
            end
        end

        if (not r or not g or not b) then
            local texR, texG, texB, texA = GetPreferredTextureColor(activeDispelIcon)
            if texR and texG and texB then
                r, g, b, a = texR, texG, texB, texA
            end
        end

        if (not r or not g or not b) and activeDispelIcon.icon and activeDispelIcon.icon.GetVertexColor then
            r, g, b, a = activeDispelIcon.icon:GetVertexColor()
        end
    end

    if frame and frame.DispelOverlay then
        shown = shown or frame.DispelOverlay:IsShown()
        local texR, texG, texB, texA = GetPreferredTextureColor(frame.DispelOverlay)
        if texR and texG and texB and (not r or not g or not b) then
            r, g, b, a = texR, texG, texB, texA
        end
    end

    return shown, r, g, b, a
end

local function GetRaidDispelAuraType(frame, cfg)
    local unit = frame and (frame.displayedUnit or frame.unit)
    if not unit or not UnitExists(unit) or not C_UnitAuras or not C_UnitAuras.GetDebuffDataByIndex then
        return nil
    end

    if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
        return nil
    end

    local index = 1
    while true do
        local rawAura = C_UnitAuras.GetDebuffDataByIndex(unit, index, "RAID")
        if not rawAura then
            break
        end

        local spellID = SafeAuraValue(rawAura.spellId) or SafeAuraValue(rawAura.spellID)
        local isExcluded = msh.IsExcludedSpell and msh.IsExcludedSpell(cfg, "excludedDebuffSpellIDs", spellID)
        if not isExcluded then
            local dispelType = NormalizeDispelType(SafeAuraValue(rawAura.dispelName)) or
                NormalizeDispelType(SafeAuraValue(rawAura.dispelType)) or
                NormalizeDispelType(SafeAuraValue(rawAura.debuffType))
            if dispelType then
                return dispelType, spellID
            end
        end

        index = index + 1
    end

    return nil
end

local function ApplySolidDispelOverlay(frame, r, g, b, a, thickness)
    local overlay = frame and frame.mshDispelOverlayFrame
    if not overlay then
        return
    end

    overlay:Show()

    HideAllPixelEdges(overlay)

    for side, texture in pairs(overlay.solidEdges or {}) do
        LayoutOverlayEdge(texture, overlay, side, 0, thickness)
        texture:SetBlendMode("BLEND")
        texture:SetVertexColor(r, g, b, a)
        texture:Show()
    end
end

local function ApplyPixelDispelOverlay(frame, r, g, b, a, thickness, dashLength, dashGap)
    local overlay = frame and frame.mshDispelOverlayFrame
    if not overlay then
        return
    end

    overlay:Show()
    HideEdgeSet(overlay.solidEdges)

    local dashThickness = math.max(1, thickness)
    dashLength = math.max(2, dashLength or (dashThickness * 3))
    dashGap = math.max(1, dashGap or (dashThickness * 2))

    for side, textures in pairs(overlay.pixelEdges or {}) do
        for _, texture in ipairs(textures) do
            texture:SetBlendMode("BLEND")
            texture:SetVertexColor(r, g, b, a)
        end
        LayoutDashedSide(textures, overlay, side, dashThickness, dashLength, dashGap)
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

    local dispelType = NormalizeDispelType(
        (msh.GetAuraDispelType and msh.GetAuraDispelType(icon)) or
        SafeDebugValue(icon.mshDispelType) or
        SafeDebugValue(icon.dispelName) or
        SafeDebugValue(icon.dispelType) or
        SafeDebugValue(icon.debuffType)
    )
    if dispelType then
        return dispelType
    end

    dispelType = GetTextureDispelType(icon.icon)
    if dispelType then
        return dispelType
    end

    dispelType = GetTextureDispelType(GetNativeIconBorder(icon))
    if dispelType then
        return dispelType
    end

    return nil
end

local function GetFrameDispelType(frame)
    local dispelType = NormalizeDispelType(frame and SafeDebugValue(frame.mshLastDispelType))
    if dispelType then
        local activeAuraInstanceID = frame and frame.mshActiveDispelAuraInstanceID
        local lastAuraInstanceID = frame and frame.mshLastDispelAuraInstanceID
        if activeAuraInstanceID and lastAuraInstanceID and SafeEquals(activeAuraInstanceID, lastAuraInstanceID) then
            return dispelType
        end
    end

    return nil
end

local function ResolveDispelType(frame, activeDispelIcon, nativeR, nativeG, nativeB)
    frame.mshActiveDispelAuraInstanceID = GetActiveDispelAuraInstanceID(activeDispelIcon)
    return frame.mshLiveDispelType or GetDispelTypeForIcon(activeDispelIcon) or GetFrameDispelType(frame) or
        GuessDispelTypeFromColor(nativeR, nativeG, nativeB)
end

local function GetDispelTypeIconVisual(dispelType)
    local normalizedType = NormalizeDispelType(dispelType) or "Magic"

    if normalizedType == "Curse" then
        return "icons_16x16_curse", nil
    elseif normalizedType == "Disease" then
        return "icons_16x16_disease", nil
    elseif normalizedType == "Poison" then
        return "icons_16x16_poison", nil
    end

    return "icons_16x16_magic", nil
end

local function SetNativeDispelFramesAlpha(frame, alpha)
    if not frame or not frame.dispelDebuffFrames then
        return
    end

    for i = 1, #frame.dispelDebuffFrames do
        local dispelFrame = frame.dispelDebuffFrames[i]
        if dispelFrame then
            dispelFrame:SetAlpha(alpha)
        end
    end
end

local function ShowDispelIndicator(frame, cfg, atlasName, texturePath, leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord)
    if not frame or not frame.mshDispelIndicator then
        return false
    end

    if frame.mshDispelIndicator.SetAtlas then
        frame.mshDispelIndicator:SetAtlas(nil)
    end
    frame.mshDispelIndicator:SetTexture(nil)
    frame.mshDispelIndicator:SetTexCoord(0, 1, 0, 1)

    if atlasName then
        frame.mshDispelIndicator:SetAtlas(atlasName)
    elseif texturePath then
        frame.mshDispelIndicator:SetTexture(texturePath)
        if leftTexCoord and rightTexCoord and topTexCoord and bottomTexCoord then
            frame.mshDispelIndicator:SetTexCoord(leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord)
        end
    else
        frame.mshDispelIndicator:Hide()
        return false
    end

    local size = cfg.dispelIndicatorSize or 18
    frame.mshDispelIndicator:SetSize(size, size)
    frame.mshDispelIndicator:SetAlpha(cfg.dispelIndicatorAlpha or 1)
    frame.mshDispelIndicator:ClearAllPoints()
    frame.mshDispelIndicator:SetPoint(cfg.dispelIndicatorPoint or "TOPRIGHT", frame, cfg.dispelIndicatorX or 0,
        cfg.dispelIndicatorY or 0)
    frame.mshDispelIndicator:Show()
    return true
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
    local usePreview = previewEnabled
    local liveDispelType = usePreview and nil or GetDispelTypeForIcon(activeDispelIcon) or GetFrameDispelType(frame)
    HideDispelOverlay(frame)
    SetNativeDispelOverlayAlpha(frame, 0)
    frame.mshResolvedDispelType = nil
    frame.mshLiveDispelType = liveDispelType
    frame.mshActiveDispelAuraInstanceID = GetActiveDispelAuraInstanceID(activeDispelIcon)

    if cfg.dispelIndicatorOverlay == false then
        return
    end

    if not usePreview and (globalMode == "0" or (not liveDispelType and not nativeShown) or (not activeDispelIcon and hadShownDispel and not liveDispelType)) then
        return
    end

    local dispelType
    local r, g, b, a

    if usePreview then
        dispelType = NormalizeDispelType(cfg.dispelOverlayPreviewType or "Magic") or "Magic"
        r, g, b, a = GetDispelOverlayColor(cfg, dispelType)
    else
        dispelType = liveDispelType or ResolveDispelType(frame, activeDispelIcon, nativeR, nativeG, nativeB)
        r, g, b, a = GetConfiguredDispelColor(frame, cfg, activeDispelIcon)
        if not r or not g or not b then
            if dispelType then
                r, g, b, a = GetDispelOverlayColor(cfg, dispelType)
            else
                r = nativeR
                g = nativeG
                b = nativeB
                a = nativeA
            end
        end

        if dispelType and (not r or not g or not b) then
            r, g, b, a = GetDispelOverlayColor(cfg, dispelType)
        end
    end

    if not r or not g or not b then
        return
    end

    frame.mshResolvedDispelType = dispelType

    EnsureDispelOverlay(frame)

    local thickness = math.max(1, math.floor(cfg.dispelOverlayThickness or 2))
    local style = cfg.dispelOverlayStyle or "SOLID"
    local dashLength = math.max(2, math.floor(cfg.dispelOverlayDashLength or math.max(4, thickness * 3)))
    local dashGap = math.max(1, math.floor(cfg.dispelOverlayDashGap or math.max(2, thickness * 2)))
    a = a or 0.95

    if style == "PIXEL" then
        ApplyPixelDispelOverlay(frame, r, g, b, a, thickness, dashLength, dashGap)
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
    EnsureAggroIndicator(frame)

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

    UpdateAggroIndicator(frame, cfg)

    if frame.mshDispelIndicator then
        local globalMode = "0"
        local previewEnabled = msh.IsDispelOverlayPreviewEnabled and msh.IsDispelOverlayPreviewEnabled(cfg)
        if msh.db and msh.db.profile and msh.db.profile.global then
            globalMode = msh.db.profile.global.dispelIndicatorMode or "0"
        end

        SetNativeDispelFramesAlpha(frame, 0)

        local blizzIcon, hadShownDispel = GetActiveDispelIcon(frame, cfg)
        local usePreview = previewEnabled
        UpdateDispelOverlay(frame, cfg, blizzIcon, globalMode, hadShownDispel)

        if cfg.showDispelIndicator == false then
            SetNativeDispelFramesAlpha(frame, 0)
            frame.mshDispelIndicator:Hide()
        elseif usePreview then
            local previewAtlas, previewTexture = GetDispelTypeIconVisual(cfg and cfg.dispelOverlayPreviewType)
            if ShowDispelIndicator(frame, cfg, previewAtlas, previewTexture) then
                SetNativeDispelFramesAlpha(frame, 0)
            else
                frame.mshDispelIndicator:Hide()
            end
        elseif globalMode == "0" then
            frame.mshDispelIndicator:Hide()
        else
            local dispelType = frame.mshResolvedDispelType or frame.mshLiveDispelType
            if not dispelType and blizzIcon and blizzIcon:IsShown() and blizzIcon.icon then
                local nativeShown, nativeR, nativeG, nativeB = GetNativeDispelVisual(frame, blizzIcon)
                dispelType = ResolveDispelType(frame, blizzIcon, nativeR, nativeG, nativeB)
            end

            if dispelType then
                local atlasName, texturePath = GetDispelTypeIconVisual(dispelType)
                local leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord = 0, 1, 0, 1
                if blizzIcon and blizzIcon.icon and blizzIcon.icon.GetTexCoord then
                    leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord = blizzIcon.icon:GetTexCoord()
                end

                if ShowDispelIndicator(frame, cfg, atlasName, texturePath or blizzIcon.icon:GetTexture(),
                        leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord) then
                    if blizzIcon then
                        blizzIcon:SetAlpha(0)
                    end
                else
                    frame.mshDispelIndicator:Hide()
                end
            elseif blizzIcon and blizzIcon:IsShown() and blizzIcon.icon then
                local leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord = 0, 1, 0, 1
                if blizzIcon.icon.GetTexCoord then
                    leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord = blizzIcon.icon:GetTexCoord()
                end

                if ShowDispelIndicator(frame, cfg, nil, blizzIcon.icon:GetTexture(),
                        leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord) then
                    blizzIcon:SetAlpha(0)
                else
                    frame.mshDispelIndicator:Hide()
                end
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
