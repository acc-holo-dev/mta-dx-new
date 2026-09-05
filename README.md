# DXUI v2 — retained-mode UI-фреймворк для MTA:SA

Один MTA-ресурс: декларативные виджеты над собственным конвейером кадра
(свойства → инвалидация → замер → раскладка → холст → dxDraw).

## Установка (два шага)

1. Скопируйте папку ресурса как `dxui` в `resources/`.
2. В meta.xml своего ресурса добавьте `<include resource="dxui" />`.

Ноль build-шагов. Если меняли сорцы фреймворка — `python dxui.py build`.

## Quickstart (первая страница WIKI)

```lua
-- resources/my-ui/meta.xml: <include resource="dxui" />
-- Экспорт возвращает КОД: клиентские ресурсы MTA живут в разных Lua VM,
-- поэтому через границу экспортов проходит только код-строка (P2/P3 брифа).
-- Исполняется ОДИН РАЗ; в кадре — ноль exports.
local ui = loadstring(exports.dxui:import(2))()

ui.Window {
    title = "Инвентарь",
    x = 100, y = 100, width = 400, height = 300,
    children = {
        ui.Edit   { placeholder = "Поиск...", width = 200, height = 28 },
        ui.GridList { id = "items", virtualized = true, width = 200, height = 200 },
        ui.Button { text = "Закрыть", onPress = function() end },
    },
}
```

> `import(2)` разворачивает полную копию фреймворка в VM вашего ресурса
> и возвращает фасад `ui`. Вызывать один раз при старте ресурса.

## Демо-ресурс

`demo/dxui-demo/` — 5 сценариев (только фасад, §9.2):

```
/dxuidemo login | inventory | hud | bank | themes | off
```

## Инструменты

| Команда | Назначение |
|---|---|
| `python dxui.py build` | meta.xml + api/bundle.lua (строка для `import(2)`) |
| `python dxui.py validate` | линт: MTA-вызовы вне whitelist, полнота doc |
| `python dxui.py test` | headless-тесты (бюджеты — падение сборки) |
| `python dxui.py wiki` | Markdown-документация из полей doc |
| `python dxui.py new-widget <Name>` | каркас файла виджета |

В игре: **F8** / `dxui:stats` — инспектор и профайлер, `dxui:demo` — демо-экран,
`dxui:save-layout` / `dxui:load-layout` — раскладка окон и тема в `layout.xml` (§3.8).

## API поверх фабрик (GLUE)

| API | Назначение |
|---|---|
| `ui.Screen` / `ui.screens` | Screen Stack (§3.8): `push(root, opts?)` / `pop(opts?)` / `current()` / `depth()` / `clear(opts?)`; переход `opts.transition = "slide"`; возврат восстанавливает фокус; `saveLayout()` → XML-строка (окна + палитра), `loadLayout(xml)` |
| `ui.dragdrop` | Drag-and-drop (§4.3): `setSource(node, payload)`, `registerTarget(node, slots)` (nil — вся площадь; `{ {id,x,y,w,h}, … }` — слоты в локальных координатах), `unregister(node)`, `active()` — пара для инспектора. Сигналы: источник `dragStart`/`dragEnd(accepted, target, slot)`; цель `dragEnter`/`dragOver`/`dragLeave`/`drop` |
| `ui.animation` / `ui.theme` / `ui.registry` | твины, темы, реестр виджетов |

## Миграция с DGS (§9.3)

| DGS | DXUI v2 | Примечание |
|---|---|---|
| `dgsCreateButton(...)` | `ui.Button { ... }` | позиционные аргументы → именованные свойства схемы |
| `dgsSetProperty(btn, "text", ...)` | `btn.text = ...` | строковый setter → типизированное свойство |
| `onDgsMouseClick` | `widget:signal("click"):connect(fn)` | события платформы → сигналы |
| `dgsStyleSetProperty` | тема через токены (`ui.theme.apply`) | строки → токены с проверкой в dev |
| OOP-класс DGS | полный OOP v2 без штрафа | один путь вместо POP/OOP |
| `dgs-dxgridlist` | GridList с виртуализацией | 10 000 строк без деградации |

## Архитектура

`core/ → node/ → layout/ → registry/ → render/ → input/ → text/ → style/ → anim/ → widget/ → widgets/ → api/ → debug/` —
только вниз по списку; циклы — ошибка сборки. MTA-вызовы только в
`boot.lua`, `render/backend_mta.lua`, `input/dispatcher.lua` (lint в `dxui.py validate`).

## Тесты

`python dxui.py test` — 135 headless-тестов, включая бюджеты из §6.2
(1000 виджетов ≤ 2 мс, GridList 10 000 строк ≤ 2 мс, смена темы 300 виджетов ≤ 5 мс,
hit-test ≥ 20× линейного перебора).
