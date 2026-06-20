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

## File I/O: loadFile / saveFile / getFileContent / reloadFile,
## plus encoding detection, line-ending normalization, and progressive
## syntax-highlight initialization for the first chunk of the file.

import std/[options, os, strutils, times]

import pkg/[celina, results]

import ../[encoding, highlight, logger, uri_utils]
import ../buffer_backends/[gap_buffer, sqrt_decomp, rope, piece_table]
import core

const ExternalModErrorMsg* =
  "File was modified externally. Use :w! to force save, or :e! to reload."

proc detectAndNormalizeLineEnding(b: TextBuffer, content: var string) =
  ## Detect line ending style, detect trailing newline, and normalize \r
  ## to \n in a single pass. Backends only handle \n as line separator;
  ## \r in line content causes terminal rendering corruption.

  # Detect if file ends with newline (before modifying content)
  if content.len > 0:
    b.endOfLine =
      content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r")

  # Single-pass detection + normalization: scan for \r
  var hasCR = false
  var hasCRLF = false
  for i in 0 ..< content.len:
    if content[i] == '\r':
      hasCR = true
      if i + 1 < content.len and content[i + 1] == '\n':
        hasCRLF = true
      # Replace \r with \n (for CR-only) or skip \r (for CRLF, handled below)
      break # One \r is enough to determine the line ending style

  if hasCRLF:
    b.lineEnding = CRLF
    # Strip \r in-place: copy non-\r bytes forward
    var writePos = 0
    for readPos in 0 ..< content.len:
      if content[readPos] != '\r':
        content[writePos] = content[readPos]
        inc writePos
      # Skip \r (only occurs before \n in CRLF files)
    content.setLen(writePos)
  elif hasCR:
    b.lineEnding = CR
    # Replace \r with \n in-place
    for i in 0 ..< content.len:
      if content[i] == '\r':
        content[i] = '\n'
  else:
    b.lineEnding = LF

proc loadFile*(b: TextBuffer, path: string): Result[(), string] =
  var content: string
  var fileSize: int64 = 0

  # Check if file exists; if not, start with empty content
  if fileExists(path):
    # File exists, read its content
    try:
      fileSize = getFileSize(path)
      content = readFile(path)
    except IOError as e:
      logError("buffer", "Failed to read file " & path & ": " & e.msg)
      return Result[(), string].err e.msg
  else:
    # File doesn't exist, start with empty content
    logDebug("buffer", "File does not exist, creating new: " & path)
    content = ""

  # Detect line ending, normalize \r, and detect encoding before backend init.
  b.detectAndNormalizeLineEnding(content)
  b.encoding = detectCharacterEncoding(content)

  let newBackend = chooseBackendForFile(fileSize)

  if b.backendKind != newBackend:
    # Reinitialize with new backend. Use newTextBuffer to handle the object
    # variant discriminant change, but pass skipHighlightInit=true to avoid
    # building a full runesBuffer (O(n) per line) that loadFile overwrites.
    let newBuffer = newTextBuffer(
      move content, some(path), backend = newBackend, skipHighlightInit = true
    )
    b[] = newBuffer[]
  else:
    case b.backendKind
    of GapBuffer:
      b.gapBuffer = newGapBuffer(move content)
    of SqrtDecomp:
      b.sqrtDecomp = newSqrtDecomp(move content)
    of Rope:
      b.rope = newRope(move content)
    of PieceTable:
      b.pieceTable = newPieceTable(move content)

  b.filePath = some(path)

  # Record file modification time for external change detection
  if fileExists(path):
    try:
      b.lastFileModTime = some(getFileInfo(path).lastWriteTime)
    except OSError:
      b.lastFileModTime = none(Time)
  else:
    b.lastFileModTime = none(Time)
  b.externalModWarned = false

  # Reset change tracking - file was just loaded
  b.changeSeq = 0
  b.savedSeq = 0
  b.contentVersion.inc # content replaced; bump the monotonic version

  # Reset markers and modification tracking for new file content
  b.lineMarkers = initCowSeq[Option[LineMarkerKind]](b.len)
  b.modifiedLines = newSeq[LineModificationKind](b.len)

  # Initialize syntax highlighting based on file extension
  b.language = detectLanguage(path)

  if b.language != SourceLanguage.langNone:
    if b.len > 0:
      const InitialChunkSize = 1000
      let chunkEnd = min(InitialChunkSize - 1, b.len - 1)

      var lines = newSeq[string](chunkEnd + 1)
      for i in 0 .. chunkEnd:
        lines[i] = b.getLine(i)

      let (segments, lineStates) = initHighlightIncremental(
        lines,
        0,
        chunkEnd,
        TokenizerState(), # Default initial state
        @[],
        b.language,
      )

      b.highlight = Highlight(colorSegments: segments)
      b.incrementalHighlight = IncrementalHighlight(
        segments: segments,
        lineStates: LineStateCache(states: lineStates, version: b.changeSeq),
        parsedUpTo: chunkEnd,
      )
    else:
      b.highlight = Highlight(colorSegments: @[])
      b.incrementalHighlight = nil
  else:
    # Plain text - single default segment covering all lines
    if b.len > 0:
      b.highlight = Highlight(
        colorSegments: @[
          ColorSegment(
            firstRow: 0,
            firstColumn: 0,
            lastRow: b.len - 1,
            lastColumn: max(0, b.getLine(b.len - 1).len - 1),
            color: EditorColorPairIndex.default,
            style: highlight.defaultStyle,
          )
        ]
      )
    else:
      b.highlight = Highlight(colorSegments: @[])
    b.incrementalHighlight = nil

  # Apply URI underlines for the initial chunk. The rest is handled
  # progressively by continueUriScan.
  let uriChunkEnd = min(999, b.len - 1)
  for lineIdx in 0 .. uriChunkEnd:
    let line = b.getLine(lineIdx)
    for m in findAllUris(line):
      b.highlight.addModifier(
        lineIdx, m.start, lineIdx, m.finish, StyleModifier.Underline
      )
  b.uriScanParsedUpTo = uriChunkEnd

  b.highlightNeedsUpdate = false

  return Result[(), string].ok ()

