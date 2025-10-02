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

## Main buffer interface

import std/[unicode, options, strutils]

import pkg/results

import gapbuffer, cursor, unicode_utils

type
  CharacterEncoding* = enum
    utf8
    utf16
    utf16Be
    utf16Le
    utf32
    utf32Be
    utf32Le
    unknown

  LineEnding* = enum
    LF
    CRLF
    CR

  BufferBackend* = enum
    GapBuffer # Best for small to medium files

  # Undo/Redo system types
  BufferChangeKind* = enum
    ckInsertText
    ckDeleteText
    ckInsertLine
    ckDeleteLine
    ckDeleteRange
    ckTransaction # Transaction containing multiple changes

  BufferChange* = object
    case kind*: BufferChangeKind
    of ckInsertText:
      insertPos*: BufferPosition
      insertText*: string
    of ckDeleteText:
      deletePos*: BufferPosition
      deletedText*: string
    of ckInsertLine:
      insertLineIdx*: int
      insertLineText*: string
    of ckDeleteLine:
      deleteLineIdx*: int
      deletedLineText*: string
    of ckDeleteRange:
      deleteStartPos*: BufferPosition
      deleteEndPos*: BufferPosition
      deletedRangeText*: string
    of ckTransaction:
      transactionChanges*: seq[BufferChange]
      transactionDescription*: string

  # Transaction for grouping multiple changes
  BufferTransaction* = object
    changes*: seq[BufferChange]
    description*: string

  TextBuffer* = ref object
    backend*: BufferBackend
    filePath*: Option[string]
    modified*: bool
    readOnly*: bool
    lineEnding*: LineEnding
    encoding*: CharacterEncoding
    endOfLine*: bool # Whether file should end with newline (vim 'endofline' option)
    cursor*: BufferPosition # Buffer-specific cursor position

    # Undo/Redo stacks
    undoStack*: seq[BufferChange]
    redoStack*: seq[BufferChange]
    maxUndoLevels*: int # Maximum number of undo levels (0 = unlimited)

    # Transaction support
    currentTransaction*: Option[BufferTransaction]
    inTransaction*: bool

    # Backend storage
    case backendKind*: BufferBackend
    of GapBuffer:
      gapBuffer*: GapBuffer

proc chooseBackend(): BufferBackend =
  GapBuffer

proc newTextBuffer*(
    content: string = "", filePath: Option[string] = none(string)
): TextBuffer =
  let backend = chooseBackend()

  case backend
  of GapBuffer:
    TextBuffer(
      backendKind: GapBuffer,
      backend: backend,
      filePath: filePath,
      modified: false,
      readOnly: false,
      lineEnding: LF,
      encoding: utf8,
      endOfLine: true, # Default to POSIX text file standard
      cursor: BufferPosition(line: 0, column: 0),
      gapBuffer: newGapBuffer(content),
      undoStack: @[],
      redoStack: @[],
      maxUndoLevels: 1000, # Default maximum undo levels
      currentTransaction: none(BufferTransaction),
      inTransaction: false,
    )

# Core text operations
proc getTextString*(b: TextBuffer): string =
  case b.backendKind
  of GapBuffer:
    $b.gapBuffer

proc len*(b: TextBuffer): int =
  ## Get number of lines in buffer
  case b.backendKind
  of GapBuffer: b.gapBuffer.lineCount

proc charAt*(b: TextBuffer, position: int): char =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.charAt(position)

proc charLen*(text: string): int =
  ## Get character length (not byte length)
  text.runeLen

proc getLine*(b: TextBuffer, lineIndex: int): string =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.getLine(lineIndex)

proc getLineLen*(b: TextBuffer, lineIndex: int): int =
  b.getLine(lineIndex).len

proc getCurrentLine*(b: TextBuffer): string =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.getLine(b.cursor.line)

proc getCurrentLineLen*(b: TextBuffer): int {.inline.} =
  b.getCurrentLine.len

# Line-based helper functions
proc lineToPosition*(b: TextBuffer, pos: BufferPosition): int =
  ## Convert line/column position (character-based) to byte position
  ## pos.column is interpreted as a character position (Unicode-aware)

  # Validate line number
  if pos.line < 0 or pos.line >= b.len:
    return 0

  # Calculate byte position of line start
  var bytePos = 0
  for i in 0 ..< pos.line:
    bytePos += b.getLine(i).len + 1 # +1 for newline character

  # Get the line content and convert character position to byte offset
  let
    line = b.getLine(pos.line)
    byteOffset = charToBytePos(line, pos.column)

  return bytePos + byteOffset

