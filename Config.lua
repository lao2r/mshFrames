local addonName, ns = ...
local msh = ns
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local LibS = LibStub("LibSerialize")
local LibD = LibStub("LibDeflate")
local L = LibStub("AceLocale-3.0"):GetLocale("mshFrames")

ns.needsReload = false

local reloadWarning = {
    type = "description",
    name = "\n|cffff0000" .. L["ВНИМАНИЕ:"] .. "|r " .. L["Требуется /reload для применения настроек."] .. "\n",
    fontSize = "medium",
    order = 0,
    hidden = function() return not ns.needsReload end,
}
local anchorPoints = {
    ["TOPLEFT"] = L["Сверху слева"],
    ["TOP"] = L["Сверху"],
    ["TOPRIGHT"] = L["Сверху справа"],
    ["LEFT"] = L["Слева"],
    ["CENTER"] = L["Центр"],
    ["RIGHT"] = L["Справа"],
    ["BOTTOMLEFT"] = L["Снизу слева"],
    ["BOTTOM"] = L["Снизу"],
    ["BOTTOMRIGHT"] = L["Снизу справа"],
}
local outlineModes = {
    ["NONE"] = L["Нет"],
    ["OUTLINE, SLUG"] = L["Тонкий Красивый"],
    ["OUTLINE"] = L["Тонкий Уродский"],
    ["THICKOUTLINE"] = L["Жирный"],
    ["MONOCHROME"] = L["Пиксельный"],
}
local outlineOrder = {
    "NONE",
    "OUTLINE, SLUG",
    "OUTLINE",
    "THICKOUTLINE",
    "MONOCHROME"
}

local function AddAuraControls(args, path, key, label, customColor)
    local toggleKey = "show" .. key
    local blizzKey = "useBlizz" .. key
    local customKey = "showCustom" .. key
    local tooltipKey = "show" .. key .. "Tooltip"
    local isDebuffs = (key == "Debuffs")
    local isBigSave = (key == "BigSave")
    local isDispelIndicator = (key == "Dispel")

    local isDisabled = function()
        local mode = msh.db.profile.global.dispelIndicatorMode or "0"

        if isDispelIndicator then
            return mode == "0"
        end

        local isEnabled = path[toggleKey]
        if isDebuffs then isEnabled = msh.db.profile.global.showDebuffs end
        if isBigSave then isEnabled = msh.db.profile.global.showBigSave end

        return not isEnabled
    end

    args[toggleKey] = {
        type = "toggle",
        name = L["Включить"] .. label .. "|r",
        order = 1,
        width = "full",
        get = function()
            if isDebuffs then return msh.db.profile.global.showDebuffs end
            if isBigSave then return msh.db.profile.global.showBigSave end
            if isDispelIndicator then return msh.db.profile.global.showDispelIndicator end
            return path[toggleKey]
        end,
        set = function(_, v)
            if isDebuffs then
                msh.db.profile.global.showDebuffs = v
                msh.db.profile.party.showDebuffs = v
                msh.db.profile.raid.showDebuffs = v
            elseif isBigSave then
                msh.db.profile.global.showBigSave = v
                msh.db.profile.party.showBigSave = v
                msh.db.profile.raid.showBigSave = v
            elseif isDispelIndicator then
                msh.db.profile.global.showDispelIndicator = v
                msh.db.profile.party.showDispelIndicator = v
                msh.db.profile.raid.showDispelIndicator = v
            else
                path[toggleKey] = v
            end

            if v and not path[blizzKey] and not path[customKey] then
                path[blizzKey] = true
            end

            msh.SyncBlizzardSettings()
            msh:Refresh()

            LibStub("AceConfigRegistry-3.0"):NotifyChange("mshFrames")
        end
    }
    args[tooltipKey] = {
        type = "toggle",
        name = L["Показать Тултип"],
        desc = L["Показывать описание при наведении на иконку"],
        order = 2,
        width = "full",
        disabled = function()
            local isEnabled = path[toggleKey]

            if isDebuffs then isEnabled = msh.db.profile.global.showDebuffs end
            if isBigSave then isEnabled = msh.db.profile.global.showBigSave end

            return not isEnabled
        end,
        get = function() return path[tooltipKey] end,
        set = function(_, value)
            path[tooltipKey] = value
            msh:Refresh()
        end,
    }
    args[blizzKey] = {
        type = "toggle",
        order = 3,
        name = function()
            local text = L["Стандартные Blizzard"]
            local color = customColor or "|cff00ffff"
            if (not path[toggleKey] or path[customKey]) then
                return text
            else
                return color .. "|cff00ff00" .. text .. "|r"
            end
        end,
        disabled = function() return isDisabled() or path[customKey] end,
        get = function() return path[blizzKey] end,
        set = function(_, v)
            path[blizzKey] = v; ns.needsReload = true; LibStub("AceConfigRegistry-3.0"):NotifyChange("mshFrames");
            msh:Refresh()
        end
    }
    args[customKey] = {
        type = "toggle",
        order = 4,
        name = function()
            local text = L["Кастомные ауры"]
            local color = customColor or "|cff00ffff"
            if (not path[toggleKey] or path[blizzKey]) then
                return text
            else
                return color .. "|cff00ff00" .. text .. "|r"
            end
        end,
        disabled = function() return isDisabled() or path[blizzKey] end,
        get = function() return path[customKey] end,
        set = function(_, v)
            path[customKey] = v; ns.needsReload = true; LibStub("AceConfigRegistry-3.0"):NotifyChange("mshFrames");
            msh:Refresh()
        end
    }
end

