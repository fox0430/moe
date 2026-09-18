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

import std/[hashes, options, os, strutils]

import pkg/results

import ../[encoding, highlight, logger, path_key]

when defined(posix):
  import std/posix
import core, atomic_write, edit
import highlight as buffer_highlight

export WritePremise, writePremise

type
  DecodedFileContent = object ## Result of `decodeFileContent`.
    text: string ## Decoded UTF-8, or the original bytes when decoding failed.
    encoding: CharacterEncoding
    hasBom: bool
    decodeFailed: bool
    decodeError: string ## Only set when `decodeFailed`.
    attemptedEncoding: Option[CharacterEncoding]
      ## `none` when no decode was attempted; `encoding` is reset to unknown on
      ## failure.

  FileShape* = object
    ## How a file was written, and so what a save of it has to put back. A
    ## buffer option rather than part of its text: like vim's `fileformat` and
    ## `fileencoding`, these survive an undo.
    encoding*: CharacterEncoding
    hasBom*: bool
    lineEnding*: LineEnding
    endOfLine*: bool

  DecodedText* = object
    ## File bytes read the way a buffer takes them, carrying the shape so bytes
    ## that reach a buffer without going through a load still have something to
    ## be saved by.
    text*: string ## Decoded UTF-8, normalized to \n, or raw bytes on failure.
    shape*: FileShape
    hasBinaryContent*: bool ## NUL near the start.
    decodeFailed*: bool
      ## No decoding accepted these bytes, so `text` holds them verbatim. Only
      ## UTF-16/32 can fail this way; anything else comes back as `unknown`.
    decodeError*: string ## Only set when `decodeFailed`.
    attemptedEncoding*: Option[CharacterEncoding]
      ## The encoding a decode was attempted as, `none` where none was.

const
  ExternalModErrorMsg* =
    "File was modified externally. Use :w! to force save, or :e! to reload."

  UnreadFileErrorMsg* =
    "File exists but was never read here. Use :w! to overwrite, or :e! to load it."

  UnverifiedFileErrorMsg* = "File on disk could not be checked. Use :w! to save anyway."

  TargetExistsErrorMsg* = "File exists (add ! to override)."

  HeldByAnotherBufferMsg* = "File is loaded in another buffer. Use :w! to force save."

  TranscodedEncodings = {
    CharacterEncoding.utf16Le, CharacterEncoding.utf16Be, CharacterEncoding.utf32Le,
    CharacterEncoding.utf32Be,
  } ## Encodings that `decodeFileContent` decodes; only these can fail.

  TranscodeCandidates =
    TranscodedEncodings + {CharacterEncoding.utf16, CharacterEncoding.utf32}
    ## Like `TranscodedEncodings` plus BOM forms that `decodeFileContent` narrows.

  UndoableReloadMaxLines* = 10000
    ## Per-reload line cap (both sides); past this, drop undo history.
    ## Same idea as vim's `undoreload`.

  UndoableReloadBudgetLines* = 100000
    ## Cap on lines all reload entries may hold on the undo stack. Per-history:
    ## an overrun drops and refills the budget. Head-room is both whole buffers;
    ## the actual charge is the entry after the diff.

  UndoableReloadMaxBytes* = 1024 * 1024
    ## Byte counterpart of `UndoableReloadMaxLines`, for files of a few very
    ## long lines.

  UndoableReloadBudgetBytes* = 16 * 1024 * 1024
    ## Byte counterpart of `UndoableReloadBudgetLines`.

proc normalizeLineEndings(content: var string): LineEnding =
  ## Convert every line ending to \n in a single pass and report the style
  ## found. Each \r is classified per-occurrence, so mixed line endings stay
  ## separate line breaks instead of being lost or duplicated.
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
    CRLF
  elif hasCR:
    CR
  else:
    LF

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
    result.attemptedEncoding = some(result.encoding)
    let decoded = decodeToUtf8(result.text[bomLen .. ^1], result.encoding)
    if decoded.isOk:
      result.text = decoded.get
    else:
      result.decodeError = decoded.error
      result.decodeFailed = true
      result.encoding = CharacterEncoding.unknown
      result.hasBom = false

