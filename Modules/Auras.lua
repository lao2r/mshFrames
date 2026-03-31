local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")


local isSetting = false
local auraSpellIDCache = setmetatable({}, { __mode = "k" })
local auraDispelTypeBySpellID = {}
local knownDispelTypes = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local dispelTypeAliases
local SafeEquals

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

local function IsManagedAuraFrame(frame)
    return frame and msh.GetConfigForFrame and msh.GetConfigForFrame(frame) ~= nil
end

local function GetAuraCacheBucket(frame)
    if not frame then
        return nil
    end

    local bucket = auraSpellIDCache[frame]
    if not bucket then
        bucket = {}
        auraSpellIDCache[frame] = bucket
    end

    return bucket
end

local function GetCachedAuraEntry(frame, auraInstanceID)
    if not auraInstanceID then
        return
    end

    local bucket = GetAuraCacheBucket(frame)
    return bucket and bucket[auraInstanceID] or nil
end

local function CacheAuraData(frame, auraInstanceID, spellID, dispelType)
    if not auraInstanceID then
        return
    end

    local bucket = GetAuraCacheBucket(frame)
    if bucket then
        local entry = bucket[auraInstanceID]
        if not entry then
            entry = {}
            bucket[auraInstanceID] = entry
        end

        if spellID then
            entry.spellID = spellID
        end

        if dispelType then
            entry.dispelType = dispelType
        end
    end
end

local function GetCachedAuraSpellID(frame, auraInstanceID)
    local entry = GetCachedAuraEntry(frame, auraInstanceID)
    return entry and entry.spellID or nil
end

local function GetCachedAuraDispelType(frame, auraInstanceID)
    local entry = GetCachedAuraEntry(frame, auraInstanceID)
    return entry and entry.dispelType or nil
end

local function ClearCachedAuraData(frame, auraInstanceID)
    local bucket = GetAuraCacheBucket(frame)
    if bucket and auraInstanceID then
        bucket[auraInstanceID] = nil
    end

    if frame and frame.mshLastDispelAuraInstanceID and SafeEquals(frame.mshLastDispelAuraInstanceID, auraInstanceID) then
        frame.mshLastDispelAuraInstanceID = nil
        frame.mshLastDispelType = nil
    end
end

local function ClearAuraCache(frame)
    if frame then
        auraSpellIDCache[frame] = nil
        frame.mshLastDispelAuraInstanceID = nil
        frame.mshLastDispelType = nil
    end
end

local function UpdateCooldownFont(button, fontPath, size)
    if button and button.cooldown then
        local cdText = button.cooldown:GetRegions()
        if cdText and cdText.SetFont then
            local safeSize = (size and size > 0) and size or 10
            local safeFont = (fontPath and fontPath ~= "") and fontPath or [[Fonts\FRIZQT__.TTF]]
            cdText:SetFont(safeFont, safeSize, "OUTLINE")
        end
    end
end

SafeEquals = function(left, right)
    local ok, matches = pcall(function()
        return left == right
    end)

    return ok and matches
end

local function GetDispelValueToken(value)
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

    if ok and type(token) == "string" and token ~= "" then
        return token
    end

    return nil
end

local function GetDispelValueText(value)
    if value == nil then
        return nil
    end

    local ok, textValue = pcall(function()
        local coercedValue = string.format("%s", value)
        if type(coercedValue) ~= "string" or coercedValue == "" then
            return nil
        end

        return coercedValue
    end)

    if ok and type(textValue) == "string" and textValue ~= "" then
        return textValue
    end

    return nil
end

local function GetStableValueKey(value)
    local textValue = GetDispelValueText(value)
    if textValue and textValue ~= "" then
        return textValue
    end

    return nil
end

