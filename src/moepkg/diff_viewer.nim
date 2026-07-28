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

import std/[osproc, strutils, os]

import pkg/results

import buffer/core, highlight, list_viewer
import syntax/tokenizer
import types/diff_viewer_types

export diff_viewer_types
export list_viewer

proc newDiffViewerState*(): DiffViewerState =
  DiffViewerState(
    items: @[],
    selectedIndex: 0,
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
    result.items = diffResult.get
  else:
    result.errorMessage = diffResult.error
    result.items = @[DiffLine(text: "Error: " & diffResult.error, kind: dlkNormal)]

proc createDiffTextBuffer*(state: DiffViewerState): TextBuffer =
  ## Create a TextBuffer from diff lines for rendering via the normal view path
  var content = ""
  for i, line in state.items:
    if i > 0:
      content.add('\n')
    content.add(line.text)
  result = newTextBuffer(content)
  result.language = langDiff
  result.readOnly = true

  # Use the capped path (initHighlightIncremental) rather than the uncapped
  # legacy initHighlight, so a very long diff line isn't tokenized in full. The
  # diff viewer applies no config, so maxHighlightLineLength is the default.
  var lines = newSeqOfCap[string](result.len)
  for line in result.lines:
    lines.add(line)
  let (segments, _) = initHighlightIncremental(
    lines, 0, lines.high, TokenizerState(), @[], langDiff, result.maxHighlightLineLength
  )
  result.highlight = Highlight(colorSegments: segments)
