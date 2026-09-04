-- demo/dxui-demo/bank.lua — сценарий 4: банк с модальными окнами (task.md §9.2)
--
-- Демонстрирует: Z-порядок, модальные ловушки, валидация формы.

function DemoBank(ui)
    local window = ui.Window {
        title = "Банк — счёт $12 500",
        x = 380, y = 200, width = 400, height = 300,
    }
    window:addChild(ui.Label { text = "Перевод другому игроку", x = 20, y = 40, width = 360, height = 24 })
    window:addChild(ui.Edit { placeholder = "Сумма", x = 20, y = 70, width = 360, height = 28, maxLength = 9 })
    window:addChild(ui.Label { text = "Кому", x = 20, y = 110, width = 360, height = 20 })
    window:addChild(ui.Edit { placeholder = "Ник получателя", x = 20, y = 135, width = 360, height = 28, maxLength = 32 })

    -- модальный диалог подтверждения: Z поверх содержимого, скрыт до подтверждения
    local modal = ui.Modal { x = 430, y = 270, width = 320, height = 180 }
    modal:addChild(ui.Label { text = "Подтвердить перевод $5 000 игроку Nick?", x = 20, y = 16, width = 280, height = 40 })
    modal:addChild(ui.Button {
        text = "Да",
        x = 20, y = 120, width = 130, height = 36,
        onPress = function() modal.visible = false end,
    })
    modal:addChild(ui.Button {
        text = "Нет",
        x = 170, y = 120, width = 130, height = 36,
        onPress = function() modal.visible = false end,
    })
    modal.visible = false

    window:addChild(ui.Button {
        text = "Перевести",
        x = 20, y = 180, width = 170, height = 36,
        onPress = function() modal.visible = true end,
    })
    window:addChild(ui.Button {
        text = "Отмена",
        x = 210, y = 180, width = 170, height = 36,
        onPress = function() window.visible = false end,
    })

    window:addChild(modal)
    return window
end

return DemoBank
