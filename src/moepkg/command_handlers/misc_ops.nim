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

## Small misc side effects (search highlight, whitespace strip, shell /
## background / man / build pending ops, theme), split out of
## result_processor.nim.

import std/[options, os]

import
  ../[
    cursor_util, editor, editor_build_jobs, editor_file_jobs, editor_notify, logger,
    registers, types,
  ]

import editor_ops, handler_result

proc processJobsResult(e: Editor, r: HandlerResult) =
  ## `:jobs` says what is still running; `:jobs!` ends it.
  if r.hrStopJobs:
    let stopped = e.stopRunningCommands()
    e.state.statusMessage =
      if stopped == 0:
        "No external commands were running"
      else:
        $stopped & " stopped"
    return

  let running = e.runningCommands()
  if running.len == 0:
    e.state.statusMessage = "No external commands are running"
  else:
    # Through the notifier so the whole list reaches `:messages`.
    e.notifyAll(running)

proc hasRelativeName(buf: TextBuffer): bool =
  buf.filePath.isSome and buf.filePath.get.len > 0 and
    not expandTilde(buf.filePath.get).isAbsolute

proc changeDirectory(e: Editor, path: Option[string]) =
  ## `:cd`: none goes home and `-` back to the previous directory.
  let current =
    try:
      getCurrentDir()
    except OSError:
      ""
  var target: string
  if path.isNone:
    target = getHomeDir()
  elif path.get == "-":
    if e.state.previousDir.len == 0:
      e.state.statusMessage = "E186: No previous directory"
      return
    target = e.state.previousDir
  else:
    target = expandTilde(path.get)

  # A relative name would follow the directory to another file.
  if current.len == 0:
    for buf in e.buffers:
      if buf.hasRelativeName:
        e.state.statusMessage =
          "Can't change directory: the current directory is gone; give \"" &
          buf.filePath.get & "\" a full path with :saveas or close it"
        return

  try:
    setCurrentDir(target)
  except OSError as err:
    e.state.statusMessage =
      if dirExists(target):
        "Can't change directory to \"" & target & "\": " &
          osErrorMsg(OSErrorCode(err.errorCode))
      else:
        "E344: Can't find directory \"" & target & "\" in cdpath"
    return

  for buf in e.buffers:
    if buf.hasRelativeName:
      buf.filePath = some(normalizedPath(current / buf.filePath.get))
  if current.len > 0:
    e.state.previousDir = current
  e.state.statusMessage =
    try:
      getCurrentDir()
    except OSError:
      target

proc processMiscResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Handle misc side-effect kinds. Returns true to continue.
  case r.kind
  of hrJobs:
    e.processJobsResult(r)
    return true
  of hrClearSearchHighlight:
    e.state.hideSearchMatches()
    return true
  of hrStripWhitespace:
    let count = r.strippedLineCount
    if count > 0:
      e.state.statusMessage = "Stripped trailing whitespace from " & $count & " lines"
    else:
      e.state.statusMessage = "No trailing whitespace found"
    return true
  of hrShellCommand:
    e.state.pending.add PendingAsyncOp(kind: paoShellCommand, command: r.shellCommand)
    return true
  of hrFilter:
    e.state.pending.add PendingAsyncOp(
      kind: paoFilter,
      filter: (
        bufferId: r.hrFilterBufferId,
        windowIndex: e.windowManager.activeWindowIndex,
        command: r.hrFilterCommand,
        first: r.hrFilterFirst,
        last: r.hrFilterLast,
        contentVersion: r.hrFilterVersion,
      ),
    )
    return true
  of hrBackground:
    e.state.pending.add PendingAsyncOp(kind: paoBackground)
    return true
  of hrMan:
    e.state.pending.add PendingAsyncOp(kind: paoManPage, command: r.hrManPage)
    return true
  of hrSubstitute:
    let count = r.hrSubstituteCount
    e.state.statusMessage = $count & " substitution" & (if count == 1: "" else: "s")
    return true
  of hrDeleteLines:
    e.state.registers.storeDeleted(none(char), r.hrDeletedText, true)
    let count = r.hrDeletedLineCount
    e.state.statusMessage =
      $count & " line" & (if count == 1: "" else: "s") & " deleted"
    # Vim leaves the cursor on the first non-blank of the line that followed the
    # deleted range, which is now its start line. A fold can widen the range
    # above the old cursor line.
    let maxLine = activeBuffer.len - 1
    e.activeWindow.cursor.line = min(max(0, r.hrDeleteStartLine), maxLine)
    e.activeWindow.cursor.column =
      firstNonBlankColumn(activeBuffer.getLine(e.activeWindow.cursor.line))
    e.state.preferredColumn = -1
    return true
  of hrBuild:
    let filePath = if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: ""
    if filePath.len == 0:
      e.state.statusMessage = "Build error: File not saved"
      logError("handler", "Build failed: No file path")
    else:
      e.submitBuild(
        (
          path: filePath,
          language: activeBuffer.language.ord,
          customCmd: "",
          workspaceRoot: parentDir(filePath),
          automatic: false,
        )
      )
    return true
  of hrTheme:
    e.applyThemeCommand(r.hrThemeName)
    return true
  of hrChangeDir:
    e.changeDirectory(r.changeDirPath)
    return true
  else:
    return true # Not a misc kind; caller misrouted (defensive)
