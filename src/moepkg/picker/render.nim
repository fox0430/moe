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

## What an open picker shows (`pickerView`, `pickerPreviewView`), and the
## drawing of it, which reads nothing else.

import std/options

import ../celina_backend as celina

import ../types/editor_types
import
  ../[
    types, color, unicode_utils, popup_render, render_utils, editor_render_window,
    wanted_column,
  ]
import session, layout, preview

export preview

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
  let s = state.picker
  pickerLayout(
    width,
    height,
    state.bottomAreaHeight(width),
    countWidth = (if s.isNil: 0 else: s.pickerCount.len),
    preview = not s.isNil and s.previews,
  )

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

proc overlaid(surface: Style, index: EditorColorPairIndex): Style =
  ## `index` drawn on the picker's `surface`: its foreground and modifiers,
  ## the surface's background, so the box stays one color whatever a theme
  ## gives the entry.
  result = getThemeStyle(index)
  result.bg = surface.bg

proc onSurface(buffer: var Buffer, left, right, y: int, under, surface: ColorValue) =
  ## Puts `surface` under the cells of row `y` drawn on `under`, the editor's
  ## background, as Neovim draws a group with no background on the window's
  ## Normal. A background of the line's own, such as a code block's, stays.
  if under == surface:
    return
  for x in left ..< right:
    var cell = buffer[x, y]
    if cell.style.bg == under:
      cell.style.bg = surface
      buffer[x, y] = cell

proc rule(left, right: string, width: int): string =
  result = left
  for _ in 0 ..< width - 2:
    result.add "─"
  result.add right

proc renderPicker*(
    buffer: var Buffer, layout: PickerLayout, view: PickerView, previewTitle = ""
) =
  let
    frame = layout.frame
    normal = getThemeStyle(EditorColorPairIndex.picker)
    border = normal.overlaid(EditorColorPairIndex.pickerBorder)
    title = normal.overlaid(EditorColorPairIndex.pickerTitle)
    current = getThemeStyle(EditorColorPairIndex.pickerSelection)
    match = getThemeStyle(EditorColorPairIndex.pickerMatch)
    matchSel = getThemeStyle(EditorColorPairIndex.pickerMatchSel)
    detail = normal.overlaid(EditorColorPairIndex.pickerDetail)
    right = frame.x + frame.width - 1
  if not layout.shown:
    return
  for y in frame.y ..< frame.y + frame.height:
    if y >= 0 and y < buffer.area.height:
      discard buffer.fillCells(frame.x, y, frame.x + frame.width, normal)
  let preview = layout.preview
  # Where the list's side of the box ends: at the rule before the preview.
  let listRight =
    if layout.previewBeside:
      preview.x - 1
    else:
      right
  buffer.drawBorder(frame.x, frame.y, frame.width, frame.height, border)
  if view.title.len > 0:
    buffer.drawText(frame.x + 2, frame.y, listRight - 1, " " & view.title & " ", title)

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
    buffer.drawText(
      frame.x,
      layout.separatorY,
      listRight + 1,
      rule("├", "┤", listRight - frame.x + 1),
      border,
    )
  if preview.height > 0:
    if layout.previewBeside:
      let bottom = frame.y + frame.height - 1
      buffer.drawText(listRight, frame.y, listRight + 1, "┬", border)
      buffer.drawText(listRight, bottom, listRight + 1, "┴", border)
      for y in frame.y + 1 ..< bottom:
        if y != layout.separatorY:
          buffer.drawText(listRight, y, listRight + 1, "│", border)
      if previewTitle.len > 0:
        buffer.drawText(
          listRight + 2, frame.y, right - 1, " " & previewTitle & " ", title
        )
    else:
      let y = preview.y - 1
      buffer.drawText(frame.x, y, right + 1, rule("├", "┤", frame.width), border)
      if previewTitle.len > 0:
        buffer.drawText(frame.x + 2, y, right - 1, " " & previewTitle & " ", title)

  let list = layout.list
  if view.rows.len == 0 and view.message.len > 0 and list.height > 0:
    buffer.drawText(list.x + 1, list.y, list.x + list.width, view.message, detail)
  for i, row in view.rows:
    if i >= list.height:
      break
    let
      y = list.y + i
      style = if row.selected: current else: normal
      matchStyle = if row.selected: matchSel else: match
    # Take the match's foreground and modifiers, as Neovim lays PmenuMatch over
    # Pmenu; the row keeps its background whatever one a theme gives the match.
    var mark = style
    mark.fg = matchStyle.fg
    mark.modifiers = mark.modifiers + matchStyle.modifiers
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

proc renderPickerPreview*(
    e: Editor, buffer: var Buffer, rect: PickerRect, view: PickerPreviewView
) =
  ## The preview's rows: the lines from `view.topLine` as a window not the
  ## active one draws them, with no cursor line and no line numbers, on the
  ## `pickerPreview` background, or why the item shows none.
  if rect.width <= 0 or rect.height <= 0:
    return
  let
    right = rect.x + rect.width
    surface = getThemeStyle(EditorColorPairIndex.pickerPreview)
  if view.buffer.isNil:
    for y in rect.y ..< rect.y + rect.height:
      discard buffer.fillCells(rect.x, y, right, surface)
    if view.message.len > 0:
      buffer.drawText(
        rect.x + 1,
        rect.y,
        right,
        view.message,
        surface.overlaid(EditorColorPairIndex.pickerDetail),
      )
    return
  let
    lines = view.buffer
    editorBg = getThemeStyle(EditorColorPairIndex.default).bg
    ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      cursorDisplayCol: -1,
      windowMode: EditorMode.Normal,
      windowRightEdge: right,
      isActiveWindow: false,
    )
  for i in 0 ..< rect.height:
    let
      y = rect.y + i
      line = view.topLine + i
    if y < 0 or y >= buffer.area.height:
      continue
    # A column of margin after the border, as the list has.
    discard buffer.fillCells(rect.x, y, min(right, rect.x + 1), surface)
    if line < lines.len and rect.width > 1:
      # Only the cells the row shows are styled one by one, as a window's are:
      # a minified file's line is long. The line's style context still scans
      # all of it, as a window's does.
      let
        text = lines.getLine(line)
        shown = text.shownFrom(0, rect.width - 1, e.tabStop)
      e.renderLineSegmentWithSelection(
        lines,
        buffer,
        text[shown.startByte ..< shown.endByte],
        rect.x + 1,
        y,
        line,
        shown.column,
        ctx,
        startCell = shown.cell,
      )
      buffer.onSurface(rect.x + 1, right, y, editorBg, surface.bg)
    else:
      discard buffer.fillCells(rect.x, y, right, surface)
