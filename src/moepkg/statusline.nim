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

import std/[strformat, options, strutils, os, unicode]

import pkg/[celina, results]

import types, buffer, modes, color, config, gitdiff, unicode_utils, highlight
import syntax/highlite

proc toggleStatusLine*(state: var EditorState) =
  ## Toggle the visibility of the status line
  state.display.showStatusLine = not state.display.showStatusLine

proc setStatusLineVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of the status line
  state.display.showStatusLine = visible

proc toggleLineCount*(state: var EditorState) =
  ## Toggle the visibility of line count in status line
  state.display.showLineCount = not state.display.showLineCount

proc setLineCountVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of line count in status line
  state.display.showLineCount = visible

proc toggleLinePercentage*(state: var EditorState) =
  ## Toggle the visibility of line percentage in status line
  state.display.showLinePercentage = not state.display.showLinePercentage

proc setLinePercentageVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of line percentage in status line
  state.display.showLinePercentage = visible

proc toggleEncoding*(state: var EditorState) =
  ## Toggle the visibility of encoding in status line
  state.display.showEncoding = not state.display.showEncoding

proc setEncodingVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of encoding in status line
  state.display.showEncoding = visible

proc toggleMultiStatusLine*(state: var EditorState) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  state.display.multiStatusLine = not state.display.multiStatusLine

proc setMultiStatusLine*(state: var EditorState, enabled: bool) =
  ## Set multi status line mode
  state.display.multiStatusLine = enabled

proc getStatusLineModeStyle(mode: EditorMode): Style =
  ## Get the status line background style based on current mode
  case mode
  of EditorMode.Normal:
    getThemeStyle(EditorColorPairIndex.statusLineNormalMode, {StyleModifier.Bold})
  of EditorMode.Insert:
    getThemeStyle(EditorColorPairIndex.statusLineInsertMode, {StyleModifier.Bold})
  of EditorMode.Visual, EditorMode.VisualLine, EditorMode.VisualBlock:
    getThemeStyle(EditorColorPairIndex.statusLineVisualMode, {StyleModifier.Bold})
  of EditorMode.Replace:
    getThemeStyle(EditorColorPairIndex.statusLineReplaceMode, {StyleModifier.Bold})
  of EditorMode.Filer:
    getThemeStyle(EditorColorPairIndex.statusLineFilerMode, {StyleModifier.Bold})
  of EditorMode.Command, EditorMode.Search:
    getThemeStyle(EditorColorPairIndex.statusLineExMode, {StyleModifier.Bold})
  else:
    getThemeStyle(EditorColorPairIndex.statusLineNormalMode, {StyleModifier.Bold})

proc getStatusLineModeLabelStyle(mode: EditorMode): Style =
  ## Get the status line mode label style based on current mode
  case mode
  of EditorMode.Normal:
    getThemeStyle(EditorColorPairIndex.statusLineNormalModeLabel, {StyleModifier.Bold})
  of EditorMode.Insert:
    getThemeStyle(EditorColorPairIndex.statusLineInsertModeLabel, {StyleModifier.Bold})
  of EditorMode.Visual, EditorMode.VisualLine, EditorMode.VisualBlock:
    getThemeStyle(EditorColorPairIndex.statusLineVisualModeLabel, {StyleModifier.Bold})
  of EditorMode.Replace:
    getThemeStyle(EditorColorPairIndex.statusLineReplaceModeLabel, {StyleModifier.Bold})
  of EditorMode.Filer:
    getThemeStyle(EditorColorPairIndex.statusLineFilerModeLabel, {StyleModifier.Bold})
  of EditorMode.Command, EditorMode.Search:
    getThemeStyle(EditorColorPairIndex.statusLineExModeLabel, {StyleModifier.Bold})
  else:
    getThemeStyle(EditorColorPairIndex.statusLineNormalModeLabel, {StyleModifier.Bold})

