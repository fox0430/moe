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

## Special mode rendering procedures (config mode, terminal mode)

import std/[options, strutils]

import pkg/[celina, results]

import
  types/editor_types,
  color,
  colorcode,
  render_utils,
  config_mode,
  editor_window_layout,
  unicode_utils
import terminal/ansi_parser

proc renderConfig*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    isBottomWindow: bool,
    tabLineOffset: int,
) =
  ## Render the configuration mode view within a window's viewport
  if window.modeState.kind != mskConfig:
    return

  # Calculate reserved lines at bottom for bottom windows only.
  # Steady value: a transiently grown command-line area overdraws the view,
  # exactly like multi-line status messages do.
  let reservedBottom = steadyReservedBottom(isBottomWindow)

  let
    configState = window.modeState.config
    listStartY = window.viewport.y + tabLineOffset
    listEndY = window.viewport.y + window.viewport.height - reservedBottom
    width = window.viewport.width
    startX = window.viewport.x

  # Calculate max name width for alignment
  let maxNameWidth = calcMaxNameWidth(configState.items, width)

  # Render config entries
  # (viewport.topLine is clamped to keep configState.selectedIndex visible in
  # advanceLayoutForFrame, so we can render straight from it.)
  var screenY = listStartY
  let isEditMode = configState.isEditing()
  let editInfo = configState.getEditInfo()

  # Cursor column, measured off the line drawn below. -1 while no row is edited.
  var editCursorX = -1

  # Effective search query: live text while the search overlay is open,
  # otherwise the committed query. Display is gated by the same global
  # hlsearch/hlsearchTempDisabled flags as buffer search, so a highlight
  # clear (double-Escape, :noh) in any window/mode hides Config matches too.
  let searchHighlightOn =
    e.state.input.search.hlsearch and not e.state.input.search.hlsearchTempDisabled
  let searchQuery =
    if not searchHighlightOn:
      ""
    elif e.state.isSearchOverlay():
      e.state.input.search.text
    else:
      configState.searchQuery

  for i in window.viewport.topLine ..< configState.items.len:
    if screenY >= listEndY:
      break

    let
      item = configState.items[i]
      isSelected = i == configState.selectedIndex
      # `editMode` is only set by `startEdit`, so the edited row is the selected one.
      isBeingEdited = isSelected and isEditMode

    # Build display line
    var displayLine: string
    if isBeingEdited:
      # Scroll the edit buffer horizontally to keep the cursor in the pane.
      let
        prefix = itemNamePrefix(item, maxNameWidth)
        prefixWidth = charDisplayWidth(prefix)
        valueWidth = max(1, width - prefixWidth)
        cursorWidth = editInfo.buffer.displayWidthUpTo(editInfo.cursor)
        # Scrolling by character position can skip more width than asked for.
        (scrollChar, scrollWidth) =
          editInfo.buffer.charStartAtWidth(max(0, cursorWidth - (valueWidth - 1)))
      displayLine = prefix & editInfo.buffer.charSubStr(scrollChar)
      # Clamped to the pane since the line is truncated below.
      editCursorX =
        startX + min(prefixWidth + cursorWidth - scrollWidth, max(0, width - 1))
    else:
      displayLine = formatItemForDisplay(item, maxNameWidth)

    # Truncate in display columns (width <= 0 safe). No ellipsis while editing:
    # those columns are live text the cursor can sit on.
    if charDisplayWidth(displayLine) > width:
      displayLine =
        displayLine.truncateToWidthWithSuffix(width, if isBeingEdited: "" else: "...")
    # Pad off the drawn width: truncation stops a column short when a wide
    # character straddles the cut.
    let drawnWidth = charDisplayWidth(displayLine)
    if drawnWidth < width:
      displayLine = displayLine & ' '.repeat(width - drawnWidth)

    # Apply style (use theme background color to match clearBuffer)
    let style =
      if isBeingEdited:
        # Edit mode style - yellow background
        getThemeStyle(EditorColorPairIndex.configModeEditMode)
      elif isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      elif item.kind == cvkSection:
        getThemeStyle(EditorColorPairIndex.configModeSection, {StyleModifier.Bold})
      else:
        normalStyle()

    discard buffer.setCharString(startX, screenY, displayLine, style)

    # Overlay the search highlight on just the matched characters (like buffer
    # search), instead of repainting the whole line. Skip while editing — the
    # edit style owns that line.
    if searchQuery.len > 0 and not isBeingEdited:
      let
        hlStyle = searchHighlightStyle()
        lineLower = displayLine.toLowerAscii
        queryLower = searchQuery.toLowerAscii
      var searchPos = 0
      while true:
        let idx = lineLower.find(queryLower, searchPos)
        if idx < 0:
          break
        let charIdx = displayLine.byteToCharPos(idx)
        let screenX = startX + displayLine.displayWidthUpTo(charIdx)
        discard buffer.setCharString(
          screenX, screenY, displayLine[idx ..< idx + queryLower.len], hlStyle
        )
        searchPos = idx + queryLower.len

    # Highlight the hex value with its actual color, the same way normal mode
    # renders inline color codes (color as background, contrasting foreground).
    # Skipped while editing and for "termDefault" (no concrete color).
    if item.kind == cvkColor and not isBeingEdited:
      let parsed = parseThemeColor(item.colorValue)
      if parsed.isOk and not parsed.get.isTermDefaultColor:
        # Column from the drawn width, not byte len, so a multibyte displayName
        # can't shift the highlight.
        let
          formatted = formatItemForDisplay(item, maxNameWidth)
          valueWidth = charDisplayWidth(item.colorValue)
          valueX = startX + charDisplayWidth(formatted) - valueWidth
        if valueX + valueWidth <= startX + width:
          discard buffer.setCharString(
            valueX, screenY, item.colorValue, colorCodeStyle(parsed.get)
          )

    inc screenY

  # Clear remaining lines (when sections are collapsed)
  let emptyLine = ' '.repeat(max(0, width))
  while screenY < listEndY:
    buffer.setString(startX, screenY, emptyLine, normalStyle())
    inc screenY

  # Render enum popup if open
  let isEnumPopupOpen = configState.isEnumPopupOpen()
  if isEnumPopupOpen:
    let enumInfo = configState.getEnumPopupInfo()
    if enumInfo.options.len > 0:
      # Calculate popup dimensions
      var popupWidth = 0
      for opt in enumInfo.options:
        popupWidth = max(popupWidth, opt.len)
      popupWidth += 4 # padding and border
      let popupHeight = enumInfo.options.len + 2 # options + border

      # Calculate popup position (near the value display position)
      let selectedY = listStartY + (configState.selectedIndex - window.viewport.topLine)
      let selectedItem = configState.getSelectedItem()
      var valueX = maxNameWidth + 5 # indent + name + " : "
      if selectedItem.isSome:
        valueX =
          selectedItem.get.depth * 2 + maxNameWidth - selectedItem.get.depth * 2 + 3

      var popupX = valueX
      var popupY = selectedY + 1
      # Adjust if popup goes off screen
      if popupX + popupWidth > width:
        popupX = max(0, width - popupWidth)
      if popupY + popupHeight > listEndY:
        popupY = max(listStartY, selectedY - popupHeight)
      if popupX < 0:
        popupX = 0

      let
        borderStyle = getThemeStyle(EditorColorPairIndex.configModePopupBg)
        popupNormalStyle = getThemeStyle(EditorColorPairIndex.configModePopupBg)
        selectedStyle = getThemeStyle(
          EditorColorPairIndex.configModePopupSelected, {StyleModifier.Bold}
        )

      # Draw top border
      let topBorder = "┌" & "─".repeat(popupWidth - 2) & "┐"
      buffer.setString(startX + popupX, popupY, topBorder, borderStyle)

      # Draw options
      for i, opt in enumInfo.options:
        let
          y = popupY + 1 + i
          isSelected = i == enumInfo.selectedIndex
          style = if isSelected: selectedStyle else: popupNormalStyle
          content = " " & opt.alignLeft(popupWidth - 4) & " "
        # Draw the side borders separately with the border style so the frame
        # stays consistent even on the highlighted (selected) row.
        buffer.setString(startX + popupX, y, "│", borderStyle)
        buffer.setString(startX + popupX + 1, y, content, style)
        buffer.setString(startX + popupX + popupWidth - 1, y, "│", borderStyle)

      # Draw bottom border
      let bottomBorder = "└" & "─".repeat(popupWidth - 2) & "┘"
      buffer.setString(
        startX + popupX, popupY + popupHeight - 1, bottomBorder, borderStyle
      )

  # Set cursor position and visibility - only visible in edit mode.
  # Note (M16): Config positions its own screen cursor here, inline with its
  # specialized draw, rather than in advanceLayoutForFrame. This is an idempotent
  # draw-side exception. The screen-cursor write is gated on no overlay/temp
  # message being active, since those own the cursor and are placed earlier in
  # advanceLayoutForFrame (preserving the former draw-order precedence).
  if isEditMode and editCursorX >= 0:
    if not e.state.hasOverlay and e.state.ui.tempMessages.len == 0:
      e.state.screenCursor.x = editCursorX
      e.state.screenCursor.y =
        listStartY + (configState.selectedIndex - window.viewport.topLine)
    e.state.cursorVisible = true
  else:
    # Not editing, or the edited row is outside the drawn range. An active
    # overlay (command/search) owns the cursor instead.
    e.state.cursorVisible = e.state.hasOverlay