local function GetLeaderIconControls(path)
    return {
        name = L["Иконка лидера"],
        type = "group",
        order = 7,
        args = {
            showLeaderIcon = {
                name = L["Включить иконку"],
                type = "toggle",
                order = 1,
                get = function() return path.showLeaderIcon ~= false end,
                set = function(_, v)
                    path.showLeaderIcon = v; msh:Refresh()
                end,
            },
            leaderIconSize = {
                name = L["Размер"],
                type = "range",
                min = 8,
                max = 40,
                step = 1,
                order = 2,
                get = function() return path.leaderIconSize or 12 end,
                set = function(_, v)
                    path.leaderIconSize = v; msh:Refresh()
                end,
            },
            leaderIconAlpha = {
                type = "range",
                name = L["Прозрачность"],
                min = 0.1,
                max = 1,
                step = 0.1,
                order = 6,
                get = function() return path.leaderIconAlpha or 12 end,
                set = function(_, v)
                    path.leaderIconAlpha = v; msh:Refresh()
                end,
            },
            leaderIconPoint = {
                name = L["Точка привязки"],
                type = "select",
                values = anchorPoints,
                order = 3,
                get = function() return path.leaderIconPoint or "TOPLEFT" end,
                set = function(_, v)
                    path.leaderIconPoint = v; msh:Refresh()
                end,
            },
            leaderIconX = {
                name = L["Смещение X"],
                type = "range",
                min = -100,
                max = 100,
                step = 1,
                order = 4,
                get = function() return path.leaderIconX or 0 end,
                set = function(_, v)
                    path.leaderIconX = v; msh:Refresh()
                end,
            },
            leaderIconY = {
                name = L["Смещение Y"],
                type = "range",
                min = -100,
                max = 100,
                step = 1,
                order = 5,
                get = function() return path.leaderIconY or 0 end,
                set = function(_, v)
                    path.leaderIconY = v; msh:Refresh()
                end,
            },
        },
    }
end