local function NormalizeAuraDispelType(value)
    local token = GetDispelValueToken(value)
    if not token then
        return nil
    end

    for _, dispelType in ipairs(knownDispelTypes) do
        local aliases = dispelTypeAliases[dispelType]
        if aliases then
            for _, alias in ipairs(aliases) do
                local aliasToken = string.lower(tostring(alias))
                local ok, matches = pcall(function()
                    return aliasToken and string.find(token, aliasToken, 1, true) ~= nil
                end)
                if ok and matches then
                    return dispelType
                end
            end
        end
    end

    return nil
end

local function IsAuraButtonFrame(frame)
    return type(frame) == "table" and frame.IsObjectType and frame:IsObjectType("Frame") and
        (frame.icon ~= nil or frame.Icon ~= nil or frame.cooldown ~= nil or frame.border ~= nil or frame.IconBorder ~= nil)
end

local function IsDispelDebuffButton(parent, button)
    if not parent or not button or not parent.dispelDebuffFrames then
        return false
    end

    for i = 1, #parent.dispelDebuffFrames do
        if SafeEquals(parent.dispelDebuffFrames[i], button) then
            return true
        end
    end

    return false
end

local function TrackAuraSpellID(button, aura, explicitDispelType)
    if not button then return end

    local parent = button:GetParent()
    if not IsManagedAuraFrame(parent) then
        return
    end

    local auraInstanceID = button.auraInstanceID or button.mshAuraInstanceID
    local spellID
    local dispelText = GetDispelValueText(explicitDispelType)
    local dispelType = NormalizeAuraDispelType(dispelText)

    if type(aura) == "table" then
        auraInstanceID = aura.auraInstanceID or auraInstanceID
        spellID = aura.spellId or aura.spellID
        dispelText = dispelText or GetDispelValueText(aura.dispelName) or GetDispelValueText(aura.dispelType) or
            GetDispelValueText(aura.debuffType)
        dispelType = dispelType or NormalizeAuraDispelType(dispelText)
    end

    if auraInstanceID then
        CacheAuraData(parent, auraInstanceID, spellID, dispelType)
        spellID = spellID or GetCachedAuraSpellID(parent, auraInstanceID)
        dispelType = dispelType or GetCachedAuraDispelType(parent, auraInstanceID)
    end

    if spellID and dispelType then
        local cacheKey = GetStableValueKey(spellID)
        if cacheKey then
            auraDispelTypeBySpellID[cacheKey] = dispelType
        end
    end

    button.mshAuraInstanceID = auraInstanceID
    button.mshSpellID = spellID
    button.mshDispelType = dispelType or dispelText

    if dispelType and IsDispelDebuffButton(parent, button) then
        parent.mshLastDispelType = dispelType
        parent.mshLastDispelAuraInstanceID = auraInstanceID
    end
end

local function GetAuraSpellID(icon)
    if not icon then return nil end

    local spellID = icon.mshSpellID or icon.spellID or icon.spellId
    if spellID then
        return spellID
    end

    local auraInstanceID = icon.mshAuraInstanceID or icon.auraInstanceID
    if not auraInstanceID then
        return nil
    end

    return GetCachedAuraSpellID(icon:GetParent(), auraInstanceID)
end

function msh.GetAuraSpellID(icon)
    return GetAuraSpellID(icon)
end

function msh.GetAuraDispelType(icon)
    if not icon then
        return nil
    end

    local dispelType = NormalizeAuraDispelType(GetDispelValueText(icon.mshDispelType)) or
        NormalizeAuraDispelType(GetDispelValueText(icon.dispelName)) or
        NormalizeAuraDispelType(GetDispelValueText(icon.dispelType)) or
        NormalizeAuraDispelType(GetDispelValueText(icon.debuffType))

    if dispelType then
        return dispelType
    end

    local auraInstanceID = icon.mshAuraInstanceID or icon.auraInstanceID
    if auraInstanceID then
        dispelType = GetCachedAuraDispelType(icon:GetParent(), auraInstanceID)
        if dispelType then
            return dispelType
        end
    end

    local spellID = GetAuraSpellID(icon)
    if not spellID then
        return nil
    end

    local cacheKey = GetStableValueKey(spellID)
    return cacheKey and auraDispelTypeBySpellID[cacheKey] or nil
