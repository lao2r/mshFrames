local addonName, ns = ...

local msh = LibStub("AceAddon-3.0"):NewAddon(ns, addonName, "AceEvent-3.0")
local spellIDListCache = setmetatable({}, { __mode = "k" })
local emptyTable = {}
local roleSortQueued = false
local roleSortPending = false
local roleSortSlotTolerance = 4
local roleSortModes = {
    TANK_HEALER_DAMAGER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 },
    TANK_DAMAGER_HEALER = { TANK = 1, DAMAGER = 2, HEALER = 3, NONE = 4 },
    HEALER_TANK_DAMAGER = { HEALER = 1, TANK = 2, DAMAGER = 3, NONE = 4 },
    HEALER_DAMAGER_TANK = { HEALER = 1, DAMAGER = 2, TANK = 3, NONE = 4 },
    DAMAGER_TANK_HEALER = { DAMAGER = 1, TANK = 2, HEALER = 3, NONE = 4 },
    DAMAGER_HEALER_TANK = { DAMAGER = 1, HEALER = 2, TANK = 3, NONE = 4 },
}

local function GetSpellNameByID(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end

    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end

    return nil
end

local function ParseSpellIDList(rawValue)
    local normalizedList = {}
    local spellIDSet = {}
    local spellNameSet = {}
    local spellNameList = {}

    if type(rawValue) ~= "string" then
        return nil, nil, ""
    end

    for token in rawValue:gmatch("[^,%s;]+") do
        local spellID = tonumber(token)
        if spellID then
            spellID = math.floor(spellID)
            if spellID > 0 and not spellIDSet[spellID] then
                spellIDSet[spellID] = true
                local spellName = GetSpellNameByID(spellID)
                if spellName and spellName ~= "" and not spellNameSet[spellName] then
                    spellNameSet[spellName] = true
                    table.insert(spellNameList, spellName)
                end
                table.insert(normalizedList, spellID)
            end
        end
    end

    if #normalizedList == 0 then
        return nil, nil, ""
    end

    return normalizedList, spellNameList, table.concat(normalizedList, ", ")
end

function msh.NormalizeSpellIDList(rawValue)
    local _, _, normalized = ParseSpellIDList(rawValue)
    return normalized
end

local function GetExcludedSpellEntry(cfg, field)
    if not cfg or not field then
        return nil
    end

    local rawValue = cfg[field] or ""
    local cacheEntry = spellIDListCache[cfg]

    if not cacheEntry then
        cacheEntry = {}
        spellIDListCache[cfg] = cacheEntry
    end

    if not cacheEntry[field] or cacheEntry[field].rawValue ~= rawValue then
        local spellIDs, spellNames = ParseSpellIDList(rawValue)
        cacheEntry[field] = {
            rawValue = rawValue,
            spellIDs = spellIDs,
            spellNames = spellNames,
        }
    end

    return cacheEntry[field]
end

function msh.GetExcludedSpellIDSet(cfg, field)
    local entry = GetExcludedSpellEntry(cfg, field)
    return entry and entry.spellIDs or nil
end

function msh.IsExcludedSpell(cfg, field, spellID)
    if not spellID then
        return false
    end

    local entry = GetExcludedSpellEntry(cfg, field)
    if not entry then
        return false
    end

    for _, excludedSpellID in ipairs(entry.spellIDs or emptyTable) do
        local ok, matches = pcall(function()
            return spellID == excludedSpellID
        end)
        if ok and matches then
            return true
        end
    end

    local okName, spellName = pcall(GetSpellNameByID, spellID)
    if okName and spellName then
        for _, excludedSpellName in ipairs(entry.spellNames or emptyTable) do
            local okMatch, matches = pcall(function()
                return spellName == excludedSpellName
            end)
            if okMatch and matches then
                return true
            end
        end
    end

    return false
end

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

local function GetRoleSortPriority(cfg, frame)
    local modePriorities = cfg and roleSortModes[cfg.roleSortMode or "DEFAULT"] or nil
    if not modePriorities then
        return nil
    end

    local unit = frame and (frame.displayedUnit or frame.unit)
    local role = unit and UnitExists(unit) and UnitGroupRolesAssigned(unit) or "NONE"
    return modePriorities[role or "NONE"] or modePriorities.NONE or 4
end

local function CompareRoleSortSlots(left, right)
    if math.abs(left.y - right.y) > roleSortSlotTolerance then
        return left.y > right.y
    end

    if math.abs(left.x - right.x) > roleSortSlotTolerance then
        return left.x < right.x
    end

    return left.order < right.order
end

local function CollectRoleSortContainers()
    local containers = {}
    local seenFrames = {}

    local function AddFrame(frame)
        if not frame or seenFrames[frame] or frame:IsForbidden() or not frame:IsShown() then
            return
        end

        local cfg = msh.GetConfigForFrame(frame)
        if not cfg or (cfg.roleSortMode or "DEFAULT") == "DEFAULT" then
            return
        end

        local priority = GetRoleSortPriority(cfg, frame)
        if not priority then
            return
        end

        local parent = frame:GetParent()
        local centerX, centerY = frame:GetCenter()
        local parentLeft, parentBottom = parent and parent:GetLeft(), parent and parent:GetBottom()
        if not parent or not centerX or not centerY or not parentLeft or not parentBottom then
            return
        end

        seenFrames[frame] = true

        local bucket = containers[parent]
        if not bucket then
            bucket = { frames = {} }
            containers[parent] = bucket
        end

        bucket.frames[#bucket.frames + 1] = {
            frame = frame,
            priority = priority,
            order = #bucket.frames + 1,
            x = centerX - parentLeft,
            y = centerY - parentBottom,
            unit = frame.displayedUnit or frame.unit or "",
        }
    end

    for i = 1, 5 do
        AddFrame(_G["CompactPartyFrameMember" .. i])
    end

    for i = 1, 40 do
        AddFrame(_G["CompactRaidFrame" .. i])
    end

    for groupIndex = 1, 8 do
        for memberIndex = 1, 5 do
            AddFrame(_G["CompactRaidGroup" .. groupIndex .. "Member" .. memberIndex])
        end
    end

    return containers
end

function msh.ApplyRoleSorting()
    if InCombatLockdown and InCombatLockdown() then
        roleSortPending = true
        return
    end

    roleSortPending = false

    for parent, bucket in pairs(CollectRoleSortContainers()) do
        local frames = bucket.frames
        if parent and frames and #frames > 1 then
            local slots = {}
            local orderedFrames = {}

            for index, entry in ipairs(frames) do
                slots[index] = {
                    x = entry.x,
                    y = entry.y,
                    order = entry.order,
                }
                orderedFrames[index] = entry
            end

            table.sort(slots, CompareRoleSortSlots)
            table.sort(orderedFrames, function(left, right)
                if left.priority ~= right.priority then
                    return left.priority < right.priority
                end

                if left.order ~= right.order then
                    return left.order < right.order
                end

                return left.unit < right.unit
            end)

            for index, entry in ipairs(orderedFrames) do
                local slot = slots[index]
                if slot then
                    entry.frame:ClearAllPoints()
                    entry.frame:SetPoint("CENTER", parent, "BOTTOMLEFT", slot.x, slot.y)
                end
            end
        end
    end
end

function msh.QueueRoleSort()
    if InCombatLockdown and InCombatLockdown() then
        roleSortPending = true
        return
    end

    if roleSortQueued then
        return
    end

    roleSortQueued = true
    C_Timer.After(0, function()
        roleSortQueued = false
        msh.ApplyRoleSorting()
    end)
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
        if msh.UpdateUnitDisplay then
            msh.UpdateUnitDisplay(frame)
        end
    end
end)

hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
    msh.ApplyStyle(frame)
    if msh.QueueRoleSort then
        msh.QueueRoleSort()
    end
end)

hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
    local cfg = msh.GetConfigForFrame(frame)
    if cfg and frame.mshLayersCreated then
        ns.cfg = cfg
        msh.UpdateUnitDisplay(frame)
    end
end)

if CompactUnitFrame_UpdateAggroHighlight then
    hooksecurefunc("CompactUnitFrame_UpdateAggroHighlight", function(frame)
        local cfg = msh.GetConfigForFrame(frame)
        if cfg and frame.mshLayersCreated and msh.UpdateUnitDisplay then
            ns.cfg = cfg
            msh.UpdateUnitDisplay(frame)
        end
    end)
end

function msh.UpdateVisibleUnitFrames(unit)
    local function UpdateFrame(frame)
        if not frame or not frame:IsShown() or not frame.mshLayersCreated then
            return
        end

        local frameUnit = frame.displayedUnit or frame.unit
        if unit and frameUnit ~= unit then
            return
        end

        msh.UpdateUnitDisplay(frame)
    end

    for i = 1, 5 do
        UpdateFrame(_G["CompactPartyFrameMember" .. i])
    end

    for i = 1, 40 do
        UpdateFrame(_G["CompactRaidFrame" .. i])
    end

    for g = 1, 8 do
        for m = 1, 5 do
            UpdateFrame(_G["CompactRaidGroup" .. g .. "Member" .. m])
        end
    end
end

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

    if CompactUnitFrameProfiles_ApplyCurrentSettings then
        hooksecurefunc("CompactUnitFrameProfiles_ApplyCurrentSettings", function()
            if msh.QueueRoleSort then
                msh.QueueRoleSort()
            end
        end)
    end

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

    self:RegisterEvent("PLAYER_ROLES_ASSIGNED", function()
        C_Timer.After(0.1, function()
            msh:Refresh()
        end)
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if roleSortPending and msh.QueueRoleSort then
            msh.QueueRoleSort()
        end
    end)

    self:RegisterEvent("RAID_TARGET_UPDATE", function()
        msh.UpdateVisibleUnitFrames()
    end)

    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", function(_, unit)
        msh.UpdateVisibleUnitFrames(unit)
    end)

    self:RegisterEvent("UNIT_THREAT_LIST_UPDATE", function(_, unit)
        msh.UpdateVisibleUnitFrames(unit)
    end)
end
