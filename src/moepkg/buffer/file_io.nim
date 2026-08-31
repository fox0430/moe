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
## plus encoding detection/transcoding (UTF-16/32 are stored as UTF-8
## internally and encoded back on save), line-ending normalization, and
## progressive syntax-highlight initialization for the first chunk of
## the file.

import std/[options, os, strutils, times]

import pkg/[celina, results]

import ../[encoding, highlight, logger]
import core, atomic_write
import highlight as buffer_highlight

type DecodedFileContent = object ## Result of `decodeFileContent`.
  text: string ## Decoded UTF-8, or the original bytes when decoding failed.
  encoding: CharacterEncoding
  hasBom: bool
  decodeFailed: bool
  decodeError: string ## Only set when `decodeFailed`.
  attemptedEncoding: CharacterEncoding
    ## Encoding attempted; `encoding` is reset to unknown on failure.

const ExternalModErrorMsg* =
  "File was modified externally. Use :w! to force save, or :e! to reload."

const TranscodedEncodings = {
  CharacterEncoding.utf16Le, CharacterEncoding.utf16Be, CharacterEncoding.utf32Le,
  CharacterEncoding.utf32Be,
} ## Encodings that `decodeFileContent` decodes; only these can fail.

const TranscodeCandidates =
  TranscodedEncodings + {CharacterEncoding.utf16, CharacterEncoding.utf32}
  ## Like `TranscodedEncodings` plus BOM forms that `decodeFileContent` narrows.

proc detectAndNormalizeLineEnding(b: TextBuffer, content: var string) =
  ## Detect line ending style and normalize to \n in a single pass.
  ## Each \r is classified per-occurrence: \r\n pairs are stripped to \n,
  ## standalone \r is converted to \n. Mixed line endings are preserved
  ## as separate line breaks instead of being lost or duplicated.

  if content.len > 0:
    b.endOfLine =
      content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r")

  var hasCR = false
  var hasCRLF = false
  var writePos = 0
  var readPos = 0
  while readPos < content.len:
    let c = content[readPos]
    if c == '\r':
      if readPos + 1 < content.len and content[readPos + 1] == '\n':
        hasCRLF = true
        content[writePos] = '\n'
        inc writePos
        readPos += 2
      else:
        hasCR = true
        content[writePos] = '\n'
        inc writePos
        inc readPos
    else:
      content[writePos] = c
      inc writePos
      inc readPos
  content.setLen(writePos)

  if hasCRLF:
    b.lineEnding = CRLF
  elif hasCR:
    b.lineEnding = CR
  else:
    b.lineEnding = LF

proc decodeFileContent(content: string): DecodedFileContent =
  ## Strip BOM and decode `content` to UTF-8. On failure, return raw bytes
  ## with `decodeFailed` set and the reason in `decodeError`.
  result.text = content
  result.encoding = detectCharacterEncoding(result.text)
  var bomLen = 0
  case result.encoding
  of CharacterEncoding.utf8:
    if result.text.startsWith("\xEF\xBB\xBF"):
      result.hasBom = true
      result.text = result.text[3 .. ^1]
  of CharacterEncoding.utf16:
    result.hasBom = true
    bomLen = 2
    result.encoding =
      if result.text.startsWith("\xFF\xFE"):
        CharacterEncoding.utf16Le
      else:
        CharacterEncoding.utf16Be
  of CharacterEncoding.utf32:
    result.hasBom = true
    bomLen = 4
    result.encoding =
      if result.text.startsWith("\xFF\xFE"):
        CharacterEncoding.utf32Le
      else:
        CharacterEncoding.utf32Be
  else:
    discard

  if result.encoding in TranscodedEncodings:
    result.attemptedEncoding = result.encoding
    let decoded = decodeToUtf8(result.text[bomLen .. ^1], result.encoding)
    if decoded.isOk:
      result.text = decoded.get
    else:
      result.decodeError = decoded.error
      result.decodeFailed = true
      result.encoding = CharacterEncoding.unknown
      result.hasBom = false

proc loadFileWithContent*(
  b: TextBuffer, path: string, content: string, fileSize: int64 = -1
): Result[(), string]

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

  return b.loadFileWithContent(path, content, fileSize)

