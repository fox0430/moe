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

import std/[strformat, options, strutils, os]

import celina_backend as celina

import types, buffer/core, modes, color, config, git_cache, unicode_utils
import syntax/tokenizer

proc toggleStatusLine*(state: var EditorState) =
  state.showStatusLine = not state.showStatusLine

proc setStatusLineVisible*(state: var EditorState, visible: bool) =
  state.showStatusLine = visible

proc toggleMultiStatusLine*(state: var EditorState) =
  state.multiStatusLine = not state.multiStatusLine

proc setMultiStatusLine*(state: var EditorState, enabled: bool) =
  state.multiStatusLine = enabled

static:
  # Verify the `statusLine<Mode>Mode` → `statusLine<Mode>ModeLabel` →
  # `statusLine<Mode>ModeInactive` triplet layout in `EditorColorPairIndex`
  # that `toStatusLineModeLabelColorIndex` depends on.
  for i in EditorColorPairIndex:
    let name = $i
    if name.startsWith("statusLine") and name.endsWith("Mode"):
      doAssert $succ(i) == name & "Label",
        "expected " & name & "Label to follow " & name
      doAssert $succ(i, 2) == name & "Inactive",
        "expected " & name & "Inactive to follow " & name & "Label"

proc toStatusLineModeColorIndex(mode: EditorMode): EditorColorPairIndex =
  ## Map an editor mode to its status line background color pair.
  ## The label/inactive variants directly follow this index in
  ## `EditorColorPairIndex` (see `toStatusLineModeLabelColorIndex`).
  case mode
  of EditorMode.Normal:
    EditorColorPairIndex.statusLineNormalMode
  of EditorMode.Insert:
    EditorColorPairIndex.statusLineInsertMode
  of EditorMode.Visual, EditorMode.VisualLine, EditorMode.VisualBlock:
    EditorColorPairIndex.statusLineVisualMode
  of EditorMode.Replace:
    EditorColorPairIndex.statusLineReplaceMode
  of EditorMode.Command:
    EditorColorPairIndex.statusLineExMode
  of EditorMode.Filer:
    EditorColorPairIndex.statusLineFilerMode
  of EditorMode.LogViewer:
    EditorColorPairIndex.statusLineLogViewerMode
  of EditorMode.Help:
    EditorColorPairIndex.statusLineHelpMode
  of EditorMode.BufferManager:
    EditorColorPairIndex.statusLineBufferManagerMode
  of EditorMode.BookmarkManager:
    EditorColorPairIndex.statusLineBookmarkManagerMode
  of EditorMode.BackupManager:
    EditorColorPairIndex.statusLineBackupManagerMode
  of EditorMode.RecoveryManager:
    EditorColorPairIndex.statusLineRecoveryManagerMode
  of EditorMode.DiffViewer:
    EditorColorPairIndex.statusLineDiffViewerMode
  of EditorMode.RecentFile:
    EditorColorPairIndex.statusLineRecentFileMode
  of EditorMode.Debug:
    EditorColorPairIndex.statusLineDebugMode
  of EditorMode.Config:
    EditorColorPairIndex.statusLineConfigMode
  of EditorMode.References:
    EditorColorPairIndex.statusLineReferencesMode
  of EditorMode.DocumentSymbol:
    EditorColorPairIndex.statusLineDocumentSymbolMode
  of EditorMode.CallHierarchy:
    EditorColorPairIndex.statusLineCallHierarchyMode
  of EditorMode.Terminal:
    EditorColorPairIndex.statusLineTerminalMode
  of EditorMode.FileTree:
    EditorColorPairIndex.statusLineFileTreeMode

proc toStatusLineModeLabelColorIndex(mode: EditorMode): EditorColorPairIndex =
  ## Map an editor mode to its status line mode label color pair.
  ## Relies on the enum layout `statusLine<Mode>Mode` →
  ## `statusLine<Mode>ModeLabel` → `statusLine<Mode>ModeInactive`.
  succ(toStatusLineModeColorIndex(mode))

proc getStatusLineModeStyle(mode: EditorMode): Style =
  ## Get the status line background style based on current mode
  getThemeStyle(toStatusLineModeColorIndex(mode), {StyleModifier.Bold})

