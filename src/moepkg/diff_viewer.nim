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

## Diff Viewer module
## Provides a UI for viewing diffs between files

import std/[options, osproc, strutils, os, unicode]

import pkg/results

import buffer, highlight, syntax/tokenizer

type
  DiffLineKind* = enum
    dlkNormal # Normal (context) line
    dlkAdded # Added line (starts with +)
    dlkDeleted # Deleted line (starts with -)
    dlkHeader # Header line (@@, ---, +++)
    dlkMeta # Meta line (diff --git, index, etc.)

  DiffLine* = object ## Represents a single line in the diff output
    text*: string
    kind*: DiffLineKind

  DiffViewerState* = ref object ## State for the diff viewer UI
    lines*: seq[DiffLine] # Diff lines
    selectedLine*: int # Currently selected/highlighted line
    topLine*: int # Scroll position (first visible line)
    sourceFilePath*: string # Path of the source file (current version)
    backupFilePath*: string # Path of the backup file (old version)
    errorMessage*: string # Error message if diff failed
    originalBuffer*: TextBuffer # Saved original buffer (restored on exit)

proc newDiffViewerState*(): DiffViewerState =
  DiffViewerState(
    lines: @[],
    selectedLine: 0,
    topLine: 0,
    sourceFilePath: "",
    backupFilePath: "",
    errorMessage: "",
  )

proc classifyDiffLine(line: string): DiffLineKind =
  ## Classify a diff line based on its content
  if line.len == 0:
    return dlkNormal

  if line.startsWith("@@"):
    return dlkHeader
  elif line.startsWith("---") or line.startsWith("+++"):
    return dlkHeader
  elif line.startsWith("diff ") or line.startsWith("index ") or
      line.startsWith("new file") or line.startsWith("deleted file"):
    return dlkMeta
  elif line[0] == '+':
    return dlkAdded
  elif line[0] == '-':
    return dlkDeleted
  else:
    return dlkNormal

proc initDiffViewerBuffer*(
    sourceFilePath, backupFilePath: string
): Result[seq[DiffLine], string] =
  ## Generate diff between source file and backup file
  ## Uses the system `diff -u` command
  ##
  ## Note: Arguments order is (sourceFilePath, backupFilePath)
  ## This means: diff shows changes FROM backup TO source
  ## - Lines starting with '-' are in backup but not in source (removed)
  ## - Lines starting with '+' are in source but not in backup (added)
  let cmdResult = execCmdEx(
    "diff -u " & quoteShell(backupFilePath) & " " & quoteShell(sourceFilePath)
  )

  # diff command exit codes:
  # 0 = no differences
  # 1 = differences found
  # 2 = error (e.g., file not found)
  if cmdResult.exitCode == 2:
    return Result[seq[DiffLine], string].err "diff command failed: " & cmdResult.output

  var lines: seq[DiffLine] = @[]

  if cmdResult.output.len == 0:
    # No differences
    lines.add(DiffLine(text: "(No differences)", kind: dlkNormal))
  else:
    for line in cmdResult.output.splitLines:
      lines.add(DiffLine(text: line, kind: classifyDiffLine(line)))

  if lines.len > 1 and lines[^1].text.len == 0:
    # Rmove the last empty line
    return Result[seq[DiffLine], string].ok lines[0 .. lines.high - 1]

  return Result[seq[DiffLine], string].ok lines

proc initDiffViewerState*(
    sourceFilePath: string, backupFilePath: string
): DiffViewerState =
  ## Initialize diff viewer state for comparing two files
  result = newDiffViewerState()
  result.sourceFilePath = sourceFilePath
  result.backupFilePath = backupFilePath

  let diffResult = initDiffViewerBuffer(sourceFilePath, backupFilePath)
  if diffResult.isOk:
    result.lines = diffResult.get
  else:
    result.errorMessage = diffResult.error
    result.lines = @[DiffLine(text: "Error: " & diffResult.error, kind: dlkNormal)]

proc moveUp*(state: DiffViewerState) =
  ## Move selection up
  if state.lines.len > 0 and state.selectedLine > 0:
    state.selectedLine.dec
    # Adjust scroll position if needed
    if state.selectedLine < state.topLine:
      state.topLine = state.selectedLine

proc moveDown*(state: DiffViewerState) =
  ## Move selection down
  if state.lines.len > 0 and state.selectedLine < state.lines.len - 1:
    state.selectedLine.inc
    # Note: scroll adjustment for moving down is handled during rendering

proc moveToFirst*(state: DiffViewerState) =
  ## Move to first line
  state.selectedLine = 0
  state.topLine = 0

proc moveToLast*(state: DiffViewerState) =
  ## Move to last line
  if state.lines.len > 0:
    state.selectedLine = state.lines.len - 1

proc getSelectedLine*(state: DiffViewerState): Option[DiffLine] =
  ## Get the currently selected diff line
  if state.selectedLine >= 0 and state.selectedLine < state.lines.len:
    some(state.lines[state.selectedLine])
  else:
    none(DiffLine)

proc createDiffTextBuffer*(state: DiffViewerState): TextBuffer =
  ## Create a TextBuffer from diff lines for rendering via the normal view path
  var content = ""
  for i, line in state.lines:
    if i > 0:
      content.add('\n')
    content.add(line.text)
  result = newTextBuffer(content)
  result.language = langDiff
  result.readOnly = true

  # Initialize syntax highlighting for diff language
  var runesBuffer: seq[seq[Rune]] = @[]
  for i in 0 ..< result.len:
    runesBuffer.add(result.getLine(i).toRunes())
  result.highlight = initHighlight(runesBuffer, @[], langDiff)
