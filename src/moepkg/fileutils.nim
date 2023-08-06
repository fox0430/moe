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

import std/[os, encodings]
import gapbuffer, unicodeext

type
  FileType* = enum
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
  case fileType:
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

  filename == "Dockerfile" or
  filename == "docker-compose.yml" or
  filename == "docker-compose.yaml" or
  filename == "compose.yaml" or
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

proc normalizedPath*(path: Runes): Runes =
  result = normalizedPath($path).toRunes
  if path.startsWith(ru'~'):
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

proc openFile*(filename: Runes):
  tuple[text: Runes, encoding: CharacterEncoding] =
    # TODO: Return Result type

    let
      raw = readFile($filename)
      encoding = detectCharacterEncoding(raw)
      text =  if encoding == CharacterEncoding.unknown or
                 encoding == CharacterEncoding.utf8:
        # If the character encoding is unknown, convert to UTF-8.
        raw.toRunes
      else:
        convert(raw, "UTF-8", $encoding).toRunes
    return (text, encoding)

proc newFile*(): GapBuffer[Runes] {.inline.} =
  result = initGapBuffer[Runes]()
  result.add(ru"", false)

proc saveFile*(
  path, runes: Runes,
  encoding: CharacterEncoding) =
    # TODO: Return Result type

    let
      encode =
        if encoding == CharacterEncoding.unknown: CharacterEncoding.utf8
        else: encoding
      buffer = convert($runes, $encode, "UTF-8")
    writeFile($path, buffer)
