#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[strformat, strutils, osproc, os]
import unicodeext, independentutils

type
  OperationType* = enum
    added
    deleted
    changed
    changedAndDeleted

  Section = object
    firstOriginalLine: int
    buffer: seq[string]

  Diff* = object
    operation*: OperationType
    firstLine*: int
    lastLine*: int

## Exec `git diff` command and return the output.
proc exexGitDiffCommand(path: string): string =
  let cmdResult = execCmdEx(fmt"git diff --no-ext-diff {path}")
  if cmdResult.exitCode == 0:
    return cmdResult.output

## Split the `git diff` command output by "@@".
proc splitGitDiffSections(output: string): seq[Section] =
  let lines = output.splitLines

  # line 0 ~ 4 are a header.
  for line in lines[4 .. lines.high]:
    if line.startsWith("@@"):
      let
        # The first character is '+' or '-' after splitting the line.
        afterFileRange = (strutils.splitWhitespace(line))[2][1 .. ^1]
        firstLineNum =
          # Count omitted if the change is one line.
          if afterFileRange.contains(","):
            (afterFileRange.split(","))[0].parseInt
          else:
            afterFileRange.parseInt

      result.add Section(firstOriginalLine: firstLineNum - 1)
    else:
      result[^1].buffer.add line

proc parseGitDiffOutput(output: string): seq[Diff] =
  ## Parse Unified diff format.

  proc inRange(s: Section, currentLine: int): bool {.inline.} =
    currentLine < s.buffer.len

  for s in output.splitGitDiffSections:
    var
      originalLine = s.firstOriginalLine
      currentLine: int
    while currentLine < s.buffer.high:
      var addedLine, deletedLine: int

      while s.inRange(currentLine) and
            (s.buffer[currentLine].len == 0 or s.buffer[currentLine].startsWith(' ')):
              # Skip no changed lines.
              originalLine.inc
              currentLine.inc

      if not s.inRange(currentLine): break

      let startOriginalLine = originalLine

      while s.inRange(currentLine) and
            (s.buffer[currentLine].len == 0 or not s.buffer[currentLine].startsWith(' ')):
              # Count deleted line or added line.
              if s.buffer[currentLine].startsWith('-'):
                deletedLine.inc
              if s.buffer[currentLine].startsWith('+'):
                originalLine.inc
                addedLine.inc

              currentLine.inc

      if deletedLine > 0 or addedLine > 0:
        # Treat lines that are both deleted and added as "changed".
        var changedLine, changedAndDeletedLine: int

        if deletedLine - addedLine == 0:
          changedLine = deletedLine
          deletedLine = 0
          addedLine = 0
        elif deletedLine > 0 and addedLine > 0:
          if deletedLine > addedLine and deletedLine > 1:
            addedLine = 0
            deletedLine = 0
            changedAndDeletedLine = 1
          elif deletedLine > addedLine:
            changedLine = addedLine
            deletedLine -= addedLine
            addedLine = 0
          else:
            changedLine = deletedLine
            addedLine -= deletedLine
            deletedLine = 0

        if changedLine > 0:
          result.add Diff(
            operation: OperationType.changed,
            firstLine: startOriginalLine,
            lastLine: startOriginalLine + changedLine - 1)

        if changedAndDeletedLine > 0:
          result.add Diff(
            operation: OperationType.changedAndDeleted,
            firstLine: startOriginalLine + changedLine,
            lastLine: startOriginalLine + changedLine)

        if deletedLine > 0:
          result.add Diff(
            operation: OperationType.deleted,
            firstLine: startOriginalLine + changedLine - 1,
            lastLine: startOriginalLine + changedLine - 1)

        elif addedLine > 0:
          result.add Diff(
            operation: OperationType.added,
            firstLine: startOriginalLine + changedLine,
            lastLine: startOriginalLine + changedLine + addedLine - 1)

## Returns changed information from HEAD using `git diff` command.
proc gitDiff*(path: string | Runes): seq[Diff] =
  let output = exexGitDiffCommand($path)
  if output.len > 0:
    return output.parseGitDiffOutput

## Return a git project root absolute path.
proc gitProjectRoot(): string =
  let cmdResult = execCmdEx("git rev-parse --show-toplevel")
  if cmdResult.output.len > 0:
    return cmdResult.output

## Returns all tracked file names by git in a current project.
proc getAllTrakedFilesByGit(): seq[string] =
  let cmdResult = execCmdEx("git ls-tree --full-tree --name-only -r HEAD")
  if cmdResult.output.len > 0:
    return strutils.splitWhitespace(cmdResult.output)

## Return true if tracked by git.
proc isTrackingByGit*(path: string): bool =
  let trackedList = getAllTrakedFilesByGit()

  if path.isAbsolute:
    let root = gitProjectRoot()
    for trackedFile in trackedList:
      if path == root / trackedFile:
        return true
  else:
    return trackedList.contains(path)

## Return true if git command is available.
proc isGitAvailable*(): bool {.inline.} =
  if execCmdExNoOutput("git -v") == 0: return true
