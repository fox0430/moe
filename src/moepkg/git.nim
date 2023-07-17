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

import std/[strformat, strutils, osproc, os, times]
import pkg/results
import unicodeext, independentutils, backgroundprocess, fileutils

type
  OperationType* = enum
    added
    deleted
    changed
    changedAndDeleted

  ChangedLines* = tuple[added, changed, deleted: int]

  Section = object
    firstOriginalLine: int
    buffer: seq[string]

  Diff* = object
    operation*: OperationType
    firstLine*: int
    lastLine*: int

  GitDiffProcess* = object
    command*: BackgroundProcessCommand
    filePath*: Runes
    tmpPath*: Runes
    process*: BackgroundProcess

proc gitProjectRoot(): string =
  ## Return a git project root absolute path.

  let cmdResult = execCmdEx("git rev-parse --show-toplevel")
  if cmdResult.output.len > 0:
    return cmdResult.output

proc getAllTrakedFilesByGit(): seq[string] =
  ## Returns all tracked file names by git in a current project.

  let cmdResult = execCmdEx("git ls-tree --full-tree --name-only -r HEAD")
  if cmdResult.output.len > 0:
    return strutils.splitWhitespace(cmdResult.output)

proc isTrackingByGit*(path: string): bool =
  ## Return true if tracked by git.

  let trackedList = getAllTrakedFilesByGit()

  if path.isAbsolute:
    let root = gitProjectRoot()
    for trackedFile in trackedList:
      if path == root / trackedFile:
        return true
  else:
    return trackedList.contains(path)

proc isGitAvailable*(): bool {.inline.} =
  ## Return true if git command is available.

  if execCmdExNoOutput("git -v") == 0: return true

proc gitDiffTmpDir*(): string {.inline.} =
  ## Return a path for a tmp dir for git diff.
  return getCacheDir() / "moe/gitDiffTmp/"

proc countChangedLines*(diffs: seq[Diff]): ChangedLines =
  ## Count and return changed lines in seq[Diff].

  for d in diffs:
    case d.operation:
      of OperationType.added:
        result.added += d.lastLine - d.firstLine + 1
      of OperationType.changed:
        result.changed += d.lastLine - d.firstLine + 1
      of OperationType.deleted:
        result.deleted += d.lastLine - d.firstLine + 1
      of OperationType.changedAndDeleted:
        result.deleted += d.lastLine - d.firstLine + 1
        result.changed += + 1

proc splitGitHunks(output: seq[string]): seq[Section] =
  ## Split the `git diff` command output by "@@".

  if output.len < 5: return

  # line 0 ~ 4 are a header.
  for line in output[4 .. ^1]:
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
    elif result.len > 0:
      result[^1].buffer.add line

proc parseGitDiffOutput*(output: seq[string]): seq[Diff] =
  ## Parse Unified diff format.

  proc inRange(s: Section, currentLine: int): bool {.inline.} =
    currentLine < s.buffer.len

  for s in output.splitGitHunks:
    var
      originalLine = s.firstOriginalLine
      currentLineNum: int
    while currentLineNum < s.buffer.high:
      template currentLine: string = s.buffer[currentLineNum]

      var addedLine, deletedLine: int

      while s.inRange(currentLineNum) and
            (currentLine.len == 0 or currentLine.startsWith(' ')):
              # Skip no changed lines.
              originalLine.inc
              currentLineNum.inc

      if not s.inRange(currentLineNum): break

      let startOriginalLine = originalLine

      while s.inRange(currentLineNum) and
            (currentLine.len == 0 or not currentLine.startsWith(' ')):
              # Count deleted line or added line.
              if currentLine.startsWith('-'):
                deletedLine.inc
              if currentLine.startsWith('+'):
                originalLine.inc
                addedLine.inc

              currentLineNum.inc

      if deletedLine > 0 or addedLine > 0:
        # Treat lines that are both deleted and added as "changed".
        var changedLine, changedAndDeletedLine: int

        if deletedLine == addedLine:
          changedLine = deletedLine
          deletedLine = 0
          addedLine = 0
        elif deletedLine > 0 and addedLine > 0:
          if deletedLine > addedLine:
            if addedLine > 1: changedLine = addedLine - 1
            changedAndDeletedLine = deletedLine - addedLine
            deletedLine = 0
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
          when not defined(release):
            doAssert(result[^1].firstLine <= result[^1].lastLine, $result[^1])

        if deletedLine > 0:
          result.add Diff(
            operation: OperationType.deleted,
            firstLine: startOriginalLine + changedLine - 1,
            lastLine: startOriginalLine + changedLine - 1 + deletedLine - 1)
          when not defined(release):
            doAssert(result[^1].firstLine <= result[^1].lastLine, $result[^1])

        if changedAndDeletedLine > 0:
          result.add Diff(
            operation: OperationType.changedAndDeleted,
            firstLine: startOriginalLine + changedLine,
            lastLine: startOriginalLine + changedLine + changedAndDeletedLine - 1)
          when not defined(release):
            doAssert(result[^1].firstLine <= result[^1].lastLine, $result[^1])

        if addedLine > 0:
          result.add Diff(
            operation: OperationType.added,
            firstLine: startOriginalLine + changedLine,
            lastLine: startOriginalLine + changedLine + addedLine - 1)
          when not defined(release):
            doAssert(result[^1].firstLine <= result[^1].lastLine, $result[^1])

proc isRunning*(bp: GitDiffProcess): bool {.inline.} = bp.process.isRunning

proc result*(bp: var GitDiffProcess): Result[seq[string], string] {.inline.} =
  bp.process.result

proc startBackgroundGitDiff*(
  path: Runes,
  buffer: Runes,
  encoding: CharacterEncoding): Result[GitDiffProcess, string] =
    ## Start a background process for the git diff command.
    ## Save the current buffer and `path` of HEAD to temporary files before exec
    ## `git diff --no-index`.

    let cacheDir = gitDiffTmpDir()
    try:
      if not dirExists(cacheDir): createDir(cacheDir)
    except CatchableError as e:
      return Result[GitDiffProcess, string].err fmt"Failed to save a tmp file {e.msg}"

    let
      # A temporary file of HEAD.
      tmpHeadFilename = fmt"{splitPath($path).tail}_{$now()}_head.tmp"
      tmpHeadPath = cacheDir / tmpHeadFilename

      # A temporary file of the current buffer.
      tmpBufFilename = fmt"{splitPath($path).tail}_{$now()}_buf.tmp"
      tmpBufPath = cacheDir / tmpBufFilename

    # TODO: Saving temporary files every time is an expensive cost,
    # so make it asynchronous(background) or take a workaround.

    if 0 != execCmdExNoOutput(fmt"git show HEAD:{path} > {tmpHeadPath}"):
      return Result[GitDiffProcess, string].err fmt"Failed to save a tmp file {path}"

    try:
      saveFile(tmpBufPath.toRunes, buffer, encoding)
    except CatchableError as e:
      return Result[GitDiffProcess, string].err fmt"Failed to save a tmp file {e.msg}"

    let command = BackgroundProcessCommand(
      cmd: "git",
      args: @["diff", "--no-index", "--no-color", $tmpHeadPath, $tmpBufPath])

    let backgroundProcess = startBackgroundProcess(command)
    if backgroundProcess.isErr:
      return Result[GitDiffProcess, string].err fmt"Failed to exec git diff commands: {backgroundProcess.error}"

    return Result[GitDiffProcess, string].ok GitDiffProcess(
      command: command,
      filePath: path,
      tmpPath: tmpBufPath.toRunes,
      process: backgroundProcess.get)
