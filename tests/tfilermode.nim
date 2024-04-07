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

import std/[unittest, strutils, algorithm, os]
import pkg/results
import moepkg/[unicodeext, bufferstatus, gapbuffer, color, windownode,
               highlight]

import moepkg/filermodeutils {.all.}

proc getCurrentFiles(path: string): seq[string] =
  var
    dirs = @["../"]
    files: seq[string]
  for p in walkDir(path):
    if p.kind == PathComponent.pcDir:
      # Delete "./" or "../" and add "/" in the end of string
      if p.path.len > 2 and p.path.startsWith("../"):
        dirs.add p.path[3 .. ^1] & "/"
      else:
        dirs.add p.path[2 .. ^1] & "/"
    else:
      # Delete "./" or "../"
      if p.path.len > 2 and p.path.startsWith("../"):
        files.add p.path[3 .. ^1]

      files.add p.path[2 .. ^1]

  result = dirs.sortedByIt(it)
  result.add files.sortedByIt(it)

suite "Filer mode":
  test "Update directory list":
    const Path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(Path)

    check filerStatus.pathList.len > 0

  test "Check highlight in filer mode":
    const Path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(Path)

    var bufStatus = initBufferStatus($Path, Mode.filer).get

    const IsShowIcons = false
    bufStatus.buffer = filerStatus.initFilerBuffer(IsShowIcons).toGapBuffer

    const currentLine = 0
    let highlight = filerStatus.initFilerHighlight(bufStatus.buffer, currentLine)

    check highlight[0].color == EditorColorPairIndex.currentFile

  test "Open current directory":
    const Path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(Path)

    var bufStatus = initBufferStatus($Path, Mode.filer).get
    const IsShowIcons = false

    bufStatus.buffer = filerStatus.initFilerBuffer(IsShowIcons).toGapBuffer

    let files = getCurrentFiles($Path)
    for i in 0 ..< bufStatus.buffer.len:
      check files[i] == $bufStatus.buffer[i]

  test "Move directory":
    const Path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(Path)

    var
      bufStatuses = @[initBufferStatus($Path, Mode.filer).get]
      mainWindow = initMainWindow()
    const IsShowIcons = false

    bufStatuses[0].buffer = filerStatus.initFilerBuffer(IsShowIcons).toGapBuffer

    assert bufStatuses.openFileOrDir(
      mainWindow.currentMainWindowNode,
      filerStatus).isOk

    filerStatus.updatePathList(bufStatuses[0].path)
    bufStatuses[0].buffer = filerStatus.initFilerBuffer(IsShowIcons).toGapBuffer

    let files = getCurrentFiles("../")
    check files.len == bufStatuses[0].buffer.len
    for i in 0 ..< bufStatuses[0].buffer.len:
      check files.contains($bufStatuses[0].buffer[i])

  test "Open a file":
    const Path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(Path)

    var
      bufStatuses = @[initBufferStatus($Path, Mode.filer).get]
      mainWindow = initMainWindow()
    const IsShowIcons = false

    bufStatuses[0].buffer = filerStatus.initFilerBuffer(IsShowIcons).toGapBuffer

    for i in 0 .. bufStatuses[0].buffer.high:
      # Search a pcFile index
      if pcFile == filerStatus.pathList[i].kind:
        break
      else:
        mainWindow.currentMainWindowNode.currentLine.inc

    check bufStatuses.openFileOrDir(
      mainWindow.currentMainWindowNode,
      filerStatus).isOk

    check Mode.normal == bufStatuses[0].mode