local function GetUnitGroups(path)
    local buffsArgs = {
        appearance = {
            type = "group",
            name = L["Внешний вид"],
            order = 10,
            inline = true,
            args = {
                buffSize = {
                    type = "range",
                    name = L["Размер"],
                    order = 10,
                    min = 8,
                    max = 40,
                    step = 1,
                    disabled = function() return not path.showBuffs end,
                    get = function()
                        return
                            path.buffSize
                    end,
                    set = function(_, v)
                        path.buffSize = v; msh:Refresh()
                    end
                },
                showbuffTimer = {
                    type = "toggle",
                    name = L["Таймер"],
                    order = 11,
                    disabled = function() return not path.showBuffs end,
                    get = function() return path.showbuffTimer end,
                    set = function(_, v)
                        path.showbuffTimer = v; msh:Refresh()
                    end
                },
                buffAlpha = {
                    type = "range",
                    name = L["Прозрачность"],
                    min = 0.1,
                    max = 1,
                    step = 0.1,
                    order = 12,
                    disabled = function() return not path.showBuffs end,
                    get = function() return path.buffAlpha end,
                    set = function(_, v)
                        path.buffAlpha = v; msh:Refresh()
                    end
                },
            },

        },

        positioning = {
            type = "group",
            name = L["Расположение (Кастом)"],
            order = 20,
            inline = true,
            disabled = function() return not path.showBuffs or path.useBlizzBuffs or not path.showCustomBuffs end,
            args = {
                buffPoint = {
                    type = "select",
                    name = L["Точка привязки"],
                    order = 11,
                    values = anchorPoints,
                    disabled = function()
                        return not path.showCustomBuffs or path.useBlizzBuffs or
                            not path.showBuffs
                    end,
                    get = function()
                        return
                            path.buffPoint
                    end,
                    set = function(_, v)
                        path.buffPoint = v; msh:Refresh()
                    end
                },
                buffGrow = {
                    type = "select",
                    name = L["Рост"],
                    order = 14,
                    values = { ["LEFT"] = L["Слева"], ["RIGHT"] = L["Справа"], ["UP"] = L["Сверху"], ["DOWN"] = L["Снизу"] },
                    disabled = function()
                        return not path.showCustomBuffs or path.useBlizzBuffs or
                            not path.showBuffs
                    end,
                    get = function()
                        return
                            path.buffGrow
                    end,
                    set = function(_, v)
                        path.buffGrow = v; msh:Refresh()
                    end
                },
                buffX = {
                    type = "range",
                    name = L["Смещение X"],
                    order = 12,
                    min = -100,
                    max = 100,
                    step = 1,
                    disabled = function()
                        return not path.showCustomBuffs or path.useBlizzBuffs or
                            not path.showBuffs
                    end,
                    get = function()
                        return
                            path.buffX
                    end,
                    set = function(_, v)
                        path.buffX = v; msh:Refresh()
                    end
                },
                buffY = {
                    type = "range",
                    name = L["Смещение Y"],
                    order = 13,
                    min = -100,
                    max = 100,
                    step = 1,
                    disabled = function()
                        return not path.showCustomBuffs or path.useBlizzBuffs or
                            not path.showBuffs
                    end,
                    get = function()
                        return
                            path.buffY
                    end,
                    set = function(_, v)
                        path.buffY = v; msh:Refresh()
                    end
                },
                buffSpacing = {
                    type = "range",
                    name = L["Отступ"],
                    order = 15,
                    min = 0,
                    max = 10,
                    step = 1,
                    disabled = function()
                        return not path.showCustomBuffs or path.useBlizzBuffs or
                            not path.showBuffs
                    end,
                    get = function()
                        return
                            path.buffSpacing
                    end,
                    set = function(_, v)
                        path.buffSpacing = v; msh:Refresh()
                    end
                },

                buffTextScale = {
                    type = "range",
                    name = L["Масштаб текста"],
                    order = 17,
                    min = 0.5,
                    max = 2,
                    step = 0.1,
                    disabled = function()
                        return not path.showBuffs
                    end,
                    get = function()
                        return
                            path.buffTextScale
                    end,
                    set = function(_, v)
                        path.buffTextScale = v; msh:Refresh()
                    end
                },
            }
        },
    }
    AddAuraControls(buffsArgs, path, L["Баффы"], "|cff00ffff")

    local debuffsArgs = {
        appearance = {
            type = "group",
            name = L["Внешний вид"],
            order = 10,
            inline = true,
            disabled = function() return not path.showDebuffs end,
            args = {
                showBossDebuffs = {
                    type = "toggle",
                    name = L["Важные дебаффы"],
                    desc = L["Показывать большие дебаффы от боссов"],
                    order = 10,
                    disabled = function()
                        return not msh.db.profile.global.showDebuffs or path.showCustomDebuffs
                    end,
                    get = function() return msh.db.profile.global.showBossDebuffs end,
                    set = function(_, v)
                        msh.db.profile.global.showBossDebuffs = v
                        msh.SyncBlizzardSettings()
                        msh:Refresh()
                    end,
                },
                showOnlyDispellable = {
                    type = "toggle",
                    name = L["Только рассеиваемые"],
                    desc = L["Показывать только дебаффы, которые можно рассеять"],
                    order = 11,
                    get = function() return msh.db.profile.global.showOnlyDispellable end,
                    set = function(_, v)
                        msh.db.profile.global.showOnlyDispellable = v
                        msh.SyncBlizzardSettings()
                        msh:Refresh()
                    end,
                },
                debuffSize = {
                    type = "range",
                    name = L["Размер иконок"],
                    order = 12,
                    min = 8,
                    max = 40,
                    step = 1,
                    disabled = function()
                        return not msh.db.profile.global.showDebuffs or not path.showCustomDebuffs
                    end,
                    get = function() return path.debuffSize end,
                    set = function(_, v)
                        path.debuffSize = v; msh:Refresh()
                    end
                },
                showDebuffTimer = {
                    type = "toggle",
                    name = L["Таймер"],
                    order = 13,
                    get = function() return path.showDebuffTimer end,
                    set = function(_, v)
                        path.showDebuffTimer = v; msh:Refresh()
                    end
                },
                debuffAlpha = {
                    type = "range",
                    name = L["Прозрачность"],
                    min = 0.1,
                    max = 1,
                    step = 0.1,
                    order = 14,
                    get = function() return path.debuffAlpha end,
                    set = function(_, v)
                        path.debuffAlpha = v; msh:Refresh()
                    end
                },
            }
        },

        positioning = {
            type = "group",
            name = L["Расположение (Кастом)"],
            order = 20,
            inline = true,
            args = {
                debuffPoint = {
                    type = "select",
                    name = L["Точка привязки"],
                    order = 1,
                    values = anchorPoints,
                    disabled = function()
                        return not path.showDebuffs or path.useBlizzDebuffs or
                            not path.showCustomDebuffs
                    end,
                    get = function() return path.debuffPoint end,
                    set = function(_, v)
                        path.debuffPoint = v; msh:Refresh()
                    end
                },
                debuffGrow = {
                    type = "select",
                    name = L["Рост"],
                    order = 21,
                    values = { ["LEFT"] = L["Слева"], ["RIGHT"] = L["Справа"], ["UP"] = L["Сверху"], ["DOWN"] = L["Снизу"] },
                    disabled = function()
                        return not path.showDebuffs or path.useBlizzDebuffs or
                            not path.showCustomDebuffs
                    end,
                    get = function() return path.debuffGrow end,
                    set = function(_, v)
                        path.debuffGrow = v; msh:Refresh()
                    end
                },
                debuffX = {
                    type = "range",
                    name = L["Смещение X"],
                    order = 22,
                    min = -100,
                    max = 100,
                    step = 1,
                    disabled = function()
                        return not path.showDebuffs or path.useBlizzDebuffs or
                            not path.showCustomDebuffs
                    end,
                    get = function() return path.debuffX end,
                    set = function(_, v)
                        path.debuffX = v; msh:Refresh()
                    end
                },
                debuffY = {
                    type = "range",
                    name = L["Смещение Y"],
                    order = 23,
                    min = -100,
                    max = 100,
                    step = 1,
                    disabled = function()
                        return not path.showDebuffs or path.useBlizzDebuffs or
                            not path.showCustomDebuffs
                    end,
                    get = function() return path.debuffY end,
                    set = function(_, v)
                        path.debuffY = v; msh:Refresh()
                    end
                },
                debuffSpacing = {
                    type = "range",
                    name = L["Отступ"],
                    order = 24,
                    min = 0,
                    max = 10,
                    step = 1,
                    disabled = function()
                        return not path.showDebuffs or path.useBlizzDebuffs or
                            not path.showCustomDebuffs
                    end,
                    get = function() return path.debuffSpacing end,
                    set = function(_, v)
                        path.debuffSpacing = v; msh:Refresh()
                    end
                },
                debuffTextScale = {
                    type = "range",
                    name = L["Масштаб текста"],
                    order = 25,
                    min = 0.5,
                    max = 2,
                    step = 0.1,
                    disabled = function() return not path.showDebuffs end,
                    get = function() return path.debuffTextScale end,
                    set = function(_, v)
                        path.debuffTextScale = v; msh:Refresh()
                    end
                },
            }
        }
    }
    AddAuraControls(debuffsArgs, path, L["Дебаффы"], "|cffff00ff")

    local dispelIndicatorArgs = {
        dispelIndicatorMode = {
            type = "select",
            name = L["Режим отображения"],
            desc = L["Выберите тип работы индикатора диспела (CVar)"],
            order = 10,
            values = {
                ["0"] = L["Выключено"],
                ["1"] = L["Я могу рассеять"],
                ["2"] = L["Показывать все"],
            },
            get = function() return msh.db.profile.global.dispelIndicatorMode or "0" end,
            set = function(_, v)
                msh.db.profile.global.dispelIndicatorMode = v
                msh.SyncBlizzardSettings()
                msh:Refresh()
                LibStub("AceConfigRegistry-3.0"):NotifyChange("mshFrames")
            end
        },
        dispelIndicatorSize = {
            type = "range",
            name = L["Размер"],
            order = 11,
            min = 8,
            max = 40,
            step = 1,
            disabled = function() return msh.db.profile.global.dispelIndicatorMode == "0" end,
            get = function()
                return
                    path.dispelIndicatorSize
            end,
            set = function(_, v)
                path.dispelIndicatorSize = v; msh:Refresh()
            end
        },
        dispelIndicatorAlpha = {
            type = "range",
            name = L["Прозрачность"],
            min = 0.1,
            max = 1,
            step = 0.1,
            order = 12,
            disabled = function() return msh.db.profile.global.dispelIndicatorMode == "0" end,
            get = function()
                return
                    path.dispelIndicatorAlpha
            end,
            set = function(_, v)
                path.dispelIndicatorAlpha = v; msh:Refresh()
            end
        },
        dispelIndicatorPoint = {
            type = "select",
            name = L["Точка привязки"],
            order = 13,
            values = anchorPoints,
            disabled = function() return msh.db.profile.global.dispelIndicatorMode == "0" end,
            get = function()
                return
                    path.dispelIndicatorPoint
            end,
            set = function(_, v)
                path.dispelIndicatorPoint = v; msh:Refresh()
            end
        },
        dispelIndicatorX = {
            type = "range",
            name = L["Смещение X"],
            order = 14,
            min = -100,
            max = 100,
            step = 1,
            disabled = function() return msh.db.profile.global.dispelIndicatorMode == "0" end,
            get = function()
                return
                    path.dispelIndicatorX
            end,
            set = function(_, v)
                path.dispelIndicatorX = v; msh:Refresh()
            end
        },
        dispelIndicatorY = {
            type = "range",
            name = L["Смещение Y"],
            order = 15,
            min = -100,
            max = 100,
            step = 1,
            disabled = function() return msh.db.profile.global.dispelIndicatorMode == "0" end,
            get = function()
                return
                    path.dispelIndicatorY
            end,
            set = function(_, v)
                path.dispelIndicatorY = v; msh:Refresh()
            end
        },

    }
    local bigSaveArgs = {
        showBigSaveTimer = {
            type = "toggle",
            name = L["Таймер"],
            order = 10,
            disabled = function() return not path.showBigSave end,
            get = function()
                return
                    path.showBigSaveTimer
            end,
            set = function(_, v)
                path.showBigSaveTimer = v; msh:Refresh()
            end
        },
        bigSaveAlpha = {
            type = "range",
            name = L["Прозрачность"],
            min = 0.1,
            max = 1,
            step = 0.1,
            order = 11,
            disabled = function() return not path.showBigSave end,
            get = function()
                return
                    path.bigSaveAlpha
            end,
            set = function(_, v)
                path.bigSaveAlpha = v; msh:Refresh()
            end
        },
        bigSaveSize = {
            type = "range",
            name = L["Размер"],
            order = 11,
            min = 10,
            max = 60,
            step = 1,
            disabled = function() return not path.showBigSave end,
            get = function()
                return
                    path.bigSaveSize
            end,
            set = function(_, v)
                path.bigSaveSize = v; msh:Refresh()
            end
        },
        bigSavePoint = {
            type = "select",
            name = L["Точка привязки"],
            order = 12,
            values = anchorPoints,
            disabled = function()
                return not path.showBigSave or path.useBlizzBigSave or not path.showBigSave
            end,
            get = function()
                return
                    path.bigSavePoint
            end,
            set = function(_, v)
                path.bigSavePoint = v; msh:Refresh()
            end
        },
        bigSaveX = {
            type = "range",
            name = L["Смещение X"],
            order = 13,
            min = -100,
            max = 100,
            step = 1,
            disabled = function()
                return not path.showBigSave or path.useBlizzBigSave or not path.showBigSave
            end,
            get = function()
                return
                    path.bigSaveX
            end,
            set = function(_, v)
                path.bigSaveX = v; msh:Refresh()
            end
        },
        bigSaveY = {
            type = "range",
            name = L["Смещение Y"],
            order = 14,
            min = -100,
            max = 100,
            step = 1,
            disabled = function()
                return not path.showBigSave or path.useBlizzBigSave or not path.showBigSave
            end,
            get = function()
                return
                    path.bigSaveY
            end,
            set = function(_, v)
                path.bigSaveY = v; msh:Refresh()
            end
        },
        bigSaveTextScale = {
            type = "range",
            name = L["Масштаб текста"],
            order = 15,
            min = 0.5,
            max = 2,
            step = 0.1,
            disabled = function() return not path.showBigSave or path.useBlizzBigSave or not path.showCustomBigSave end,
            get = function()
                return
                    path.bigSaveTextScale
            end,
            set = function(_, v)
                path.bigSaveTextScale = v; msh:Refresh()
            end
        },
    }
    AddAuraControls(bigSaveArgs, path, "BigSave", "|cffff0000")

    return {
        general = {
            name = L["Общие"],
            type = "group",
            order = 1,
            args = {
                texture = {
                    name = L["Текстура"],
                    type = "select",
                    dialogControl = "LSM30_Statusbar",
                    order = 1,
                    values = AceGUIWidgetLSMlists.statusbar,
                    get = function() return path.texture end,
                    set = function(_, v)
                        path.texture = v; msh:Refresh()
                    end,
                },

                showGroups = {
                    name = L["Заголовки групп"],
                    desc = L["Показывать названия групп"],
                    type = "toggle",
                    order = 2,
                    get = function() return path.showGroups end,
                    set = function(_, v)
                        path.showGroups = v
                        msh.SyncBlizzardSettings()
                        msh:Refresh()
                    end,
                },
                hoverAlpha = {
                    name = L["Яркость подсветки"],
                    desc = L["Прозрачность блика при наведении мыши."],
                    type = "range",
                    order = 3,
                    min = 0,
                    max = 1,
                    step = 0.05,
                    isPercent = true,
                    get = function() return path.hoverAlpha or 0.2 end,
                    set = function(_, v)
                        path.hoverAlpha = v
                    end,
                },
            }
        },
        names = {
            name = L["Имена"],
            type = "group",
            order = 2,
            args = {
                fontName = {
                    type = "select",
                    name = L["Шрифт"],
                    order = 1,
                    values = LSM:HashTable("font"),
                    dialogControl = "LSM30_Font",
                    get = function() return path.fontName end,
                    set = function(_, v)
                        path.fontName = v; msh:Refresh()
                    end,
                },
                nameOutline = {
                    type = "select",
                    name = L["Контур"],
                    order = 2,
                    values = outlineModes,
                    sorting = outlineOrder,
                    get = function() return path.nameOutline or "OUTLINE" end,
                    set = function(_, v)
                        path.nameOutline = v; msh:Refresh()
                    end,
                },
                fontSize = {
                    type = "range",
                    name = L["Размер"],
                    order = 3,
                    min = 6,
                    max = 32,
                    step = 1,
                    get = function() return path.fontSizeName end,
                    set = function(_, v)
                        path.fontSizeName = v; msh:Refresh()
                    end,
                },
                nameLength = {
                    type = "range",
                    name = L["Длина имени"],
                    order = 4,
                    min = 2,
                    max = 30,
                    step = 1,
                    get = function() return path.nameLength end,
                    set = function(_, v)
                        path.nameLength = v; msh:Refresh()
                    end,
                },
                namePoint = {
                    type = "select",
                    name = L["Точка привязки"],
                    order = 6,
                    values = anchorPoints,
                    get = function() return path.namePoint end,
                    set = function(_, v)
                        path.namePoint = v; msh:Refresh()
                    end,
                },
                nameX = {
                    type = "range",
                    name = L["Смещение X"],
                    order = 7,
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function() return path.nameX end,
                    set = function(_, v)
                        path.nameX = v; msh:Refresh()
                    end,
                },
                nameY = {
                    type = "range",
                    name = L["Смещение Y"],
                    order = 8,
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function() return path.nameY end,
                    set = function(_, v)
                        path.nameY = v; msh:Refresh()
                    end,
                },
            }
        },
        hp = {
            name = L["Здоровье"],
            type = "group",
            order = 3,
            args = {
                fontStatus = {
                    type = "select",
                    name = L["Шрифт"],
                    order = 1,
                    values = LSM:HashTable("font"),
                    dialogControl = "LSM30_Font",
                    get = function() return path.fontStatus end,
                    set = function(_, v)
                        path.fontStatus = v; msh:Refresh()
                    end,
                },
                statusOutline = {
                    type = "select",
                    name = L["Контур"],
                    order = 2,
                    values = outlineModes,
                    sorting = outlineOrder,
                    get = function() return path.statusOutline or "OUTLINE" end,
                    set = function(_, v)
                        path.statusOutline = v; msh:Refresh()
                    end,
                },
                fontSizeStatus = {
                    type = "range",
                    name = L["Размер"],
                    order = 3,
                    min = 6,
                    max = 32,
                    step = 1,
                    get = function() return path.fontSizeStatus end,
                    set = function(_, v)
                        path.fontSizeStatus = v; msh:Refresh()
                    end,
                },
                statusPoint = {
                    type = "select",
                    name = L["Точка привязки"],
                    order = 4,
                    values = anchorPoints,
                    get = function() return path.statusPoint end,
                    set = function(_, v)
                        path.statusPoint = v; msh:Refresh()
                    end,
                },
                statusX = {
                    type = "range",
                    name = L["Смещение X"],
                    order = 5,
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        return
                            path.statusX
                    end,
                    set = function(_, v)
                        path.statusX = v; msh:Refresh()
                    end
                },
                statusY = {
                    type = "range",
                    name = L["Смещение Y"],
                    order = 6,
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        return
                            path.statusY
                    end,
                    set = function(_, v)
                        path.statusY = v; msh:Refresh()
                    end
                },
            }
        },
        auras = {
            name = L["Ауры"],
            type = "group",
            order = 4,
            args = {
                buffs = { name = L["Баффы"], type = "group", order = 1, args = buffsArgs },
                debuffs = { name = L["Дебаффы"], type = "group", order = 2, args = debuffsArgs },
                dispelIndicator = { name = L["Иконка диспела"], type = "group", order = 3, args = dispelIndicatorArgs },
                bigSave = { name = L["Центральный Сейв"], type = "group", order = 4, args = bigSaveArgs },
            }
        },
        raidMarks = {
            name = L["Рейдовые метки"],
            type = "group",
            order = 5,
            args = {
                showRaidMark = {
                    type = "toggle",
                    name = L["Включить метки"],
                    order = 1,
                    get = function() return path.showRaidMark end,
                    set = function(_, v)
                        path.showRaidMark = v;
                        msh.SyncBlizzardSettings()
                        msh:Refresh()
                    end,
                },
                raidMarkSize = {
                    type = "range",
                    name = L["Размер"],
                    order = 2,
                    min = 8,
                    max = 60,
                    step = 1,
                    get = function() return path.raidMarkSize end,
                    set = function(_, v)
                        path.raidMarkSize = v; msh:Refresh()
                    end,
                },
                raidMarkAlpha = {
                    type = "range",
                    name = L["Прозрачность"],
                    min = 0.1,
                    max = 1,
                    step = 0.1,
                    order = 3,
                    get = function() return path.raidMarkAlpha end,
                    set = function(_, v)
                        path.raidMarkAlpha = v; msh:Refresh()
                    end,
                },
                raidMarkPoint = {
                    type = "select",
                    name = L["Точка привязки"],
                    order = 4,
                    values = anchorPoints,
                    get = function() return path.raidMarkPoint end,
                    set = function(_, v)
                        path.raidMarkPoint = v; msh:Refresh()
                    end,
                },
                raidMarkX = {
                    type = "range",
                    name = L["Смещение X"],
                    order = 5,
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function() return path.raidMarkX end,
                    set = function(_, v)
                        path.raidMarkX = v; msh:Refresh()
                    end,
                },
                raidMarkY = {
                    type = "range",
                    name = L["Смещение Y"],
                    order = 6,
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function() return path.raidMarkY end,
                    set = function(_, v)
                        path.raidMarkY = v; msh:Refresh()
                    end,
                },
            }
        },
        roles = {
            name = L["Иконки ролей"],
            type = "group",
            order = 6,
            args = {
                warning = reloadWarning,
                useBlizzRole = {
                    type = "toggle",
                    name = L["Стандартные Blizzard"],
                    desc = L["Полностью отключает кастомизацию ролей и возвращает родные иконки игры."],
                    order = 1,
                    width = "full",
                    get = function(_) return path.useBlizzRole end,
                    set = function(_, v)
                        path.useBlizzRole = v;
                        ns.needsReload = true
                        LibStub("AceConfigRegistry-3.0"):NotifyChange("mshFrames")
                        msh:Refresh()
                    end,
                },
                showCustomRoleIcon = {
                    type = "toggle",
                    name = L["Включить кастомные иконки ролей"],
                    desc = L["Отображает иконку танка, целителя или урона"],
                    order = 2,
                    width = "full",
                    disabled = function() return path.useBlizzRole end,
                    get = function(_) return path.showCustomRoleIcon end,
                    set = function(_, v)
                        path.showCustomRoleIcon = v; msh:Refresh()
                    end,
                },
                showRoleTank = {
                    type = "toggle",
                    name = L["Танк"],
                    order = 3,
                    disabled = function() return path.useBlizzRole or not path.showCustomRoleIcon end,
                    get = function() return path.showRoleTank end,
                    set = function(_, v)
                        path.showRoleTank = v; msh:Refresh()
                    end,
                },
                showRoleHeal = {
                    type = "toggle",
                    name = L["Хил"],
                    order = 4,
                    disabled = function() return path.useBlizzRole or not path.showCustomRoleIcon end,
                    get = function() return path.showRoleHeal end,
                    set = function(_, v)
                        path.showRoleHeal = v; msh:Refresh()
                    end,
                },
                showRoleDamager = {
                    type = "toggle",
                    name = L["ДД"],
                    order = 5,
                    disabled = function() return path.useBlizzRole or not path.showCustomRoleIcon end,
                    get = function() return path.showRoleDamager end,
                    set = function(_, v)
                        path.showRoleDamager = v; msh:Refresh()
                    end,
                },
                roleIconSize = {
                    type = "range",
                    name = L["Размер"],
                    order = 6,
                    min = 8,
                    max = 40,
                    step = 1,
                    disabled = function() return path.useBlizzRole end,
                    get = function() return path.roleIconSize end,
                    set = function(_, v)
                        path.roleIconSize = v; msh:Refresh()
                    end,
                },
                roleIconAlpha = {
                    type = "range",
                    name = L["Прозрачность"],
                    min = 0.1,
                    max = 1,
                    step = 0.1,
                    order = 7,
                    disabled = function() return path.useBlizzRole end,
                    get = function() return path.roleIconAlpha end,
                    set = function(_, v)
                        path.roleIconAlpha = v; msh:Refresh()
                    end,
                },
                roleIconPoint = {
                    type = "select",
                    name = L["Точка привязки"],
                    order = 8,
                    values = anchorPoints,
                    disabled = function() return path.useBlizzRole end,
                    get = function() return path.roleIconPoint end,
                    set = function(_, v)
                        path.roleIconPoint = v; msh:Refresh()
                    end,
                },
                roleIconX = {
                    type = "range",
                    name = L["Смещение X"],
                    order = 9,
                    min = -50,
                    max = 50,
                    step = 1,
                    disabled = function() return path.useBlizzRole end,
                    get = function() return path.roleIconX end,
                    set = function(_, v)
                        path.roleIconX = v; msh:Refresh()
                    end,
                },
                roleIconY = {
                    type = "range",
                    name = L["Смещение Y"],
                    order = 10,
                    min = -50,
                    max = 50,
                    step = 1,
                    disabled = function() return path.useBlizzRole end,
                    get = function() return path.roleIconY end,
                    set = function(_, v)
                        path.roleIconY = v; msh:Refresh()
                    end,
                },
            }
        },
        leader = GetLeaderIconControls(path),
    }