proc positionToLine*(b: TextBuffer, position: int): BufferPosition =
  ## Convert byte position to line/column position (character-based)
  ## Returns column as character position (Unicode-aware)

  var
    currentLine = 0
    bytePos = 0

  # Find which line the position is on
  for lineIdx in 0 ..< b.len:
    let
      line = b.getLine(lineIdx)
      lineEndByte = bytePos + line.len

    if position <= lineEndByte:
      # Position is on this line
      let
        byteOffsetInLine = position - bytePos
        charColumn = byteToCharPos(line, byteOffsetInLine)
      return BufferPosition(line: lineIdx, column: charColumn)

    bytePos = lineEndByte + 1 # +1 for newline

    currentLine = lineIdx + 1

  # Position is past the end of the buffer
  if b.len > 0:
    let lastLine = b.getLine(b.len - 1)
    BufferPosition(line: b.len - 1, column: charLen(lastLine))
  else:
    BufferPosition(line: 0, column: 0)

# Forward declaration for undo system
proc pushUndoChange(b: TextBuffer, change: BufferChange)

# Editing operations
proc insertText*(b: TextBuffer, pos: BufferPosition, text: string) =
  if text.len == 0:
    return

  case b.backendKind
  of GapBuffer:
    let position = b.lineToPosition(pos)
    b.gapBuffer.insert(position, text)

  # Record change for undo
  b.pushUndoChange(BufferChange(kind: ckInsertText, insertPos: pos, insertText: text))

  b.modified = true

proc charToBytePos*(text: string, charPos: int): int =
  ## Convert character position to byte position (Unicode-aware)
  var currentChar = 0

  for rune in text.runes:
    if currentChar >= charPos:
      break
    result += rune.size
    currentChar += 1

proc deleteChar*(b: TextBuffer, pos: BufferPosition) =
  # Unicode-aware character deletion
  case b.backendKind
  of GapBuffer:
    # Use byte-based approach to avoid line reconstruction issues
    if pos.line >= 0 and pos.line < b.len:
      let line = b.getLine(pos.line)
      if pos.column >= 0 and pos.column < line.charLen:
        # Get the character that will be deleted for undo
        let
          deletedChar = line.runeAtPos(pos.column)
          charSize = len($deletedChar)

        # Convert to byte position and delete directly
        let bytePos = b.lineToPosition(pos)
        b.gapBuffer.delete(bytePos, charSize)

        # Record change for undo
        b.pushUndoChange(
          BufferChange(kind: ckDeleteText, deletePos: pos, deletedText: $deletedChar)
        )

  b.modified = true

proc insertLine*(b: TextBuffer, lineIndex: int, content: string) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.insertLine(lineIndex, content)

  # Record change for undo
  b.pushUndoChange(
    BufferChange(kind: ckInsertLine, insertLineIdx: lineIndex, insertLineText: content)
  )

  b.modified = true

proc deleteLine*(b: TextBuffer, lineIndex: int) =
  # Save line content before deleting for undo
  let deletedContent = b.getLine(lineIndex)

  case b.backendKind
  of GapBuffer:
    b.gapBuffer.deleteLine(lineIndex)

  # Record change for undo
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteLine, deleteLineIdx: lineIndex, deletedLineText: deletedContent
    )
  )

  b.modified = true

proc getTextInRange*(b: TextBuffer, startPos, endPos: BufferPosition): string =
  ## Get text from startPos to endPos (inclusive)
  if startPos.line == endPos.line:
    let line = b.getLine(startPos.line)
    if endPos.column >= line.charLen:
      # Include newline
      result = line.substr(startPos.column) & "\n"
    else:
      result = line.substr(startPos.column, endPos.column)
  else:
    # Multi-line range
    for lineIdx in startPos.line .. endPos.line:
      let line = b.getLine(lineIdx)
      if lineIdx == startPos.line:
        result &= line.substr(startPos.column) & "\n"
      elif lineIdx == endPos.line:
        if endPos.column >= line.charLen:
          result &= line & "\n"
        else:
          result &= line.substr(0, endPos.column)
      else:
        result &= line & "\n"

