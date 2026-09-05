#!/usr/bin/env python3
# dxui.py — инструмент поставки DXUI v2 (task.md §8)
#
# Python 3, stdlib only, ноль внешних зависимостей.
#
#   build               сгенерировать meta.xml из порядка зависимостей слоёв
#   validate            линт: MTA-вызовы вне whitelist; полнота doc в схемах
#   test                headless-тесты (.debug/lua51/lua.exe)
#   wiki                генерация Markdown-документации из полей doc
#   new-widget <Name>   каркас файла виджета со обязательными полями схемы

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(ROOT, "source", "client")
LUA = os.path.join(ROOT, ".debug", "lua51", "lua.exe")
TESTS = os.path.join(ROOT, ".debug", "tests", "run.lua")

# ------------------------------------------------------------------ layout order
# Слои по зависимостям: только вниз по списку (task.md §3.1).
# Внутри каталога порядок фиксирован вручную там, где он важен.

LAYERS = [
    # core/ — zero-dependency
    "core/class.lua",
    "core/log.lua",
    "core/signal.lua",
    "core/pool.lua",
    "core/time.lua",
    # node/
    "node/prop.lua",
    "node/node.lua",
    "node/tree_ops.lua",
    # layout/
    "layout/lay.lua",
    "layout/constraints.lua",
    "layout/flex.lua",
    "layout/grid.lua",
    "layout/anchors.lua",
    "layout/measure.lua",
    # registry/
    "registry/base.lua",
    "registry/registry.lua",
    # render/
    "render/canvas.lua",
    "render/backend_mta.lua",
    "render/backend_headless.lua",
    "render/frame.lua",
    # input/
    "input/hit_test.lua",
    "input/focus.lua",
    "input/dispatcher.lua",
    "input/dragdrop.lua",
    # text/
    "text/editor.lua",
    # style/ (токены и темы поверх палитры; theme батчит дефолты в runtime)
    "style/tokens.lua",
    "style/theme.lua",
    "style/states.lua",
    "style/transitions.lua",
    # anim/
    "anim/easing.lua",
    "anim/tween.lua",
    # widget/ (palette — первым: цвета схемы по умолчанию)
    "widget/palette.lua",
]

# каталоги виджетов: 1 файл = 1 виджет, порядок алфавитный
WIDGET_DIR = "widget"

# api/ и debug/ грузятся после виджетов: фасад и инспектор поверх registry.
# api/bundle.lua — сгенерированная строка исходников для import(2);
# screens.lua — ДО bundle/exports: GLUE ссылается на DXUI.screens.
POST_WIDGETS = [
    "api/screens.lua",
    "api/bundle.lua",
    "api/exports.lua",
    "debug/inspector.lua",
    "debug/profiler.lua",
]

# файлы, которые подключаются всегда после слоёв
TAIL = [
    "boot.lua",
]


def widget_files():
    wdir = os.path.join(SOURCE, WIDGET_DIR)
    names = []
    for entry in os.listdir(wdir):
        if entry.endswith(".lua") and entry != "palette.lua":
            names.append(entry)
    names.sort()
    return [WIDGET_DIR + "/" + n for n in names]


def boot_order():
    return LAYERS[:-1] + [LAYERS[-1]] + widget_files() + POST_WIDGETS + TAIL


# ------------------------------------------------------------------ build

BUNDLE_PATH = os.path.join("api", "bundle.lua")
BUNDLE_LEVEL = 8  # [=========[ ... ]=========]


def bundle_files():
    """Модули, входящие в import(2): всё кроме boot.lua и api/ (они —
    для собственного инстанса dxui-ресурса; потребителю нужен свой мост)."""
    for rel in boot_order():
        if rel == "boot.lua" or rel.startswith("api/"):
            continue
        yield rel