proc getFileContent*(buffer: TextBuffer): string =
  ## Get the buffer content as it would be written to a file,
  ## with proper trailing newline handling based on endOfLine setting.
  ## Internal \n line endings are restored to the original line ending style.
  result = buffer.getTextString

  # Restore original line ending style (internal representation uses \n only)
  case buffer.lineEnding
  of CRLF:
    result = result.replace("\n", "\r\n")
  of CR:
    result = result.replace('\n', '\r')
  of LF:
    discard

  if buffer.endOfLine:
    # Ensure content ends with the appropriate line ending
    let endsWithNewline =
      case buffer.lineEnding
      of LF:
        result.endsWith("\n")
      of CRLF:
        result.endsWith("\r\n")
      of CR:
        result.endsWith("\r")
    if result.len == 0 or not endsWithNewline:
      case buffer.lineEnding
      of LF:
        result.add('\n')
      of CRLF:
        result.add("\r\n")
      of CR:
        result.add('\r')
  else:
    # Remove ONE trailing line ending if present (endOfLine=false)
    if result.len > 0:
      if result.endsWith("\r\n"):
        result.setLen(result.len - 2)
      elif result.endsWith("\n") or result.endsWith("\r"):
        result.setLen(result.len - 1)

proc isExternallyModified*(b: TextBuffer): bool =
  ## Check if the file was modified externally (outside the editor)
  ## Returns true if:
  ##   - Buffer has a file path
  ##   - File exists on disk
  ##   - File's modification time is newer than when we last loaded/saved it
  if b.filePath.isNone:
    return false

  let path = b.filePath.get
  if not fileExists(path):
    return false

  if b.lastFileModTime.isNone:
    return false

  try:
    let currentModTime = getFileInfo(path).lastWriteTime
    return currentModTime > b.lastFileModTime.get
  except OSError:
    return false

proc saveFile*(
    buffer: TextBuffer, path: string, checkExternalMod: bool = false
): Result[(), string] =
  case buffer.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    let content = buffer.getFileContent

    # Re-check external modification right before writing to shrink the
    # check-to-write TOCTOU window (callers may have checked earlier).
    # Only guards writes back to the buffer's own file; a save-as to a
    # different path has no external-mod baseline to compare against.
    if checkExternalMod and buffer.filePath == some(path) and
        buffer.isExternallyModified():
      return Result[(), string].err ExternalModErrorMsg

    # Write to file
    try:
      writeFile(path, content)
      logDebug("buffer", "File written successfully: " & path)
    except IOError as e:
      logError("buffer", "Failed to write file " & path & ": " & e.msg)
      return Result[(), string].err e.msg

    buffer.markSaved()
    buffer.filePath = some(path)

    # Update file modification time after saving
    try:
      buffer.lastFileModTime = some(getFileInfo(path).lastWriteTime)
    except OSError:
      buffer.lastFileModTime = none(Time)
    buffer.externalModWarned = false

  return Result[(), string].ok ()

proc reloadFile*(b: TextBuffer): Result[(), string] =
  ## Reload file from disk, preserving the file path
  ## Call this when external modification is detected
  if b.filePath.isNone:
    return err("Buffer has no file path")

  let path = b.filePath.get
  b.loadFile(path)
