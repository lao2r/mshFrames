local _, ns = ...
local msh = ns
local LSM = LibStub("LibSharedMedia-3.0")

function msh.CreateUnitLayers(frame)
    if frame.mshLayersCreated then return end

    frame.mshName = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall", 8)
    if frame.name then frame.name:SetAlpha(0) end

    frame.mshRole = frame:CreateTexture(nil, "OVERLAY", nil, 5)
    frame.mshRaidIcon = frame:CreateTexture(nil, "OVERLAY", nil, 5)
    frame.mshLeader = frame:CreateTexture(nil, "OVERLAY", nil, 5)
    frame.mshDispelIndicator = frame:CreateTexture(nil, "OVERLAY", nil, 5)

    if frame.leaderIcon then frame.leaderIcon:SetAlpha(0) end

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
        if globalMode == "0" then
            frame.mshDispelIndicator:Hide()
        else
            local blizzIcon = frame.dispelDebuffFrames and frame.dispelDebuffFrames[1]

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