proc terminalColorToColorValue(tc: TerminalColor): ColorValue =
  ## Convert ansi_parser TerminalColor to celina ColorValue.
  case tc.kind
  of ckDefault:
    ColorValue(kind: Default)
  of ckIndexed:
    ColorValue(kind: Indexed256, indexed256: tc.index)
  of ckRgb:
    ColorValue(kind: celina.Rgb, rgb: RgbColor(r: tc.r, g: tc.g, b: tc.b))

proc terminalCellToStyle(cell: TerminalCell): Style =
  ## Convert a TerminalCell's colors and attributes to a celina Style.
  var modifiers: set[StyleModifier] = {}
  if taBold in cell.attrs:
    modifiers.incl(StyleModifier.Bold)
  if taDim in cell.attrs:
    modifiers.incl(StyleModifier.Dim)
  if taItalic in cell.attrs:
    modifiers.incl(StyleModifier.Italic)
  if taUnderline in cell.attrs:
    modifiers.incl(StyleModifier.Underline)
  if taReverse in cell.attrs:
    modifiers.incl(StyleModifier.Reversed)
  if taStrikethrough in cell.attrs:
    modifiers.incl(StyleModifier.Crossed)

  Style(
    fg: terminalColorToColorValue(cell.fg),
    bg: terminalColorToColorValue(cell.bg),
    modifiers: modifiers,
  )

