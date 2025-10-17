#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Git diff integration for sidebar indicators
##
## This module provides functionality for getting git diff information
## and applying it to buffer sidebar markers.

import std/[options, osproc, strutils, tables, os, tempfiles]

import pkg/results

import buffer

type
  GitDiffLineKind* = enum
    ## Type of change in git diff
    Added ## Line was added
    Modified ## Line was modified
    Deleted ## Line was deleted

  GitDiffLine* = object ## Represents a single line change in git diff
    lineNumber*: int ## Line number in the current file (0-based)
    kind*: GitDiffLineKind ## Type of change

  GitDiffInfo* = object ## Git diff information for a file
    lines*: seq[GitDiffLine] ## Changed lines

proc parseDiffHunk(hunkHeader: string): tuple[startLine: int, lineCount: int] =
  ## Parse a diff hunk header like "@@ -10,5 +10,7 @@"
  ## Returns the start line and line count for the new file
  ## Example: "@@ -10,5 +10,7 @@" means starting at line 10 with 7 lines

  # Find the second part (new file info) after the space
  let parts = hunkHeader.split(' ')
  if parts.len < 3:
    return (0, 0)

  # Parse "+10,7" -> startLine=10, lineCount=7
  let newInfo = parts[2]
  if not newInfo.startsWith('+'):
    return (0, 0)

  let newInfoParts = newInfo[1 ..^ 1].split(',')
  if newInfoParts.len == 0:
    return (0, 0)

  let startLine =
    try:
      parseInt(newInfoParts[0])
    except ValueError:
      0

  let lineCount =
    if newInfoParts.len > 1:
      try:
        parseInt(newInfoParts[1])
      except ValueError:
        1
    else:
      1

  return (startLine, lineCount)

proc processDeleteAddPairs(lines: seq[GitDiffLine]): seq[GitDiffLine] =
  ## Convert consecutive delete+add groups to modified
  ## Collects groups of consecutive deletes followed by adds and converts
  ## matching pairs to Modified kind
  ##
  ## This is a common pattern in git diff output where a modified line
  ## is represented as a delete followed by an add
  var i = 0
  while i < lines.len:
    # Collect all consecutive deletes
    var deleteStart = i
    var deleteCount = 0
    while i < lines.len and lines[i].kind == Deleted:
      deleteCount.inc
      i.inc

    # Collect all consecutive adds that follow
    var addStart = i
    var addCount = 0
    while i < lines.len and lines[i].kind == Added:
      addCount.inc
      i.inc

    if deleteCount > 0 and addCount > 0:
      # We have deletes followed by adds - convert pairs to modified
      let minCount = min(deleteCount, addCount)

      # Convert matching pairs to modified
      for j in 0 ..< minCount:
        let addLine = lines[addStart + j]
        result.add(GitDiffLine(lineNumber: addLine.lineNumber, kind: Modified))

      # Add remaining deletes (if any)
      for j in minCount ..< deleteCount:
        result.add(lines[deleteStart + j])

      # Add remaining adds (if any)
      for j in minCount ..< addCount:
        result.add(lines[addStart + j])
    elif deleteCount > 0:
      # Only deletes, no adds
      for j in 0 ..< deleteCount:
        result.add(lines[deleteStart + j])
    elif addCount > 0:
      # Only adds, no deletes
      for j in 0 ..< addCount:
        result.add(lines[addStart + j])
    # else: no deletes or adds, continue to next iteration

