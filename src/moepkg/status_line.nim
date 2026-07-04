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

import std/[strformat, options, strutils, os, unicode, tables, monotimes, times]

import pkg/[celina, results]

import types, buffer, modes, color, config, git_diff, unicode_utils, highlight
import syntax/tokenizer

type
  GitDiffCacheEntry = object
    counts: tuple[added, modified, deleted: int]
    changeSeqAtRefresh: int
    lastRefresh: MonoTime
    pending: Option[GitDiffProcess]
    populated: bool
    gitTracked: bool
      ## Whether the buffer's file is tracked by git (exists in HEAD). Set from the
      ## result of `startGitDiffFromBufferAsync`, which errors for files not under
      ## git. When true, the git-diff gutter is the authoritative change indicator,
      ## so the session "modified lines" sidebar fallback is suppressed (it would
      ## otherwise draw the same `~`/`+` glyphs and linger after the buffer is
      ## edited back to match HEAD, since it is history- rather than content-based).
    pendingDiffInfo: Option[GitDiffInfo]
      ## Holds the most recent completed diff so the sidebar gutter can be
      ## refreshed independently of the status-line `counts` readout. The
      ## editor tick consumes this via `maybeApplyGitMarkers`, gated on the
      ## user's `showGitDiff` flag — we don't touch `lineMarkers` from the
      ## render path anymore.

  GitBranchCacheEntry = object
    path: string
    name: string
    lastRefresh: MonoTime
    populated: bool

# Per-buffer git status cache for the status line. Without caching, every
# frame spawns `git diff --no-index` (dumping the whole buffer to a tempfile
# — ~30ms on a 40k-line JSON) and `git rev-parse --abbrev-ref HEAD`, pegging
# idle j/k at ~30 FPS. The buffer reference (ref object) is used as the
# key; entries for closed buffers linger but are small.
#
# Diff refresh strategy: non-blocking. We spawn `git diff` in the background
# via startGitDiffFromBufferAsync and keep showing the previous counts until
# the process completes. A refresh is kicked off when changeSeq changes OR
# the last refresh is older than GitDiffRefreshIntervalMs — the TTL path is
# what picks up external commits / checkouts without an edit.
#
# Branch refresh strategy: synchronous TTL. `git rev-parse` is cheap
# (~5ms) and re-running it on every keystroke is unnecessary but also not
# catastrophic. A short TTL keeps branch switches in sync.
const
  DefaultGitDiffRefreshIntervalMs: int64 = 2000
  GitBranchTtlMs = 5000

var
  diffCacheStore: Table[pointer, GitDiffCacheEntry]
  branchCacheStore: Table[pointer, GitBranchCacheEntry]
  gitDiffRefreshIntervalMs: int64 = DefaultGitDiffRefreshIntervalMs

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

proc setLineEndingVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of line ending in status line
  state.display.showLineEnding = visible

proc toggleMultiStatusLine*(state: var EditorState) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  state.display.multiStatusLine = not state.display.multiStatusLine

proc setMultiStatusLine*(state: var EditorState, enabled: bool) =
  ## Set multi status line mode
  state.display.multiStatusLine = enabled

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
  of EditorMode.QuickRun:
    EditorColorPairIndex.statusLineQuickRunMode
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

proc buildFileDisplay(
    textBuffer: TextBuffer, mode: EditorMode, config: StatusLineConfig
): string =
  ## Build the file display text based on config settings
  ## For special modes (non-file-edit modes), show mode label instead of filename
  ## Includes filename, directory, and changed mark as configured

  # Filer mode: show directory path
  if mode == EditorMode.Filer:
    if textBuffer.filePath.isSome:
      let path = textBuffer.filePath.get()
      if dirExists(path):
        return " " & path & "/"
      return " " & path
    return ""

  # For other special modes, the mode label is already shown separately
  if not mode.isFileEditMode:
    return ""

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
  if config.changedMark and textBuffer.isModified:
    displayText &= " [+]"

  return displayText

