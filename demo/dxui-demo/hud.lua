-- demo/dxui-demo/hud.lua — сценарий 3, HUD (task.md §9.2)
--
-- Демонстрирует: статичный HUD, изменение данных без пересоздания узлов.

function DemoHud(ui)
    -- cache=true: HUD растеризуется в текстуру и пересобирается только
    -- при изменении данных (здоровье тикает раз в секунду — §6.1 в живую)
    local root = ui.Panel { x = 20, y = 20, width = 260, height = 90, cache = true }

    local health = ui.Label { text = "Здоровье: 100", x = 12, y = 12, width = 200, height = 24 }
    local money = ui.Label { text = "Деньги: $0", x = 12, y = 40, width = 200, height = 24 }
    local hint = ui.Label { text = "M — добавить денег, H — подлечиться", x = 12, y = 64, width = 240, height = 20 }

    root:addChild(health)
    root:addChild(money)
    root:addChild(hint)

    local healthValue = 100
    local moneyValue = 25000

    bindKey("m", "down", function()
        moneyValue = moneyValue + 500
        money.text = "Деньги: $" .. moneyValue
    end)

    bindKey("h", "down", function()
        healthValue = 100
        health.text = "Здоровье: " .. healthValue
    end)

    -- небольшая жизнь: здоровье медленно тает
    setTimer(function()
        if healthValue > 0 then
            healthValue = healthValue - 1
        end
        health.text = "Здоровье: " .. healthValue
    end, 1000, 0)

    return root
end

return DemoHud
