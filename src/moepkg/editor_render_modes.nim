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
  documentsymbol_viewer

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

proc renderFiler*(e: Editor, buffer: var Buffer) =
  ## Render the file explorer view
  if e.state.filerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    filerState = e.state.filerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header (current path)
  let headerText =
    if filerState.currentPath.len > width - 2:
      "..." & filerState.currentPath[^(width - 5) .. ^1]
    else:
      filerState.currentPath
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected entry is visible (pass total reserved: 1 header + reservedBottom)
  filerState.ensureSelectedVisible(buffer.area.height, 1 + reservedBottom)

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
    let themeBg = normalStyle().bg
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif entry.kind == fekDirectory:
        Style(fg: rgb(0x5f, 0x87, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif entry.kind == fekSymlink:
        # Symlinks: cyan for files, magenta for directories
        if entry.targetKind == fekDirectory:
          Style(fg: rgb(0xaf, 0x5f, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
        else:
          Style(fg: rgb(0x00, 0xff, 0xff), bg: themeBg, modifiers: {})
      elif entry.isHidden:
        Style(fg: rgb(0x80, 0x80, 0x80), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in filer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (filerState.selectedIndex - filerState.topLine)

proc renderBufferManager*(e: Editor, buffer: var Buffer) =
  ## Render the buffer manager view
  if e.state.bufferManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bmState = e.state.bufferManagerState.get
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
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
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
    let themeBg = normalStyle().bg
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif entry.active:
        Style(fg: rgb(0x5f, 0xff, 0x5f), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif entry.modified:
        Style(fg: rgb(0xff, 0x87, 0x00), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in buffer manager mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bmState.selectedIndex - bmState.topLine)

proc renderConfigMode*(e: Editor, buffer: var Buffer) =
  ## Render the configuration mode view
  if e.state.configModeState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    configState = e.state.configModeState.get
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
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
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
  let themeBg = normalStyle().bg

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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xd7, 0x00), modifiers: {})
      elif isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif item.kind == cvkSection:
        Style(fg: rgb(0x5f, 0xff, 0x5f), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif item.kind == cvkBool:
        if item.boolValue:
          Style(fg: rgb(0x5f, 0xaf, 0x5f), bg: themeBg, modifiers: {})
        else:
          Style(fg: rgb(0xaf, 0x5f, 0x5f), bg: themeBg, modifiers: {})
      elif item.kind == cvkEnum:
        Style(fg: rgb(0x87, 0xaf, 0xd7), bg: themeBg, modifiers: {})
      elif item.kind == cvkInt:
        Style(fg: rgb(0xd7, 0xaf, 0x5f), bg: themeBg, modifiers: {})
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
        popupBg = rgb(0x30, 0x30, 0x30)
        popupFg = rgb(0xff, 0xff, 0xff)
        selectedBg = rgb(0x00, 0x5f, 0xaf)
        borderStyle = Style(fg: popupFg, bg: popupBg, modifiers: {})
        popupNormalStyle = Style(fg: popupFg, bg: popupBg, modifiers: {})
        selectedStyle =
          Style(fg: popupFg, bg: selectedBg, modifiers: {StyleModifier.Bold})

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

  # Set cursor position - only visible in edit mode
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
  else:
    # Hide cursor by moving it off-screen
    e.state.screenCursor.x = -1
    e.state.screenCursor.y = -1

proc renderBackupManager*(e: Editor, buffer: var Buffer) =
  ## Render the backup manager view
  if e.state.backupManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bkState = e.state.backupManagerState.get
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
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Handle empty list
  if bkState.entries.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No backup files found",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: normalStyle().bg, modifiers: {}),
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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bkState.selectedIndex - bkState.topLine)

proc renderDiffViewer*(e: Editor, buffer: var Buffer) =
  ## Render the diff viewer view
  if e.state.diffViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    dvState = e.state.diffViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText =
    "-- Diff: " & extractFilename(dvState.sourceFilePath) & " vs backup --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    if headerText.len > width:
      headerText[0 ..< width]
    else:
      headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Handle empty diff
  if dvState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No diff content",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: themeBg, modifiers: {}),
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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        case line.kind
        of dlkAdded:
          # Added lines in green
          Style(fg: rgb(0x00, 0xd7, 0x00), bg: themeBg, modifiers: {})
        of dlkDeleted:
          # Deleted lines in red
          Style(fg: rgb(0xff, 0x5f, 0x5f), bg: themeBg, modifiers: {})
        of dlkHeader:
          # Header lines (@@, ---, +++) in cyan/bold
          Style(fg: rgb(0x00, 0xd7, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
        of dlkMeta:
          # Meta lines (diff --git, index) in yellow
          Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {})
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
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Handle empty list
  if state.files.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No recent files found",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: themeBg, modifiers: {}),
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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif not exists:
        # Non-existent files in dim gray
        Style(fg: rgb(0x60, 0x60, 0x60), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (state.selectedIndex - state.topLine)

proc renderDebugMode*(e: Editor, buffer: var Buffer) =
  ## Render the debug viewer
  if e.state.debugViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    debugState = e.state.debugViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width
    viewportHeight = listEndY - listStartY

  # Get theme colors
  let
    defaultStyle = getThemeStyle(EditorColorPairIndex.default)
    defaultBg = defaultStyle.bg

  # Fill entire area with default background first
  let emptyLine = spaces(width)
  for y in buffer.area.y ..< listEndY:
    buffer.setString(buffer.area.x, y, emptyLine, defaultStyle)

  # Render header
  let headerText = "-- DEBUG --"
  let headerStyle =
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: defaultBg, modifiers: {StyleModifier.Bold})
  buffer.setString(buffer.area.x, headerY, headerText, headerStyle)

  # Handle empty list
  if debugState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No debug information available",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: defaultBg, modifiers: {}),
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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif line.startsWith("--"):
        # Section headers
        Style(fg: rgb(0x87, 0xaf, 0xff), bg: defaultBg, modifiers: {StyleModifier.Bold})
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
  if e.state.referencesViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    refState = e.state.referencesViewerState.get
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
    Style(
      fg: rgb(0x00, 0xaf, 0xff), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in references viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (refState.selectedIndex - refState.topLine)

proc renderDocumentSymbolViewer*(e: Editor, buffer: var Buffer) =
  ## Render the document symbol viewer view
  if e.state.documentSymbolViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    symState = e.state.documentSymbolViewerState.get
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
    Style(
      fg: rgb(0xaf, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in document symbol viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (symState.selectedIndex - symState.topLine)

proc renderHelpViewer*(e: Editor, buffer: var Buffer) =
  ## Render the help viewer view
  if e.state.helpViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    helpState = e.state.helpViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- HELP --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
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
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif isHeader:
        Style(fg: rgb(0x5f, 0xaf, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in help viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (helpState.selectedIndex - helpState.topLine)