proc getGitDiff*(filePath: string): Result[GitDiffInfo, string] =
  ## Get git diff information for a file on disk
  ## Returns error if file is not in a git repository or git command fails

  # Check if file exists
  if not fileExists(filePath):
    return err("File does not exist: " & filePath)

  # Get the directory containing the file
  let fileDir = filePath.parentDir()
  let fileName = filePath.extractFilename()

  # Run git diff command
  # Using --unified=0 to get only changed lines without context
  let gitCmd = "git diff --unified=0 -- " & quoteShell(fileName)

  let (output, exitCode) =
    try:
      execCmdEx(gitCmd, workingDir = fileDir)
    except OSError as e:
      return err("Failed to execute git command: " & e.msg)

  if exitCode != 0:
    # Exit code 1 might just mean no changes, check output
    if output.len == 0:
      # No changes
      return ok(GitDiffInfo(lines: @[]))
    # Git command failed for another reason
    return err("Git command failed with exit code " & $exitCode)

  # Parse git diff output
  var diffInfo = GitDiffInfo(lines: @[])

  # Track current line number while parsing
  var currentLine = 0
  var inHunk = false

  for line in output.splitLines():
    if line.startsWith("@@"):
      # Parse hunk header to get starting line number
      let (startLine, _) = parseDiffHunk(line)
      currentLine = startLine - 1 # Convert to 0-based
      inHunk = true
    elif inHunk:
      if line.startsWith("+") and not line.startsWith("+++"):
        # Added line
        diffInfo.lines.add(GitDiffLine(lineNumber: currentLine, kind: Added))
        currentLine.inc
      elif line.startsWith("-") and not line.startsWith("---"):
        # Deleted line (doesn't increment currentLine)
        diffInfo.lines.add(GitDiffLine(lineNumber: currentLine, kind: Deleted))
      elif line.startsWith(" "):
        # Unchanged line (context)
        currentLine.inc
      elif line.len > 0 and not line.startsWith("\\"):
        # Modified line is represented as delete + add
        # This is handled by the above cases
        discard

  # Convert consecutive delete+add groups to modified
  diffInfo.lines = processDeleteAddPairs(diffInfo.lines)
  return ok(diffInfo)

proc getGitDiffFromBuffer*(buffer: TextBuffer): Result[GitDiffInfo, string] =
  ## Get git diff information by comparing buffer contents with HEAD
  ## This allows real-time diff updates without saving the file
  ## Returns error if buffer has no file path or git command fails

  if buffer.filePath.isNone:
    return err("Buffer has no associated file path")

  let filePath = buffer.filePath.get

  # Find git repository root
  let fileDir = filePath.parentDir()

  # Get git repository root by running git rev-parse
  let (gitRootOutput, gitRootExitCode) =
    try:
      execCmdEx("git rev-parse --show-toplevel", workingDir = fileDir)
    except OSError as e:
      return err("Failed to find git repository root: " & e.msg)

  if gitRootExitCode != 0:
    return err("File is not in a git repository")

  let gitRoot = gitRootOutput.strip()

  # Calculate relative path from git root
  let relativePath =
    if filePath.isAbsolute:
      # Absolute path: convert to relative
      if filePath.startsWith(gitRoot & "/"):
        filePath[gitRoot.len + 1 .. ^1]
      elif filePath.startsWith(gitRoot):
        filePath[gitRoot.len .. ^1]
      else:
        # File is outside git root, just use filename
        filePath.extractFilename()
    else:
      # Already relative path: use as-is
      filePath

  # First, get the original file from git HEAD using relative path
  let gitShowCmd = "git show HEAD:" & quoteShell(relativePath)

  let (headContent, showExitCode) =
    try:
      execCmdEx(gitShowCmd, workingDir = gitRoot)
    except OSError as e:
      return err("Failed to execute git show: " & e.msg)

  if showExitCode != 0:
    # File not in git yet, return empty diff (no markers)
    return ok(GitDiffInfo(lines: @[]))

  # Create temporary files for comparison
  let tempOriginal =
    try:
      genTempPath("moe_original_", ".tmp", fileDir)
    except OSError as e:
      return err("Failed to create temp file path: " & e.msg)

  let tempModified =
    try:
      genTempPath("moe_modified_", ".tmp", fileDir)
    except OSError as e:
      return err("Failed to create temp file path: " & e.msg)

  # Ensure cleanup of temporary files on function exit
  defer:
    try:
      if fileExists(tempOriginal):
        removeFile(tempOriginal)
    except:
      discard # Ignore cleanup errors

    try:
      if fileExists(tempModified):
        removeFile(tempModified)
    except:
      discard # Ignore cleanup errors

  # Write original content from HEAD
  try:
    writeFile(tempOriginal, headContent)
  except IOError as e:
    return err("Failed to write original temp file: " & e.msg)

  # Write buffer contents to modified temp file
  try:
    let content = buffer.getTextString()
    writeFile(tempModified, content)
  except IOError as e:
    return err("Failed to write modified temp file: " & e.msg)

  # Run git diff with --no-index to compare the two files
  let gitCmd =
    "git diff --no-index --unified=0 " & quoteShell(tempOriginal) & " " &
    quoteShell(tempModified)

  let (output, exitCode) =
    try:
      execCmdEx(gitCmd, workingDir = gitRoot)
    except OSError as e:
      return err("Failed to execute git diff: " & e.msg)

  # Exit code 1 from git diff --no-index means differences found (this is normal)
  # Exit code 0 means no differences
  if exitCode != 0 and exitCode != 1:
    return err("Git diff failed with exit code " & $exitCode)

  # Parse git diff output
  var diffInfo = GitDiffInfo(lines: @[])

  # Track current line number while parsing
  var currentLine = 0
  var inHunk = false

  for line in output.splitLines():
    if line.startsWith("@@"):
      # Parse hunk header to get starting line number
      let (startLine, _) = parseDiffHunk(line)
      currentLine = startLine - 1 # Convert to 0-based
      inHunk = true
    elif inHunk:
      if line.startsWith("+") and not line.startsWith("+++"):
        # Added line
        diffInfo.lines.add(GitDiffLine(lineNumber: currentLine, kind: Added))
        currentLine.inc
      elif line.startsWith("-") and not line.startsWith("---"):
        # Deleted line (doesn't increment currentLine)
        diffInfo.lines.add(GitDiffLine(lineNumber: currentLine, kind: Deleted))
      elif line.startsWith(" "):
        # Unchanged line (context)
        currentLine.inc
      elif line.len > 0 and not line.startsWith("\\"):
        # Modified line is represented as delete + add
        # This is handled by the above cases
        discard

  # Convert consecutive delete+add groups to modified
  diffInfo.lines = processDeleteAddPairs(diffInfo.lines)
  return ok(diffInfo)