proc setGitDiffRefreshInterval*(ms: int64) =
  ## Override the async diff refresh cadence (ms). Called from
  ## `applyConfigSettings` so the existing `[git] updateInterval` toml
  ## setting still controls how often the status-line counts (and sidebar
  ## gutter, via `maybeApplyGitMarkers`) re-check against HEAD.
  if ms > 0:
    gitDiffRefreshIntervalMs = ms

proc bufferKey(b: TextBuffer): pointer {.inline.} =
  cast[pointer](b)

proc cachedGitDiffCounts(b: TextBuffer): tuple[added, modified, deleted: int] =
  let key = bufferKey(b)
  var entry = diffCacheStore.getOrDefault(key)

  # If a background git diff was running, check if it finished this frame.
  if entry.pending.isSome:
    let completion = checkGitDiffComplete(entry.pending.get)
    if completion.isSome:
      if completion.get.isOk:
        let diffInfo = completion.get.get
        entry.counts = countGitChangedLines(diffInfo)
        # Stash the completed diff for the sidebar gutter. The actual
        # `applyGitDiffToBuffer` is deferred to `maybeApplyGitMarkers`,
        # called from editor.tick under the `showGitDiff` flag — so the
        # gutter is only mutated when the user has opted in.
        entry.pendingDiffInfo = some(diffInfo)
      # On error/timeout we keep the last known counts — better to show
      # slightly stale info than to flicker to zero.
      entry.pending = none(GitDiffProcess)
      entry.lastRefresh = getMonoTime()
      entry.populated = true

  # Decide whether to kick off a new refresh.
  let now = getMonoTime()
  let needsRefresh =
    entry.pending.isNone and (
      not entry.populated or entry.changeSeqAtRefresh != b.changeSeq or
      (now - entry.lastRefresh).inMilliseconds >= gitDiffRefreshIntervalMs
    )

  if needsRefresh:
    entry.changeSeqAtRefresh = b.changeSeq
    let startResult = startGitDiffFromBufferAsync(b)
    # `startGitDiffFromBufferAsync` errors when the file is not in git / not in
    # HEAD, so its success doubles as a "git-tracked" probe for the sidebar.
    entry.gitTracked = startResult.isOk
    if startResult.isOk:
      entry.pending = some(startResult.get)
    else:
      # Couldn't start the subprocess — treat this as a refresh attempt so
      # we don't keep retrying every frame.
      entry.lastRefresh = now
      entry.populated = true

  diffCacheStore[key] = entry
  result = entry.counts

proc cachedGitBranchName(b: TextBuffer, filePath: string): string =
  let key = bufferKey(b)
  var entry = branchCacheStore.getOrDefault(key)

  let now = getMonoTime()
  let expired =
    not entry.populated or entry.path != filePath or
    (now - entry.lastRefresh).inMilliseconds >= GitBranchTtlMs

  if expired:
    let branchResult = getGitBranch(filePath)
    entry.path = filePath
    entry.lastRefresh = now
    entry.populated = true
    entry.name =
      if branchResult.isErr:
        ""
      else:
        branchResult.get()
    branchCacheStore[key] = entry

  result = entry.name

proc cleanupGitDiffCache*() =
  ## Terminate any pending async git diff subprocesses and discard all
  ## cached entries. Intended to be called once from the editor shutdown
  ## path so that child processes and their tempfiles do not outlive moe.
  for entry in diffCacheStore.mvalues:
    if entry.pending.isSome:
      abandonGitDiffProcess(entry.pending.get)
      entry.pending = none(GitDiffProcess)
  diffCacheStore.clear()
  branchCacheStore.clear()