proc getStatusLineModeLabelStyle(mode: EditorMode): Style =
  ## Get the status line mode label style based on current mode
  getThemeStyle(toStatusLineModeLabelColorIndex(mode), {StyleModifier.Bold})

proc getOverlayStyle(overlay: OverlayKind): Style =
  ## Get the status line background style for overlay modes
  getThemeStyle(EditorColorPairIndex.statusLineExMode, {StyleModifier.Bold})

proc getOverlayLabelStyle(overlay: OverlayKind): Style =
  ## Get the status line label style for overlay modes
  getThemeStyle(EditorColorPairIndex.statusLineExModeLabel, {StyleModifier.Bold})

const PreservedWorkMark* = "[recover]"
  ## A crash preserved work for this file that nobody has dealt with yet.

type
  StatusRole = enum
    ## How a part left of the ruler gives way in a narrow status line, after
    ## what stands for it in Vim.
    srLabel
      ## Vim's mode message, on the command line: kept at any width, drawn in
      ## the mode label's style
    srExtra
      ## Not in Vim's status line: goes, last first, before the name loses its
      ## last path component
    srMark
      ## A flag by Vim's file name: kept while the name is cut, then the flags
      ## lose their start as Vim's do
    srName ## Vim's file name: loses its start, `<` marking the cut

  StatusItem = object ## One part of a status line left of the ruler.
    text: string
    role: StatusRole

  Ruler = object
    text: string
    fieldWidth: int
      ## Columns kept for `text` wherever the cursor is, as Vim's ruler width:
      ## the file name is cut against them, not against `text`

proc part(text: string, role: StatusRole): StatusItem =
  StatusItem(text: text, role: role)

proc buildFileDisplay(
    textBuffer: TextBuffer,
    mode: EditorMode,
    config: StatusLineConfig,
    owesPreservedWork = false,
): seq[StatusItem] =
  ## The file display parts as config settings choose them: the file name,
  ## directory, and changed mark. Special modes (non-file-edit modes) show
  ## none, since the mode label stands for them.

  # Filer mode: show directory path
  if mode == EditorMode.Filer:
    if textBuffer.filePath.isSome:
      let path = sanitizeForDisplay(textBuffer.filePath.get())
      if dirExists(textBuffer.filePath.get()):
        return @[part(" " & path & "/", srName)]
      return @[part(" " & path, srName)]
    return

  # For other special modes, the mode label is already shown separately
  if not mode.isFileEditMode:
    return

  if textBuffer.filePath.isNone:
    return @[part(" [No Name]", srName)]

  let filePath = sanitizeForDisplay(textBuffer.filePath.get())

  # Not behind a setting: it stands for text that exists nowhere else.
  if owesPreservedWork:
    result.add part(" " & PreservedWorkMark, srMark)

  # Show directory if enabled
  let name =
    if config.directory:
      filePath
    elif config.filename:
      # Show just filename if directory is disabled
      filePath.extractFilename()
    else:
      ""
  # Not padded: a file name's own trailing spaces are part of it.
  if name.len > 0:
    result.add part(" " & name, srName)

  # Add changed mark if enabled and buffer is modified
  if config.changedMark and textBuffer.isModified:
    result.add part(" [+]", srMark)

proc buildGitInfo(
    gc: GitCacheState,
    textBuffer: TextBuffer,
    mode: EditorMode,
    config: StatusLineConfig,
    isActiveWindow: bool,
): seq[StatusItem] =
  ## Git parts (changed lines and branch name) shown ahead of the file name

  if mode == EditorMode.FileTree:
    return

  # Git changed lines count (if enabled and active window or showGitInactive)
  if config.gitChangedLines and (isActiveWindow or config.showGitInactive):
    if textBuffer.filePath.isSome:
      let counts = gc.gitDiffCounts(textBuffer)
      # Always show +N ~N -N format
      result.add part(
        " +" & $counts.added & " ~" & $counts.modified & " -" & $counts.deleted, srExtra
      )

  # Git branch name (if enabled and active window or showGitInactive)
  if config.gitBranchName and (isActiveWindow or config.showGitInactive):
    if textBuffer.filePath.isSome:
      let branch = sanitizeForDisplay(gc.gitBranchName(textBuffer))
      if branch.len > 0:
        result.add part(" ᚠ " & branch, srExtra)

