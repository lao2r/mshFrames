local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")


local isSetting = false
local auraSpellIDCache = setmetatable({}, { __mode = "k" })

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

local function CacheAuraSpellID(frame, auraInstanceID, spellID)
    if not auraInstanceID or not spellID then
        return
    end

    local bucket = GetAuraCacheBucket(frame)
    if bucket then
        bucket[auraInstanceID] = spellID
    end
end

local function GetCachedAuraSpellID(frame, auraInstanceID)
    if not auraInstanceID then
        return nil
    end

    local bucket = GetAuraCacheBucket(frame)
    return bucket and bucket[auraInstanceID] or nil
end

local function ClearCachedAuraSpellID(frame, auraInstanceID)
    local bucket = GetAuraCacheBucket(frame)
    if bucket and auraInstanceID then
        bucket[auraInstanceID] = nil
    end
end

local function ClearAuraCache(frame)
    if frame then
        auraSpellIDCache[frame] = nil
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

local function TrackAuraSpellID(button, aura)
    if not button then return end

    if type(aura) == "table" then
        local parent = button:GetParent()
        if not IsManagedAuraFrame(parent) then
            return
        end

        local auraInstanceID = aura.auraInstanceID
        local spellID = aura.spellId or aura.spellID

        button.mshAuraInstanceID = auraInstanceID
        if spellID then
            CacheAuraSpellID(parent, auraInstanceID, spellID)
        else
            spellID = GetCachedAuraSpellID(parent, auraInstanceID)
        end

        button.mshSpellID = spellID
        button.mshDispelType = aura.dispelName or aura.dispelType or aura.debuffType
    else
        button.mshSpellID = nil
        button.mshAuraInstanceID = nil
        button.mshDispelType = nil
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

    return icon.mshDispelType or icon.dispelName or icon.dispelType or icon.debuffType
end

if CompactUnitFrame_UtilSetBuff then
    hooksecurefunc("CompactUnitFrame_UtilSetBuff", function(buffFrame, aura)
        TrackAuraSpellID(buffFrame, aura)
    end)
end

if CompactUnitFrame_UtilSetDebuff then
    hooksecurefunc("CompactUnitFrame_UtilSetDebuff", function(_, debuffFrame, aura)
        TrackAuraSpellID(debuffFrame, aura)
    end)
end

if CompactUnitFrame_UtilSetDispelDebuff then
    hooksecurefunc("CompactUnitFrame_UtilSetDispelDebuff", function(_, dispellDebuffFrame, aura)
        TrackAuraSpellID(dispellDebuffFrame, aura)
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
                ClearCachedAuraSpellID(frame, auraInstanceID)
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
