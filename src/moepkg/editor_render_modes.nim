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

## Special mode rendering procedures (filer, buffer manager, config mode, etc.)

import std/[options, strutils, os]

import pkg/celina

import
  editor_types, color, render_utils, filer, buffermanager, helpviewer, configmode,
  backupmanager, diffviewer, recentfilemode, debugviewer, references_viewer,
  documentsymbol_viewer, callhierarchy_viewer

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

proc renderWindowFiler*(
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

proc renderFiler*(e: Editor, buffer: var Buffer) =
  ## Render the file explorer view (full screen mode - calls per-window version)
  e.renderWindowFiler(buffer, e.activeWindow, true, 0)

proc renderBufferManager*(e: Editor, buffer: var Buffer) =
  ## Render the buffer manager view
  if e.activeWindow.bufferManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bmState = e.activeWindow.bufferManagerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- Buffer Manager --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  if bmState.selectedIndex >= bmState.topLine + visibleLines:
    bmState.topLine = bmState.selectedIndex - visibleLines + 1
  if bmState.selectedIndex < bmState.topLine:
    bmState.topLine = bmState.selectedIndex

  # Render buffer entries
  var screenY = listStartY
  for i in bmState.topLine ..< bmState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = bmState.entries[i]
      isSelected = i == bmState.selectedIndex

    # Build display line
    var displayLine: string
    let prefix = if isSelected: "> " else: "  "
    let activeMark = if entry.active: "* " else: "  "
    let modifiedMark = if entry.modified: "[+] " else: "    "
    let indexStr = $entry.index & ": "

    displayLine = prefix & activeMark & indexStr & modifiedMark & entry.name

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
      elif entry.active:
        getThemeStyle(EditorColorPairIndex.bufferManagerActive, {StyleModifier.Bold})
      elif entry.modified:
        getThemeStyle(EditorColorPairIndex.bufferManagerModified)
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in buffer manager mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bmState.selectedIndex - bmState.topLine)

proc renderConfigMode*(e: Editor, buffer: var Buffer) =
  ## Render the configuration mode view
  if e.activeWindow.configModeState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    configState = e.activeWindow.configModeState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  var headerText = "-- Configuration --"
  if headerText.len < width:
    headerText = headerText & ' '.repeat(width - headerText.len)
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

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
      elif item.kind == cvkBool:
        if item.boolValue:
          getThemeStyle(EditorColorPairIndex.configModeBoolTrue)
        else:
          getThemeStyle(EditorColorPairIndex.configModeBoolFalse)
      elif item.kind == cvkEnum:
        getThemeStyle(EditorColorPairIndex.configModeEnum)
      elif item.kind == cvkInt:
        getThemeStyle(EditorColorPairIndex.configModeInt)
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Clear remaining lines (when sections are collapsed)
  let emptyLine = ' '.repeat(width)
  while screenY < listEndY:
    buffer.setString(buffer.area.x, screenY, emptyLine, normalStyle())
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
      buffer.setString(buffer.area.x + popupX, popupY, topBorder, borderStyle)

      # Draw options
      for i, opt in enumInfo.options:
        let
          y = popupY + 1 + i
          isSelected = i == enumInfo.selectedIndex
          style = if isSelected: selectedStyle else: popupNormalStyle
          line = "│ " & opt.alignLeft(popupWidth - 4) & " │"
        buffer.setString(buffer.area.x + popupX, y, line, style)

      # Draw bottom border
      let bottomBorder = "└" & "─".repeat(popupWidth - 2) & "┘"
      buffer.setString(
        buffer.area.x + popupX, popupY + popupHeight - 1, bottomBorder, borderStyle
      )

  # Set cursor position and visibility - only visible in edit mode
  if isEditMode:
    # Position cursor within the edit buffer
    let selectedItem = configState.getSelectedItem()
    if selectedItem.isSome:
      let item = selectedItem.get
      let indent = item.depth * 2
      let nameWidth = maxNameWidth - item.depth * 2
      # cursor x = indent + name + " : " + edit cursor position
      e.state.screenCursor.x = indent + nameWidth + 3 + editInfo.cursor
      e.state.screenCursor.y =
        listStartY + (configState.selectedIndex - configState.topLine)
      e.state.cursorVisible = true
  else:
    # Hide cursor when not in edit mode
    e.state.cursorVisible = false

