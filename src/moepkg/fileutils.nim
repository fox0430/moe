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

import std/[os, encodings, strformat, strutils]

import pkg/results

import gapbuffer, unicodeext

type
  TextAndEncoding* = object
    text*: seq[Runes]
    encoding*: CharacterEncoding

  OpenFileResult* = Result[TextAndEncoding, string]

  SaveFileResult* = Result[(), string]

  FileType* {.pure.} = enum
    dir
    docker
    nim
    nimble
    rpm
    deb
    py
    ui
    glade
    txt
    md
    rst
    cpp
    cxx
    hpp
    c
    h
    java
    php
    js
    json
    rs
    html
    xhtml
    css
    xml
    cfg
    ini
    sh
    pdf
    doc
    odf
    ods
    odt
    wav
    mp3
    ogg
    zip
    bz2
    xz
    gz
    tgz
    zstd
    exe
    bin
    mp4
    webm
    avi
    mpeg
    patch
    lock
    pem
    crt
    png
    jpeg
    jpg
    bmp
    gif
    unknown

proc fileTypeIcon*(fileType: FileType): Runes =
  case fileType
  of dir:
    ru"📁"
  of docker:
    ru"🐳"
  of nim:
    ru"👑"
  of nimble, rpm, deb:
    ru"📦"
  of py:
    ru"🐍"
  of ui, glade:
    ru"🏠"
  of txt, md, rst:
    ru"📝"
  of cpp, cxx, hpp:
    ru"⧺"
  of c, h:
    ru"🅒"
  of java:
    ru"🍵"
  of php:
    ru"🙈"
  of js, json:
    ru"🙉"
  of rs:
    ru"🦀"
  of html, xhtml:
    ru"🏄"
  of css:
    ru"👚"
  of xml:
    ru"༕"
  of cfg, ini:
    ru"🍳"
  of sh:
    ru"🐚"
  of pdf, doc, odf, ods, odt:
    ru"🍞"
  of wav, mp3, ogg:
    ru"🎼"
  of zip, bz2, xz, gz, tgz, zstd:
    ru"🚢"
  of exe, bin:
    ru"🏃"
  of mp4, webm, avi, mpeg:
    ru"🎞"
  of patch:
    ru"💊"
  of lock:
    ru"🔒"
  of pem, crt:
    ru"🔏"
  of png, jpeg, jpg, bmp, gif:
    ru"🎨"
  else:
    ru"🍕"

proc isDockerFile*(filename: string): bool {.inline.} =
  ## Return true if Dockerfile or docker compose file.

  filename == "Dockerfile" or filename == "docker-compose.yml" or
    filename == "docker-compose.yaml" or filename == "compose.yaml" or
    filename == "compose.yml"

proc getFileType*(path: string): FileType =
  if dirExists(path):
    return FileType.dir
  else:
    let fileSplit = splitFile(path)
    if fileSplit.ext.len == 0:
      if isDockerFile(fileSplit.name):
        return FileType.docker
      else:
        # Not sure if this is a perfect solution,
        # it should detect if the current user can execute the file or not:
        try:
          let permissions = getFilePermissions(path)
          if fpUserExec in permissions or fpGroupExec in permissions:
            return FileType.exe
        except:
          return FileType.unknown
    else:
      for ext in FileType:
        if ext != FileType.unknown and fileSplit.ext[1 .. ^1] == $ext:
          return ext
      return FileType.unknown

proc getFileExtension*(path: Runes): Runes =
  ## Return a file extension from path.
  ## Return empty string if doesn't exist.

  if not dirExists($path) and path.contains(ru '.'):
    let position = path.rfind(ru '.')
    if position < path.high:
      return path[position + 1 .. ^1]

proc normalizedPath*(path: Runes): Runes =
  result = normalizedPath($path).toRunes
  if path.startsWith(ru '~'):
    if path == ru"~" or path == ru"~/":
      return getHomeDir().toRunes
    elif path.startsWith(ru"~/") and path.len > 2:
      return getHomeDir().toRunes & path[2 .. ^1]