proc loadFileWithContent*(
    b: TextBuffer, path: string, content: string, fileSize: int64 = -1
): Result[(), string] =
  ## Init buffer from pre-read content.
  let effFileSize = if fileSize >= 0: fileSize else: content.len.int64

  var decoded = decodeFileContent(content)
  if decoded.decodeFailed:
    logWarn(
      "buffer",
      "Failed to decode " & path & " as " & encodingToString(decoded.attemptedEncoding) &
        ": " & decoded.decodeError & "; keeping raw bytes",
    )
  var contentMut = move decoded.text

  b.encoding = decoded.encoding
  b.hasBom = decoded.hasBom
  b.keepRaw = decoded.decodeFailed
  # NUL near start indicates binary (git/grep/vim convention).
  b.hasBinaryContent =
    '\0' in
    contentMut.toOpenArray(0, min(contentMut.high, EncodingDetectionSampleSize - 1))
  # Reset warning when file path changes.
  if b.filePath != some(path):
    b.warnedUnusualContent = ucOrdinary
  if decoded.decodeFailed:
    # Raw bytes: keep verbatim. `lineEnding` is unused (shows RAW);
    # `endOfLine` is preserved for round-trip.
    b.lineEnding = LF
    b.endOfLine = contentMut.len > 0 and contentMut[^1] == '\n'
  else:
    b.detectAndNormalizeLineEnding(contentMut)

  let newBackend = chooseBackendForFile(effFileSize)
  b.storage = newBufferStorage(newBackend, move contentMut)
  b.advanceContentVersion()

  b.filePath = some(path)

  if fileExists(path):
    try:
      b.lastFileModTime = some(getFileInfo(path).lastWriteTime)
    except OSError:
      b.lastFileModTime = none(Time)
  else:
    b.lastFileModTime = none(Time)
  b.externalModWarned = false

  b.changeSeq = 0
  b.savedSeq = 0

  b.clearUndoRedoState()
  b.diagnostics.setLen(0)
  b.diagnosticsDirty = true
  b.conflictBlocks.setLen(0)
  b.lastChangedLines = 0
  b.changeList.setLen(0)
  b.changeListIndex = 0

  b.foldState.clampFoldsToLineCount(b.len)
  while b.bookmarks.len > 0 and b.bookmarks[^1] >= b.len:
    b.bookmarks.setLen(b.bookmarks.len - 1)

  b.lineMarkers = initCowSeq[Option[LineMarkerKind]](b.len)
  b.modifiedLines = newSeq[LineModificationKind](b.len)

  # Raw buffer: skip highlighting.
  b.language =
    if not b.allowsTextTransforms:
      SourceLanguage.langNone
    else:
      detectLanguage(path)

  if b.language != SourceLanguage.langNone:
    if b.len > 0:
      const InitialChunkSize = 1000
      let chunkEnd = min(InitialChunkSize - 1, b.len - 1)

      var lines = newSeq[string](chunkEnd + 1)
      for i in 0 .. chunkEnd:
        lines[i] = b.getLine(i)

      let (segments, lineStates) = initHighlightIncremental(
        lines, 0, chunkEnd, TokenizerState(), @[], b.language, b.maxHighlightLineLength
      )

      b.highlight = Highlight(colorSegments: segments)
      b.incrementalHighlight = IncrementalHighlight(
        segments: segments,
        lineStates: LineStateCache(states: lineStates),
        parsedUpTo: chunkEnd,
      )
    else:
      b.highlight = Highlight(colorSegments: @[])
      b.incrementalHighlight = nil
  else:
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

  # Raw buffer: skip URI scan. Reset frontier regardless.
  b.uriScanParsedUpTo = -1
  if b.allowsTextTransforms:
    let uriChunkEnd = min(999, b.len - 1)
    discard buffer_highlight.scanAndApplyUriUnderlines(b, 0, uriChunkEnd)
    b.uriScanParsedUpTo = uriChunkEnd

  b.highlightNeedsUpdate = false

  return Result[(), string].ok ()

proc getFileContent*(buffer: TextBuffer): string =
  ## Get the buffer content as it would be written to a file,
  ## with proper trailing newline handling based on endOfLine setting.
  ## Internal \n line endings are restored to the original line ending style
  ## and internal UTF-8 is encoded back to the buffer's on-disk encoding.
  if not buffer.allowsTextTransforms:
    # Raw buffer: return bytes verbatim.
    result = buffer.getTextString
    # Restore trailing newline from `endOfLine`.
    if buffer.endOfLine:
      if not result.endsWith("\n"):
        result.add('\n')
    elif result.endsWith("\n"):
      result.setLen(result.len - 1)
    return result
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

  # Restore the on-disk encoding (internal representation is UTF-8).
  if buffer.encoding in TranscodeCandidates:
    result = encodeFromUtf8(result, buffer.encoding)
  if buffer.hasBom:
    result = bomBytes(buffer.encoding) & result

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
    # Use debug to avoid spam from autoSave; decode failure already warned at load.
    if not buffer.allowsTextTransforms:
      logDebug("buffer", "Saving raw bytes verbatim (undecodable encoding): " & path)
    elif buffer.encoding == CharacterEncoding.unknown:
      # Routine for latin-1 and other unclassifiable text.
      logDebug("buffer", "Saving file with unknown encoding: " & path)

    let content = buffer.getFileContent

    # Re-check external modification right before writing to shrink the
    # check-to-write TOCTOU window (callers may have checked earlier).
    # Only guards writes back to the buffer's own file; a save-as to a
    # different path has no external-mod baseline to compare against.
    if checkExternalMod and buffer.filePath == some(path) and
        buffer.isExternallyModified():
      return Result[(), string].err ExternalModErrorMsg

    # Atomic-ish write: temp+rename with hardlink/symlink fallback plus fsync.
    # Guards against truncation on crash and durability loss on power failure.
    let wr = writeAtomic(path, content)
    if wr.isErr:
      logError("buffer", "Failed to write file " & path & ": " & wr.error)
      return Result[(), string].err wr.error
    logDebug("buffer", "File written successfully: " & path)

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
