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
        afterFileRange = (strutils.splitWhitespace(line))[1][1 .. ^1]
        firstLineNum =
          # Count omitted if the change is one line.
          if afterFileRange.contains(","):
            (afterFileRange.split(","))[0].parseInt
          else:
            afterFileRange.parseInt

      result.add Section(firstOriginalLine: firstLineNum)
    else:
      result[^1].buffer.add line

## Parse a raw git diff command result.
proc parseGitDiffOutput(output: string): seq[Diff] =
  for s in output.splitGitDiffSections:
    var
      countChanged = 0
      currentLine = 0

    while currentLine < s.buffer.len:
      if s.buffer[currentLine].startsWith("+"):
        let firstLine = currentLine
        while s.buffer[currentLine + 1].startsWith("+"): currentLine.inc

        result.add Diff(
          operation: OperationType.added,
          firstLine: s.firstOriginalLine + firstLine - 1 - countChanged,
          lastLine: s.firstOriginalLine + currentLine - 1 - countChanged)
      elif s.buffer[currentLine].startsWith("-"):
        if s.buffer[currentLine + 1].startsWith("+"):
          # If it's the added line next to the deleted line,
          # it's regarded as changed the line.
          result.add Diff(
            operation: OperationType.changed,
            firstLine: s.firstOriginalLine + currentLine - 1,
            lastLine: s.firstOriginalLine + currentLine - 1)
          currentLine.inc
          countChanged.inc
        else:
          let firstLine = currentLine
          while s.buffer[currentLine + 1].startsWith("-"): currentLine.inc
          if s.buffer[currentLine + 1].startsWith("+"):
            # Considered as "Changed" if the next line is "+".
            currentLine.inc
            result.add Diff(
              operation: OperationType.changedAndDeleted,
              firstLine: s.firstOriginalLine + firstLine - 1 - countChanged,
              lastLine: s.firstOriginalLine + firstLine - 1 - countChanged)
          else:
            result.add Diff(
              operation: OperationType.deleted,
              firstLine: s.firstOriginalLine + firstLine - 1 - countChanged,
              lastLine: s.firstOriginalLine + firstLine - 1 - countChanged)

          countChanged.inc

      currentLine.inc

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