proc decodeForBuffer*(content: string): DecodedText =
  ## Turn file bytes into buffer content: BOM stripped, UTF-16/32 decoded to
  ## UTF-8, every line ending style normalized, and a trailing newline read as
  ## terminating the last line rather than starting an empty one.
  ##
  ## The one reader: a load and a whole-file replacement both come through
  ## here, so neither can drift from the other.
  var decoded = decodeFileContent(content)
  result.text = move decoded.text
  result.shape.encoding = decoded.encoding
  result.shape.hasBom = decoded.hasBom
  result.decodeFailed = decoded.decodeFailed
  result.decodeError = move decoded.decodeError
  result.attemptedEncoding = decoded.attemptedEncoding
  # NUL near start indicates binary (git/grep/vim convention), sampled before
  # normalization so the window covers the bytes as decoded.
  result.hasBinaryContent =
    '\0' in
    result.text.toOpenArray(0, min(result.text.high, EncodingDetectionSampleSize - 1))
  if result.decodeFailed:
    # Raw bytes: keep verbatim. `lineEnding` is unused (shows RAW);
    # `endOfLine` is preserved for round-trip.
    result.shape.lineEnding = LF
    result.shape.endOfLine = result.text.len > 0 and result.text[^1] == '\n'
  else:
    result.shape.endOfLine =
      result.text.len > 0 and (result.text.endsWith("\n") or result.text.endsWith("\r"))
    result.shape.lineEnding = normalizeLineEndings(result.text)

proc lines*(decoded: DecodedText): seq[string] =
  ## `decoded.text` split the way buffer storage splits it on load.
  result = decoded.text.split('\n')
  if result.len > 1 and result[^1].len == 0:
    result.setLen(result.len - 1)

proc lineCount*(decoded: DecodedText): int =
  ## How many lines `lines` would return, without building them.
  result = decoded.text.count('\n') + 1
  if decoded.text.len > 0 and decoded.text[^1] == '\n':
    dec result

proc replacementSanitizesBytes*(decoded: DecodedText): bool =
  ## True if a replacement would rewrite bytes (invalid UTF-8 to U+FFFD). A load
  ## keeps such bytes verbatim. Scanned here, not at decode, so a plain load
  ## does not pay for it.
  decoded.decodeFailed or invalidUtf8At(decoded.text) != -1

proc adoptFileShape(b: TextBuffer, shape: FileShape) =
  ## Make `b` save its text back the way `shape` was written.
  b.encoding = shape.encoding
  b.hasBom = shape.hasBom
  b.lineEnding = shape.lineEnding
  b.endOfLine = shape.endOfLine

proc noteDecodedContent(b: TextBuffer, decoded: DecodedText) =
  ## Record what the bytes `b` now holds turned out to be, and queue the notice
  ## if that is not ordinary text. `keepRaw` is set here: undecoded bytes must
  ## never reach a buffer that still allows text transforms.
  b.keepRaw = decoded.decodeFailed
  b.hasBinaryContent = decoded.hasBinaryContent
  b.noteContent()

proc replaceWithDecodedText*(
    b: TextBuffer,
    decoded: DecodedText,
    description: string,
    adoptShape = false,
    sanitizesBytes = none(bool),
): Result[LineDiff, string] =
  ## Make `b` hold `decoded` as one undo entry named `description`.
  ## Undecodable bytes are refused rather than sanitized into U+FFFD.
  ##
  ## `adoptShape` takes the file's encoding/EOL (reload / initial content).
  ## Leave it off when the buffer already has its own shape. Undo restores
  ## the old lines under the new shape. Content kind is always recorded.
  ##
  ## `sanitizesBytes` reuses a prior scan; omitted means scan here.
  if sanitizesBytes.get(decoded.replacementSanitizesBytes):
    return err(
      "Cannot " & description & ": the replacement text holds bytes no decoding read"
    )
  let replaced = b.replaceAllLines(decoded.lines, description)
  if replaced.isErr:
    return err(replaced.error)
  # Diagnostics have no remap path; drop them when lines moved. An empty diff
  # (EOL-only rewrite) moved none.
  if replaced.get.hunks.len > 0:
    b.diagnostics.setLen(0)
    b.diagnosticsDirty = true
  b.noteDecodedContent(decoded)
  if adoptShape:
    b.adoptFileShape(decoded.shape)
  ok(replaced.get)

proc loadFileWithDecoded*(
  b: TextBuffer,
  path: string,
  content: string,
  decoded: var DecodedText,
  fileSize: int64 = -1,
  stamp: Option[FileStamp] = none(FileStamp),
): Result[(), string]

