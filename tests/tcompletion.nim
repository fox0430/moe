#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[unittest, os, algorithm, sequtils, strutils, sugar]

import moepkg/unicodeext

import moepkg/completion {.all.}

suite "completion: isCompletionCharacter":
  test "Basics":
    check isCompletionCharacter(ru'a')
    check isCompletionCharacter("あ".toRunes[0])
    check isCompletionCharacter(ru'.')
    check isCompletionCharacter(ru'/')

    check not isCompletionCharacter(ru'=')

suite "completion: pathCompletionList":
  const TestDir = "pathCompletionListTest"

  setup:
    createDir(TestDir)

  teardown:
    removeDir(TestDir)

  test "Basic":
    createDir(TestDir / "dir1")
    createDir(TestDir / "dir2")
    writeFile(TestDir / "file1", "hello")

    check pathCompletionList(TestDir.toRunes & ru'/')
      .items
      .sortedByIt($it.label) == @[
        CompletionItem(label: ru"dir1/", insertText: ru"dir1/"),
        CompletionItem(label: ru"dir2/", insertText: ru"dir2/"),
        CompletionItem(label: ru"file1", insertText: ru"file1")
      ]

  test "Basic 2":
    createDir(TestDir / "dir1")
    createDir(TestDir / "dir2")
    writeFile(TestDir / "file1", "hello")

    check pathCompletionList(TestDir.toRunes / ru"di")
      .items
      .sortedByIt($it.label) == @[
        CompletionItem(label: ru"dir1/", insertText: ru"dir1/"),
        CompletionItem(label: ru"dir2/", insertText: ru"dir2/"),
      ]

  test "Root dir":
    check pathCompletionList(ru"/").items.len > 0

  test "Home dir":
    let expectList = collect:
      for k in walkDir(getHomeDir()):
        if k.kind == pcDir:
          k.path.replace(getHomeDir(), "") & '/'
        else:
          k.path.replace(getHomeDir(), "")

    check expectList.sorted == pathCompletionList(ru"~/")
      .items
      .mapIt($it.insertText)
      .sorted

  test "Current dir":
    let expectList = collect:
      for k in walkDir(getCurrentDir()):
        if k.kind == pcDir:
          k.path.splitPath.tail & '/'
        else:
          k.path.splitPath.tail

    check expectList.sorted == pathCompletionList(ru"./")
      .items
      .mapIt($it.insertText)
      .sorted

  test "Current dir 2":
    let expectList = collect:
      for k in walkDir("./"):
        if k.path.splitPath.tail.startsWith("s"):
          if k.kind == pcDir:
            k.path.splitPath.tail & '/'
          else:
            k.path.splitPath.tail

    check expectList.sorted == pathCompletionList(ru"s")
      .items
      .mapIt($it.insertText)
      .sorted

  test "Current dir 3":
    let expectList = collect:
      for k in walkDir("./"):
        if k.path.splitPath.tail.startsWith("s"):
          if k.kind == pcDir:
            k.path.splitPath.tail & '/'
          else:
            k.path.splitPath.tail

    check expectList.sorted == pathCompletionList(ru"./s")
      .items
      .mapIt($it.insertText)
      .sorted