proc deleteRange*(b: TextBuffer, startPos, endPos: BufferPosition) =
  ## Delete text from startPos to endPos (inclusive)
  ## Assumes startPos <= endPos (normalized range)
  ## If selection extends to/past line end, includes the newline

  # Save deleted text for undo
  let deletedText = b.getTextInRange(startPos, endPos)

  case b.backendKind
  of GapBuffer:
    if startPos.line == endPos.line:
      # Single line deletion
      let line = b.getLine(startPos.line)
      let lineLen = line.charLen

      # Check if selection extends to or past line end (includes newline)
      if endPos.column >= lineLen:
        # Delete from startPos to end of line, then join with next line
        if endPos.line < b.len - 1:
          # Multi-line: join with next line
          let nextLine = b.getLine(endPos.line + 1)
          var newLine = ""
          if startPos.column < lineLen:
            newLine = line.substr(0, startPos.column - 1)
          newLine &= nextLine

          # Delete current and next line, insert combined
          b.gapBuffer.deleteLine(endPos.line + 1)
          b.gapBuffer.deleteLine(startPos.line)
          b.gapBuffer.insertLine(startPos.line, newLine)
        else:
          # Last line: just delete to end
          var newLine = ""
          if startPos.column < lineLen:
            newLine = line.substr(0, startPos.column - 1)
          b.gapBuffer.deleteLine(startPos.line)
          b.gapBuffer.insertLine(startPos.line, newLine)
      elif startPos.column < lineLen and endPos.column < lineLen:
        # Normal single-line deletion within bounds
        var newLine = line
        for i in countdown(endPos.column, startPos.column):
          if i < newLine.charLen:
            newLine = newLine.deleteCharAt(i)

        b.gapBuffer.deleteLine(startPos.line)
        b.gapBuffer.insertLine(startPos.line, newLine)
    else:
      # Multi-line deletion
      let
        startLine = b.getLine(startPos.line)
        endLine = b.getLine(endPos.line)
        endLineLen = endLine.charLen

      # Create new combined line
      var newLine = ""

      # Keep chars before selection start
      if startPos.column < startLine.charLen:
        newLine = startLine.substr(0, startPos.column - 1)

      # If endPos is at or past line end, delete the newline (join lines)
      # Otherwise, keep chars after selection end
      if endPos.column < endLineLen:
        # Selection ends within the line - keep remaining chars
        newLine &= endLine.substr(endPos.column + 1)
      elif endPos.line < b.len - 1:
        # Selection extends to/past line end - join with next line instead
        let nextLine = b.getLine(endPos.line + 1)
        newLine &= nextLine
        # Delete one more line (the next line that we're joining)
        b.gapBuffer.deleteLine(endPos.line + 1)

      # Delete all lines from startPos.line to endPos.line
      for i in countdown(endPos.line, startPos.line):
        b.gapBuffer.deleteLine(i)

      # Insert the combined line
      b.gapBuffer.insertLine(startPos.line, newLine)

  # Record change for undo
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteRange,
      deleteStartPos: startPos,
      deleteEndPos: endPos,
      deletedRangeText: deletedText,
    )
  )

  b.modified = true

proc splitLine*(b: TextBuffer, pos: BufferPosition) =
  # splitLine just inserts a newline, which is already recorded by insertText
  b.insertText(pos, "\n")

# Undo/Redo system

proc pushUndoChange(b: TextBuffer, change: BufferChange) =
  ## Add a change to the undo stack (or current transaction)
  if b.inTransaction and b.currentTransaction.isSome:
    # Add to current transaction
    var transaction = b.currentTransaction.get
    transaction.changes.add(change)
    b.currentTransaction = some(transaction)
  else:
    # Add directly to undo stack
    b.undoStack.add(change)

    # Clear redo stack when new change is made
    b.redoStack.setLen(0)

    # Limit undo stack size if maxUndoLevels is set
    if b.maxUndoLevels > 0 and b.undoStack.len > b.maxUndoLevels:
      b.undoStack.delete(0)

proc beginTransaction*(b: TextBuffer, description: string = "") =
  ## Begin a transaction to group multiple changes
  if b.inTransaction:
    return # Already in a transaction

  b.inTransaction = true
  b.currentTransaction = some(BufferTransaction(changes: @[], description: description))

proc commitTransaction*(b: TextBuffer) =
  ## Commit the current transaction
  if not b.inTransaction or b.currentTransaction.isNone:
    return

  let transaction = b.currentTransaction.get
  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)

  # Add transaction as a single undo entry if it has changes
  if transaction.changes.len > 0:
    b.undoStack.add(
      BufferChange(
        kind: ckTransaction,
        transactionChanges: transaction.changes,
        transactionDescription: transaction.description,
      )
    )

    # Clear redo stack when new change is made
    b.redoStack.setLen(0)

    # Limit undo stack size if maxUndoLevels is set
    if b.maxUndoLevels > 0 and b.undoStack.len > b.maxUndoLevels:
      b.undoStack.delete(0)

