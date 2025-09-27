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

  TextBuffer* = ref object
    backend*: BufferBackend
    filePath*: Option[string]
    modified*: bool
    readOnly*: bool
    lineEnding*: LineEnding
    encoding*: CharacterEncoding
    endOfLine*: bool # Whether file should end with newline (vim 'endofline' option)
    cursor*: BufferPosition # Buffer-specific cursor position

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

# Line-based helper functions
proc lineToPosition*(b: TextBuffer, pos: BufferPosition): int =
  ## Convert line/column position to character position
  var
    currentLine = 0
    lineStart = 0

  for i in 0 ..< b.len:
    if currentLine == pos.line:
      return lineStart + pos.column
    if b.charAt(i) == '\n':
      inc currentLine
      lineStart = i + 1

  if currentLine == pos.line:
    lineStart + pos.column
  else:
    b.len

proc positionToLine*(b: TextBuffer, position: int): BufferPosition =
  ## Convert character position to line/column position
  var
    currentLine = 0
    lineStart = 0

  for i in 0 ..< min(position, b.len):
    if b.charAt(i) == '\n':
      inc currentLine
      lineStart = i + 1

  BufferPosition(line: currentLine, column: position - lineStart)

# Editing operations
proc insertText*(b: TextBuffer, pos: BufferPosition, text: string) =
  if text.len == 0:
    return

  case b.backendKind
  of GapBuffer:
    let position = b.lineToPosition(pos)
    b.gapBuffer.insert(position, text)

  b.modified = true

proc getLine*(b: TextBuffer, lineIndex: int): string =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.getLine(lineIndex)

proc getLineLen*(b: TextBuffer, lineIndex: int): int =
  b.getLine(lineIndex).len

proc charToBytePos*(text: string, charPos: int): int =
  ## Convert character position to byte position (Unicode-aware)
  var currentChar = 0

  for rune in text.runes:
    if currentChar >= charPos:
      break
    result += rune.size
    currentChar += 1

proc charLen*(text: string): int =
  ## Get character length (not byte length)
  text.runeLen

proc deleteChar*(b: TextBuffer, pos: BufferPosition) =
  # Unicode-aware character deletion
  case b.backendKind
  of GapBuffer:
    # Use line-based approach to handle Unicode properly
    if pos.line >= 0 and pos.line < b.len:
      let line = b.getLine(pos.line)
      if pos.column >= 0 and pos.column < line.charLen:
        # Use Unicode utilities for safe character deletion
        let newLine = line.deleteCharAt(pos.column)

        # Delete old line and insert new one
        b.gapBuffer.deleteLine(pos.line)
        b.gapBuffer.insertLine(pos.line, newLine)

  b.modified = true

proc insertLine*(b: TextBuffer, lineIndex: int, content: string) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.insertLine(lineIndex, content)

  b.modified = true

proc deleteLine*(b: TextBuffer, lineIndex: int) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.deleteLine(lineIndex)

  b.modified = true

proc splitLine*(b: TextBuffer, pos: BufferPosition) =
  b.insertText(pos, "\n")

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
