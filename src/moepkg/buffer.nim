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
  CharacterEncofing* = enum
    utf8
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
    encoding*: CharacterEncofing
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
      cursor: BufferPosition(line: 0, column: 0),
      gapBuffer: newGapBuffer(content),
    )

# Core text operations
proc getTextString*(b: TextBuffer): string =
  case b.backendKind
  of GapBuffer:
    $b.gapBuffer

proc len*(b: TextBuffer): int =
  case b.backendKind
  of GapBuffer: b.gapBuffer.len

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

template detectLineEnding(b: TextBuffer, content: lent string) =
  ## Detect line ending
  if content.contains("\r\n"):
    b.lineEnding = CRLF
  elif content.contains("\r"):
    b.lineEnding = CR
  else:
    b.lineEnding = LF

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

  b.filePath = some(path)
  b.modified = false

  return Result[(), string].ok ()

proc saveFile*(buffer: TextBuffer, path: string): Result[(), string] =
  case buffer.backendKind
  of GapBuffer:
    # Get full content and write
    try:
      writeFile(path, buffer.getTextString)
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