proc splitPath*(path: Runes): tuple[head, tail: Runes] =
  let (head, tail) = splitPath($path)
  return (head: head.toRunes, tail: tail.toRunes)

proc splitAndNormalizedPath*(path: Runes): tuple[head, tail: Runes] =
  ## Returns a normalized path after split.

  let (head, tail) = splitPath(path)
  return (head: normalizedPath(head), tail: normalizedPath(tail))

proc readFile(path: Runes): seq[Runes] =
  ## Read file and return `seq[Runes]`.

  # Get file size to optimize memory allocation
  let fileSize = getFileSize($path)

  # For small files, read all at once (reduces intermediate copies)
  const smallFileSizeThreshold = 1024 * 1024 * 10 # 10MB
  if fileSize <= smallFileSizeThreshold:
    # Read the entire file at once
    let content = readFile($path)

    # Initialize result array (pre-allocate with estimated line count)
    let estimatedLineCount = max(1, content.count('\n') + 1)
    result = newSeqOfCap[Runes](estimatedLineCount)

    # Buffer to hold the current line (pre-allocate with estimated average line length)
    let avgLineLen = max(10, fileSize div estimatedLineCount)
    var currentLine = newSeqOfCap[Rune](avgLineLen)

    var i = 0
    while i < content.len:
      # Process line breaks
      if content[i] == '\n':
        result.add currentLine
        currentLine = newSeqOfCap[Rune](avgLineLen)
        i += 1
        continue
      elif content[i] == '\r':
        if i + 1 < content.len and content[i + 1] == '\n':
          # Windows-style line break (\r\n)
          result.add currentLine
          currentLine = newSeqOfCap[Rune](avgLineLen)
          i += 2
          continue
        else:
          # Old Mac-style line break (\r)
          result.add currentLine
          currentLine = newSeqOfCap[Rune](avgLineLen)
          i += 1
          continue

      # Get rune length
      let runeLen = runeLenAt(content, i)

      # Add the rune to the current line (with boundary check)
      if i + runeLen <= content.len:
        currentLine.add content.runeAt(i)
      i += runeLen

    # Add the last line (if the file doesn't end with a line break)
    if currentLine.len > 0:
      result.add currentLine
  else:
    # For large files, use buffering (balance with memory usage)
    var f = open($path, fmRead)
    defer:
      f.close

    # Use a value close to system page size (4KB-16KB on most systems)
    const bufferSize = 16384
    var buffer = newString(bufferSize)

    # Use a variable-length buffer that can be accessed directly to reduce buffer concatenation copies
    var workBuffer: string
    workBuffer.setLen(2 * bufferSize) # Allocate sufficient initial size
    var workBufferLen = 0

    # Initialize result array (pre-allocate with estimated line count)
    # Assuming average line length of 80 bytes
    let estimatedLineCount = max(1, fileSize div 80 + 1)
    result = newSeqOfCap[Runes](estimatedLineCount)

    # Buffer to hold the current line
    var currentLine = newSeqOfCap[Rune](80) # Assume average line length

    # File reading loop
    while not f.endOfFile():
      let bytesRead = f.readChars(buffer)
      if bytesRead <= 0:
        break

      # Check and extend workBuffer capacity
      if workBufferLen + bytesRead > workBuffer.len:
        # New size = 2x current size or enough to hold bytesRead
        let newSize = max(workBuffer.len * 2, workBufferLen + bytesRead)
        workBuffer.setLen(newSize)

      # Add newly read data to workBuffer (direct copy)
      copyMem(addr workBuffer[workBufferLen], addr buffer[0], bytesRead)
      workBufferLen += bytesRead

      var processedPos = 0
      var i = 0
      while i < workBufferLen:
        # Process line breaks
        if workBuffer[i] == '\n':
          result.add currentLine
          currentLine = newSeqOfCap[Rune](80)
          i += 1
          processedPos = i
          continue
        elif workBuffer[i] == '\r':
          if i + 1 < workBufferLen and workBuffer[i + 1] == '\n':
            # Windows-style line break (\r\n)
            result.add currentLine
            currentLine = newSeqOfCap[Rune](80)
            i += 2
            processedPos = i
            continue
          else:
            # Old Mac-style line break (\r)
            result.add currentLine
            currentLine = newSeqOfCap[Rune](80)
            i += 1
            processedPos = i
            continue

        # Get rune length
        let runeLen = runeLenAt(workBuffer, i)

        # If rune length exceeds buffer remainder, interrupt processing
        if i + runeLen > workBufferLen:
          break

        # Add the rune to the current line
        currentLine.add workBuffer.runeAt(i)
        i += runeLen
        processedPos = i

      # Remove processed portion from buffer (data shift)
      if processedPos > 0:
        if processedPos < workBufferLen:
          # Move remaining data to beginning (memory move)
          moveMem(
            addr workBuffer[0],
            addr workBuffer[processedPos],
            workBufferLen - processedPos,
          )
        workBufferLen -= processedPos

    # Process the last line (if the file doesn't end with a line break)
    if workBufferLen > 0:
      # Convert remaining buffer to runes
      var i = 0
      while i < workBufferLen:
        let runeLen = runeLenAt(workBuffer, i)
        if i + runeLen <= workBufferLen:
          currentLine.add workBuffer.runeAt(i)
        i += runeLen

    # Add the last line if it exists
    if currentLine.len > 0:
      result.add currentLine

