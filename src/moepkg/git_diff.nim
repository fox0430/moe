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

## Git diff integration for sidebar indicators
##
## This module provides functionality for getting git diff information
## and applying it to buffer sidebar markers.

import std/[options, osproc, strutils, tables, os, tempfiles, streams, times]

import pkg/results

import buffer, logger

const
  DEFAULT_GIT_DIFF_TIMEOUT* = 5.0 ## Default timeout for git diff operations in seconds
  PROCESS_RUNNING = -1 ## Exit code value indicating process is still running

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

  GitDiffProcess* = ref object ## Background git diff process
    process: Process ## The running process
    startTime: float ## Process start time (for timeout)
    filePath: string ## File path being diffed
    workingDir: string ## Working directory for the process
    isBufferDiff: bool ## True if comparing buffer contents, false for file diff
    tempOriginal: string ## Temp file for original content (buffer diff only)
    tempModified: string ## Temp file for modified content (buffer diff only)

proc removeTempFileSafely(filePath: string) =
  ## Safely remove a temporary file, ignoring errors
  ## Safe to call with empty path or non-existent file
  if filePath.len == 0:
    return

  try:
    if fileExists(filePath):
      removeFile(filePath)
  except CatchableError as e:
    # Ignore cleanup errors - file might already be deleted
    logWarn("git diff", "Failed to remove temp file " & filePath & ": " & e.msg)

proc cleanupTempFiles(diffProc: GitDiffProcess) =
  ## Clean up temporary files created for buffer diff
  ## Safe to call multiple times or when temp files don't exist
  if not diffProc.isBufferDiff:
    return

  removeTempFileSafely(diffProc.tempOriginal)
  removeTempFileSafely(diffProc.tempModified)

proc abandonGitDiffProcess*(diffProc: GitDiffProcess) =
  ## Terminate a pending GitDiffProcess and release its resources without
  ## waiting for completion. Used by callers that cache pending async diffs
  ## (e.g. status-line cache) to clean up on buffer close or editor
  ## shutdown. Safe to call multiple times; swallows all process/OS
  ## errors so it can be used from shutdown paths.
  try:
    diffProc.process.terminate()
  except CatchableError as e:
    logWarn("git diff", "Failed to terminate pending git diff: " & e.msg)
    try:
      diffProc.process.kill()
    except CatchableError as killErr:
      logError("git diff", "Failed to kill pending git diff: " & killErr.msg)
  try:
    diffProc.process.close()
  except CatchableError as e:
    logWarn("git diff", "Failed to close pending git diff process: " & e.msg)
  cleanupTempFiles(diffProc)

proc getGitRoot(filePath: string): Result[string, string] =
  ## Get git repository root for a given file path
  ## Returns error if file is not in a git repository
  let fileDir = filePath.parentDir()

  let (gitRootOutput, gitRootExitCode) =
    try:
      execCmdEx("git rev-parse --show-toplevel", workingDir = fileDir)
    except OSError as e:
      return err("Failed to find git repository root: " & e.msg)

  if gitRootExitCode != 0:
    return err("File is not in a git repository")

  return ok(gitRootOutput.strip())

proc calculateRelativePath(filePath, gitRoot: string): string =
  ## Calculate relative path from git root to file
  ## Handles both absolute and relative paths
  if filePath.isAbsolute:
    # Absolute path: convert to relative
    if filePath.startsWith(gitRoot & "/"):
      return filePath[gitRoot.len + 1 .. ^1]
    elif filePath.startsWith(gitRoot):
      return filePath[gitRoot.len .. ^1]
    else:
      # File is outside git root, just use filename
      return filePath.extractFilename()
  else:
    # Already relative path: use as-is
    return filePath

proc getHeadContent(relativePath, gitRoot: string): Result[string, string] =
  ## Get file content from git HEAD
  ## Returns error if file is not in git repository or git command fails
  ##
  ## Uses startProcess + readAll (not execCmdEx) to preserve the blob's
  ## exact byte sequence. execCmdEx reads line-by-line and appends "\n"
  ## per iteration, which fabricates a trailing newline for files that
  ## were committed without one.
  var process: Process = nil
  var headContent = ""
  var showExitCode: int = -1
  try:
    process =
      try:
        startProcess(
          "git",
          workingDir = gitRoot,
          args = ["show", "HEAD:" & relativePath],
          options = {poUsePath, poStdErrToStdOut},
        )
      except OSError as e:
        return err("Failed to execute git show: " & e.msg)

    headContent = process.outputStream.readAll()
    showExitCode = process.waitForExit()
  finally:
    if not process.isNil:
      try:
        process.close()
      except CatchableError:
        logWarn(
          "git diff", "Failed to close git show process: " & getCurrentExceptionMsg()
        )

  if showExitCode != 0:
    return err("File is not in git repository")

  return ok(headContent)