proc maybeApplyGitMarkers*(b: TextBuffer) =
  ## Consume the most recent async git diff result (if any) and apply it
  ## to the sidebar gutter. Safe to call on every editor tick; no-op if
  ## no new diff has arrived since the last call. Intended to be invoked
  ## from `editor.tick` under the `showGitDiff` flag so markers are only
  ## written when the user has the gutter turned on.
  let key = bufferKey(b)
  diffCacheStore.withValue(key, entry):
    if entry[].pendingDiffInfo.isSome:
      let diffInfo = entry[].pendingDiffInfo.get
      applyGitDiffToBuffer(b, diffInfo)
      entry[].pendingDiffInfo = none(GitDiffInfo)

proc isBufferGitTracked*(b: TextBuffer): bool =
  ## Whether `b`'s file is tracked by git (present in HEAD), per the most recent
  ## diff scheduling attempt. Returns false until the git-diff cache has been
  ## populated for this buffer. Used by the renderer to decide whether the
  ## git-diff gutter should take over from the session "modified lines"
  ## fallback, so the two don't draw overlapping `~`/`+` markers.
  let key = bufferKey(b)
  let entry = diffCacheStore.getOrDefault(key)
  entry.populated and entry.gitTracked

proc evictGitCacheForBuffer*(b: TextBuffer) =
  ## Drop the cache entries associated with `b`. Call before a buffer is
  ## removed so that its pending git diff (if any) gets terminated and its
  ## address does not alias a future buffer that happens to land at the
  ## same pointer.
  let key = bufferKey(b)
  diffCacheStore.withValue(key, entry):
    if entry[].pending.isSome:
      abandonGitDiffProcess(entry[].pending.get)
      entry[].pending = none(GitDiffProcess)
  diffCacheStore.del(key)
  branchCacheStore.del(key)