proc rollbackTransaction*(b: TextBuffer) =
  ## Rollback the current transaction without applying changes
  if not b.inTransaction:
    return

  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)

proc getChangePosition(change: BufferChange): BufferPosition =
  ## Get the starting position of a change
  case change.kind
  of ckInsertText:
    return change.insertPos
  of ckDeleteText:
    return change.deletePos
  of ckInsertLine:
    return BufferPosition(line: change.insertLineIdx, column: 0)
  of ckDeleteLine:
    return BufferPosition(line: change.deleteLineIdx, column: 0)
  of ckDeleteRange:
    return change.deleteStartPos
  of ckTransaction:
    # For transactions, return the position of the first change
    if change.transactionChanges.len > 0:
      return getChangePosition(change.transactionChanges[0])
    else:
      return BufferPosition(line: 0, column: 0)

proc undoChange(b: TextBuffer, change: BufferChange) =
  ## Apply the inverse of a single change (internal helper)
  case change.kind
  of ckInsertText:
    # Undo insert by deleting the inserted text (all bytes at once)
    case b.backendKind
    of GapBuffer:
      let position = b.lineToPosition(change.insertPos)
      b.gapBuffer.delete(position, change.insertText.len)
  of ckDeleteText:
    # Undo delete by inserting the deleted text
    case b.backendKind
    of GapBuffer:
      let position = b.lineToPosition(change.deletePos)
      b.gapBuffer.insert(position, change.deletedText)
  of ckInsertLine:
    # Undo insert line by deleting it
    case b.backendKind
    of GapBuffer:
      b.gapBuffer.deleteLine(change.insertLineIdx)
  of ckDeleteLine:
    # Undo delete line by inserting it
    case b.backendKind
    of GapBuffer:
      b.gapBuffer.insertLine(change.deleteLineIdx, change.deletedLineText)
  of ckDeleteRange:
    # Undo delete range by inserting the deleted text
    case b.backendKind
    of GapBuffer:
      let position = b.lineToPosition(change.deleteStartPos)
      b.gapBuffer.insert(position, change.deletedRangeText)
  of ckTransaction:
    # Undo all changes in transaction in reverse order
    for i in countdown(change.transactionChanges.len - 1, 0):
      b.undoChange(change.transactionChanges[i])

proc undo*(b: TextBuffer, count: int = 1): Result[(), string] =
  ## Undo the last 'count' changes (or all changes in a transaction group)
  ## Moves cursor to the position of the first undone change
  if b.undoStack.len == 0:
    return Result[(), string].err "Nothing to undo"

  var undoneChanges: seq[BufferChange] = @[]

  # Undo 'count' changes
  for i in 0 ..< count:
    if b.undoStack.len == 0:
      break

    let change = b.undoStack.pop()
    b.undoChange(change)
    undoneChanges.add(change)

  # Add all undone changes to redo stack (in reverse order to maintain correct redo)
  for change in undoneChanges:
    b.redoStack.add(change)

  # Move cursor to the position of the first change
  if undoneChanges.len > 0:
    b.cursor = getChangePosition(undoneChanges[0])

  # Mark buffer as modified
  b.modified = true

  return Result[(), string].ok ()

proc redoChange(b: TextBuffer, change: BufferChange) =
  ## Re-apply a single change (internal helper)
  case change.kind
  of ckInsertText:
    case b.backendKind
    of GapBuffer:
      let position = b.lineToPosition(change.insertPos)
      b.gapBuffer.insert(position, change.insertText)
  of ckDeleteText:
    case b.backendKind
    of GapBuffer:
      let position = b.lineToPosition(change.deletePos)
      b.gapBuffer.delete(position, change.deletedText.len)
  of ckInsertLine:
    case b.backendKind
    of GapBuffer:
      b.gapBuffer.insertLine(change.insertLineIdx, change.insertLineText)
  of ckDeleteLine:
    case b.backendKind
    of GapBuffer:
      b.gapBuffer.deleteLine(change.deleteLineIdx)
  of ckDeleteRange:
    # Re-apply delete range (delete all bytes at once)
    case b.backendKind
    of GapBuffer:
      let position = b.lineToPosition(change.deleteStartPos)
      b.gapBuffer.delete(position, change.deletedRangeText.len)
  of ckTransaction:
    # Redo all changes in transaction in forward order
    for change in change.transactionChanges:
      b.redoChange(change)

