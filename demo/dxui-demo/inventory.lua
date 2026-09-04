-- demo/dxui-demo/inventory.lua — сценарий 2, инвентарь с поиском (task.md §9.2)
--
-- Демонстрирует: виртуализация, gridlist, список + фильтр.

function DemoInventory(ui)
    local items = {}
    for i = 1, 10000 do
        items[i] = "Предмет #" .. i
    end

    local window = ui.Window {
        title = "Инвентарь (10 000 предметов)",
        x = 300, y = 120, width = 460, height = 480,
        children = {
            ui.Label { text = "Поиск:", y = 40, x = 20, width = 60, height = 24 },
            ui.Edit { placeholder = "Что ищем?", x = 90, y = 40, width = 350, height = 28 },
        },
    }
    local search = window:getChildren()[2]
    local list = ui.GridList {
        x = 20, y = 80, width = 420, height = 340,
        columns = 2, rowHeight = 24,
        virtualized = true,
        items = items,
    }
    window:addChild(list)

    -- поиск: фильтруем массив данных (скролл подменяет данные, §6.1)
    local function applyFilter()
        local query = search:getText()
        local filtered = {}
        local n = 0
        if query == "" then
            for i = 1, #items do
                filtered[i] = items[i]
            end
        else
            local lower = query:lower()
            for i = 1, #items do
                if items[i]:lower():find(lower, 1, true) then
                    n = n + 1
                    filtered[n] = items[i]
                end
            end
        end
        list.items = filtered
        list.scrollY = 0
    end

    -- после подключения Binding-API сюда придёт onText; пока — фильтр
    -- по клику на поле поиска
    search:signal("click"):connect(applyFilter)

    return window
end

return DemoInventory