end

local defaultProfile = {

    texture = "Solid",
    showGroups = false,
    hoverAlpha = 0.2,

    fontName = "Friz Quadrata TT",
    nameOutline = "OUTLINE, SLUG",
    fontSizeName = 13,
    shortenNames = true,
    nameLength = 5,
    namePoint = "TOP",
    nameX = 0,
    nameY = -6,

    fontStatus = "Friz Quadrata TT",
    statusOutline = "OUTLINE, SLUG",
    fontSizeStatus = 10,
    statusPoint = "RIGHT",
    statusX = -2,
    statusY = 0,

    showBuffs = true,
    useBlizzBuffs = true,
    showCustomBuffs = false,
    showBuffsTooltip = false,
    buffSize = 20,
    buffTextScale = 0.6,
    buffPoint = "BOTTOMLEFT",
    buffGrow = "RIGHT",
    buffSpacing = 2,
    showbuffTimer = true,
    buffAlpha = 1,
    buffX = 2,
    buffY = 2,

    showDebuffs = true,
    useBlizzDebuffs = true,
    showCustomDebuffs = false,
    showDebuffsTooltip = false,
    debuffSize = 20,
    debuffPoint = "BOTTOMRIGHT",
    debuffX = 2,
    debuffY = 2,
    debuffGrow = "LEFT",
    debuffSpacing = 2,
    showDebuffTimer = true,
    debuffAlpha = 1,
    debuffTextScale = 0.6,
    showBossDebuffs = true,
    showOnlyDispellable = false,

    showDispelIndicator = true,
    dispelIndicatorOverlay = true,
    dispelIndicatorSize = 20,
    dispelIndicatorAlpha = 1,
    dispelIndicatorPoint = "TOPRIGHT",
    dispelIndicatorX = 5,
    dispelIndicatorY = 5,

    showBigSave = true,
    useBlizzBigSave = true,
    showCustomBigSave = false,
    showBigSaveTooltip = false,
    showBigSaveTimer = true,
    bigSaveSize = 40,
    bigSavePoint = "CENTER",
    bigSaveX = 0,
    bigSaveY = 0,
    bigSaveTextScale = 0.5,
    bigSaveAlpha = 1,

    showRaidMark = true,
    raidMarkSize = 20,
    raidMarkAlpha = 1,
    raidMarkPoint = "RIGHT",
    raidMarkX = -5,
    raidMarkY = 15,

    useBlizzRole = false,
    showCustomRoleIcon = true,
    showRoleTank = true,
    showRoleHeal = true,
    showRoleDamager = false,
    roleIconSize = 15,
    roleIconAlpha = 1,
    roleIconPoint = "TOPLEFT",
    roleIconX = 2,
    roleIconY = -2,

    showLeaderIcon = true,
    leaderIconSize = 15,
    leaderIconPoint = "TOPLEFT",
    leaderIconX = 15,
    leaderIconY = 8,
    leaderIconAlpha = 1
}