proc loadFileWithContent*(
    b: TextBuffer,
    path: string,
    content: string,
    fileSize: int64 = -1,
    stamp: Option[FileStamp] = none(FileStamp),
): Result[(), string] =
  ## Init buffer from pre-read content. `stamp` is identity from before the
  ## read; omitted means stamp against the file as it is now.
  var decoded = decodeForBuffer(content)
  b.loadFileWithDecoded(path, content, decoded, fileSize, stamp)

proc captureFileStamp*(path: string): FileStamp =
  ## Current state of `path`. Only a missing-file stat is `fileObservedAbsent`.
  try:
    let info = getFileInfo(path)
    if info.kind in {pcFile, pcLinkToFile}:
      presentStamp(
        info.lastWriteTime, info.size.int64, info.id.device.uint64, info.id.file.uint64
      )
    else:
      FileStamp(observed: fileNeverObserved)
  except OSError as e:
    when defined(posix):
      if e.errorCode.cint in [ENOENT, ENOTDIR]:
        FileStamp(observed: fileObservedAbsent)
      else:
        FileStamp(observed: fileNeverObserved)
    else:
      if fileExists(path):
        FileStamp(observed: fileNeverObserved)
      else:
        FileStamp(observed: fileObservedAbsent)

proc applyFileStamp*(b: TextBuffer, stamp: FileStamp) =
  ## Set `stamp` as the baseline for external-change checks.
  b.fileBaseline = stamp
  b.externalModWarned = false
  b.autoSaveSkipWarned = false
  b.reloadDeferred = false

proc noteFileStamp*(b: TextBuffer, path: string) =
  ## Baseline `b` against the file as it is now. A load stamps before reading.
  b.applyFileStamp(captureFileStamp(path))

proc fingerprint*(content: string): ContentFingerprint =
  ContentFingerprint(size: content.len, hash: hash(content))

proc loadFile*(b: TextBuffer, path: string): Result[(), string] =
  var content: string

  # Stamp before reading so a write in between is seen as a later change.
  var stamp = captureFileStamp(path)

  # Check if file exists; if not, start with empty content
  if fileExists(path):
    # File exists, read its content
    try:
      content = readFile(path)
    except IOError as e:
      logError("buffer", "Failed to read file " & path & ": " & e.msg)
      return Result[(), string].err e.msg
    if stamp.observed != fileObservedPresent:
      # Re-stat: appeared after the first lookup, or the lookup failed.
      stamp = captureFileStamp(path)
  else:
    # File doesn't exist, start with empty content
    logDebug("buffer", "File does not exist, creating new: " & path)
    content = ""

  return b.loadFileWithContent(path, content, content.len.int64, some(stamp))