proc buildGitInfo(
    textBuffer: TextBuffer,
    mode: EditorMode,
    config: StatusLineConfig,
    isActiveWindow: bool,
): string =
  ## Build git info text (branch name and changed lines) for display before filename

  if mode == EditorMode.FileTree:
    return ""

  var parts: seq[string] = @[]

  # Git changed lines count (if enabled and active window or showGitInactive)
  if config.gitChangedLines and (isActiveWindow or config.showGitInactive):
    if textBuffer.filePath.isSome:
      let counts = cachedGitDiffCounts(textBuffer)
      # Always show +N ~N -N format
      parts.add(" +" & $counts.added & " ~" & $counts.modified & " -" & $counts.deleted)

  # Git branch name (if enabled and active window or showGitInactive)
  if config.gitBranchName and (isActiveWindow or config.showGitInactive):
    if textBuffer.filePath.isSome:
      let branch = cachedGitBranchName(textBuffer, textBuffer.filePath.get())
      if branch.len > 0:
        parts.add("ᚠ " & branch)

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
  ##   {lineEnding}    - Line ending (LF, CRLF, CR)
  ##   {gitBranch}     - Git branch name
  ##   {gitChanges}    - Git changes (+N ~N -N)
  let
    currentLine = state.cursor.line + 1
    totalLines = textBuffer.len
    currentCol = state.cursor.column + 1
    totalCols =
      if textBuffer.len > 0 and state.cursor.line < textBuffer.len:
        textBuffer.getLineLen(state.cursor.line)
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
    modeStr =
      if state.overlay.isSome:
        overlayLabel(state.overlay.get())
      else:
        modeLabel(state.mode, state.insertNormalMode)
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

  # Get git info (uses cached values to avoid per-frame subprocess spawns)
  var gitBranch = ""
  var gitChanges = ""
  if textBuffer.filePath.isSome:
    gitBranch = cachedGitBranchName(textBuffer, textBuffer.filePath.get())
    let counts = cachedGitDiffCounts(textBuffer)
    gitChanges = "+" & $counts.added & " ~" & $counts.modified & " -" & $counts.deleted

  result = setupText
  result = result.replace("{lineNumber}", $currentLine)
  result = result.replace("{totalLines}", $totalLines)
  result = result.replace("{columnNumber}", $currentCol)
  result = result.replace("{totalColumns}", $totalCols)
  result = result.replace("{encoding}", encoding)
  result = result.replace("{lineEnding}", $textBuffer.lineEnding)
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
    mode: EditorMode,
    config: StatusLineConfig,
    isActiveWindow: bool,
): string =
  ## Build the right-side status line info (file type, encoding, line count, etc.)
  ## If setupText is configured, use custom format; otherwise use default format.

  # Hide right-side info in FileTree mode
  if mode == EditorMode.FileTree:
    return ""

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

  # Line ending
  if state.display.showLineEnding:
    parts.add($textBuffer.lineEnding)

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

  # Use overlay styles if an overlay is active, otherwise use mode styles
  let (modeLabelStyle, statusLineStyle, modeLabelText) =
    if state.overlay.isSome:
      let overlayKind = state.overlay.get()
      let labelStyle = getOverlayLabelStyle(overlayKind)
      let lineStyle = getOverlayStyle(overlayKind)
      let labelText =
        if config.mode:
          fmt" {overlayLabel(overlayKind)} "
        else:
          ""
      (labelStyle, lineStyle, labelText)
    else:
      let labelStyle = getStatusLineModeLabelStyle(state.mode)
      let lineStyle = getStatusLineModeStyle(state.mode)
      let labelText =
        if config.mode:
          fmt" {modeLabel(state.mode, state.insertNormalMode)} "
        else:
          ""
      (labelStyle, lineStyle, labelText)

  # Build git info (displayed before filename)
  let gitInfoText = buildGitInfo(textBuffer, state.mode, config, true)

  # Build file display text
  let filePathText = buildFileDisplay(textBuffer, state.mode, config)

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
  let rightSideText = buildRightSideInfo(state, textBuffer, state.mode, config, true)
  let rightSideWidth = displayWidth(rightSideText)

  # Build LSP progress text (displayed in the middle section)
  let progressText =
    if state.ui.lspProgressText.len > 0:
      " " & state.ui.lspProgressText & " "
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
    windowMode: EditorMode,
    config: StatusLineConfig,
) =
  ## Render a status line for a specific window
  if not state.display.showStatusLine or not state.display.multiStatusLine:
    return

  # Build mode label (show for active window, or inactive if showModeInactive)
  let showMode = config.mode and (isActiveWindow or config.showModeInactive)

  # Use overlay styles if an overlay is active, otherwise use mode styles
  let (modeLabelStyle, statusLineStyle, modeLabelText) =
    if isActiveWindow and state.overlay.isSome:
      let overlayKind = state.overlay.get()
      let labelStyle = getOverlayLabelStyle(overlayKind)
      let lineStyle = getOverlayStyle(overlayKind)
      let labelText =
        if showMode:
          fmt" {overlayLabel(overlayKind)} "
        else:
          ""
      (labelStyle, lineStyle, labelText)
    else:
      let labelStyle = getStatusLineModeLabelStyle(windowMode)
      let lineStyle = getStatusLineModeStyle(windowMode)
      let labelText =
        if showMode:
          fmt" {modeLabel(windowMode, state.insertNormalMode)} "
        else:
          ""
      (labelStyle, lineStyle, labelText)

  # Build git info (displayed before filename)
  let gitInfoText = buildGitInfo(textBuffer, windowMode, config, isActiveWindow)

  # Build file display text
  let filePathText = buildFileDisplay(textBuffer, windowMode, config)

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
  let rightSideText =
    buildRightSideInfo(state, textBuffer, windowMode, config, isActiveWindow)
  let rightSideWidth = displayWidth(rightSideText)

  # Build LSP progress text (displayed in the middle section, only for active window)
  let progressText =
    if isActiveWindow and state.ui.lspProgressText.len > 0:
      " " & state.ui.lspProgressText & " "
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