def cmd_build():
    lines = ["<meta>",
             '    <info author="DXUI" name="dxui" version="0.1.0" type="script" />',
             "    <!--",
             "        Порядок загрузки = порядок зависимостей.",
             "        Файл генерируется: python dxui.py build. Ручные правки будут потеряны.",
             "    -->"]
    for rel in boot_order():
        path = os.path.join(SOURCE, rel)
        if not os.path.isfile(path):
            continue
        lines.append('    <script src="source/client/%s" type="client" cache="false" />' % rel)
    lines.append('    <export function="import" type="client" />')
    # hot-reload темы (G6): клиентские file* видят только объявленные файлы
    lines.append('    <file src="hot-theme.lua" />')
    lines.append('    <settings>')
    lines.append('        <setting name="dxui_debug" value="#true" />')
    lines.append('        <setting name="dxui_priority" value="#normal" />')
    lines.append('    </settings>')
    lines.append("</meta>")
    with open(os.path.join(ROOT, "meta.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    # api/bundle.lua: исходники всех модулей одной строкой для import(2).
    # Клиентские ресурсы MTA — раздельные Lua VM: потребитель исполняет
    # код-строку в своей VM (см. api/exports.lua).
    chunks = []
    for rel in bundle_files():
        with open(os.path.join(SOURCE, rel), "r", encoding="utf-8") as f:
            src = f.read()
        if "]=" + "=" * BUNDLE_LEVEL + "]" in src:
            raise SystemExit("bundle: %s использует слишком высокий уровень длинных скобок" % rel)
        # каждый файл — IIFE: его `return` не рвёт общий chunk
        chunks.append("(function()\n" + src + "\nend)();\n")
    body = "".join(chunks)
    open_n = "[" + "=" * BUNDLE_LEVEL + "["
    close_n = "]" + "=" * BUNDLE_LEVEL + "]"
    bundle = (
        "-- api/bundle.lua — СГЕНЕРИРОВАН `python dxui.py build`. Не править руками.\n"
        "-- Исходники всех модулей одной строкой: их исполняет потребитель import(2)\n"
        "-- в собственной Lua VM (MTA-ресурсы изолированы, P2/P3 из task.md).\n\n"
        "local BUNDLE = " + open_n + "\n" + body + close_n + "\n"
        + "if _G.DXUI == nil then _G.DXUI = {} end\n"
        + "_G.DXUIBundle = BUNDLE\n"
        + "return BUNDLE\n"
    )
    with open(os.path.join(SOURCE, BUNDLE_PATH), "w", encoding="utf-8", newline="\n") as f:
        f.write(bundle)

    print("meta.xml: %d файлов | bundle: %d модулей"
          % (sum(1 for l in lines if "<script" in l), len(chunks)))
    return 0


# ------------------------------------------------------------------ validate

# MTA-API разрешены ТОЛЬКО здесь (task.md §2, whitelist)
WHITELIST = {
    "render/backend_mta.lua",
    "input/dispatcher.lua",
    "boot.lua",
}

MTA_CALL = re.compile(
    r"\b("
    r"dxDraw\w+|dxSet\w+|dxCreate\w+|dxGet\w+"
    r"|addEventHandler|addCommandHandler|removeEventHandler"
    r"|bindKey|unbindKey|guiGetScreenSize|getTickCount|guiSetInputMode"
    r"|triggerEvent|outputChatBox|setElementFrozen"
    r")\s*\(")

# вызов функции, не упоминание в строке/комментарии: грубая очистка строк и комментариев


def strip_literals(text):
    # длинные скобки любого уровня: --[==[ ... ]==] и [=====[ ... ]=====]
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    text = re.sub(r"\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"'(?:\\.|[^'\\])*'", "''", text)
    return text


def lint_mta_calls(errors):
    for dirpath, _dirs, files in os.walk(SOURCE):
        for name in files:
            if not name.endswith(".lua"):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SOURCE).replace("\\", "/")
            if rel in WHITELIST:
                continue
            with open(full, "r", encoding="utf-8") as f:
                text = f.read()
            for i, line in enumerate(strip_literals(text).splitlines(), 1):
                if MTA_CALL.search(line):
                    errors.append("%s:%d: MTA-вызов вне whitelist: %s"
                                  % (rel, i, line.strip()))


def lint_widget_docs(errors):
    wdir = os.path.join(SOURCE, WIDGET_DIR)
    for name in sorted(os.listdir(wdir)):
        if not name.endswith(".lua"):
            continue
        full = os.path.join(wdir, name)
        with open(full, "r", encoding="utf-8") as f:
            text = f.read()
        text = strip_literals(text)
        # блочный сканер: схемные записи вида key = { type = ... }
        depth = 0
        block_start = None
        has_type = False
        has_doc = False
        key_name = None
        for lineno, line in enumerate(text.splitlines(), 1):
            opens = line.count("{")
            closes = line.count("}")
            m = re.match(r"\s*([A-Za-z_]\w*)\s*=\s*\{", line)
            if depth == 0 and m:
                block_start = lineno
                key_name = m.group(1)
                has_type = False
                has_doc = False
                rest = line[m.end():]
                has_type = has_type or "type" in rest
                has_doc = has_doc or "doc" in rest
                depth = opens - closes
                continue
            if depth > 0:
                if "type" in line:
                    has_type = True
                if "doc" in line:
                    has_doc = True
                depth += opens - closes
                if depth <= 0:
                    if key_name == "schema" or not has_type:
                        pass  # не схемная запись
                    elif not has_doc:
                        errors.append("%s:%d: свойство '%s' без doc" % (name, block_start, key_name))
                    depth = 0
        if "name = " not in text and "registry.define" not in text:
            pass