end

local function ResolveAuraHookArgs(...)
    local button
    local aura
    local dispelType

    for i = 1, select("#", ...) do
        local arg = select(i, ...)
        if type(arg) == "table" and arg.IsObjectType and arg:IsObjectType("Frame") then
            if IsAuraButtonFrame(arg) then
                button = arg
            elseif not button then
                button = arg
            end
        elseif not aura and type(arg) == "table" and (arg.auraInstanceID or arg.spellId or arg.spellID or arg.dispelName or arg.dispelType or arg.debuffType) then
            aura = arg
        elseif not dispelType then
            dispelType = NormalizeAuraDispelType(GetDispelValueText(arg))
        end
    end

    return button, aura, dispelType
end

if CompactUnitFrame_UtilSetBuff then
    hooksecurefunc("CompactUnitFrame_UtilSetBuff", function(...)
        local buffFrame, aura = ResolveAuraHookArgs(...)
        TrackAuraSpellID(buffFrame, aura)
    end)
end

if CompactUnitFrame_UtilSetDebuff then
    hooksecurefunc("CompactUnitFrame_UtilSetDebuff", function(...)
        local debuffFrame, aura = ResolveAuraHookArgs(...)
        TrackAuraSpellID(debuffFrame, aura)
    end)
end

if CompactUnitFrame_UtilSetDispelDebuff then
    hooksecurefunc("CompactUnitFrame_UtilSetDispelDebuff", function(...)
        local dispellDebuffFrame, aura, dispelType = ResolveAuraHookArgs(...)
        TrackAuraSpellID(dispellDebuffFrame, aura, dispelType)
    end)
end

if CompactUnitFrame_UpdateAuras then
    hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame, unitAuraUpdateInfo)
        if not frame or frame:IsForbidden() or not IsManagedAuraFrame(frame) or not unitAuraUpdateInfo then
            return
        end

        if unitAuraUpdateInfo.isFullUpdate then
            ClearAuraCache(frame)
        end

        if unitAuraUpdateInfo.removedAuraInstanceIDs then
            for _, auraInstanceID in ipairs(unitAuraUpdateInfo.removedAuraInstanceIDs) do
                ClearCachedAuraData(frame, auraInstanceID)
            end
        end
    end)
end

if CompactUnitFrame_SetUnit then
    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
        if frame and not frame:IsForbidden() and IsManagedAuraFrame(frame) then
            ClearAuraCache(frame)
        end
    end)
end