proc applyGitDiffToBuffer*(buffer: TextBuffer, diffInfo: GitDiffInfo) =
  ## Apply git diff information to buffer sidebar markers
  ## This will set appropriate markers for added, modified, and deleted lines

  # Clear existing git markers
  buffer.clearAllMarkers()

  # Group consecutive changes to identify modified regions
  var lineKinds = initTable[int, GitDiffLineKind]()

  for diffLine in diffInfo.lines:
    lineKinds[diffLine.lineNumber] = diffLine.kind

  # Apply markers based on line kinds
  for lineNum, kind in lineKinds.pairs():
    if lineNum >= 0 and lineNum < buffer.len:
      let markerKind =
        case kind
        of Added: GitAdded
        of Modified: GitChanged
        of Deleted: GitDeleted

      buffer.setLineMarker(lineNum, markerKind)

proc updateBufferWithGitDiff*(
    buffer: TextBuffer, useBuffer: bool = true
): Result[(), string] =
  ## Convenience function to update buffer with git diff in one call
  ## Returns error if buffer has no file path or git diff fails
  ##
  ## Parameters:
  ## - buffer: The text buffer to update
  ## - useBuffer: If true, compare buffer contents with HEAD (real-time)
  ##              If false, compare disk file with working tree (saved changes only)
  ##
  ## This function should be called:
  ## - When a file is loaded (initial diff)
  ## - After buffer modifications (for real-time updates)
  ## - After saving a file (to refresh diff markers)
  ## - When git diff display is toggled on
  ## - Manually via editor.refreshGitDiff()
  ##
  ## Note: When useBuffer=true, compares in-memory buffer with git HEAD
  ##       When useBuffer=false, compares disk file with working tree

  if buffer.filePath.isNone:
    return err("Buffer has no associated file path")

  let diffResult =
    if useBuffer:
      # Compare buffer contents with HEAD (real-time, shows unsaved changes)
      getGitDiffFromBuffer(buffer)
    else:
      # Compare disk file with working tree (saved changes only)
      getGitDiff(buffer.filePath.get)

  if diffResult.isErr:
    return err(diffResult.error)

  buffer.applyGitDiffToBuffer(diffResult.get)
  return ok(())