def lint_widget_specs(errors):
    """Каждый файл виджета: name + render обязательны."""
    wdir = os.path.join(SOURCE, WIDGET_DIR)
    for name in sorted(os.listdir(wdir)):
        if not name.endswith(".lua") or name == "palette.lua":
            continue
        with open(os.path.join(wdir, name), "r", encoding="utf-8") as f:
            text = f.read()
        if "registry.define" not in text:
            errors.append("%s: нет registry.define" % name)
        elif "render = " not in text and "render=" in text.replace(" ", ""):
            pass
        if "registry.define" in text and "render" not in text:
            errors.append("%s: у виджета нет render" % name)


def cmd_validate():
    errors = []
    lint_mta_calls(errors)
    lint_widget_docs(errors)
    lint_widget_specs(errors)
    for e in errors:
        print("  FAIL", e)
    print("validate: %s" % ("OK" if not errors else "%d ошибок" % len(errors)))
    return 1 if errors else 0


# ------------------------------------------------------------------ test

def cmd_test():
    if not os.path.isfile(LUA):
        print("test: headless lua не найден (%s)" % LUA)
        return 1
    r = subprocess.call([LUA, TESTS])
    return r


# ------------------------------------------------------------------ wiki

def cmd_wiki():
    docs = []
    wdir = os.path.join(SOURCE, WIDGET_DIR)
    for name in sorted(os.listdir(wdir)):
        if not name.endswith(".lua") or name == "palette.lua":
            continue
        with open(os.path.join(wdir, name), "r", encoding="utf-8") as f:
            text = f.read()
        m = re.search(r'name\s*=\s*"(\w+)"', text)
        if not m:
            continue
        widget = m.group(1)
        doc = ["## %s" % widget, ""]
        for pm in re.finditer(
                r"(\w+)\s*=\s*\{\s*\n([^}]*)\}", text):
            entry, body = pm.group(1), pm.group(2)
            if "type" not in body:
                continue
            ty = re.search(r'type\s*=\s*"(\w+)"', body)
            dv = re.search(r'default\s*=\s*([^\n,]+)', body)
            dc = re.search(r'doc\s*=\s*"([^"]*)"', body)
            doc.append("- **%s** `%s`%s — %s"
                       % (entry,
                          ty.group(1) if ty else "?",
                          (" = " + dv.group(1).strip()) if dv else "",
                          dc.group(1) if dc else ""))
        docs.append("\n".join(doc))
    out = os.path.join(ROOT, "wiki.md")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("# DXUI v2 — виджеты\n\n" + "\n\n".join(docs) + "\n")
    print("wiki.md: %d виджетов" % len(docs))
    return 0


# ------------------------------------------------------------------ new-widget

TEMPLATE = """-- widget/{name}.lua — {name}

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {{
    name = "{Name}",
    schema = {{
        -- пример; каждое свойство обязано иметь doc
        text = {{
            type = "string", default = "", invalidates = {{ prop.DIRTY.RENDER }},
            doc = "Описание свойства",
        }},
    }},
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.bg, {{ radius = 4 }})
    end,
}}
"""


def cmd_new_widget(name):
    if not name:
        print("new-widget: укажи имя, например: new-widget ColorPicker")
        return 1
    if not re.match(r"^\w+$", name):
        print("new-widget: имя должно быть словом [A-Za-z0-9_]")
        return 1
    path = os.path.join(SOURCE, WIDGET_DIR, name.lower() + ".lua")
    if os.path.exists(path):
        print("new-widget: %s уже существует" % path)
        return 1
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(TEMPLATE.format(name=name.lower(), Name=name))
    print("new-widget: создан %s (не забудь: python dxui.py build)" % path)
    return 0


# ------------------------------------------------------------------ main

def main():
    if len(sys.argv) < 2:
        print("dxui.py build|validate|test|wiki|new-widget <Name>")
        return 1
    cmd = sys.argv[1]
    if cmd == "build":
        return cmd_build()
    if cmd == "validate":
        return cmd_validate()
    if cmd == "test":
        return cmd_test()
    if cmd == "wiki":
        return cmd_wiki()
    if cmd == "new-widget":
        return cmd_new_widget(sys.argv[2] if len(sys.argv) > 2 else None)
    print("unknown command: %s" % cmd)
    return 1


if __name__ == "__main__":
    sys.exit(main())