proc lineEndingLabel(textBuffer: TextBuffer): string =
  ## Raw buffer: `lineEnding` is unused; report RAW.
  if not textBuffer.allowsTextTransforms:
    "RAW"
  else:
    $textBuffer.lineEnding

const
  WidestNumber = 999 ## The ruler's field fits columns and git counts up to this
  WidestModeText = block:
    var widest = ""
    for mode in EditorMode:
      for insertNormal in [false, true]:
        if modeLabel(mode, insertNormal).len > widest.len:
          widest = modeLabel(mode, insertNormal)
    for overlay in OverlayKind:
      if overlayLabel(overlay).len > widest.len:
        widest = overlayLabel(overlay)
    widest

proc windowModeText(
    state: EditorState, mode: EditorMode, isActiveWindow: bool
): string =
  ## The mode a window's status line names. Only the active window has an
  ## overlay or a pending Insert.
  if isActiveWindow and state.overlay.isSome:
    overlayLabel(state.overlay.get)
  else:
    modeLabel(mode, isActiveWindow and state.insertNormalMode)

proc parseSetupText(
    gc: GitCacheState,
    textBuffer: TextBuffer,
    cursor: BufferPosition,
    modeText, setupText: string,
    widest = false,
): string =
  ## Parse setupText format string and replace placeholders with the values of
  ## the window showing `textBuffer`. `widest` puts what changes without the
  ## buffer changing at its widest, for the ruler's field: the last line, the
  ## widest mode, and columns and git counts up to `WidestNumber`.
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
  ##   {lineEnding}    - Line ending (LF, CRLF, CR, or RAW for undecoded bytes)
  ##   {gitBranch}     - Git branch name
  ##   {gitChanges}    - Git changes (+N ~N -N)
  let
    totalLines = textBuffer.len
    # The last line also has the widest percentage
    currentLine =
      if widest:
        totalLines
      else:
        cursor.line + 1
    currentCol =
      if widest:
        WidestNumber
      else:
        cursor.column + 1
    totalCols =
      if widest:
        WidestNumber
      elif textBuffer.len > 0 and cursor.line < textBuffer.len:
        textBuffer.getLineLen(cursor.line)
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
    modeStr = if widest: WidestModeText else: modeText
    filePath =
      if textBuffer.filePath.isSome:
        sanitizeForDisplay(textBuffer.filePath.get())
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

  # Get git info (uses cached values to avoid per-frame subprocess spawns)
  var gitBranch = ""
  var gitChanges = ""
  if textBuffer.filePath.isSome:
    gitBranch = sanitizeForDisplay(gc.gitBranchName(textBuffer))
    let counts =
      if widest:
        (added: WidestNumber, modified: WidestNumber, deleted: WidestNumber)
      else:
        gc.gitDiffCounts(textBuffer)
    gitChanges = "+" & $counts.added & " ~" & $counts.modified & " -" & $counts.deleted

  result = setupText
  result = result.replace("{lineNumber}", $currentLine)
  result = result.replace("{totalLines}", $totalLines)
  result = result.replace("{columnNumber}", $currentCol)
  result = result.replace("{totalColumns}", $totalCols)
  result = result.replace("{encoding}", encoding)
  result = result.replace("{lineEnding}", lineEndingLabel(textBuffer))
  result = result.replace("{fileType}", fileType)
  result = result.replace("{percentage}", $percentage & "%")
  result = result.replace("{mode}", modeStr)
  result = result.replace("{filename}", filename)
  result = result.replace("{directory}", directory)
  result = result.replace("{filePath}", filePath)
  result = result.replace("{gitBranch}", gitBranch)
  result = result.replace("{gitChanges}", gitChanges)
  result = sanitizeForDisplay(result)