function msh.UpdateAuras(frame)
    if not frame or frame:IsForbidden() or isSetting then return end

    local cfg = msh.GetConfigForFrame(frame)
    if not cfg or not msh.db or not msh.db.profile then return end

    isSetting = true
    local ok, err = xpcall(function()
        local globalFont = msh.db.profile.globalFont
        local globalShowDebuffs = msh.db.profile.global.showDebuffs
        local globalShowBigSave = msh.db.profile.global.showBigSave
        local localFont = cfg.fontName
        local activeFont = (localFont and localFont ~= "Default" and localFont ~= "") and localFont or globalFont
        local fontPath = LSM:Fetch("font", activeFont or "Friz Quadrata TT")
        local centerStatusIcon = frame.CenterDefensiveBuff or frame.centerStatusIcon

        local auraSettings = {
            {
                pool = frame.buffFrames,
                enabled = cfg.showBuffs,
                isBlizz = cfg.useBlizzBuffs,
                isCustom = cfg.showCustomBuffs,
                size = cfg.buffSize,
                point = cfg.buffPoint,
                x = cfg.buffX,
                y = cfg.buffY,
                grow = cfg.buffGrow,
                space = cfg.buffSpacing,
                timer = cfg.showbuffTimer,
                textScale = cfg.buffTextScale,
                showtooltip = cfg.showBuffsTooltip,
                alpha = cfg.buffAlpha or 1,
                excludedField = "excludedBuffSpellIDs",
            },
            {
                pool = frame.debuffFrames,
                enabled = globalShowDebuffs,
                isBlizz = cfg.useBlizzDebuffs,
                isCustom = cfg.showCustomDebuffs,
                size = cfg.debuffSize,
                point = cfg.debuffPoint,
                x = cfg.debuffX,
                y = cfg.debuffY,
                grow = cfg.debuffGrow,
                space = cfg.debuffSpacing,
                timer = cfg.showDebuffTimer,
                textScale = cfg.debuffTextScale,
                showtooltip = cfg.showDebuffsTooltip,
                alpha = cfg.debuffAlpha or 1,
                excludedField = "excludedDebuffSpellIDs",
            },
            {
                pool = { centerStatusIcon },
                enabled = globalShowBigSave,
                isBlizz = cfg.useBlizzBigSave,
                isCustom = cfg.showCustomBigSave,
                size = cfg.bigSaveSize,
                point = cfg.bigSavePoint,
                x = cfg.bigSaveX,
                y = cfg.bigSaveY,
                grow = "RIGHT",
                space = 0,
                timer = cfg.showBigSaveTimer,
                textScale = cfg.bigSaveTextScale,
                showtooltip = cfg.showBigSaveTooltip,
                alpha = cfg.bigSaveAlpha or 1,
                excludedField = "excludedBuffSpellIDs",
            }
        }

        for _, data in ipairs(auraSettings) do
            local pool = data.pool
            local isBlizz = data.isBlizz
            if pool then
                local previousIcon = nil

                if not data.enabled then
                    for i = 1, #pool do
                        if pool[i] then pool[i]:Hide() end
                    end
                else
                    for i = 1, #pool do
                        local icon = pool[i]
                        if icon and icon:IsShown() then
                            local spellID = GetAuraSpellID(icon)
                            local isExcluded = msh.IsExcludedSpell and msh.IsExcludedSpell(cfg, data.excludedField, spellID)

                            if isExcluded then
                                icon:Hide()
                            else
                                icon:EnableMouse(data.showtooltip)
                                icon:SetAlpha(data.alpha)

                                if data.isCustom or (data.pool[1] == centerStatusIcon) then
                                    local currentSize = data.size or 20
                                    icon:SetSize(currentSize, currentSize)
                                else
                                    if not (data.isBlizz and data.pool == frame.debuffFrames) then
                                        icon:SetSize(data.size or 18, data.size or 18)
                                    end
                                end

                                if not isBlizz then
                                    icon:ClearAllPoints()
                                    if not previousIcon then
                                        icon:SetPoint(data.point, frame, data.point, data.x, data.y)
                                    else
                                        local anchor, rel, offX, offY = "LEFT", "RIGHT", (data.space or 2), 0
                                        if data.grow == "LEFT" then
                                            anchor, rel, offX = "RIGHT", "LEFT", -(data.space or 2)
                                        elseif data.grow == "UP" then
                                            anchor, rel, offX, offY = "BOTTOM", "TOP", 0, (data.space or 2)
                                        elseif data.grow == "DOWN" then
                                            anchor, rel, offX, offY = "TOP", "BOTTOM", 0, -(data.space or 2)
                                        end
                                        icon:SetPoint(anchor, previousIcon, rel, offX, offY)
                                    end
                                    previousIcon = icon
                                end

                                if icon.cooldown then
                                    icon.cooldown:SetHideCountdownNumbers(not data.timer)
                                    local currentWidth = icon:GetWidth()
                                    local fontSize = currentWidth * (data.textScale or 0.7)
                                    UpdateCooldownFont(icon, fontPath, fontSize)
                                end
                            end
                        end
                    end
                end
            end
        end
    end, geterrorhandler())

    isSetting = false
    if not ok then
        return
    end
end