proc redo*(b: TextBuffer, count: int = 1): Result[(), string] =
  ## Redo the last 'count' undone changes
  ## Moves cursor to the position of the first redone change
  if b.redoStack.len == 0:
    return Result[(), string].err "Nothing to redo"

  var redoneChanges: seq[BufferChange] = @[]

  # Redo 'count' changes
  for i in 0 ..< count:
    if b.redoStack.len == 0:
      break

    let change = b.redoStack.pop()
    b.redoChange(change)
    redoneChanges.add(change)

  # Add all redone changes back to undo stack (in reverse order)
  for i in countdown(redoneChanges.len - 1, 0):
    b.undoStack.add(redoneChanges[i])

  # Move cursor to the position of the first change
  if redoneChanges.len > 0:
    b.cursor = getChangePosition(redoneChanges[0])

  # Mark buffer as modified
  b.modified = true

  return Result[(), string].ok ()

# File operations
proc chooseBackendForFile(): BufferBackend =
  # TODO: Choose appropriate backend based on file size
  chooseBackend()

proc encodingToString*(encoding: CharacterEncoding): string =
  ## Convert encoding enum to display string
  case encoding
  of CharacterEncoding.utf8:
    return "UTF-8"
  of CharacterEncoding.utf16:
    return "UTF-16"
  of CharacterEncoding.utf16Be:
    return "UTF-16BE"
  of CharacterEncoding.utf16Le:
    return "UTF-16LE"
  of CharacterEncoding.utf32:
    return "UTF-32"
  of CharacterEncoding.utf32Be:
    return "UTF-32BE"
  of CharacterEncoding.utf32Le:
    return "UTF-32LE"
  of CharacterEncoding.unknown:
    return "UNKNOWN"

proc validateUtf16Be(s: string): bool =
  if (s.len mod 2) != 0:
    return false

  var i = 0

  proc advance(): int =
    result = 256 * ord(s[i]) + ord(s[i + 1])
    i += 2

  while i < s.len:
    let curr = advance()
    if curr <= 0xD7FF or (0xE000 <= curr and curr <= 0xFFFF):
      continue
    let next = advance()
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or
        (not (0xDC00 <= next and next <= 0xDFFF)):
      return false
    let
      higher = (curr and 0b11_1111_1111) shl 10
      lower = (next and 0b11_1111_1111)
      point = higher or lower
    if point < 0x10000:
      return false

  return true

proc validateUtf16Le(s: string): bool =
  if (s.len mod 2) != 0:
    return false

  var i = 0

  proc advance(): int =
    result = ord(s[i]) + 256 * ord(s[i + 1])
    i += 2

  while i < s.len:
    let curr = advance()
    if curr <= 0xD7FF or (0xE000 <= curr and curr <= 0xFFFF):
      continue
    let next = advance()
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or
        (not (0xDC00 <= next and next <= 0xDFFF)):
      return false
    let
      higher = (curr and 0b11_1111_1111) shl 10
      lower = (next and 0b11_1111_1111)
      point = higher or lower
    if point < 0x10000:
      return false

  return true

proc validateUtf32Be(s: string): bool =
  if (s.len mod 4) != 0:
    return false

  var i = 0
  proc advance(): uint32 =
    result =
      0x1000000'u32 * uint32(ord(s[i])) + 0x10000'u32 * uint32(ord(s[i + 1])) +
      0x100'u32 * uint32(ord(s[i + 2])) + uint32(ord(s[i + 3]))
    i += 4

  while i < s.len:
    let curr = advance()
    if curr > 0x10FFFF'u32:
      return false

  return true

proc validateUtf32Le(s: string): bool =
  if (s.len mod 4) != 0:
    return false

  var i = 0
  proc advance(): uint32 =
    result =
      uint32(ord(s[i])) + 0x100'u32 * uint32(ord(s[i + 1])) +
      0x10000'u32 * uint32(ord(s[i + 2])) + 0x1000000'u32 * uint32(ord(s[i + 3]))
    i += 4

  while i < s.len:
    let curr = advance()
    if curr > 0x10FFFF'u32:
      return false

  return true

proc count0000(s: string): int =
  var i = 0
  while i + 1 < s.len:
    if ord(s[i]) == 0x00 and ord(s[i + 1]) == 0x00:
      inc(result)
    i += 2

