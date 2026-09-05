# DXUI v2 — виджеты

## Button

- **schema** `string` = "" — 
- **icon** `table` — 
- **disabled** `boolean` = false — 
- **onPress** `function` — 
- **color** `number` = P.accent — 
- **textColor** `number` = P.white — 

## Checkbox

- **schema** `string` = "" — 
- **checked** `boolean` = false — 
- **boxColor** `number` = P.accent — 

## Combobox

- **schema** `table` — 
- **selectedIndex** `number` = 0 — 
- **opened** `boolean` = false — 
- **itemHeight** `number` = 24 — 

## ContextMenu

- **schema** `table` — 
- **itemHeight** `number` = 26 — 
- **hoverIndex** `number` = 0 — 

## Edit

- **schema** `string` = "" — 
- **maxLength** `number` = 0 — 
- **password** `boolean` = false — 

## GridList

- **schema** `number` = 0 — 
- **columns** `number` = 1 — 
- **items** `table` — 
- **rowHeight** `number` = 24 — 
- **scrollY** `number` = 0 — 
- **virtualized** `boolean` = true — 

## Image

- **schema** `table` — 
- **slice** `table` — 
- **rotate** `number` = 0 — 

## Label

- **schema** `string` = "" — 
- **color** `number` = P.text — 

## List

- **schema** `table` — 
- **rowHeight** `number` = 24 — 
- **scrollY** `number` = 0 — 
- **selectedIndex** `number` = 0 — 

## Memo

- **schema** `number` = 0 — 
- **lineHeight** `number` = 15 — 

## Modal

- **schema** `string` = "" — 

## Panel

- **schema** `number` = P.bg — 
- **radius** `number` = 0 — 

## Popup

- **schema** `number` = 0 — 
- **anchorY** `number` = 0 — 

## ProgressBar

- **schema** `number` = 0 — 
- **max** `number` = 100 — 
- **color** `number` = P.accent — 

## RadioButton

- **schema** `string` = "" — 
- **selected** `boolean` = false — 
- **radioGroup** `string` = "default" — 

## Scroll

- **schema** `number` = 0 — 
- **total** `number` = 100 — 
- **viewport** `number` = 100 — 
- **horizontal** `boolean` = false — 

## ScrollPanel

- **schema** `number` = 0 — 
- **rowHeight** `number` = 20 — 

## Slider

- **schema** `number` = 0 — 
- **max** `number` = 100 — 
- **min** `number` = 0 — 
- **step** `number` = 1 — 

## TabPanel

- **schema** `table` — 
- **activeIndex** `number` = 1 — 
- **tabHeight** `number` = 30 — 

## Tooltip

- **schema** `string` = "" — 
- **anchorX** `number` = 0 — 
- **anchorY** `number` = 0 — 

## TreeList

- **schema** `table` — 
- **rowHeight** `number` = 24 — 
- **scrollY** `number` = 0 — 

## Window

- **schema** `string` = "Window" — 
- **draggable** `boolean` = true — 
- **resizable** `boolean` = true — 
- **headerHeight** `number` = 28 — 
- **minWidth** `number` = 80 — 
- **minHeight** `number` = 50 — 
- **padding** `number` = 10 — 
