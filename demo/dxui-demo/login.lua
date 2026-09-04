-- demo/dxui-demo/login.lua — сценарий 1: логин-панель (task.md §9.2)
--
-- Демонстрирует: фокус, ввод, ограничения, темы. Только фасад ui.*

local login = {}

function DemoLogin(ui)
    local window = ui.Window {
        title = "Вход",
        x = 480, y = 280, width = 320, height = 260,
        children = {
            ui.Label { text = "Имя пользователя", y = 40, width = 280, height = 20 },
            ui.Edit { placeholder = "логин…", x = 20, y = 65, width = 280, height = 28, maxLength = 24 },
            ui.Label { text = "Пароль", y = 100, width = 280, height = 20 },
            ui.Edit { placeholder = "пароль…", x = 20, y = 125, width = 280, height = 28, password = true, maxLength = 32 },
            ui.Checkbox { text = " Запомнить меня", y = 160, width = 280, height = 24 },
        },
    }
    return window
end

return DemoLogin