ns.defaults = {
    profile = {
        global = {
            hpMode = "PERCENT",
            showBossDebuffs = true,
            raidClassColor = true,
            globalFontName = "Friz Quadrata TT",

        },
        party = defaultProfile,
        raid = defaultProfile,

    }
}

ns.options = {
    type = "group",
    name = "mshFrames",
    args = {
        globalSettings = {
            name = "|cffffd100Global|r",
            type = "group",
            order = 1,
            args = {
                header = { name = L["Стандартные Blizzard"], type = "header", order = 1 },
                warning = reloadWarning,
                globalFont = {
                    name = L["Глобальный шрифт"],
                    desc = L["Устанавливает этот шрифт для всех текстов в аддоне."],
                    type = "select",
                    order = 2,
                    values = function() return LibStub("LibSharedMedia-3.0"):HashTable("font") end,
                    dialogControl = "LSM30_Font",
                    get = function() return msh.db.profile.global.globalFontName end,
                    set = function(_, value)
                        msh.db.profile.global.globalFontName = value

                        msh.db.profile.party.fontName = value
                        msh.db.profile.party.fontStatus = value
                        msh.db.profile.party.fontBuffsTimer = value
                        msh.db.profile.party.fontDebuffsTimer = value
                        msh.db.profile.raid.fontBigSaveTimer = value

                        msh.db.profile.raid.fontName = value
                        msh.db.profile.raid.fontStatus = value
                        msh.db.profile.raid.fontBuffsTimer = value
                        msh.db.profile.raid.fontDebuffsTimer = value
                        msh.db.profile.party.fontBigSaveTimer = value

                        msh:RefreshConfig()
                    end,
                },
                hpMode = {
                    name = L["Формат данных ХП"],
                    desc = L["Влияет на то, какие данные Blizzard готовит для отображения (CVar)"],
                    type = "select",
                    order = 3,
                    values = {
                        ["VALUE"] = L["Цифры"],
                        ["PERCENT"] = L["Проценты"],
                        ["NONE"] = L["Скрыть"]
                    },
                    get = function() return msh.db.profile.global.hpMode end,
                    set = function(_, v)
                        msh.db.profile.global.hpMode = v
                        msh.SyncBlizzardSettings()
                        ns.needsReload = true
                        LibStub("AceConfigRegistry-3.0"):NotifyChange("mshFrames");
                        msh:Refresh()
                    end,
                },
                raidClassColor = {
                    name = L["Цвета классов"],
                    desc = L["Включает окрашивание фреймов в цвета классов (CVar)"],
                    type = "toggle",
                    order = 4,
                    get = function() return msh.db.profile.global.raidClassColor end,
                    set = function(_, v)
                        msh.db.profile.global.raidClassColor = v
                        msh.SyncBlizzardSettings()
                        msh:Refresh()
                    end,
                },
                logo = {
                    type = "description",
                    name = "",
                    image = [[Interface\AddOns\mshFrames\Media\logo]],
                    imageWidth = 150,
                    imageHeight = 150,
                    order = 0,
                },

            }
        },
        partyTab = {
            name = "|cff00ff00Party|r",
            type = "group",
            order = 2,
            childGroups = "tree",
            args = {}
        },
        raidTab = {
            name = "|cff00ffffRaid|r",
            type = "group",
            order = 3,
            childGroups = "tree",
            args = {}
        },
    }
}