proc buildRuler(
    gc: GitCacheState,
    textBuffer: TextBuffer,
    cursor: BufferPosition,
    modeText: string,
    mode: EditorMode,
    config: StatusLineConfig,
): Ruler =
  ## The ruler of the window showing `textBuffer` in `mode`, in the setupText
  ## format as Vim's 'rulerformat'. Not padded: the layout spaces it.
  if mode == EditorMode.FileTree:
    return
  let format = config.effectiveSetupText
  Ruler(
    text: parseSetupText(gc, textBuffer, cursor, modeText, format).strip(),
    fieldWidth: charDisplayWidth(
      parseSetupText(gc, textBuffer, cursor, modeText, format, widest = true).strip()
    ),
  )

const MinCutWidth = 3 ## Narrower, a cut file name shows nothing but its mark

proc cutFromLeft(text: string, width: int): string =
  ## `text` in `width` columns, losing its start with `<` marking the cut, or
  ## nothing when that leaves less than `MinCutWidth`. A leading separator
  ## space stays.
  if charDisplayWidth(text) <= width:
    return text
  if width < MinCutWidth:
    return
  let
    lead = if text.startsWith(' '): " " else: ""
    body = text[lead.len .. ^1]
    budget = width - lead.len - 1
  var
    shownWidth = charDisplayWidth(body)
    byteOff = 0
  # Zero-width marks go with the character they combine with
  while byteOff < body.len:
    let (r, size) = body.charAtByte(byteOff)
    if shownWidth <= budget and r.charWidth > 0:
      break
    shownWidth -= r.charWidth
    byteOff += size
  lead & "<" & body[byteOff .. ^1]

proc keptWidth(name: string): int =
  ## Columns `name` keeps before extras go: its last path component, behind
  ## the `<` of the cut.
  let
    lead = if name.startsWith(' '): 1 else: 0
    path =
      if name.endsWith('/'):
        name[0 ..< ^1]
      else:
        name
    slash = path.rfind('/')
  if slash < 0:
    charDisplayWidth(name)
  else:
    min(charDisplayWidth(name), lead + 1 + charDisplayWidth(name[slash + 1 .. ^1]))

proc layoutStatusLine(
    left: openArray[StatusItem], ruler: Ruler, width: int
): tuple[left: seq[string], ruler: string, rulerCol: int] =
  ## What of `left` and `ruler` a status line `width` columns wide shows, and
  ## the column the ruler starts at, laid out as Vim lays out a file name and
  ## a ruler: the ruler's field stays right of the middle and its text, flush
  ## right in it, loses its end, and the name gets the columns left of the field, losing its
  ## start. Labels keep their columns, extras go before the name loses its
  ## last path component, and the marks lose their start once the name is
  ## gone.
  var
    widths = newSeq[int](left.len)
    labelWidth, extraWidth, markWidth, nameKept = 0
  for i, item in left:
    widths[i] = charDisplayWidth(item.text)
    case item.role
    of srLabel:
      labelWidth += widths[i]
    of srExtra:
      extraWidth += widths[i]
    of srMark:
      markWidth += widths[i]
    of srName:
      nameKept += keptWidth(item.text)

  # A blank column on each side of the ruler's field
  let field =
    min(ruler.fieldWidth, min(width div 2, width - min(labelWidth, width)) - 2)
  result.ruler = truncateToWidthWithSuffix(ruler.text, field, "").strip(leading = false)
  var room = width
  if result.ruler.len > 0:
    room = width - field - 2
    # Flush right: the field's spare columns go left of the ruler
    result.rulerCol = width - charDisplayWidth(result.ruler) - 1

  var dropped = newSeq[bool](left.len)
  for i in countdown(left.high, 0):
    if labelWidth + extraWidth + markWidth + nameKept <= room:
      break
    if left[i].role == srExtra:
      dropped[i] = true
      extraWidth -= widths[i]

  let
    fileRoom = room - labelWidth - extraWidth
    nameRoom = fileRoom - markWidth
  var
    marksAfter = markWidth
    used = 0
  result.left = newSeq[string](left.len)
  for i, item in left:
    if dropped[i]:
      continue
    result.left[i] =
      case item.role
      of srLabel, srExtra:
        # Kept extras fit: only labels wider than the window lose their end
        truncateToWidthWithSuffix(item.text, room - used, "")
      of srName:
        cutFromLeft(item.text, nameRoom)
      of srMark:
        # The marks after this one keep their columns, as Vim's trailing flags
        marksAfter -= widths[i]
        cutFromLeft(item.text, fileRoom - marksAfter)
    used += charDisplayWidth(result.left[i])