proc detectCharacterEncoding*(s: string): CharacterEncoding =
  ## Guess the character encoding.
  ## In currently, only Unicode formats are supported.
  ## Returns `CharacterEncoding.utf8` if only ASCII characters are included.
  ## Returns `CharacterEncoding.unknown` if encoding format is unknown.

  # Check UTF-8 BOM
  if s.len >= 3 and s[0 .. 2] == "\xEF\xBB\xBF":
    return CharacterEncoding.utf8

  if s.len >= 4:
    # Check UTF-32 BOM
    if s[0 .. 3] == "\x00\x00\xFE\xFF" or s[0 .. 3] == "\xFF\xFE\x00\x00":
      return CharacterEncoding.utf32

    # Check UTF-16 BOM
    if s[0 .. 1] == "\xFE\xFF" or s[0 .. 1] == "\xFF\xFE":
      return CharacterEncoding.utf16

  if s.validateUtf8 == -1:
    return CharacterEncoding.utf8

  var validEncodings: seq[CharacterEncoding]
  if s.validateUtf16Be:
    validEncodings.add(CharacterEncoding.utf16Be)
  if s.validateUtf16Le:
    validEncodings.add(CharacterEncoding.utf16Le)
  if s.validateUtf32Be:
    validEncodings.add(CharacterEncoding.utf32Be)
  if s.validateUtf32Le:
    validEncodings.add(CharacterEncoding.utf32Le)

  let threshold = (s.len / 2) * (2 / 5)
  if float(count0000(s)) >= threshold:
    # If there are too many 0x000, assume it is not UTF-16.
    if validEncodings.contains(CharacterEncoding.utf16Be):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Be))
    if validEncodings.contains(CharacterEncoding.utf16Le):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Le))

  if validEncodings.len == 1:
    return validEncodings[0]

  return CharacterEncoding.unknown

template detectLineEnding(b: TextBuffer, content: lent string) =
  ## Detect line ending and trailing newline
  if content.contains("\r\n"):
    b.lineEnding = CRLF
  elif content.contains("\r"):
    b.lineEnding = CR
  else:
    b.lineEnding = LF

  # Detect if file ends with newline (vim 'endofline' behavior)
  b.endOfLine =
    content.len > 0 and
    (content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r"))

proc loadFile*(b: TextBuffer, path: string): Result[(), string] =
  let newBackend = chooseBackendForFile()
  var content: string
  # Reinitialize with new backend if needed
  if b.backendKind != newBackend:
    content =
      try:
        readFile(path)
      except IOError as e:
        return Result[(), string].err e.msg
    let newBuffer = newTextBuffer(content, some(path))
    b[] = newBuffer[]
  else:
    case b.backendKind
    of GapBuffer:
      content =
        try:
          readFile(path)
        except IOError as e:
          return Result[(), string].err e.msg
      b.gapBuffer = newGapBuffer(content)

  b.detectLineEnding(content)
  b.encoding = detectCharacterEncoding(content)

  b.filePath = some(path)
  b.modified = false

  return Result[(), string].ok ()

proc saveFile*(buffer: TextBuffer, path: string): Result[(), string] =
  case buffer.backendKind
  of GapBuffer:
    # Get full content
    var content = buffer.getTextString

    # Handle trailing newline according to endOfLine setting (vim behavior)
    if buffer.endOfLine:
      # Ensure file ends with newline
      if content.len == 0 or
          not (
            content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r")
          ):
        case buffer.lineEnding
        of LF:
          content.add('\n')
        of CRLF:
          content.add("\r\n")
        of CR:
          content.add('\r')
    else:
      # Remove trailing newline if present
      while content.len > 0 and
          (content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r")):
        if content.endsWith("\r\n"):
          content.setLen(content.len - 2)
        else:
          content.setLen(content.len - 1)

    # Write to file
    try:
      writeFile(path, content)
    except IOError as e:
      return Result[(), string].err e.msg

    buffer.modified = false
    buffer.filePath = some(path)

  return Result[(), string].ok ()

# Memory usage monitoring
proc estimateMemoryUsage*(buffer: TextBuffer): int =
  result = sizeof(TextBuffer)

  case buffer.backendKind
  of GapBuffer:
    result += buffer.gapBuffer.estimateMemoryUsage()

proc getPerformanceStats*(
    buffer: TextBuffer
): tuple[backend: string, memoryUsage: int, length: int] =
  let backendName =
    case buffer.backendKind
    of GapBuffer: "GapBuffer"

  (backend: backendName, memoryUsage: buffer.estimateMemoryUsage(), length: buffer.len)
