#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## What an open picker shows (`pickerView`), and the drawing of it, which
## reads nothing else.

import std/options

import ../celina_backend as celina

import ../[types, color, unicode_utils, popup_render, render_utils]
import session, layout

type
  PickerRowView* = object
    text*: string
    matched*: seq[int] ## The characters of `text` the query matched
    selected*: bool

  PickerView* = object
    title*: string
    query*: string ## As the prompt shows it
    cursor*: int ## The character of `query` the cursor is on
    count*: string ## Matched / all
    message*: string ## Why the source has no items
    rows*: seq[PickerRowView]

proc pickerCount*(s: PickerSession): string =
  $s.rowCount & "/" & $s.items.len

proc pickerView*(state: EditorState, height: int): PickerView =
  let s = state.picker
  if s.isNil:
    return
  result.title = s.title
  (result.query, result.cursor) = state.input.line.shownPromptLine
  result.count = s.pickerCount
  result.message = s.message
  let selected = s.selectedRow
  var
    scratch: FuzzyMatcher
    positions: seq[int]
  for row in s.topIndex ..< min(s.rowCount, s.topIndex + height):
    let item = s.items[s.rowItem(row)]
    var view = PickerRowView(text: item.display, selected: row == selected)
    if not s.matches.everyItem:
      positions.setLen 0
      if scratch.fuzzyMatchPos(s.matches.pattern, item.key, positions).isSome:
        for column in fuzzyRuneColumns(item.key, positions):
          if column >= 0:
            view.matched.add item.keyAt + column
    result.rows.add view

proc pickerScreenLayout*(state: EditorState, width, height: int): PickerLayout =
  let countWidth = if state.picker.isNil: 0 else: state.picker.pickerCount.len
  pickerLayout(width, height, state.bottomAreaHeight(width), countWidth)

proc drawText(
    buffer: var Buffer,
    x, y, limitX: int,
    text: string,
    style: Style,
    skip = 0,
    marked: seq[int] = @[],
    markStyle = style,
) =
  ## `text` from `x` up to `limitX`, its first `skip` cells left out and the
  ## characters `marked` in `markStyle`.
  if y < 0 or y >= buffer.area.height:
    return
  let limitX = min(limitX, buffer.area.width)
  var
    cellX = x - skip
    column = 0
  for r in text.toCharRunes:
    let w = charWidth(sanitizeCellRune(r))
    if cellX + w > limitX:
      break
    if cellX >= x:
      let s = if column in marked: markStyle else: style
      cellX += buffer.setRuneCell(cellX, y, r, s)
    else:
      cellX += w
    inc column

proc renderPicker*(buffer: var Buffer, layout: PickerLayout, view: PickerView) =
  let
    frame = layout.frame
    normal = getThemeStyle(EditorColorPairIndex.popupWindow)
    border = getThemeStyle(EditorColorPairIndex.popupWindowBorder)
    current = getThemeStyle(EditorColorPairIndex.popupWinCurrentLine)
    match = getThemeStyle(EditorColorPairIndex.popupWindowMatch)
    matchSel = getThemeStyle(EditorColorPairIndex.popupWindowMatchSel)
    detail = getThemeStyle(EditorColorPairIndex.popupWindowDetail)
    right = frame.x + frame.width - 1
  if not layout.shown:
    return
  for y in frame.y ..< frame.y + frame.height:
    if y >= 0 and y < buffer.area.height:
      discard buffer.fillCells(frame.x, y, frame.x + frame.width, normal)
  buffer.drawBorder(frame.x, frame.y, frame.width, frame.height, border)
  if view.title.len > 0:
    buffer.drawText(frame.x + 2, frame.y, right - 1, " " & view.title & " ", border)

  let promptY = layout.prompt.y
  buffer.drawText(frame.x + 1, promptY, layout.prompt.x, PromptMark, detail)
  let (skip, _) = promptScroll(view.query, view.cursor, layout.prompt.width)
  buffer.drawText(
    layout.prompt.x,
    promptY,
    layout.prompt.x + layout.prompt.width,
    view.query,
    normal,
    skip = skip,
  )
  buffer.drawText(layout.countX, promptY, right, view.count, detail)

  if layout.separatorY < frame.y + frame.height - 1:
    var rule = "├"
    for _ in frame.x + 1 ..< right:
      rule.add "─"
    rule.add "┤"
    buffer.drawText(frame.x, layout.separatorY, right + 1, rule, border)

  let list = layout.list
  if view.rows.len == 0 and view.message.len > 0 and list.height > 0:
    buffer.drawText(list.x + 1, list.y, list.x + list.width, view.message, detail)
  for i, row in view.rows:
    if i >= list.height:
      break
    let
      y = list.y + i
      style = if row.selected: current else: normal
    # Only the match's foreground, as Neovim lays PmenuMatch over Pmenu, so
    # the row keeps its background whatever one a theme gives the match.
    var mark = style
    mark.fg = (if row.selected: matchSel else: match).fg
    discard buffer.fillCells(list.x, y, list.x + list.width, style)
    buffer.drawText(
      list.x + 1,
      y,
      list.x + list.width,
      row.text,
      style,
      marked = row.matched,
      markStyle = mark,
    )
