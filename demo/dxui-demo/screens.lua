-- demo/dxui-demo/screens.lua — сценарий 6: Screen Stack + drag-and-drop
--
-- Демонстрирует: ui.screens.push/pop со slide-переходом и возвратом фокуса;
-- ui.dragdrop — источник -> цель со слотами; overlay показывает пару (F8).

function DemoScreens(ui)
    local window = ui.Window {
        title = "Экраны и DnD",
        x = 420, y = 220, width = 360, height = 300,
        children = {
            ui.Label { text = "Главный экран (root)", y = 40, width = 320, height = 20 },
        },
    }

    local function openDetails()
        local details = ui.Window {
            title = "Детали",
            x = 460, y = 260, width = 300, height = 200,
            children = {
                ui.Label { text = "Экран поверх; pop вернёт фокус назад", y = 44, width = 268, height = 40 },
                ui.Button {
                    text = "Назад (pop)", y = 140, width = 130, height = 32,
                    onPress = function()
                        ui.screens.pop({ destroy = true })
                    end,
                },
            },
        }
        ui.screens.push(details, { transition = "slide" })
    end

    window:addChild(ui.Button {
        text = "Открыть детали (push)", x = 20, y = 70, width = 210, height = 32,
        onPress = openDetails,
    })

    -- drag-and-drop: перетащи кнопку на панель
    local slotLabel
    local target = ui.Panel { x = 180, y = 120, width = 160, height = 90, radius = 6 }
    local targetColor = target.color
    ui.dragdrop.registerTarget(target, "default")
    target:signal("dragEnter"):connect(function()
        target.color = 0x66FFFFFF
    end)
    target:signal("dragLeave"):connect(function()
        target.color = targetColor
    end)
    target:signal("drop"):connect(function(payload, slot)
        if slotLabel then
            slotLabel.text = "Принято: " .. tostring(payload.item)
        end
    end)
    window:addChild(target)
    slotLabel = ui.Label { text = "Слот пуст", x = 180, y = 218, width = 160, height = 20 }
    window:addChild(slotLabel)

    local src = ui.Button { text = "Тяни меня", x = 20, y = 130, width = 120, height = 32, onPress = function() end }
    ui.dragdrop.setSource(src, { item = "меч" })
    window:addChild(src)

    window:addChild(ui.Label {
        text = "F8 — инспектор: активная dnd-пара в оверлее",
        x = 20, y = 250, width = 320, height = 20,
    })

    return window
end

return DemoScreens