proc loadFileWithDecoded*(
    b: TextBuffer,
    path: string,
    content: string,
    decoded: var DecodedText,
    fileSize: int64 = -1,
    stamp: Option[FileStamp] = none(FileStamp),
): Result[(), string] =
  ## Init buffer from `content` already run through `decodeForBuffer`, for a
  ## caller that had to read the decoded text to decide whether to load at all.
  ## `decoded.text` is moved into the buffer. `stamp` is identity from before
  ## the read; omitted means stamp against the file as it is now.
  let effFileSize = if fileSize >= 0: fileSize else: content.len.int64

  if decoded.decodeFailed:
    logWarn(
      "buffer",
      "Failed to decode " & path & " as " &
        encodingToString(decoded.attemptedEncoding.get(CharacterEncoding.unknown)) & ": " &
        decoded.decodeError & "; keeping raw bytes",
    )

  if b.filePath != some(path):
    b.clearNotices()
  b.adoptFileShape(decoded.shape)
  b.noteDecodedContent(decoded)

  let newBackend = chooseBackendForFile(effFileSize)
  b.storage = newBufferStorage(newBackend, move decoded.text)
  b.advanceContentVersion()

  b.filePath = some(path)

  if stamp.isSome:
    b.applyFileStamp(stamp.get)
  else:
    b.noteFileStamp(path)
  b.lastLoadedContent = some(fingerprint(content))

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
        lines,
        0,
        chunkEnd,
        b.newBufferTokenizerState(),
        @[],
        b.language,
        b.maxHighlightLineLength,
      )

      b.highlight = Highlight(colorSegments: segments)
      b.incrementalHighlight = IncrementalHighlight(
        backend: b.effectiveHighlightBackend,
        initialState: b.newBufferTokenizerState(),
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

  # Last, so a subscriber can clamp against a fully consistent buffer.
  b.emitContentReplaced()

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

proc bufferHoldsFile*(buf: TextBuffer, path: string): bool =
  ## Whether `buf` holds the file at `path` (spelling or entity).
  ## This is the "same file?" predicate: overwrite, holder lookup, save-as.
  if buf.isNil or buf.filePath.isNone or path.len == 0:
    return false
  let held = buf.filePath.get
  samePath(held, path) or sameFileEntity(held, path)

proc indexOfBufferHoldingPath*(
    buffers: openArray[TextBuffer], path: string, excluding: TextBuffer = nil
): int =
  ## Index of the buffer holding the file at `path`, or -1. Skips utility and directory buffers.
  for i, buf in buffers:
    if buf.isNil or buf.isUtilityBuffer or buf.filePath.isNone:
      continue
    if not excluding.isNil and buf.id == excluding.id:
      continue
    if buf.bufferHoldsFile(path):
      return i
  -1

proc bufferHoldingPath*(
    buffers: openArray[TextBuffer], path: string, excluding: TextBuffer = nil
): Option[TextBuffer] =
  ## The buffer holding the file at `path`, if any.
  let i = indexOfBufferHoldingPath(buffers, path, excluding)
  if i < 0:
    none(TextBuffer)
  else:
    some(buffers[i])

proc editedBufferHoldingPath*(
    buffers: openArray[TextBuffer], path: string, excluding: TextBuffer = nil
): Option[TextBuffer] =
  ## Buffer holding `path` with unsaved edits, if any. Clean duplicates don't block writes.
  for buf in buffers:
    if buf.isNil or buf.isUtilityBuffer or buf.filePath.isNone:
      continue
    if not excluding.isNil and buf.id == excluding.id:
      continue
    if buf.isModified and buf.bufferHoldsFile(path):
      return some(buf)
  none(TextBuffer)

proc diskChangeSince*(b: TextBuffer): DiskChange =
  ## Compare the file at `b`'s path now against its baseline.
  if b.filePath.isNone:
    return diskUnknown

  let now = captureFileStamp(b.filePath.get)
  case b.fileBaseline.observed
  of fileNeverObserved:
    diskUnknown
  of fileObservedAbsent:
    case now.observed
    of fileNeverObserved: diskUnknown
    of fileObservedAbsent: diskUnchanged
    of fileObservedPresent: diskAppeared
  of fileObservedPresent:
    case now.observed
    of fileNeverObserved:
      diskUnknown
    of fileObservedAbsent:
      diskVanished
    of fileObservedPresent:
      # `!=`, not "newer than": mtime can move backwards (restore, checkout, clock step).
      if now == b.fileBaseline: diskUnchanged else: diskChanged

proc isExternallyModified*(b: TextBuffer): bool =
  ## Whether on-disk content differs from what this buffer read. Appeared
  ## counts; vanished does not.
  b.diskChangeSince in {diskChanged, diskAppeared}

proc targetExistsOnDisk*(path: string): bool =
  ## Whether anything is at `path` (lstat-based; also matches FIFOs, dirs, dangling links).
  classifyTarget(path).exists

proc writeGate*(
    buffer: TextBuffer, savePath: string, force = false
): tuple[refusal: WriteRefusal, expectAbsent: bool] =
  ## Whether `buffer` may be written to `savePath`, and whether that rests on
  ## the path being empty. Own path uses the baseline; other paths only if empty.
  if force or buffer.isNil:
    return (writeAllowed, false)

  if buffer.bufferHoldsFile(savePath):
    case buffer.diskChangeSince
    of diskUnchanged:
      # Unchanged covers "still absent" and "still same file"; only absent expects emptiness.
      (writeAllowed, buffer.fileBaseline.observed == fileObservedAbsent)
    of diskVanished:
      # Vanished: `:w` recreates the file, as Vim does.
      (writeAllowed, true)
    of diskChanged:
      (writeRefusedChangedOnDisk, false)
    of diskAppeared:
      (writeRefusedUnreadFile, false)
    of diskUnknown:
      # Uncheckable: allow only when there is nothing to lose.
      if targetExistsOnDisk(savePath):
        (writeRefusedUnverifiedFile, false)
      else:
        (writeAllowed, true)
  elif targetExistsOnDisk(savePath):
    (writeRefusedTargetExists, false)
  else:
    (writeAllowed, true)

proc writeRefusal*(buffer: TextBuffer, savePath: string, force = false): WriteRefusal =
  ## Whether `buffer` may be written to `savePath`, and if not, why.
  buffer.writeGate(savePath, force).refusal

proc message*(refusal: WriteRefusal): string =
  ## User message for a refusal; "" when allowed.
  case refusal
  of writeAllowed: ""
  of writeRefusedChangedOnDisk: ExternalModErrorMsg
  of writeRefusedUnreadFile: UnreadFileErrorMsg
  of writeRefusedUnverifiedFile: UnverifiedFileErrorMsg
  of writeRefusedHeldByAnotherBuffer: HeldByAnotherBufferMsg
  of writeRefusedTargetExists: TargetExistsErrorMsg

proc putBufferOnFile(
    buffer: TextBuffer, path: string, checkExternalMod: bool
): Result[string, string] =
  ## Write the buffer bytes to `path`; file half of a save without bookkeeping.
  case buffer.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    # Use debug to avoid spam from autoSave; decode failure already warned at load.
    if not buffer.allowsTextTransforms:
      logDebug("buffer", "Saving raw bytes verbatim (undecodable encoding): " & path)
    elif buffer.encoding == CharacterEncoding.unknown:
      # Routine for latin-1 and other unclassifiable text.
      logDebug("buffer", "Saving file with unknown encoding: " & path)

    let content = buffer.getFileContent

    # Re-check just before writing; pass the gate's premise, not a default.
    let premise =
      if not checkExternalMod:
        wpForce
      else:
        let gate = buffer.writeGate(path)
        if gate.refusal != writeAllowed:
          return Result[string, string].err gate.refusal.message
        writePremise(gate.expectAbsent, force = false)

    let wr = writeAtomic(path, content, premise)
    if wr.isErr:
      logError("buffer", "Failed to write file " & path & ": " & wr.error)
      return Result[string, string].err wr.error
    logDebug("buffer", "File written successfully: " & path)

    return Result[string, string].ok content

proc saveFile*(
    buffer: TextBuffer, path: string, checkExternalMod: bool = false
): Result[(), string] =
  let written = buffer.putBufferOnFile(path, checkExternalMod)
  if written.isErr:
    return Result[(), string].err written.error

  buffer.markSaved()
  buffer.filePath = some(path)

  buffer.noteFileStamp(path)
  # The bytes on disk are exactly the ones just written.
  buffer.lastLoadedContent = some(fingerprint(written.get))

  return Result[(), string].ok ()

proc reloadFile*(b: TextBuffer): Result[(), string] =
  ## Reload file from disk, preserving the file path
  ## Call this when external modification is detected
  if b.filePath.isNone:
    return err("Buffer has no file path")

  let path = b.filePath.get
  b.loadFile(path)

proc undoBytesAtMost(b: TextBuffer, cap: int): int =
  ## Byte size of `b` (each line plus its break), stopping once past `cap`.
  for line in b.lines:
    result += line.len + 1
    if result > cap:
      return

proc remapThroughHunks(
    b: TextBuffer, positions: seq[BufferPosition], hunks: seq[LineEdit]
): seq[BufferPosition] =
  ## Remap `positions` through `hunks`. A hit inside a rewritten span snaps to
  ## the span's first line so the changelist index stays valid.
  result = newSeqOfCap[BufferPosition](positions.len)
  let lastLine = max(0, b.len - 1)
  for pos in positions:
    var
      line = pos.line
      column = pos.column
      offset = 0
      snapped = false
    for hunk in hunks:
      if pos.line < hunk.start:
        break
      if pos.line < hunk.start + hunk.delete:
        line = hunk.start + offset
        column = 0
        snapped = true
        break
      offset += hunk.insert.len - hunk.delete
    if not snapped:
      line = pos.line + offset
    line = clamp(line, 0, lastLine)
    result.add BufferPosition(line: line, column: min(column, b.getLineLen(line)))

proc reloadFileIfContentChanged*(b: TextBuffer): Result[bool, string] =
  ## Reload `b` from disk if the on-disk bytes differ from last load/save.
  ## Compared against stored bytes, not a re-serialize (normalization would
  ## look like a change). A no-op write (`touch`) is skipped.
  if b.filePath.isNone:
    return err("Buffer has no file path")

  let path = b.filePath.get
  if not fileExists(path):
    return err("File does not exist: " & path)

  let stamp = captureFileStamp(path)

  var content: string
  try:
    content = readFile(path)
  except IOError as e:
    logError("buffer", "Failed to read file " & path & ": " & e.msg)
    return err(e.msg)

  let onDisk = fingerprint(content)
  if b.lastLoadedContent.isSome and onDisk == b.lastLoadedContent.get:
    # Same bytes: only the stat moved, so re-baseline and leave the buffer be.
    b.applyFileStamp(stamp)
    return ok(false)

  # Both ways in decode, so decode once and hand the result to whichever runs.
  var decoded = decodeForBuffer(content)

  # Prefer a minimal edit so undo history and per-line state survive.
  # Fallback is a wholesale load. Binary content rides no undo entry.
  let oldLineCount = b.len
  var landsAsEdit =
    b.allowsTextTransforms and not b.readOnly and oldLineCount <= UndoableReloadMaxLines and
    decoded.lineCount <= UndoableReloadMaxLines and
    decoded.text.len <= UndoableReloadMaxBytes and
    b.reloadUndoLines + oldLineCount + decoded.lineCount <= UndoableReloadBudgetLines and
    chooseBackendForFile(content.len.int64) == b.backendKind and
    decoded.hasBinaryContent == b.hasBinaryContent
  # UTF-8 scan walks the whole text: do it after cheaper checks, and reuse.
  var sanitizesBytes = none(bool)
  if landsAsEdit:
    sanitizesBytes = some(decoded.replacementSanitizesBytes)
    landsAsEdit = not sanitizesBytes.get
  if landsAsEdit:
    # Walk the buffer only after cheaper checks pass. Head-room is both whole
    # buffers; count a trailing break the new text may omit.
    let oldBytes = b.undoBytesAtMost(UndoableReloadMaxBytes)
    landsAsEdit =
      oldBytes <= UndoableReloadMaxBytes and
      b.reloadUndoBytes + oldBytes + decoded.text.len + 1 <= UndoableReloadBudgetBytes
  if landsAsEdit:
    # A reload is not a user change, so keep the changelist as-is.
    let
      changeListBefore = b.changeList
      changeListIndexBefore = b.changeListIndex
    # Transaction rollback failure falls back to a wholesale load; a Defect
    # still propagates (the process is already unsound).
    let newestEntryBefore = b.currentChangeId
    var replaced: Result[LineDiff, string]
    try:
      replaced = b.replaceWithDecodedText(
        decoded, "reload", adoptShape = true, sanitizesBytes = sanitizesBytes
      )
    except CatchableError as e:
      replaced = Result[LineDiff, string].err(e.msg)
    if replaced.isOk:
      # Charge only if this reload pushed an entry. An empty/swallowed diff
      # has nothing to bill; charging the previous entry would overwrite its
      # still-owed charge.
      if replaced.get.hunks.len > 0 and b.currentChangeId != newestEntryBefore:
        var
          chargedLines = 0
          chargedBytes = 0
        for hunk in replaced.get.hunks:
          chargedLines += hunk.delete + hunk.insert.len
          chargedBytes += hunk.deleteBytes
          for line in hunk.insert:
            chargedBytes += line.len + 1
        b.chargeReloadUndoBudget(chargedLines, chargedBytes)
        b.changeList = changeListBefore
        b.changeListIndex = changeListIndexBefore
        b.dropChangeListFuture()
        let changeListOnOldLines = b.changeList
        b.changeList = b.remapThroughHunks(changeListOnOldLines, replaced.get.hunks)
        b.detachLastEntryFromChangeList(changeListOnOldLines, b.changeListIndex)
      b.conflictBlocks.setLen(0)
      b.applyFileStamp(stamp)
      b.lastLoadedContent = some(onDisk)
      b.markSaved()
      if replaced.get.hunks.len > 0:
        # Positions held outside the buffer (selection, jumplist) need this.
        b.emitContentReplaced()
      return ok(true)
    # Edit path failed; fall back to a wholesale load.
    logWarn(
      "buffer",
      "Could not reload " & path & " as an edit: " & replaced.error &
        "; replacing the contents wholesale",
    )

  let loaded =
    b.loadFileWithDecoded(path, content, decoded, content.len.int64, some(stamp))
  if loaded.isErr:
    return err(loaded.error)
  ok(true)