proc prepareBufferDiffTempFiles(
    filePath, gitRoot: string, bufferContent: string
): Result[(string, string), string] =
  ## Prepare temporary files for buffer diff comparison
  ## Returns (tempOriginal, tempModified) file paths
  ## Caller is responsible for cleanup using removeTempFileSafely()
  let fileDir = filePath.parentDir()
  let relativePath = calculateRelativePath(filePath, gitRoot)

  # Get HEAD content
  let headContentResult = getHeadContent(relativePath, gitRoot)
  if headContentResult.isErr:
    return err(headContentResult.error)
  let headContent = headContentResult.get

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

  # Write original content from HEAD
  try:
    writeFile(tempOriginal, headContent)
  except IOError as e:
    return err("Failed to write original temp file: " & e.msg)

  # Write buffer contents to modified temp file
  try:
    writeFile(tempModified, bufferContent)
  except IOError as e:
    # Clean up original temp file
    removeTempFileSafely(tempOriginal)
    return err("Failed to write modified temp file: " & e.msg)

  return ok((tempOriginal, tempModified))

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

proc parseDiffOutput(output: string): GitDiffInfo =
  ## Parse git diff output into GitDiffInfo
  ## This is a shared function used by both sync and async implementations
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
  return diffInfo

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

  # Parse git diff output using shared parser
  return ok(parseDiffOutput(output))

proc checkGitDiffComplete*(
    diffProc: GitDiffProcess, timeout: float = DEFAULT_GIT_DIFF_TIMEOUT
): Option[Result[GitDiffInfo, string]] =
  ## Check if git diff process has completed
  ## Returns:
  ## - none() if process is still running (and not timed out)
  ## - some(ok(GitDiffInfo)) if process completed successfully
  ## - some(err(msg)) if process failed or timed out

  # Check for timeout
  if epochTime() - diffProc.startTime > timeout:
    # Kill the process - try terminate() first, then kill() if that fails
    try:
      diffProc.process.terminate()
    except CatchableError as e:
      # If terminate() fails, try kill() as a last resort
      logError("git diff", "Failed to terminate git diff process: " & e.msg)
      try:
        diffProc.process.kill()
      except CatchableError as killErr:
        # Process termination failed completely
        logError("git diff", "Failed to kill git diff process: " & killErr.msg)
    # Clean up temp files if this is a buffer diff
    cleanupTempFiles(diffProc)
    return some(
      Result[GitDiffInfo, string].err(
        "Git diff timed out after " & $timeout & " seconds"
      )
    )

  # Check if process has completed
  let exitCode = diffProc.process.peekExitCode()
  if exitCode == PROCESS_RUNNING:
    # Process still running
    return none(Result[GitDiffInfo, string])

  # Process has completed - read output
  let output =
    try:
      let stream = diffProc.process.outputStream()
      stream.readAll()
    except CatchableError as e:
      logError("git diff", "Failed to read git diff output stream: " & e.msg)
      ""

  # Close the process
  try:
    diffProc.process.close()
  except CatchableError as e:
    logError("git diff", "Failed to close git diff process: " & e.msg)

  # Clean up temp files if this is a buffer diff
  cleanupTempFiles(diffProc)

  # Check exit code
  # For buffer diffs (--no-index), exit code 1 means differences found (normal)
  # For regular diffs, exit code 0 means success
  if diffProc.isBufferDiff:
    # Exit code 0 = no differences, 1 = differences found
    if exitCode != 0 and exitCode != 1:
      return some(
        Result[GitDiffInfo, string].err("Git diff failed with exit code " & $exitCode)
      )
  else:
    # Regular file diff
    if exitCode != 0:
      # Exit code 1 might just mean no changes, check output
      if output.len == 0:
        # No changes
        return some(Result[GitDiffInfo, string].ok(GitDiffInfo(lines: @[])))
      # Git command failed for another reason
      return some(
        Result[GitDiffInfo, string].err(
          "Git command failed with exit code " & $exitCode
        )
      )

  # Parse output and return result
  return some(Result[GitDiffInfo, string].ok(parseDiffOutput(output)))

