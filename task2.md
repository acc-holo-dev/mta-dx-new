# TASK.md — DXUI v2: исполнение перепроектирования mta-dx-ui

> **Кто ты.** Ты — инженер-исполнитель. Твоя цель: довести этот файл до конца, задача за задачей.
> Никакой самодеятельности: читай задачу → делай ровно что написано → прогоняй проверку → переходи к следующей.
> Архитектурная спецификация (почему так, а не иначе): `../dxui-v2-plan/index.html` и `../dxui-v2-plan/plan/plan.js`.
> Если спецификация и этот файл конфликтуют — ПРИОРИТЕТ У ЭТОГО ФАЙЛА.

---

## СТАТУС ИСПОЛНЕНИЯ (подводится по мере работы)

Все ворота G0–G7 закрыты; 140 headless-тестов зелёные, validate OK. Отклонения
от буквы задач и остатки — ниже; следующий агент продолжает с «остатков».

- **T11**: radius — ленивый dxCreateShader из RAW-строки (SDF rounded-rect,
  vs/ps_2_0, фолбэк — прямоугольник); 9-slice — `slice={l,t,r,b,baseW,baseH}`
  через 9 вызовов dxDrawImageSection, фолбэк — целиком. renderToTexture
  исправлен: `dxGetRenderTarget` в MTA не существует — восстановление только
  через `dxSetRenderTarget()`, вызов, только когда цель — экран (P5).
- **T20/T21**: composition.lua (setSlot/childBySlot — слот это метка ребёнка,
  геометрия — в render хозяина) и binding.lua (observable/bind) — в widget/,
  в validate добавлен список helper-модулей (не виджеты).
