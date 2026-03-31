local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")


local isSetting = false

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

function msh.UpdateAuras(frame)
    if not frame or frame:IsForbidden() or isSetting then return end

    local cfg = msh.GetConfigForFrame(frame)
    if not cfg or not msh.db or not msh.db.profile then return end

    isSetting = true

    local globalFont = msh.db.profile.globalFont
    local globalShowDebuffs = msh.db.profile.global.showDebuffs
    local globalShowBigSave = msh.db.profile.global.showBigSave
    local localFont = cfg.fontName
    local activeFont = (localFont and localFont ~= "Default" and localFont ~= "") and localFont or globalFont
    local fontPath = LSM:Fetch("font", activeFont or "Friz Quadrata TT")


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
        },
        {
            pool = { frame.CenterDefensiveBuff or frame.centerStatusIcon },
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
        }
    }

    for _, data in ipairs(auraSettings) do
        local pool = data.pool
        local isBlizz = data.isBlizz
        if pool then
            local previousIcon = nil


            if not data.enabled then
                for i = 1, #pool do if pool[i] then pool[i]:Hide() end end
            else
                for i = 1, #pool do
                    local icon = pool[i]
                    if icon and icon:IsShown() then
                        icon:EnableMouse(data.showtooltip)
                        icon:SetAlpha(data.alpha)

                        if data.isCustom or (data.pool[1] == (frame.CenterDefensiveBuff or frame.centerStatusIcon)) then
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

    isSetting = false
end