proc drawStatusLineRow(
    buffer: var Buffer,
    x, y, width: int,
    left: openArray[StatusItem],
    ruler: Ruler,
    labelStyle, lineStyle: Style,
) =
  ## Draw one status line in `width` columns from `x`, `left` from its left
  ## edge and `ruler` in its field by the right edge, as `layoutStatusLine`
  ## lays them out.
  let shown = layoutStatusLine(left, ruler, width)
  if width > 0:
    buffer.setString(x, y, " ".repeat(width), lineStyle)

  var leftX = x
  for i, item in left:
    if shown.left[i].len > 0:
      let style = if item.role == srLabel: labelStyle else: lineStyle
      leftX = buffer.setCharString(leftX, y, shown.left[i], style)

  if shown.ruler.len > 0:
    discard buffer.setCharString(x + shown.rulerCol, y, shown.ruler, lineStyle)

proc drawStatusLine(
    state: EditorState,
    textBuffer: TextBuffer,
    cursor: BufferPosition,
    buffer: var Buffer,
    x, y, width: int,
    mode: EditorMode,
    config: StatusLineConfig,
    isActiveWindow, showMode, owesPreservedWork: bool,
) =
  ## Draw the status line of a window in `mode` with its cursor at `cursor`.
  ## Only the active window shows an overlay and LSP progress.
  let modeText = state.windowModeText(mode, isActiveWindow)

  # Use overlay styles if an overlay is active, otherwise use mode styles
  let (labelStyle, lineStyle) =
    if isActiveWindow and state.overlay.isSome:
      (getOverlayLabelStyle(state.overlay.get), getOverlayStyle(state.overlay.get))
    else:
      (getStatusLineModeLabelStyle(mode), getStatusLineModeStyle(mode))

  var left: seq[StatusItem]
  if showMode:
    left.add part(fmt" {modeText} ", srLabel)
  left.add buildGitInfo(state.git, textBuffer, mode, config, isActiveWindow)
  left.add buildFileDisplay(textBuffer, mode, config, owesPreservedWork)
  if isActiveWindow and state.ui.lspProgressText.len > 0:
    # A blank column apart from the file name
    left.add part(fmt"  {sanitizeForDisplay(state.ui.lspProgressText)} ", srExtra)

  buffer.drawStatusLineRow(
    x,
    y,
    width,
    left,
    buildRuler(state.git, textBuffer, cursor, modeText, mode, config),
    labelStyle,
    lineStyle,
  )

proc renderStatusLine*(
    state: EditorState,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    statusLineY: int,
    config: StatusLineConfig,
    owesPreservedWork = false,
) =
  ## Render the status line at the specified Y position
  if not state.showStatusLine:
    return

  state.drawStatusLine(
    textBuffer,
    state.cursor,
    buffer,
    buffer.area.x,
    statusLineY,
    buffer.area.width,
    state.mode,
    config,
    isActiveWindow = true,
    showMode = config.mode,
    owesPreservedWork,
  )

proc renderWindowStatusLine*(
    state: EditorState,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    statusLineY: int,
    statusLineX: int,
    statusLineWidth: int,
    isActiveWindow: bool,
    windowMode: EditorMode,
    windowCursor: BufferPosition,
    config: StatusLineConfig,
    owesPreservedWork = false,
) =
  ## Render a status line for a specific window
  if not state.showStatusLine or not state.multiStatusLine:
    return

  state.drawStatusLine(
    textBuffer,
    windowCursor,
    buffer,
    statusLineX,
    statusLineY,
    statusLineWidth,
    windowMode,
    config,
    isActiveWindow,
    # Show mode for active window, or inactive if showModeInactive
    showMode = config.mode and (isActiveWindow or config.showModeInactive),
    owesPreservedWork,
  )