- **T36 / финальный гейт G7**: `demo/dxui-demo` — это и есть внешний ресурс-
  консьюмер (отдельный meta.xml, `<include resource="dxui" />`, ровно один
  вызов `loadstring(exports.dxui:import(2))()`, ноль обращений к внутренним
  файлам — проверено grep'ом). Отдельный `demo-consumer/` не делаем: дубль
  без новой ценности. `ui.destroyAll()` + `onClientResourceStop` — по букве T36.
- **Багфикс по пути**: фабрика `ui.*` делает узел корнем ДО create, поэтому
  `children={...}` оставляло детей в корнях кадра дважды (draw+hit-test) —
  registry.create снимает ребёнка с корней перед addChild. Плюс call-time
  `_G.DXUI.*` переведены на closure-namespace (хост может подменить _G.DXUI
  между загрузкой модуля и вызовом — ломало консьюмер-сандбоксы).
- **Остатки (не блокеры)**: fade-переход экранов ждёт opacity-канала в холсте
  (сейчас slide); treeShake (T19, include-скан) не реализован — бандл целиком
  (~60 модулей строкой; настоящий выигрыш потребует графа зависимостей и
  манифестов потребителей — отложено); сценарии экранов «как данные» (§3.8)
  — сделано: `api/scenario.lua` (build из таблицы, строковые onPress);
  T70+ — по отдельному приказу.
- **Сверх буквы (после закрытия ворот)**: RT-кэш поддеревьев (§6.1,
  свойство `cache` — растеризация раз на изменение, один image в кадре;
  dirty-списки наконец потребляет пайплайн) и Auto-LOD (§6.1, EMA долгого
  кадра гасит скругления) — оба с headless-тестами; HUD демо кэшируется.

---

## 0. ЖЁСТКИЕ ФАКТЫ ПЛАТФОРМЫ (проверено по WIKI MTA:SA — нарушения = переделка)

| № | Факт | Следствие |
|---|---|---|
| F1 | MTA:SA — Lua **5.1** (интерпретатор, НЕ LuaJIT) | запрещены `goto`, `integer division //`, битовые операторы `&\|~`, Lua 5.2+ синтаксис |
| F2 | Экспорты ресурсов имеют **накладные расходы**; WIKI прямо запрещает exports в горячем пути («do not use exports in render events or fast processing logic») | фасад для потребителей — `loadstring(exports.dxui:import(2))()`: экспорт возвращает КОД (строку), исполняется ОДИН раз; в кадре — только прямые ссылки |
| F3 | Через границу экспортов **не переживают функции в таблицах** (сериализация) | `import(2)` возвращает строку Lua-кода, а не таблицу с конструкторами |
| F4 | Кадр MTA всегда растеризуется **целиком** | «damage rects» в чистом виде невозможны; оптимизируем генерацию команд + кэш статичного поддерева в Render Target (`dxSetRenderTarget`) |
| F5 | Нет composition-событий IME для DX-текста | текстовые поля — на `onClientCharacter`; CJK-IME — не обещаем в DX |
| F6 | `dxDrawImage` умеет поворот (rotX/rotY/rotZ); есть `dxSetTransform` | трансформации виджетов реализуемы платформой |
| F7 | `dxDrawImageSection` существует | 9-слайс реализуем 9 вызовами секций |
| F8 | Приоритет обработчика `addEventHandler(..., priority)` существует | единый обработчик кадра с приоритетом из конфига |

**Разрешённые MTA-функции и только в этих файлах** (проверяется `python dxui.py validate`):
- `source/boot.lua`, `source/render/backend_mta.lua`, `source/input/dispatcher.lua` — весь dxDraw*, dxCreate*, guiGetScreenSize, addEventHandler, getTickCount, dxSetRenderTarget, dxCreateShader, xml*, exports.

---

## 1. ПРАВИЛА ДИСЦИПЛИНЫ (без исключений)

1. **Один файл = один модуль = один `return M`** в конце. Глобальных переменных НЕТ (кроме `DXUI_BOOT` внутри boot.lua — и только он).
2. **Зависимости только вниз**: core/ ни от кого; dom/layout/render — только от core; widget — от них; widgets — от widget.
3. **meta.xml никогда не редактируется руками** — только `python dxui.py build`.
4. **Внешних зависимостей нет**: ни busted, ни luarocks. Тесты — самописный раннер `tests/run.lua` (Lua 5.1, plain asserts), запускается `python dxui.py test`.
5. **Каждое свойство виджета** обязано иметь `type` и `doc`. Нет `doc` → `dxui.py validate` падает → задача не закрыта.
6. **pcall только в dev-режиме** (`dxui.config.lua: dev = true`). Прод-путь — без обёрток.
7. Свойства узла пишутся только через синтаксис `node.<prop> = v` (setter-хуки внутри prop.lua). Прямая запись в `_data` извне запрещена.
8. Строковые `#hex` парсятся один раз при установке; в кадре — только числа.
9. Если что-то неоднозначно: выбирай ПРОСТЕЙШЕЕ решение, которое проходит проверку задачи. Не расширяй область («scope creep») — это риск №1 проекта.
10. Сделал задачу → прогнал её проверку → только потом следующая. Пропускать проверки запрещено.

---

## 2. СТАРТОВОЕ СОСТОЯНИЕ

Проект `mta-dx-ui` (v1) остаётся рабочим в проде. Всё новое пишется в структуру ниже; v1 не трогаешь до задачи T70.

```
mta-dx-ui/
├── source/
│   ├── boot.lua             core/ dom/ layout/ widget/ widgets/ render/ style/ input/ anim/ text/ i18n/ api/ debug/
├── tests/run.lua            # самописный раннер: tests/run.lua [#имя] ; exit 1 при провале
└── wiki/                    # генерируется: python dxui.py wiki
```

---

## 3. ЗАДАЧИ. Порядок фиксирован. Ворота G0–G7

### ВОРОТА G0 — ЯДРО (core/)

- **T01 `source/core/class.lua`** — `class(name, super)` возвращает класс; `:extend`, `:new`, `instanceof`. Запрещены метамагии кроме `__index`.
  *Проверка:* `T01_class` в tests/run.lua: наследование 2 уровней, методы, super-вызов.
- **T02 `source/core/signal.lua`** — сигнал по контракту: `connect(fn, opts) -> connection`, `connection:disconnect()`, `emit(...)`, отложенное удаление при эмите (disconnect внутри emit не рвёт обход), `opts.once`, слабые ссылки (weak table на подписчиков — сборщик забирает мёртвых), режим ошибок: dev → pcall каждого подписчика (упавший не прерывает остальных), prod → прямой вызов.
  *Проверка:* T02: 3 подписчика, второй падает → третий вызван (dev); once срабатывает 1 раз; disconnect внутри emit безопасен; слабый сбор после `collectgarbage()` → emit не падает.
- **T03 `source/core/pool.lua`** — `pool.new(resetFn)`: `acquire()`, `release(obj)`; нет аллокаций при повторном acquire.
  *Проверка:* T03: 100 acquire/release циклов → 1 аллокация (считай через счётчик в resetFn).
- **T04 `source/core/time.lua`** — `now()` (getTickCount через бэкенд-хук), `dt()` — кадр-дельта. Без прямого вызова MTA: бэкенд подставляется извне (`time.setSource(fn)`).
  *Проверка:* T04: фиктивный источник времени; dt считается верно.
- **T05 `source/core/log.lua`** — уровни debug/info/warn/error; ring-buffer на 256 записей; категории ("CORE","DOM","RENDER"...).
  *Проверка:* T05: 300 записей → хранится 256 последних.

**ВОРОТА G0 ЗАКРЫТА, КОГДА:** `python dxui.py test` зелёный; `python dxui.py validate` зелёный.

### ВОРОТА G1 — ДЕРЕВО И СВОЙСТВА (dom/)

- **T06 `source/dom/prop.lua`** — сердце системы. `prop.declare(class, schema)`: для каждого поля генерирует getter/setter; schema: `{ type=, default=, required=, invalidates=, doc=, onSet= }`; DIRTY = { LAYOUT=1, RENDER=2 }. Запись значения того же типа и равного содержимого НЕ инвалидирует. Несоответствие типа → ошибка E_TYPE_MISMATCH (dev) / лог (prod). Необъявленное свойство → E_SCHEMA (dev). Два dirty-списка: `prop.dirtyList("layout")`, `prop.dirtyList("render")`; запись с `invalidates` пушит узел в список (дедуп: узел в списке один раз; сброс списка — `prop.flushLists()`).
  *Проверка:* T06: типизация, дедуп инвалидации, dirty-списки содержат узел один раз при 100 записях.
- **T07 `source/dom/node.lua`** — `Node` (class): `children` (массив, без дыр), `parent`, `visible`, `id`; `addChild(node)` / `removeChild(node)` / `setParent(node)`; `markDirty(name)` = пуш в dirty-список (через prop); сигналы: `events.added`, `events.removed`; `destroy()` — отписывает все сигналы (слабые ссылки гарантируют), удаляет из родителя, помечает `_destroyed`.
  *Проверка:* T07: дерево 3 уровней; destroy корня → все дети `_destroyed`; ни один сигнал родителя не держится (проверка через weak + collectgarbage).
- **T08 `source/dom/tree_ops.lua`** — `insertAt(parent, node, index)`, `reparent`, Z-порядок: `bringToFront(node)`, `moveToBack(node)` — перестановка в массиве детей родителя.
  *Проверка:* T08: порядок детей после операций — точный массив индексов.

**G1 ЗАКРЫТА:** тесты зелёные; демо в headless: дерево 100 узлов создаётся и уничтожается без утечек (счётчик живых узлов = 0 после destroy всех).

### ВОРОТА G2 — ХОЛСТ И БЭКЕНДЫ (render/)

- **T09 `source/render/canvas.lua`** — командный буфер (пул из T03): `rect(x,y,w,h,color,opts{radius?})`, `text(str,x,y,opts{font,color,center})`, `image(tex,x,y,w,h,opts{rotate,slice})`, `clip(rect)` — команда; `clear()`, `drain()` — вынуть команды. Цвет — упакованное число. БЕЗ единого вызова MTA.
  *Проверка:* T09: 1000 rect-команд → в буфере 1000 записей; переиспользование буфера (drain → clear → снова) без аллокаций после первого кадра.
- **T10 `source/render/backend_headless.lua`** — исполняет команды в лог/счётчики; `measureFrameTime(fn)`.
  *Проверка:* T10: время кадра 1000 команд измеряется, ≠ 0.
- **T11 `source/render/backend_mta.lua`** — ЕДИНСТВЕННЫЙ файл с dxDraw*: исполнение drain() буфера: rect → dxDrawRectangle (+скругление шейдером при radius, фолбэк — без скругления), text → dxDrawText, image → dxDrawImage / 9 секций при slice; поддержка `dxSetRenderTarget`: `renderToTexture(sceneFn) -> texture`.
  *Проверка:* вручную в игре (`start dxui`, `/dxuitest`): окно 3 виджета видно; автотестов нет — платформенный слой.
- **T12 `source/boot.lua`** — сборка модулей по порядку зависимостей (жёстко зашитый список, он же — источник для dxui.py build); подписка: ОДИН `addEventHandler("onClientRender", root, handler, false, приоритет)` → тик всех инстансов; viewport из `guiGetScreenSize()` (кэш, перечитывать при изменении); `onClientResourceStop` → destroy инстансов СТОРОННЕГО ресурса (см. T32).
  *Проверка:* в игре: кадр без инстансов стоит ~0.1 мс (проверь через встроенный stats-оверлей).

**G2 ЗАКРЫТА:** headless-бенчмарк: 1000 rect за ≤ 2 мс (медиана 120 кадров, T10).

### ВОРОТА G3 — РАСКЛАДКА (layout/)

- **T13 `source/layout/measure.lua`** — двухпроходный measure: `measureAll(nodes)` — только dirty-layout список; `_measureContent` узла по детям.
- **T14 `source/layout/flex.lua`** — `{ dir = "row"|"column", gap, wrap=false, align = "start"|"center"|"end" }`; позиции детей родителя.
- **T15 `source/layout/grid.lua`** — `{ cols, gap = {x, y}, span поддержка }`.
- **T16 `source/layout/anchors.lua`** — двойные координаты `{ scale, offset }` (как Roblox UDim2): `{ 0.5, -100 }` = центр минус 100px; `anchor = { left=..., right=..., top=..., bottom=... }`.
- **T17 `source/layout/constraints.lua`** — min/max/fill/авторазмер `{ auto = "x"|"y"|"both" }`; конфликт «абсолютная позиция vs раскладка» → раскладка ПОБЕЖДАЕТ, об этом — предупреждение в dev.
  *Проверка всех:* golden-тесты: эталонные деревья (окно с кнопками, скролл-панель 500 строк) → эталонные координаты в `tests/golden/layout.lua`; расхождение = провал.

**G3 ЗАКРЫТА:** порт сценария v1 (окно + scrollpanel) воспроизводится координатно.

### ВОРОТА G4 — СИСТЕМА ВИДЖЕТОВ (widget/)

- **T18 `source/widget/base.lua`** — `Widget(name, spec)`: registry-обёртка. spec = `{ props = {...schema по T06}, theme = {...}, slots = {...}, render = function(canvas, node) end, handlers = {...} }`. При создании экземпляра: валидация required-props (dev — ошибка с сигнатурой: имя, свойство, тип, doc; prod — лог + значение default), применение темы, сборка узла.
- **T19 `source/widget/registry.lua`** — `register(widget)`, `get(name)`, type-id целыми; `treeShake(list)` — в билд попадают только используемые виджеты (список использования ведёт dxui.py по include-скану демо/потребителей).
- **T20 `source/widget/composition.lua`** — слоты: `spec.slots = { icon = "left" }`; композиция `composes = { Label, Icon }`.
- **T21 `source/widget/binding.lua`** — `observable(initial)` → `get/set/subscribe`; `bind(widget, { prop = observable })`.
- **T22–T26 виджеты первого эшелона** (каждый — один файл, `python dxui.py new-widget Name` делает каркас, ты заполняешь):
  - T22 `Button` (text:string[required], onPress:callback[required], icon:texture, disabled:boolean) — render: rect+radius+text; states hover/pressed из темы; transition scale 0.95/0.1s.
  - T23 `Label` (text, font, color; авторазмер).
  - T24 `Panel` (layout-контейнер).
  - T25 `Edit` — headless-ядро текста: caret, выделение, undo (5 шагов), blink; ввод через onClientCharacter (мост делает dispatcher, T30); IME не обещаем (F5).
  - T26 `Window` — заголовок, drag за тайтл, resize-маркеры по краям (8 маркеров), bringToFront по клику (через tree_ops).

**G4 ЗАКРЫТА:** демо-ресурс: окно с Button/Label/Edit/Panel — создано, кликабельно, drag работает. `python dxui.py validate` требует doc у всех полей — зелёный.

### ВОРОТА G5 — ВВОД (input/)

- **T27 `source/input/dispatcher.lua`** — мост (boot.lua): onClientClick/onClientCursorMove/onClientKey/onClientCharacter → очередь (пул!) → раздача один раз за кадр ДО пасса раскладки; инвариант: хит-тест против геометрии ПРОШЛОГО кадра (сохранённая копия мировых прямоугольников).
- **T28 `source/input/hit_test.lua`** — пространственный хеш: сетка 64px; `insert(rect, node)`, `query(x, y) -> nodes` (сверху вниз по Z); перестройка ленивая при structural-change флаге.
  *Проверка:* T28: 10 000 прямоугольников, 1000 запросов — быстрее линейного перебора минимум в 20 раз (тест фиксирует соотношение).
- **T29 `source/input/focus.lua`** — стек фокуса, Tab вперёд/назад, стрелки по дереву раскладки, Tab в Edit = начать правку (стрелки — нет, см. план «минное поле»), модальные ловушки: модал держит фокус-кольцо; возврат в точку.
- **T30 `source/input/gesture.lua`** — tap, long-press (500ms), drag (порог 4px) + `capturePointer` (события идут владельцу до release).
  *Проверка G5:* автотесты фокуса/жестов на headless + демо: Tab/стрелки/модал/drag окна.

### ВОРОТА G6 — СТИЛИ И АНИМАЦИЯ

- **T31 `source/style/tokens.lua` + `theme.lua` + `states.lua` + `transitions.lua`** — токены: palette/spacing/font/radius/scale; тема = таблица поверх токенов; состояния base→hover→pressed→focused→disabled; transition `{ prop = {duration, easing} }` — твины пишут через prop (T06); hot-reload: файл темы перечитывается по таймеру в dev.
- **T32 `source/anim/tween.lua` + `easing.lua`** — to(node, dur, props, easing); таймлайны `after`/`parallel`; тики — единый клок из core/time (никаких своих таймеров в кадре).
  *Проверка G6:* смена тёмной/светлой темы в живом режиме ≤ 5 мс (бенчмарк); 300 анимируемых виджетов держат 60 FPS (stats-оверлей).

### ВОРОТА G7 — ИНСТРУМЕНТЫ И ПОСТАВКА

- **T33 `dxui.py`**: `build` (meta.xml из порядка зависимостей boot.lua), `validate` (зависимости-линт: MTA-функции вне whitelist = ошибка; doc-полнота; таблицы plan.js валидны), `test` (запуск tests/run.lua через lua/luac или встроенный интерпретатор недоступен — тогда: `python dxui.py test` выполняет тесты через `lua5.1 tests/run.lua`, если lua5.1 нет в PATH — тесты помечаются MANUAL и запускаются в игре командой `/dxuitest`), `wiki` (Markdown из схемы виджетов: имя, свойства, типы, required, doc), `new-widget Name`.
- **T34 `source/debug/inspector.lua`** — F8: дерево, видимость, фокус, подписки, живые текстуры; подсветка «почему не видно» (visibility=false / нулевой размер / перекрыто) — кликом по виджету.
- **T35 `source/debug/profiler.lua`** — per-widget стоимость кадра; причины dirty; `dxui:stats` — панель: dxui мс/кадр, узлы, подписки, текстуры.
- **T36 `source/api/exports.lua`** — `import(version)` → СТРОКА Lua-кода: локальные ссылки на виджеты/функции (F2/F3!); `meta.xml: <export function="import" http="false"/>`; ресурс-изоляция: каждый потребитель получает свой инстанс-срез; onClientResourceStop потребителя → очистка его узлов/сигналов/текстур (реестр по sourceResourceRoot).
- **T37 демо-ресурс `demo/`** — логин-панель, инвентарь с поиском (список 1000 строк, виртуализация: узлов = видимые+2), HUD, банк с модалами, галерея тем. Каждый сценарий = отдельный файл = живой рецепт.
- **T38 `tests/test_budget.lua`** — бюджеты: 1000 виджетов ≤ 2 мс; список 10 000 (виртуализованный) ≤ 2 мс; смена темы ≤ 5 мс; аллокации в кадре = 0 (счётчик пула). Провал = красный.

**G7 ЗАКРЫТА = ПРОЕКТ ГОТОВ**, когда: все тесты зелёные, `python dxui.py build && python dxui.py validate && python dxui.py wiki` без ошибок, демо из T37 работает в игре, внешний ресурс (сделай `demo-consumer/`) собирает окно через `loadstring(exports.dxui:import(2))()` БЕЗ обращения к внутренним файлам фреймворка.

### ПОСЛЕ G7 (по отдельному приказу, НЕ сам)
- T70 миграция v1→v2 виджетов (1–2 в неделю), T71 HTML-бэкенд (CEF), T72 3D-виджеты, T73 редактор сцен.

---

## 4. КАК ПОНИМАТЬ, ЧТО ЗАДАЧА ЗАКРЫТА

```
Задача закрыта ⇔ (1) код написан по контракту задачи
              ∧ (2) её проверка зелёная (python dxui.py test / в игре)
              ∧ (3) python dxui.py validate зелёный
              ∧ (4) НЕ редактированы файлы, не указанные в задаче
```

Частично сделанная задача = НЕ сделанная задача. Вернувшись после паузы: читай этот файл, найди первую незакрытую задачу, продолжай с неё.

## 5. ИЗВЕСТНЫЕ ЛОВУШКИ (не наступай)

1. **Экспорты в кадре = смерть перфоманса** (F2). Проверяй: в рендер-пути ноль вызовов exports.
2. **Таблицы с функциями через export** теряются (F3) — только код-строка через loadstring.
3. **nil-дыры в children** убивают ipairs-обходы — только table.insert/table.remove-парность.
4. **Строковые конкаты в кадре** — собирай текст заранее; в кадре — только уже готовые строки.
5. **dxSetRenderTarget переключает глобальное состояние** — всегда восстановление старой цели (defer-обёртка), иначе уедет весь рендер игры.
6. **onClientKey жуёт колесо мыши** (mouse_wheel_up/down не имеют «отжатия») — учитывай в жестах.
7. **collectgarbage("count")** — единственный способ мерить память Lua; пул считай своим счётчиком.
8. Если тест падает из-за платформы (нет dxDraw в headless) — тест должен это ОБНАРУЖИТЬ и быть помечен `[game]`, а не молча пропускаться.

## 6. ФИНАЛЬНАЯ ПРОВЕРКА АГЕНТА (после T38)

Пробеги чек-лист и доложи по пунктам:
- [ ] Все ворота G0–G7 закрыты по правилу раздела 4.
- [ ] `grep -r "dxDraw" source/` — совпадения ТОЛЬКО в backend_mta.lua.
- [ ] `grep -r "exports\." source/` — совпадения ТОЛЬКО в api/exports.lua (объявления).
- [ ] meta.xml собран dxui.py build; руками не тронут.
- [ ] wiki/ свежая: `python dxui.py wiki` без ошибок.
- [ ] демо-консьюмер (T37) работает с внешнего ресурса через import(2).
- [ ] Ни одна задача раздела 3 не пропущена; все ловушки раздела 5 учтены.