proc renderWindowConfig*(
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
    listStartY = window.viewport.y + tabLineOffset + 1
    listEndY = window.viewport.y + window.viewport.height - reservedBottom
    width = window.viewport.width
    startX = window.viewport.x

  # Render header
  var headerText = "-- Configuration --"
  if headerText.len < width:
    headerText = headerText & ' '.repeat(width - headerText.len)
  buffer.setString(
    startX,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

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
      elif item.kind == cvkBool:
        if item.boolValue:
          getThemeStyle(EditorColorPairIndex.configModeBoolTrue)
        else:
          getThemeStyle(EditorColorPairIndex.configModeBoolFalse)
      elif item.kind == cvkEnum:
        getThemeStyle(EditorColorPairIndex.configModeEnum)
      elif item.kind == cvkInt:
        getThemeStyle(EditorColorPairIndex.configModeInt)
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

proc renderBackupManager*(e: Editor, buffer: var Buffer) =
  ## Render the backup manager view
  if e.activeWindow.backupManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bkState = e.activeWindow.backupManagerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- Backup Manager: " & bkState.sourceFilePath & " --"
  buffer.setString(
    buffer.area.x,
    headerY,
    if headerText.len > width:
      headerText[0 ..< width]
    else:
      headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

  # Handle empty list
  if bkState.entries.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No backup files found",
      getThemeStyle(EditorColorPairIndex.viewerEmptyMessage),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  if bkState.selectedIndex >= bkState.topLine + visibleLines:
    bkState.topLine = bkState.selectedIndex - visibleLines + 1
  if bkState.selectedIndex < bkState.topLine:
    bkState.topLine = bkState.selectedIndex

  # Render backup entries
  var screenY = listStartY
  for i in bkState.topLine ..< bkState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = bkState.entries[i]
      isSelected = i == bkState.selectedIndex

    # Build display line with formatted timestamp
    let prefix = if isSelected: "> " else: "  "
    let displayLine = prefix & formatEntry(entry)

    # Apply style (use theme background color to match clearBuffer)
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bkState.selectedIndex - bkState.topLine)

proc renderDiffViewer*(e: Editor, buffer: var Buffer) =
  ## Render the diff viewer view
  if e.activeWindow.diffViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    dvState = e.activeWindow.diffViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText =
    "-- Diff: " & extractFilename(dvState.sourceFilePath) & " vs backup --"
  buffer.setString(
    buffer.area.x,
    headerY,
    if headerText.len > width:
      headerText[0 ..< width]
    else:
      headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

  # Handle empty diff
  if dvState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No diff content",
      getThemeStyle(EditorColorPairIndex.viewerEmptyMessage),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Ensure selected line is visible
  let visibleLines = listEndY - listStartY
  if dvState.selectedLine >= dvState.topLine + visibleLines:
    dvState.topLine = dvState.selectedLine - visibleLines + 1
  if dvState.selectedLine < dvState.topLine:
    dvState.topLine = dvState.selectedLine

  # Render diff lines
  var screenY = listStartY
  for i in dvState.topLine ..< dvState.lines.len:
    if screenY >= listEndY:
      break

    let
      line = dvState.lines[i]
      isSelected = i == dvState.selectedLine

    # Truncate line if too long
    let displayText =
      if line.text.len > width:
        line.text[0 ..< width]
      else:
        line.text

    # Apply style based on diff line kind and selection (use theme background)
    let style =
      if isSelected:
        # Highlighted/selected line
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      else:
        case line.kind
        of dlkAdded:
          # Added lines in green
          getThemeStyle(EditorColorPairIndex.diffViewerAddedLine)
        of dlkDeleted:
          # Deleted lines in red
          getThemeStyle(EditorColorPairIndex.diffViewerDeletedLine)
        of dlkHeader:
          # Header lines (@@, ---, +++) in cyan/bold
          getThemeStyle(EditorColorPairIndex.diffViewerHeader, {StyleModifier.Bold})
        of dlkMeta:
          # Meta lines (diff --git, index) in yellow
          getThemeStyle(EditorColorPairIndex.diffViewerMeta)
        of dlkNormal:
          # Normal context lines
          normalStyle()

    buffer.setString(buffer.area.x, screenY, displayText, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (dvState.selectedLine - dvState.topLine)

proc renderRecentFileMode*(e: Editor, buffer: var Buffer) =
  ## Render the recent file selection view
  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    state = e.recentFileModeState
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width
    viewportHeight = listEndY - listStartY

  # Render header
  let headerText = "-- Recent Files --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

  # Handle empty list
  if state.files.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No recent files found",
      getThemeStyle(EditorColorPairIndex.viewerEmptyMessage),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Adjust viewport to keep selected visible
  state.adjustViewport(viewportHeight)

  # Render file entries
  let visibleFiles = state.getVisibleFiles(viewportHeight)
  var screenY = listStartY
  for i, entry in visibleFiles:
    if screenY >= listEndY:
      break

    let
      actualIndex = state.topLine + i
      isSelected = actualIndex == state.selectedIndex

    # Build display line
    let prefix = if isSelected: "> " else: "  "
    var displayLine = prefix & entry.path

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Apply style - check if file exists (use theme background)
    let exists = fileExists(entry.path)
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      elif not exists:
        # Non-existent files in dim gray
        getThemeStyle(EditorColorPairIndex.recentFileMissing)
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (state.selectedIndex - state.topLine)

proc renderDebugMode*(e: Editor, buffer: var Buffer) =
  ## Render the debug viewer
  if e.activeWindow.debugViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    debugState = e.activeWindow.debugViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width
    viewportHeight = listEndY - listStartY

  # Get theme colors
  let defaultStyle = getThemeStyle(EditorColorPairIndex.default)

  # Fill entire area with default background first
  let emptyLine = spaces(width)
  for y in buffer.area.y ..< listEndY:
    buffer.setString(buffer.area.x, y, emptyLine, defaultStyle)

  # Render header
  let headerText = "-- DEBUG --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

  # Handle empty list
  if debugState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No debug information available",
      getThemeStyle(EditorColorPairIndex.viewerEmptyMessage),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Render debug lines
  var screenY = listStartY
  for i in debugState.topLine ..<
      min(debugState.lines.len, debugState.topLine + viewportHeight):
    if screenY >= listEndY:
      break

    let
      line = debugState.lines[i]
      isSelected = i == debugState.selectedLine

    # Truncate if too long
    var displayLine = line
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Apply style based on content
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      elif line.startsWith("--"):
        # Section headers
        getThemeStyle(
          EditorColorPairIndex.debugViewerSectionHeader, {StyleModifier.Bold}
        )
      else:
        defaultStyle

    # Pad line to fill width for consistent background
    let paddedLine = displayLine & spaces(max(0, width - displayLine.len))
    buffer.setString(buffer.area.x, screenY, paddedLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (debugState.selectedLine - debugState.topLine)

proc renderReferencesViewer*(e: Editor, buffer: var Buffer) =
  ## Render the references viewer view
  if e.activeWindow.referencesViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    refState = e.activeWindow.referencesViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header with title
  let headerText =
    "-- " & refState.title.toUpperAscii() & " (" & $refState.itemCount() & ") --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.referencesViewerHeader, {StyleModifier.Bold}),
  )

  # Ensure selected line is visible
  refState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render reference lines
  var screenY = listStartY
  for i in refState.topLine ..< refState.itemCount:
    if screenY >= listEndY:
      break

    let
      line = refState.getLine(i)
      isSelected = i == refState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in references viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (refState.selectedIndex - refState.topLine)

proc renderDocumentSymbolViewer*(e: Editor, buffer: var Buffer) =
  ## Render the document symbol viewer view
  if e.activeWindow.documentSymbolViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    symState = e.activeWindow.documentSymbolViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header with title
  let headerText = "-- SYMBOLS (" & $symState.itemCount() & ") --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.documentSymbolViewerHeader, {StyleModifier.Bold}),
  )

  # Ensure selected line is visible
  symState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render symbol lines
  var screenY = listStartY
  for i in symState.topLine ..< symState.itemCount:
    if screenY >= listEndY:
      break

    let
      line = symState.getLine(i)
      isSelected = i == symState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in document symbol viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (symState.selectedIndex - symState.topLine)

proc renderCallHierarchyViewer*(e: Editor, buffer: var Buffer) =
  ## Render the call hierarchy viewer view
  if e.activeWindow.callHierarchyViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    chState = e.activeWindow.callHierarchyViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header with title
  let headerText = "-- " & chState.title & " (" & $chState.itemCount() & ") --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.callHierarchyViewerHeader, {StyleModifier.Bold}),
  )

  # Ensure selected line is visible
  chState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render call hierarchy lines
  var screenY = listStartY
  for i in chState.topLine ..< chState.itemCount:
    if screenY >= listEndY:
      break

    let
      line = chState.getLine(i)
      isSelected = i == chState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in call hierarchy viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (chState.selectedIndex - chState.topLine)

proc renderHelpViewer*(e: Editor, buffer: var Buffer) =
  ## Render the help viewer view
  if e.activeWindow.helpViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    helpState = e.activeWindow.helpViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- HELP --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    getThemeStyle(EditorColorPairIndex.viewerHeader, {StyleModifier.Bold}),
  )

  # Ensure selected line is visible
  helpState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render help lines
  var screenY = listStartY
  for i in helpState.topLine ..< helpState.lineCount:
    if screenY >= listEndY:
      break

    let
      line = helpState.getLine(i)
      isSelected = i == helpState.selectedIndex
      isHeader = line.len > 0 and line[0] == '#'

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        getThemeStyle(EditorColorPairIndex.viewerSelectedLine)
      elif isHeader:
        getThemeStyle(
          EditorColorPairIndex.helpViewerSectionHeader, {StyleModifier.Bold}
        )
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in help viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (helpState.selectedIndex - helpState.topLine)