proc buildFileDisplay(textBuffer: TextBuffer, config: StatusLineConfig): string =
  ## Build the file display text based on config settings
  ## Includes filename, directory, and changed mark as configured
  if textBuffer.filePath.isNone:
    return " [No Name]"

  let filePath = textBuffer.filePath.get()

  var displayText = " "

  # Show directory if enabled
  if config.directory:
    displayText &= filePath
  else:
    # Show just filename if directory is disabled
    if config.filename:
      displayText &= filePath.extractFilename()
    else:
      displayText &= filePath.extractFilename()

  # Add changed mark if enabled and buffer is modified
  if config.chanedMark and textBuffer.isModified:
    displayText &= " [+]"

  return displayText

proc buildGitInfo(
    textBuffer: TextBuffer, config: StatusLineConfig, isActiveWindow: bool
): string =
  ## Build git info text (branch name and changed lines) for display before filename
  var parts: seq[string] = @[]

  # Git changed lines count (if enabled and active window or showGitInactive)
  if config.gitChangedLines and (isActiveWindow or config.showGitInactive):
    if textBuffer.filePath.isSome:
      let diffResult = getGitDiffFromBuffer(textBuffer)
      if not diffResult.isErr:
        let counts = countGitChangedLines(diffResult.get())
        # Always show +N ~N -N format
        parts.add(
          " +" & $counts.added & " ~" & $counts.modified & " -" & $counts.deleted
        )

  # Git branch name (if enabled and active window or showGitInactive)
  if config.gitBranchName and (isActiveWindow or config.showGitInactive):
    if textBuffer.filePath.isSome:
      let branchResult = getGitBranch(textBuffer.filePath.get())
      if not branchResult.isErr:
        parts.add("ᚠ " & branchResult.get())

  if parts.len > 0:
    return parts.join(" ")
  else:
    return ""

proc parseSetupText(
    state: EditorState, textBuffer: TextBuffer, setupText: string
): string =
  ## Parse setupText format string and replace placeholders with actual values.
  ## Supported placeholders:
  ##   {lineNumber}    - Current line number (1-indexed)
  ##   {totalLines}    - Total lines in buffer
  ##   {columnNumber}  - Current column number (1-indexed)
  ##   {totalColumns}  - Total columns in current line
  ##   {encoding}      - File encoding (e.g., "UTF-8")
  ##   {fileType}      - File type/language (e.g., "Nim", "Toml")
  ##   {percentage}    - Line percentage (e.g., "50%")
  ##   {mode}          - Current editor mode
  ##   {filename}      - Filename only
  ##   {directory}     - Directory path
  ##   {filePath}      - Full file path
  ##   {gitBranch}     - Git branch name
  ##   {gitChanges}    - Git changes (+N ~N -N)
  let
    currentLine = state.cursor.line + 1
    totalLines = textBuffer.len
    currentCol = state.cursor.column + 1
    totalCols =
      if textBuffer.len > 0 and state.cursor.line < textBuffer.len:
        textBuffer[state.cursor.line].len
      else:
        0
    percentage =
      if totalLines > 0:
        int((currentLine.float / totalLines.float) * 100.0)
      else:
        0
    fileType =
      if textBuffer.language != SourceLanguage.langNone:
        sourceLanguageToStr[textBuffer.language]
      else:
        ""
    encoding = encodingToString(textBuffer.encoding)
    modeStr = modeLabel(state.mode)
    filePath =
      if textBuffer.filePath.isSome:
        textBuffer.filePath.get()
      else:
        ""
    filename =
      if filePath.len > 0:
        filePath.extractFilename()
      else:
        ""
    directory =
      if filePath.len > 0:
        filePath.parentDir()
      else:
        ""

  # Get git info
  var gitBranch = ""
  var gitChanges = ""
  if textBuffer.filePath.isSome:
    let branchResult = getGitBranch(textBuffer.filePath.get())
    if not branchResult.isErr:
      gitBranch = branchResult.get()
    let diffResult = getGitDiffFromBuffer(textBuffer)
    if not diffResult.isErr:
      let counts = countGitChangedLines(diffResult.get())
      gitChanges =
        "+" & $counts.added & " ~" & $counts.modified & " -" & $counts.deleted

  result = setupText
  result = result.replace("{lineNumber}", $currentLine)
  result = result.replace("{totalLines}", $totalLines)
  result = result.replace("{columnNumber}", $currentCol)
  result = result.replace("{totalColumns}", $totalCols)
  result = result.replace("{encoding}", encoding)
  result = result.replace("{fileType}", fileType)
  result = result.replace("{percentage}", $percentage & "%")
  result = result.replace("{mode}", modeStr)
  result = result.replace("{filename}", filename)
  result = result.replace("{directory}", directory)
  result = result.replace("{filePath}", filePath)
  result = result.replace("{gitBranch}", gitBranch)
  result = result.replace("{gitChanges}", gitChanges)