function msh:OnInitialize()
    local fontName = "Montserrat-SemiBold"
    local fontPath = "Interface\\AddOns\\mshFrames\\Media\\Montserrat-SemiBold.ttf"
    LSM:Register("font", fontName, fontPath)
    if not AceGUIWidgetLSMlists.font[fontName] then AceGUIWidgetLSMlists.font[fontName] = fontName end

    self.db = LibStub("AceDB-3.0"):New("mshFramesDB", ns.defaults, true)

    if not self.db.profile.global then
        self.db.profile.global = {
            globalFontName = "Friz Quadrata TT",
            showDebuffs = true,
            showBigSave = true,
        }
    end

    ns.options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    ns.options.args.profiles.name = L["Профили"]
    ns.options.args.profiles.order = 100
    ns.options.args.profiles.args.exportHeader = {
        type = "header",
        name = L["Экспорт профиля"],
        order = 101,
    }
    ns.options.args.profiles.args.importExportHeader = {
        type = "header",
        name = L["Экспорт и Импорт (строка)"],
        order = 110,
    }

    ns.options.args.profiles.args.exportBox = {
        type = "input",
        name = L["Экспорт"],
        order = 111,
        width = "full",
        get = function() return msh:GetExportString() end,
        set = function() end,
    }

    ns.options.args.profiles.args.importBox = {
        type = "input",
        name = L["Импорт"],
        order = 112,
        width = "full",
        get = function() return "" end,
        set = function(info, value) msh:ImportProfileFromString(value) end,
        confirm = true,
        confirmText = L["Вы уверены, что хотите перезаписать текущий профиль этими настройками?"],
    }

    self:RefreshMenu()

    self.db.RegisterCallback(msh, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(msh, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(msh, "OnProfileReset", "RefreshConfig")

    AceConfig:RegisterOptionsTable("mshFrames", ns.options)
    self.optionsFrame = AceConfigDialog:AddToBlizOptions("mshFrames", "mshFrames")

    SLASH_MSH1 = "/msh"
    SlashCmdList["MSH"] = function()
        AceConfigDialog:SetDefaultSize("mshFrames", 1000, 600)
        AceConfigDialog:Open("mshFrames")
    end
    print(string.format(L["LOAD_MESSAGE"], L["mshFrames"], "/msh"))
end

function msh:RefreshMenu()
    ns.options.args.partyTab.args = GetUnitGroups(self.db.profile.party)
    ns.options.args.raidTab.args = GetUnitGroups(self.db.profile.raid)


    LibStub("AceConfigRegistry-3.0"):NotifyChange("mshFrames")
end

function msh.SyncBlizzardSettings()
    local profile = msh.db and msh.db.profile
    if not profile then return end

    local global = profile.global
    local isRaid = IsInRaid()
    local groupCfg = isRaid and profile.raid or profile.party
    local showBossDebuffs = msh.db.profile.global.showBossDebuffs
    local showOnlyDispellable = msh.db.profile.global.showOnlyDispellable
    local showBigSave = msh.db.profile.global.showBigSave
    local dispelVal = msh.db.profile.global.dispelIndicatorMode


    if global.hpMode == "VALUE" then
        SetCVar("raidFramesHealthText", "health")
    elseif global.hpMode == "PERCENT" then
        SetCVar("raidFramesHealthText", "perc")
    else
        SetCVar("raidFramesHealthText", "none")
    end

    SetCVar("raidFramesDisplayClassColor", global.raidClassColor and "1" or "0")

    SetCVar("raidFramesDisplayDebuffs", groupCfg.showDebuffs and "1" or "0")
    SetCVar("raidFramesDisplayOnlyDispellableDebuffs", showOnlyDispellable and "1" or "0")
    SetCVar("raidFramesDisplayLargerRoleSpecificDebuffs", showBossDebuffs and "1" or "0")

    SetCVar("raidFramesDispelIndicatorType", dispelVal)


    SetCVar("raidFramesCenterBigDefensive", showBigSave and "1" or "0")

    local currentShowGroups = false
    if IsInRaid() then
        currentShowGroups = profile.raid and profile.raid.showGroups
    else
        currentShowGroups = profile.party and profile.party.showGroups
    end
    local alpha = currentShowGroups and 1 or 0

    for i = 1, 8 do
        local groupFrame = _G["CompactRaidGroup" .. i]
        if groupFrame and groupFrame.title then
            groupFrame.title:SetAlpha(alpha)
        end
    end

    if CompactPartyFrame and CompactPartyFrame.title then
        CompactPartyFrame.title:SetAlpha(alpha)
    end

    if CompactUnitFrameProfiles_ApplyCurrentSettings then
        CompactUnitFrameProfiles_ApplyCurrentSettings()
    end
end

function msh:RefreshConfig()
    C_Timer.After(0.2, function()
        if self.RefreshMenu then self:RefreshMenu() end

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
    end)
end

function msh:GetExportString()
    local profileData = self.db:GetCurrentProfile()
    local settings = self.db.profile

    local serialized = LibS:Serialize(settings)
    local compressed = LibD:CompressDeflate(serialized)
    local encoded = LibD:EncodeForPrint(compressed)

    return "MSH:" .. encoded
end

function msh:ImportProfileFromString(str)
    if not str or str == "" then return end


    local data = str:match("MSH:(.+)")
    if not data then
        print("Cannot parse string"); return
    end

    local decoded = LibD:DecodeForPrint(data)
    local decompressed = LibD:DecompressDeflate(decoded)
    local success, settings = LibS:Deserialize(decompressed)

    if success then
        for k, v in pairs(settings) do
            self.db.profile[k] = v
        end
        self:RefreshConfig()
        print("Profile imported!")
    else
        print("Cannot parse string")
    end
end

function msh:SetupConfig()
    self.db = LibStub("AceDB-3.0"):New("mshFramesDB", ns.defaults, true)
    self.db.RegisterCallback(msh, "OnProfileReset", "RefreshConfig")
    self.db.RegisterCallback(msh, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(msh, "OnProfileCopied", "RefreshConfig")

    local options = {
        name = "mshFrames",
        handler = msh,
        type = "group",
        args = {

        },
    }

    AceConfig:RegisterOptionsTable("mshFrames", options)
    self.optionsFrame = AceConfigDialog:AddToBlizOptions("mshFrames", "mshFrames")
end
