-- demo/dxui-demo/themes.lua — сценарий 5: галерея тем (task.md §9.2)
--
-- Демонстрирует: смена тем батчевым обновлением, токены.

function DemoThemes(ui)
    local DARK = {
        bg = 0xFF1E2430, bgHover = 0xFF2A3546, bgPressed = 0xFF34435C,
        bgDisabled = 0xFF1A1F28, border = 0xFF3A4456,
        text = 0xFFE8ECF2, textDim = 0xFF8A93A3,
        accent = 0xFF1E6FE8, accentDim = 0xFF153F83,
        danger = 0xFFE85151, overlay = 0xB4000000,
        windowBg = 0xFF222A38, white = 0xFFFFFFFF,
    }
    local LIGHT = {
        bg = 0xFFF2F4F8, bgHover = 0xFFE2E8F2, bgPressed = 0xFFD0DAEA,
        bgDisabled = 0xFFE8E8E8, border = 0xFFC0C8D4,
        text = 0xFF20242C, textDim = 0xFF6A7383,
        accent = 0xFF1E6FE8, accentDim = 0xFF153F83,
        danger = 0xFFE85151, overlay = 0xB4FFFFFF,
        windowBg = 0xFFFFFFFF, white = 0xFFFFFFFF,
    }
    local CUSTOM = {
        accent = 0xFF00A86B, windowBg = 0xFF10231C,
        bg = 0xFF0F1B15, bgHover = 0xFF1A2C22, bgPressed = 0xFF24402F,
        bgDisabled = 0xFF0C130F, border = 0xFF2A4A38,
        text = 0xFFE6FFF2, textDim = 0xFF79A98B,
        danger = 0xFFFF6B6B, overlay = 0xB4000000,
        accentDim = 0xFF0B7A50, white = 0xFFFFFFFF,
    }

    local window = ui.Window {
        title = "Галерея тем",
        x = 420, y = 160, width = 360, height = 320,
    }
    window:addChild(ui.Label { text = "Выберите тему оформления:", x = 20, y = 40, width = 320, height = 24 })

    local cb = ui.Checkbox { text = " Чекбокс в текущей теме", x = 20, y = 200, width = 320, height = 24 }
    local preview = ui.Button {
        text = "Предпросмотр кнопки",
        x = 20, y = 230, width = 320, height = 40,
        onPress = function() end,
    }
    local grid = ui.GridList { x = 20, y = 90, width = 320, height = 100, columns = 3, rowHeight = 24 }
    grid.items = { "token", "token", "token", "batch", "batch", "batch", "hot-reload", "hot-reload", "hot-reload" }
    window:addChild(cb)
    window:addChild(preview)
    window:addChild(grid)

    local status = ui.Label { text = "Строка состояния: тема применена", x = 20, y = 250, width = 320, height = 24 }
    window:addChild(status)

    local function select(themeName, overrides)
        ui.theme.apply(overrides)
        status.text = "Строка состояния: тема " .. themeName
    end

    local buttons = {
        { "Тёмная", DARK },
        { "Светлая", LIGHT },
        { "Кастомная", CUSTOM },
    }
    for i = 1, 3 do
        local name, overrides = buttons[i][1], buttons[i][2]
        window:addChild(ui.Button {
            text = name,
            x = 20 + (i - 1) * 110, y = 280, width = 100, height = 32,
            onPress = function() select(name, overrides) end,
        })
    end

    return window
end

return DemoThemes