proc renderTerminal*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    isBottomWindow: bool,
    tabLineOffset: int,
) =
  ## Render the terminal emulator grid within a window's viewport.
  if window.modeState.kind != mskTerminal:
    return

  let
    termState = window.modeState.terminal
    grid = termState.grid
    startX = window.viewport.x
    startY = window.viewport.y + tabLineOffset
    # Same formula as the PTY sizing in calculateTerminalAreaDimensions, so
    # the rendered grid and the PTY size cannot diverge.
    maxRows = terminalContentRows(window, isBottomWindow, tabLineOffset)
    maxCols = window.viewport.width

  case termState.subMode
  of tsmInput:
    # Render live terminal grid directly to celina buffer
    for row in 0 ..< min(grid.rows, maxRows):
      for col in 0 ..< min(grid.cols, maxCols):
        let cell = grid.cells[row][col]
        if cell.widePadding:
          continue # celina's setString handles wide char's second column
        let style = terminalCellToStyle(cell)
        let ch = if cell.ch.len > 0: cell.ch else: " "
        buffer.setString(startX + col, startY + row, ch, style)
      # Clear remaining columns if grid is narrower than viewport
      if grid.cols < maxCols:
        let emptyStr = " ".repeat(maxCols - grid.cols)
        buffer.setString(startX + grid.cols, startY + row, emptyStr, normalStyle())

    # Clear remaining rows
    if grid.rows < maxRows:
      let emptyLine = " ".repeat(maxCols)
      for row in grid.rows ..< maxRows:
        buffer.setString(startX, startY + row, emptyLine, normalStyle())

    # Position cursor at terminal cursor location.
    # Note (M16): Terminal-Input positions its own screen cursor here from the
    # grid, inline with its specialized draw, rather than in
    # advanceLayoutForFrame. This is an idempotent draw-side exception. The
    # screen-cursor write is gated on no overlay/temp message being active, since
    # those own the cursor and are placed earlier in advanceLayoutForFrame
    # (preserving the former draw-order precedence).
    if grid.cursorVisible and grid.cursorRow < maxRows and grid.cursorCol < maxCols:
      if not e.state.hasOverlay and e.state.ui.tempMessages.len == 0:
        e.state.screenCursor.x = startX + grid.cursorCol
        e.state.screenCursor.y = startY + grid.cursorRow
      e.state.cursorVisible = true
    else:
      e.state.cursorVisible = false
  of tsmNormal:
    # In Normal sub-mode, rendering is handled by editor_render_views.nim
    # via renderWindow (the snapshot buffer is already set as window.buffer).
    e.state.cursorVisible = false
