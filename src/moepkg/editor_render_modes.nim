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

import pkg/celina

import editor_types, color, render_utils, config_mode
import terminal/ansi_parser

proc renderConfig*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    isBottomWindow: bool,
    tabLineOffset: int,
) =
  ## Render the configuration mode view within a window's viewport
  if window.configModeState.isNone:
    return

  # Calculate reserved lines at bottom for bottom windows only
  let reservedBottom =
    if isBottomWindow and e.state.display.showStatusLine:
      StatusAndCommandReserve
    elif isBottomWindow:
      CommandLineReserve
    else:
      0

  let
    configState = window.configModeState.get
    listStartY = window.viewport.y + tabLineOffset
    listEndY = window.viewport.y + window.viewport.height - reservedBottom
    width = window.viewport.width
    startX = window.viewport.x

  # Calculate max name width for alignment
  var maxNameWidth = 0
  for item in configState.items:
    if item.kind != cvkSection:
      maxNameWidth = max(maxNameWidth, item.displayName.len + item.depth * 2)
  maxNameWidth = min(maxNameWidth + 4, width div 2) # Limit to half of width

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  configState.ensureSelectedVisible(visibleLines)

  # Render config entries
  var screenY = listStartY
  let isEditMode = configState.isEditing()
  let editInfo = configState.getEditInfo()

  for i in configState.topLine ..< configState.items.len:
    if screenY >= listEndY:
      break

    let
      item = configState.items[i]
      isSelected = i == configState.selectedIndex
      isBeingEdited = isSelected and isEditMode and item.kind in {cvkInt, cvkString}

    # Build display line
    var displayLine: string
    if isBeingEdited:
      # Show edit buffer
      let indent = "  ".repeat(item.depth)
      let name = item.displayName.alignLeft(maxNameWidth - item.depth * 2)
      displayLine = indent & name & " : " & editInfo.buffer
    else:
      displayLine = formatItemForDisplay(item, maxNameWidth)

    # Truncate if too long, or pad to full width for consistent background
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."
    elif displayLine.len < width:
      displayLine = displayLine & ' '.repeat(width - displayLine.len)

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

    buffer.setString(startX, screenY, displayLine, style)
    inc screenY

  # Clear remaining lines (when sections are collapsed)
  let emptyLine = ' '.repeat(width)
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
      let selectedY = listStartY + (configState.selectedIndex - configState.topLine)
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
          line = "│ " & opt.alignLeft(popupWidth - 4) & " │"
        buffer.setString(startX + popupX, y, line, style)

      # Draw bottom border
      let bottomBorder = "└" & "─".repeat(popupWidth - 2) & "┘"
      buffer.setString(
        startX + popupX, popupY + popupHeight - 1, bottomBorder, borderStyle
      )

  # Set cursor position and visibility - only visible in edit mode
  if isEditMode:
    # Position cursor within the edit buffer
    let selectedItem = configState.getSelectedItem()
    if selectedItem.isSome:
      let item = selectedItem.get
      let indent = item.depth * 2
      let nameWidth = maxNameWidth - item.depth * 2
      # cursor x = startX + indent + name + " : " + edit cursor position
      e.state.screenCursor.x = startX + indent + nameWidth + 3 + editInfo.cursor
      e.state.screenCursor.y =
        listStartY + (configState.selectedIndex - configState.topLine)
      e.state.cursorVisible = true
  else:
    # Hide cursor when not in edit mode
    e.state.cursorVisible = false

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
  if window.terminalState.isNone:
    return

  let reservedBottom =
    if isBottomWindow and e.state.display.showStatusLine:
      StatusAndCommandReserve
    elif isBottomWindow:
      CommandLineReserve
    else:
      0

  let
    termState = window.terminalState.get
    grid = termState.grid
    startX = window.viewport.x
    startY = window.viewport.y + tabLineOffset
    maxRows = window.viewport.height - reservedBottom - tabLineOffset
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

    # Position cursor at terminal cursor location
    if grid.cursorVisible and grid.cursorRow < maxRows and grid.cursorCol < maxCols:
      e.state.screenCursor.x = startX + grid.cursorCol
      e.state.screenCursor.y = startY + grid.cursorRow
      e.state.cursorVisible = true
    else:
      e.state.cursorVisible = false
  of tsmNormal:
    # In Normal sub-mode, rendering is handled by editor_render_views.nim
    # via renderWindow (the snapshot buffer is already set as window.buffer).
    e.state.cursorVisible = false