proc buildRightSideInfo(
    state: EditorState,
    textBuffer: TextBuffer,
    config: StatusLineConfig,
    isActiveWindow: bool,
): string =
  ## Build the right-side status line info (file type, encoding, line count, etc.)
  ## If setupText is configured, use custom format; otherwise use default format.

  # Use custom format if setupText is configured
  if config.setupText.len > 0:
    let customText = parseSetupText(state, textBuffer, config.setupText)
    if customText.len > 0:
      return " " & customText
    else:
      return ""

  # Default format
  var parts: seq[string] = @[]

  # File type (language)
  if textBuffer.language != SourceLanguage.langNone:
    parts.add(sourceLanguageToStr[textBuffer.language])

  # Encoding
  if state.display.showEncoding:
    parts.add(encodingToString(textBuffer.encoding))

  # Line percentage
  if state.display.showLinePercentage:
    let
      currentLine = state.cursor.line + 1
      totalLines = textBuffer.len
      percentage =
        if totalLines > 0:
          int((currentLine.float / totalLines.float) * 100.0)
        else:
          0
    parts.add(fmt"{percentage}%")

  # Line count
  if state.display.showLineCount:
    let
      currentLine = state.cursor.line + 1
      totalLines = textBuffer.len
    parts.add(fmt"{currentLine}/{totalLines}")

  if parts.len > 0:
    return " " & parts.join(" ")
  else:
    return ""

proc renderStatusLine*(
    state: EditorState,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    statusLineY: int,
    config: StatusLineConfig,
) =
  ## Render the status line at the specified Y position
  if not state.display.showStatusLine:
    return

  let
    modeLabelStyle = getStatusLineModeLabelStyle(state.mode)
    statusLineStyle = getStatusLineModeStyle(state.mode)

  # Build mode label (always shown in single status line mode)
  let modeLabelText =
    if config.mode:
      fmt" {modeLabel(state.mode)} "
    else:
      ""

  # Build git info (displayed before filename)
  let gitInfoText = buildGitInfo(textBuffer, config, true)

  # Build file display text
  let filePathText = buildFileDisplay(textBuffer, config)

  let statusLeftWidth =
    displayWidth(modeLabelText) + displayWidth(gitInfoText) + displayWidth(filePathText)

  var currentX = buffer.area.x

  # Draw mode label
  if modeLabelText.len > 0:
    buffer.setString(currentX, statusLineY, modeLabelText, modeLabelStyle)
    currentX += displayWidth(modeLabelText)

  # Draw git info (same style as filename)
  if gitInfoText.len > 0:
    buffer.setString(currentX, statusLineY, gitInfoText, statusLineStyle)
    currentX += displayWidth(gitInfoText)

  # Draw file path
  buffer.setString(currentX, statusLineY, filePathText, statusLineStyle)
  currentX += displayWidth(filePathText)

  # Build right side info
  let rightSideText = buildRightSideInfo(state, textBuffer, config, true)
  let rightSideWidth = displayWidth(rightSideText)

  # Build LSP progress text (displayed in the middle section)
  let progressText =
    if state.lspProgressText.len > 0:
      " " & state.lspProgressText & " "
    else:
      ""
  let progressWidth = displayWidth(progressText)

  # Fill the rest of the line with background
  let remainingWidth = max(0, buffer.area.width - statusLeftWidth)
  if remainingWidth > 0:
    let background = " ".repeat(remainingWidth)
    buffer.setString(currentX, statusLineY, background, statusLineStyle)

  # Draw LSP progress (in the middle, after left side content)
  if progressText.len > 0:
    let progressX = currentX + 1 # Add some padding after file path
    if progressX + progressWidth < buffer.area.x + buffer.area.width - rightSideWidth - 2:
      buffer.setString(progressX, statusLineY, progressText, statusLineStyle)

  # Draw right side info
  if rightSideText.len > 0 and buffer.area.width >= rightSideWidth + 1:
    buffer.setString(
      buffer.area.x + buffer.area.width - rightSideWidth - 1,
      statusLineY,
      rightSideText,
      statusLineStyle,
    )

