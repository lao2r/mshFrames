local addonName, ns = ...

local msh = LibStub("AceAddon-3.0"):NewAddon(ns, addonName, "AceEvent-3.0")

function msh.GetConfigForFrame(frame)
    if not msh.db or not msh.db.profile then
        return {}
    end

    if not frame or frame:IsForbidden() then return nil end

    local name = frame:GetName() or ""

    if name:find("CompactRaidGroup") or name:find("CompactRaidFrame") then
        return msh.db.profile.raid
    elseif name:find("CompactParty") then
        return msh.db.profile.party
    end


    return nil
end

function msh.ApplyStyle(frame)
    if not msh.db then return end
    if not frame or frame:IsForbidden() then return end

    local cfg = msh.GetConfigForFrame(frame)
    if not cfg then return end

    ns.cfg = cfg

    if msh.CreateUnitLayers then msh.CreateUnitLayers(frame) end
    if msh.CreateHealthLayers then msh.CreateHealthLayers(frame) end

    msh.UpdateUnitDisplay(frame)
    msh.UpdateHealthDisplay(frame)
    if msh.UpdateAuras then msh.UpdateAuras(frame) end
end

hooksecurefunc("CompactUnitFrame_UpdateHealth", function(frame)
    local cfg = msh.GetConfigForFrame(frame)
    if cfg and frame.mshHealthCreated then
        ns.cfg = cfg
        msh.UpdateHealthDisplay(frame)
    end
end)

hooksecurefunc("CompactUnitFrame_UpdateStatusText", function(frame)
    local cfg = msh.GetConfigForFrame(frame)
    if cfg and frame.mshLayersCreated then
        ns.cfg = cfg
        msh.UpdateUnitDisplay(frame)
    end
end)

hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
    if frame.mshLayersCreated and msh.UpdateAuras then
        msh.UpdateAuras(frame)
    end
end)

hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
    msh.ApplyStyle(frame)
end)

hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
    local cfg = msh.GetConfigForFrame(frame)
    if cfg and frame.mshLayersCreated then
        ns.cfg = cfg
        msh.UpdateUnitDisplay(frame)
    end
end)

function msh:Refresh()
    for i = 1, 5 do
        local pf = _G["CompactPartyFrameMember" .. i]
        if pf then msh.ApplyStyle(pf) end
    end


    for i = 1, 40 do
        local rf = _G["CompactRaidFrame" .. i]
        if rf then msh.ApplyStyle(rf) end
    end

    for g = 1, 8 do
        for m = 1, 5 do
            local rfg = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if rfg then msh.ApplyStyle(rfg) end
        end
    end

    if msh.SyncBlizzardSettings then msh.SyncBlizzardSettings() end
end

function msh:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if msh.SyncBlizzardSettings then msh.SyncBlizzardSettings() end
        C_Timer.After(0.5, function() msh:Refresh() end)
    end)

    if _G.EditMode and _G.EditMode.Exit then
        hooksecurefunc(_G.EditMode, "Exit", function() msh:Refresh() end)
    end

    if _G.EditModeManagerFrame and _G.EditModeManagerFrame.UpdateLayoutInfo then
        hooksecurefunc(_G.EditModeManagerFrame, "UpdateLayoutInfo", function() msh:Refresh() end)
    end

    self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        C_Timer.After(0.1, function()
            msh:Refresh()
        end)
    end)

    self:RegisterEvent("RAID_TARGET_UPDATE", function()
        for i = 1, 5 do
            local pf = _G["CompactPartyFrameMember" .. i]
            if pf and pf:IsShown() and pf.mshLayersCreated then
                msh.UpdateUnitDisplay(pf)
            end
        end

        for i = 1, 40 do
            local rf = _G["CompactRaidFrame" .. i]
            if rf and rf:IsShown() and rf.mshLayersCreated then
                msh.UpdateUnitDisplay(rf)
            end
        end

        for g = 1, 8 do
            for m = 1, 5 do
                local rfg = _G["CompactRaidGroup" .. g .. "Member" .. m]
                if rfg and rfg:IsShown() and rfg.mshLayersCreated then
                    msh.UpdateUnitDisplay(rfg)
                end
            end
        end
    end)
end
