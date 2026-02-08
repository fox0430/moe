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

## Special mode rendering procedures (filer, config mode)

import std/[options, strutils]

import pkg/celina

import editor_types, color, render_utils, filer, config_mode, editor_render_helpers

proc pathToIcon(entry: FileEntry): string =
  ## Get an emoji icon for a file entry based on its type and extension
  if entry.kind == fekDirectory or entry.targetKind == fekDirectory:
    return "📁 "

  if entry.isExecutable:
    return "🏃 "

  let filename = entry.name
  # Check for Dockerfile
  if filename == "Dockerfile" or filename.startsWith("Dockerfile."):
    return "🐳 "

  # Get extension
  let dotPos = filename.rfind('.')
  if dotPos < 0:
    return "📄 "

  let ext = filename[dotPos + 1 .. ^1].toLower()
  case ext
  of "nim": "👑 "
  of "nimble", "rpm", "deb": "📦 "
  of "py": "🐍 "
  of "ui", "glade": "🏠 "
  of "txt", "md", "rst": "📝 "
  of "cpp", "cxx", "hpp", "cc": "⧺ "
  of "c", "h": "🅒 "
  of "java": "🍵 "
  of "php": "🙈 "
  of "js", "json", "mjs", "cjs": "🙉 "
  of "ts", "tsx": "📘 "
  of "rs": "🦀 "
  of "go": "🐹 "
  of "html", "xhtml", "htm": "🏄 "
  of "css", "scss", "sass": "👚 "
  of "xml": "༕ "
  of "cfg", "ini", "conf": "🍳 "
  of "sh", "bash", "zsh", "fish": "🐚 "
  of "pdf", "doc", "docx", "odf", "ods", "odt": "🍞 "
  of "wav", "mp3", "ogg", "flac", "m4a": "🎼 "
  of "zip", "bz2", "xz", "gz", "tgz", "zst", "tar", "7z", "rar": "🚢 "
  of "exe", "bin", "elf": "🏃 "
  of "mp4", "webm", "avi", "mpeg", "mkv", "mov": "🎞 "
  of "patch", "diff": "💊 "
  of "lock": "🔒 "
  of "pem", "crt", "key": "🔏 "
  of "png", "jpeg", "jpg", "bmp", "gif", "svg", "webp", "ico": "🎨 "
  of "toml", "yaml", "yml": "⚙ "
  of "nix": "❄ "
  of "hs", "lhs": "λ "
  of "lua": "🌙 "
  of "rb": "💎 "
  of "pl", "pm": "🐪 "
  of "sql": "🗃 "
  of "vim": "📗 "
  of "el", "lisp", "scm": "λ "
  else: "📄 "

proc renderFiler*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    isBottomWindow: bool,
    tabLineOffset: int,
) =
  ## Render the file explorer view within a window's viewport
  if window.filerState.isNone:
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
    filerState = window.filerState.get
    headerY = window.viewport.y + tabLineOffset
    listStartY = window.viewport.y + tabLineOffset + 1
    listEndY = window.viewport.y + window.viewport.height - reservedBottom
    width = window.viewport.width
    startX = window.viewport.x
    theNormalStyle = normalStyle()

  # Fill the entire viewport area with spaces first
  let headerStyle =
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold})
  buffer.fillLine(startX, headerY, width, headerStyle)
  for y in listStartY ..< listEndY:
    buffer.fillLine(startX, y, width, theNormalStyle)

  # Render header (current path)
  let headerText =
    if filerState.currentPath.len > width - 2:
      "..." & filerState.currentPath[^(width - 5) .. ^1]
    else:
      filerState.currentPath
  buffer.setString(
    startX,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

  # Ensure selected entry is visible (pass total reserved: 1 header + reservedBottom)
  filerState.ensureSelectedVisible(
    window.viewport.height - tabLineOffset, 1 + reservedBottom
  )

  # Render file entries
  var screenY = listStartY
  for i in filerState.topLine ..< filerState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = filerState.entries[i]
      isSelected = i == filerState.selectedIndex

    # Build display line
    var displayLine: string

    let icon =
      if e.config.filer.showIcons:
        pathToIcon(entry)
      else:
        case entry.kind
        of fekDirectory: "▸ "
        of fekSymlink: "@ "
        of fekFile: "  "

    let name =
      if entry.isDirectory:
        entry.name & "/"
      else:
        entry.name

    displayLine = " " & icon & name

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Pad to full width for selected line (so background color fills entire line)
    if isSelected and displayLine.len < width:
      displayLine = displayLine & " ".repeat(width - displayLine.len)

    # Apply style (use theme background color to match clearBuffer)
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      elif entry.kind == fekDirectory:
        getThemeStyle(EditorColorPairIndex.filerDirectory, {StyleModifier.Bold})
      elif entry.kind == fekSymlink:
        # Symlinks: cyan for files, magenta for directories
        if entry.targetKind == fekDirectory:
          getThemeStyle(EditorColorPairIndex.filerSymlinkDir, {StyleModifier.Bold})
        else:
          getThemeStyle(EditorColorPairIndex.filerSymlink)
      elif entry.isHidden:
        getThemeStyle(EditorColorPairIndex.filerHiddenFile)
      else:
        normalStyle()

    buffer.setString(startX, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in filer mode, but set to selected line)
  e.state.screenCursor.x = startX
  e.state.screenCursor.y = listStartY + (filerState.selectedIndex - filerState.topLine)

  # Hide cursor when not in edit mode
  e.state.cursorVisible = false

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
    headerY = window.viewport.y + tabLineOffset
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
