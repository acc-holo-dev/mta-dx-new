-- node/tree_ops.lua — операции над деревом и Z-порядком
--
-- Z-порядок = позиция в children родителя (раньше = ниже).
-- В API узла — индекс в _children родителя; сквозной Z-порядок пиксельного
-- пересечения вычисляет input/hit_test по геометрии прошлого кадра.

local rawget = rawget
local error = error
local table_remove = table.remove

local DXUI = _G.DXUI
local Node = DXUI.Node

local tree_ops = {}

local function checkNode(node, fn)
    if node == nil then
        error(("tree_ops.%s: node is nil"):format(fn), 2)
    end
end

local function childrenOf(node)
    return rawget(node, "_").children
end

-- --- Z-порядок ------------------------------------------------------------

-- вверх в стопке родителя (к последнему индексу); у потолка — no-op
function tree_ops.bringToFront(node)
    checkNode(node, "bringToFront")
    local parent = rawget(node, "_").parent
    if parent == nil then return false end
    local siblings = childrenOf(parent)
    local n = #siblings
    if n <= 1 then return false end
    for i = 1, n do
        if siblings[i] == node then
            if i == n then return false end
            table_remove(siblings, i)
            siblings[n] = node
            return true
        end
    end
    return false
end

-- вниз в стопке родителя (к первому индексу)
function tree_ops.sendToBack(node)
    checkNode(node, "sendToBack")
    local parent = rawget(node, "_").parent
    if parent == nil then return false end
    local siblings = childrenOf(parent)
    local n = #siblings
    for i = 1, n do
        if siblings[i] == node then
            if i == 1 then return false end
            table_remove(siblings, i)
            table.insert(siblings, 1, node)
            return true
        end
    end
    return false
end

-- переставить узел внутри родителя на заданный индекс (0-based slot)
function tree_ops.setIndex(node, index)
    checkNode(node, "setIndex")
    local parent = rawget(node, "_").parent
    if parent == nil then return false end
    local siblings = childrenOf(parent)
    local n = #siblings
    if index < 1 or index > n then
        error(("tree_ops.setIndex: index %d out of range 1..%d"):format(index, n), 2)
    end
    local pos
    for i = 1, n do
        if siblings[i] == node then pos = i break end
    end
    if pos == nil then return false end
    table_remove(siblings, pos)
    local at = pos < index and index + 1 or index
    table.insert(siblings, at, node)
    return true
end

-- --- обхождение -----------------------------------------------------------

-- pre-order: узел, затем дети слева направо; fn(node) возвращает false = не спускаться
function tree_ops.walk(root, fn)
    checkNode(root, "walk")
    if fn(root) == false then return end
    local children = childrenOf(root)
    for i = 1, #children do
        tree_ops.walk(children[i], fn)
    end
end

-- вверх по цепочке родителей; fn(node) возвращает true = прекратить
function tree_ops.walkUp(node, fn)
    checkNode(node, "walkUp")
    local cur = rawget(node, "_").parent
    while cur do
        if fn(cur) then return end
        cur = rawget(cur, "_").parent
    end
end

-- первый узел (включая root), удовлетворяющий predicate
function tree_ops.findFirst(root, predicate)
    local found = nil
    tree_ops.walk(root, function(n)
        if found == nil and predicate(n) then found = n end
    end)
    return found
end

function tree_ops.isAncestorOf(ancestor, node)
    checkNode(ancestor, "isAncestorOf")
    checkNode(node, "isAncestorOf")
    local cur = rawget(node, "_").parent
    while cur do
        if cur == ancestor then return true end
        cur = rawget(cur, "_").parent
    end
    return false
end

DXUI.tree_ops = tree_ops
return tree_ops