proc getGitDiffFromBuffer*(buffer: TextBuffer): Result[GitDiffInfo, string] =
  ## Get git diff information by comparing buffer contents with HEAD
  ## This allows real-time diff updates without saving the file
  ## Returns error if buffer has no file path or git command fails

  if buffer.filePath.isNone:
    return err("Buffer has no associated file path")

  let filePath = buffer.filePath.get

  # Get git repository root
  let gitRootResult = getGitRoot(filePath)
  if gitRootResult.isErr:
    return err(gitRootResult.error)
  let gitRoot = gitRootResult.get

  # Prepare temporary files for comparison
  let bufferContent = buffer.getFileContent()
  let tempFilesResult = prepareBufferDiffTempFiles(filePath, gitRoot, bufferContent)

  # Handle case where file is not in git yet
  if tempFilesResult.isErr:
    if tempFilesResult.error == "File is not in git repository":
      return ok(GitDiffInfo(lines: @[]))
    return err(tempFilesResult.error)

  let (tempOriginal, tempModified) = tempFilesResult.get

  # Ensure cleanup of temporary files on function exit
  defer:
    removeTempFileSafely(tempOriginal)
    removeTempFileSafely(tempModified)

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

  # Parse git diff output using shared parser
  return ok(parseDiffOutput(output))

proc startGitDiffFromBufferAsync*(buffer: TextBuffer): Result[GitDiffProcess, string] =
  ## Start git diff for buffer contents as a background process
  ## Returns GitDiffProcess object that can be polled for completion
  ## Use checkGitDiffComplete() to check if the process has finished
  ##
  ## This compares in-memory buffer contents with git HEAD, allowing
  ## real-time diff updates without saving the file.

  if buffer.filePath.isNone:
    return err("Buffer has no associated file path")

  let filePath = buffer.filePath.get

  # Get git repository root
  let gitRootResult = getGitRoot(filePath)
  if gitRootResult.isErr:
    return err(gitRootResult.error)
  let gitRoot = gitRootResult.get

  # Prepare temporary files for comparison
  let bufferContent = buffer.getFileContent()
  let tempFilesResult = prepareBufferDiffTempFiles(filePath, gitRoot, bufferContent)
  if tempFilesResult.isErr:
    return err(tempFilesResult.error)

  let (tempOriginal, tempModified) = tempFilesResult.get

  # Prepare git diff command
  let gitCmd = "git"
  let args = ["diff", "--no-index", "--unified=0", tempOriginal, tempModified]

  # Start the process in background
  let process =
    try:
      startProcess(
        gitCmd,
        workingDir = gitRoot,
        args = args,
        options = {poUsePath, poStdErrToStdOut},
      )
    except OSError as e:
      # Clean up temp files on error
      removeTempFileSafely(tempOriginal)
      removeTempFileSafely(tempModified)
      return err("Failed to start git process: " & e.msg)

  # Create and return the process object
  let diffProc = GitDiffProcess(
    process: process,
    startTime: epochTime(),
    filePath: filePath,
    workingDir: gitRoot,
    isBufferDiff: true,
    tempOriginal: tempOriginal,
    tempModified: tempModified,
  )

  return ok(diffProc)

proc applyGitDiffToBuffer*(buffer: TextBuffer, diffInfo: GitDiffInfo) =
  ## Apply git diff information to buffer sidebar markers
  ## This will set appropriate markers for added, modified, and deleted lines

  # Clear existing git markers only. LSP diagnostics and other marker kinds
  # (SessionModified, Bookmark, GitConflict) are preserved, since this
  # proc may run periodically via the async cache refresh and blowing away
  # diagnostics on every tick causes the LSP error gutter to flicker.
  buffer.clearGitMarkers()

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

proc getGitBranch*(filePath: string): Result[string, string] =
  ## Get the current git branch name for a file
  ## Returns error if file is not in a git repository or git command fails
  if not fileExists(filePath):
    return err("File does not exist: " & filePath)

  let fileDir = filePath.parentDir()

  # Get current branch name
  let (output, exitCode) =
    try:
      execCmdEx("git rev-parse --abbrev-ref HEAD", workingDir = fileDir)
    except OSError as e:
      return err("Failed to execute git command: " & e.msg)

  if exitCode != 0:
    return err("Not in a git repository")

  return ok(output.strip())

proc countGitChangedLines*(
    diffInfo: GitDiffInfo
): tuple[added: int, modified: int, deleted: int] =
  ## Count the number of added, modified, and deleted lines in a git diff
  result = (added: 0, modified: 0, deleted: 0)
  for line in diffInfo.lines:
    case line.kind
    of Added: result.added.inc
    of Modified: result.modified.inc
    of Deleted: result.deleted.inc

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