proc renderWindowStatusLine*(
    state: EditorState,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    statusLineY: int,
    statusLineX: int,
    statusLineWidth: int,
    isActiveWindow: bool,
    config: StatusLineConfig,
) =
  ## Render a status line for a specific window
  if not state.display.showStatusLine or not state.display.multiStatusLine:
    return

  let
    modeLabelStyle = getStatusLineModeLabelStyle(state.mode)
    statusLineStyle = getStatusLineModeStyle(state.mode)

  # Build mode label (show for active window, or inactive if showModeInactive)
  let showMode = config.mode and (isActiveWindow or config.showModeInactive)
  let modeLabelText =
    if showMode:
      fmt" {modeLabel(state.mode)} "
    else:
      ""

  # Build git info (displayed before filename)
  let gitInfoText = buildGitInfo(textBuffer, config, isActiveWindow)

  # Build file display text
  let filePathText = buildFileDisplay(textBuffer, config)

  # Draw mode label with white background
  var currentX = statusLineX
  if modeLabelText.len > 0:
    buffer.setString(currentX, statusLineY, modeLabelText, modeLabelStyle)
    currentX += displayWidth(modeLabelText)

  # Draw git info (same style as filename)
  if gitInfoText.len > 0:
    buffer.setString(currentX, statusLineY, gitInfoText, statusLineStyle)
    currentX += displayWidth(gitInfoText)

  # Build and draw file path (with truncation if needed)
  let
    maxFilePathWidth = statusLineWidth - (currentX - statusLineX) - 1
    filePathWidth = displayWidth(filePathText)
    truncatedFilePath =
      if filePathWidth > maxFilePathWidth:
        let (charCount, _) = displayWidthSubstr(filePathText, 0, maxFilePathWidth)
        var s = ""
        var i = 0
        for r in filePathText.runes:
          if i >= charCount:
            break
          s.add($r)
          i.inc
        s
      else:
        filePathText

  buffer.setString(currentX, statusLineY, truncatedFilePath, statusLineStyle)
  currentX += displayWidth(truncatedFilePath)

  # Build right side info
  let rightSideText = buildRightSideInfo(state, textBuffer, config, isActiveWindow)
  let rightSideWidth = displayWidth(rightSideText)

  # Build LSP progress text (displayed in the middle section, only for active window)
  let progressText =
    if isActiveWindow and state.lspProgressText.len > 0:
      " " & state.lspProgressText & " "
    else:
      ""
  let progressWidth = displayWidth(progressText)

  # Fill the rest of the line with background
  let remainingWidth = max(0, (statusLineX + statusLineWidth) - currentX)
  if remainingWidth > 0:
    let background = " ".repeat(remainingWidth)
    buffer.setString(currentX, statusLineY, background, statusLineStyle)

  # Draw LSP progress (in the middle, after left side content)
  if progressText.len > 0:
    let progressX = currentX + 1 # Add some padding after file path
    if progressX + progressWidth < statusLineX + statusLineWidth - rightSideWidth - 2:
      buffer.setString(progressX, statusLineY, progressText, statusLineStyle)

  # Draw right side info
  if rightSideText.len > 0 and statusLineWidth >= rightSideWidth + 1:
    buffer.setString(
      statusLineX + statusLineWidth - rightSideWidth - 1,
      statusLineY,
      rightSideText,
      statusLineStyle,
    )