proc detectFileEncoding(path: string): Result[CharacterEncoding, string] =
  var f =
    try:
      open(path, fmRead)
    except IOError as e:
      return Result[CharacterEncoding, string].err fmt"Failed to read file: {e.msg}"
  defer:
    f.close()

  const MaxReadBytes = 100
  let
    fileSize = getFileSize(path)
    bytesToRead = min(MaxReadBytes, fileSize)

  var buf = newSeq[byte](bytesToRead)
  let bytesRead = f.readBytes(buf, 0, bytesToRead)

  if bytesRead < bytesToRead:
    buf.setLen(bytesRead)

  var str = newString(bytesRead)
  for i in 0 ..< bytesRead:
    str[i] = char(buf[i])

  let e = detectCharacterEncoding(str)
  return Result[CharacterEncoding, string].ok e

proc openFile*(path: string | Runes): OpenFileResult =
  var t: TextAndEncoding

  block:
    let e = detectFileEncoding($path)
    if e.isOk:
      t.encoding = e.get
    else:
      return OpenFileResult.err fmt"Failed to read file: {e.error}"

  case t.encoding
  of CharacterEncoding.unknown, CharacterEncoding.utf8:
    # If the character encoding is unknown, convert to UTF-8.
    t.text =
      try:
        readFile(path.toRunes)
      except IOError as e:
        return OpenFileResult.err fmt"Failed to read file: {e.msg}"
  else:
    let raw =
      try:
        readFile($path)
      except IOError as e:
        return OpenFileResult.err fmt"Failed to read file: {e.msg}"

    let text = convert(raw, "UTF-8", $t.encoding)
    t.text = text.toSeqRunes

  return OpenFileResult.ok t

proc newFile*(): GapBuffer[Runes] {.inline.} =
  result = initGapBuffer[Runes]()
  result.add(ru"", false)

proc saveFile*(
    path: string | Runes, runes: Runes, encoding: CharacterEncoding
): SaveFileResult =
  let
    encode =
      if encoding == CharacterEncoding.unknown: CharacterEncoding.utf8 else: encoding
    buffer = convert($runes & '\n', $encode, "UTF-8")

  try:
    writeFile($path, buffer)
  except IOError as e:
    return SaveFileResult.err fmt"Failed to save file: {e.msg}"

  return SaveFileResult.ok ()

proc isAccessibleDir*(path: string): bool =
  ## Return true if the path is a directory and accessible.

  if dirExists(path):
    for _ in walkDir(path):
      return true

proc expandTilde*(path: Runes): Runes {.inline.} =
  expandTilde($path).toRunes
