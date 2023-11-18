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

import std/[unittest, osproc]
import pkg/results
import moepkg/[independentutils, gapbuffer, unicodeext, bufferstatus,
               editorstatus, settings, registers, windownode]
import moepkg/syntax/highlite

import moepkg/editor {.all.}
import moepkg/ui {.all.}
import moepkg/platform {.all.}

proc isXselAvailable(): bool {.inline.} =
  execCmdExNoOutput("xset q") == 0 and execCmdExNoOutput("xsel --version") == 0

proc sourceLangToStr(lang: SourceLanguage): string =
  case lang:
    of SourceLanguage.langC:
      "C"
    of SourceLanguage.langCpp:
      "C++"
    of SourceLanguage.langCsharp:
      "C#"
    of SourceLanguage.langHaskell:
      "Haskell"
    of SourceLanguage.langJava:
      "Java"
    of SourceLanguage.langJavaScript:
      "JavaScript"
    of SourceLanguage.langMarkdown:
      "Markdown"
    of SourceLanguage.langNim:
      "Nim"
    of SourceLanguage.langPython:
      "Python"
    of SourceLanguage.langRust:
      "Rust"
    of SourceLanguage.langShell:
      "Shell"
    of SourceLanguage.langYaml:
      "Yaml"
    else:
      "Plain text"

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "Editor: Auto indent":
  test "Auto indent in current Line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  a", ru"b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"  a")
    check(status.bufStatus[0].buffer[1] == ru"  b")

  test "Auto indent in current Line 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"  b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(
      currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru""])

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"")

suite "Editor: Delete trailing spaces":
  test "Delete trailing spaces 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d  ", ru"efg"])

    status.bufStatus[0].deleteTrailingSpaces

    check status.bufStatus[0].buffer.len == 3
    check status.bufStatus[0].buffer[0] == ru"abc"
    check status.bufStatus[0].buffer[1] == ru"d"
    check status.bufStatus[0].buffer[2] == ru"efg"

  test "Fix #1582":
    # Fix for https://github.com/fox0430/moe/issues/1582.

    var bufStatus = initBufferStatus(Mode.normal).get
    bufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi "])

    bufStatus.deleteTrailingSpaces

    check bufStatus.buffer[0] == ru"abc"
    check bufStatus.buffer[1] == ru"def"
    check bufStatus.buffer[2] == ru"ghi"

suite "Editor: Delete word":
  test "With space":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"test  "])

    let settings = initEditorSettings()
    const
      Loop = 1
      WithSpace = true
      RegisterName = ""
    currentBufStatus.deleteWord(
      currentMainWindowNode,
      Loop,
      WithSpace,
      status.registers,
      RegisterName,
      settings)

    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check status.registers.noNameRegisters.buffer == @[ru"test  "]

  test "Without space":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"test  "])

    let settings = initEditorSettings()
    const
      Loop = 1
      WithSpace = false
      RegisterName = ""
    currentBufStatus.deleteWord(
      currentMainWindowNode,
      Loop,
      WithSpace,
      status.registers,
      RegisterName,
      settings)

    check currentBufStatus.buffer.toSeqRunes == @[ru"  "]
    check status.registers.noNameRegisters.buffer == @[ru"test"]

  test "Fix #842":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentBufStatus.buffer = initGapBuffer(@[ru"block:", ru"  "])
    currentMainWindowNode.currentLine = 1

    let settings = initEditorSettings()
    const
      Loop = 2
      WithSpace = true
      RegisterName = ""
    currentBufStatus.deleteWord(
      currentMainWindowNode,
      Loop,
      WithSpace,
      status.registers,
      RegisterName,
      settings)

suite "Editor: keyEnter":
  test "Delete all characters in the previous line if only whitespaces":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  "])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 2

    const IsAutoIndent = true
    for i in 0 ..< 2:
      status.bufStatus[0].keyEnter(
        currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

    check status.bufStatus[0].buffer[0] == ru"block:"
    check status.bufStatus[0].buffer[1] == ru""
    check status.bufStatus[0].buffer[2] == ru""
    check status.bufStatus[0].buffer[3] == ru"  "

  test "Fix #1370":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentBufStatus.buffer = initGapBuffer(@[ru""])
    currentBufStatus.mode = Mode.insert

    const IsAutoIndent = false
    currentBufStatus.keyEnter(
      currentMainWindowNode,
      IsAutoIndent,
      status.settings.standard.tabStop)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru ""

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Fix #1490":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentBufStatus.buffer = initGapBuffer(@[ru"import std/os",
                                              ru"       a"])
    currentBufStatus.mode = Mode.insert

    currentBufStatus.language = SourceLanguage.langNim
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = currentBufStatus.buffer[1].len

    for i in 0 ..< 2:
      const IsAutoIndent = true
      currentBufStatus.keyEnter(
        currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

  proc newLineTestCase1(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## Newline in some languages

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 1: Enable autoindent: Newline in " & langStr
        else: "Case 1: Disable autoindent: Newline in " & langStr

    # Generate test code
    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
      status.bufStatus[0].language = lang
      status.bufStatus[0].mode = Mode.insert

      block:
        let buffer = status.bufStatus[0].buffer
        status.mainWindow.currentMainWindowNode.currentColumn = buffer[0].len

      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru"test"
      check currentBufStatus.buffer[1] == ru""

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      newLineTestCase1(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      newLineTestCase1(l, IsAutoIndent)

  proc newLineTestCase2(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## Newline in some language.

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 2: Enable autoindent: Newline in " & langStr
        else: "Case 2: Disable autoindent: Newline in " & langStr

    # Generate test code
    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
      status.bufStatus[0].language = lang
      status.bufStatus[0].mode = Mode.insert

      status.mainWindow.currentMainWindowNode.currentColumn = 2

      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru"te"
      check currentBufStatus.buffer[1] == ru"st"

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      newLineTestCase2(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      newLineTestCase2(l, IsAutoIndent)

  proc newLineTestCase3(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## Newline in some languages

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 3: Enable autoindent: Newline in " & langStr
        else: "Case 3: Disable autoindent: Newline in " & langStr

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
      status.bufStatus[0].language = lang
      status.bufStatus[0].mode = Mode.insert

      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru""
      check currentBufStatus.buffer[1] == ru"test"

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      newLineTestCase3(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      newLineTestCase3(l, IsAutoIndent)

  proc newLineTestCase4(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## Newline in some languages

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 4: Enable autoindent: Newline in " & langStr
        else: "Case 4: Disable autoindent: Newline in " & langStr

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru""])
      status.bufStatus[0].language = lang
      status.bufStatus[0].mode = Mode.insert

      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru""
      check currentBufStatus.buffer[1] == ru""

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      newLineTestCase4(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      newLineTestCase4(l, IsAutoIndent)

  proc newLineTestDisableAutoindent1(lang: SourceLanguage) =
    ## Disable autoindent
    ## Line break test that case there is an indent on the current line.

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle = "Case 5: Disable autoindent: Newline in " & langStr

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
      status.bufStatus[0].language = lang
      status.bufStatus[0].mode = Mode.insert
      block:
        let buffer = status.bufStatus[0].buffer
        status.mainWindow.currentMainWindowNode.currentColumn = buffer[0].len

      const IsAutoIndent = false
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru"  test"
      check currentBufStatus.buffer[1] == ru""

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    newLineTestDisableAutoindent1(l)

suite "Editor: keyEnter: Enable autoindent in Nim":

  proc newLineTestInNimCase1(keyword: string) =
    ## Disable autoindent
    ## Line break test that case there is some keyword on the current line.
    ## keywords: "var", "let", "const"

    # Generate test title
    let testTitle = "Case 1: if the current line is " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[keyword.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert
      block:
        let lineLen = status.bufStatus[0].buffer[0].len
        status.mainWindow.currentMainWindowNode.currentColumn = lineLen

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru keyword
      check currentBufStatus.buffer[1] == ru "  "

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == status.settings.standard.tabStop

  block:
    const Keyword = "var"
    newLineTestInNimCase1(Keyword)
  block:
    const Keyword = "let"
    newLineTestInNimCase1(Keyword)
  block:
    const Keyword = "const"
    newLineTestInNimCase1(Keyword)

  proc newLineTestInNimCase2(keyword: string) =
    ## Disable autoindent
    ## Line break test that case there are some keyword and an indent on the current line.
    ## keywords: "var", "let", "const"

    # Generate test title
    let testTitle = "Case 2: if the current line is " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      const Indent = "  "
      let buffer = Indent & keyword
      status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert
      block:
        let lineLen = status.bufStatus[0].buffer[0].len
        status.mainWindow.currentMainWindowNode.currentColumn = lineLen

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check $currentBufStatus.buffer[0] == Indent & keyword
      check currentBufStatus.buffer[1] == ru "    "

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == "    ".len

  block:
    const Keyword = "var"
    newLineTestInNimCase2(Keyword)
  block:
    const Keyword = "let"
    newLineTestInNimCase2(Keyword)
  block:
    const Keyword = "const"
    newLineTestInNimCase2(Keyword)

  proc newLineTestInNimCase3(keyword: string) =
    ## Disable autoindent
    ## currentColumn is 0
    ## Line break test that case there are some keyword and an indent on the current line.
    ## keywords: "var", "let", "const"

    # Generate test title
    let testTitle = "Case 3: if the current line is " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[keyword.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru ""
      check $currentBufStatus.buffer[1] == keyword

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 0

  block:
    const Keyword = "var"
    newLineTestInNimCase3(Keyword)
  block:
    const Keyword = "let"
    newLineTestInNimCase3(Keyword)
  block:
    const Keyword = "const"
    newLineTestInNimCase3(Keyword)

  proc newLineTestInNimCase4(keyword: string) =
    ## Enable autoindent
    ## Line break test when the current line ends with "or", "and", ':', "object".

    # Generate test title
    let testTitle = "Case 4: When the current line ends with " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = @["test " & keyword].toSeqRunes
      status.bufStatus[0].buffer = initGapBuffer(buffer)
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert
      block:
        let lineLen = status.bufStatus[0].buffer[0].len
        status.mainWindow.currentMainWindowNode.currentColumn = lineLen

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      check status.bufStatus[0].buffer[0] == buffer[0]
      check $status.bufStatus[0].buffer[1] == "  "

  # Generate test code
  block:
    const Keyword = "or"
    newLineTestInNimCase4(Keyword)
  block:
    const Keyword = "and"
    newLineTestInNimCase4(Keyword)
  block:
    const Keyword = ":"
    newLineTestInNimCase4(Keyword)
  block:
    const Keyword = "object"
    newLineTestInNimCase4(Keyword)
  block:
    const Keyword = "="
    newLineTestInNimCase4(Keyword)

  proc newLineTestInNimCase5(keyword: string) =
    ## Enable autoindent
    ## currentColumn is 0
    ## Line break test when the current line ends with "or", "and", ':', "object".

    # Generate test title
    let testTitle = "Case 5: When the current line ends with " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = "test " & keyword
      status.bufStatus[0].buffer = initGapBuffer(@[buffer.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer[0] == ru ""
      check currentBufStatus.buffer[1] == buffer.toRunes

  block:
    const Keyword = "or"
    newLineTestInNimCase5(Keyword)
  block:
    const Keyword = "and"
    newLineTestInNimCase5(Keyword)
  block:
    const Keyword = ":"
    newLineTestInNimCase5(Keyword)
  block:
    const Keyword = "objecT"
    newLineTestInNimCase5(Keyword)
  block:
    const Keyword = "="
    newLineTestInNimCase5(Keyword)

  proc newLineTestInNimCase6(pair: string) =
    ## Enable autoindent
    ## currentColumn is 1
    ## Line break test when the current line ends with pair of paren.

    # Generate test title
    let testTitle = "Case 6: When the current line ends with " & pair & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[pair.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert
      status.mainWindow.currentMainWindowNode.currentColumn = 1

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check $currentBufStatus.buffer[0] == $(pair[0])
      check $currentBufStatus.buffer[1] == "  " & $(pair[1])

  block:
    const Keyword = "{}"
    newLineTestInNimCase6(Keyword)
  block:
    const Keyword = "[]"
    newLineTestInNimCase6(Keyword)
  block:
    const Keyword = "()"
    newLineTestInNimCase6(Keyword)

  proc newLineTestInNimCase7(pair: string) =
    ## Enable autoindent
    ## currentColumn is 0
    ## Line break test when the current line ends with pair of paren.

     # Generate test title
    let testTitle = "Case 7: When the current line ends with " & pair & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[pair.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check $currentBufStatus.buffer[0] == ""
      check $currentBufStatus.buffer[1] == pair

  block:
    const Keyword = "{}"
    newLineTestInNimCase7(Keyword)
  block:
    const Keyword = "[]"
    newLineTestInNimCase7(Keyword)
  block:
    const Keyword = "()"
    newLineTestInNimCase7(Keyword)

  proc newLineTestInNimCase8(pair: string) =
    ## Enable autoindent
    ## currentColumn is 1
    ## Line break test when the current line ends with the close paren.

    # Generate test title
    let testTitle = "Case 8: When the current line ends with " & pair & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = pair[0] & "a" & pair[1]
      status.bufStatus[0].buffer = initGapBuffer(@[buffer.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim
      status.bufStatus[0].mode = Mode.insert
      status.mainWindow.currentMainWindowNode.currentColumn = 1

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check $currentBufStatus.buffer[0] == $pair[0]
      check $currentBufStatus.buffer[1] == "  a" & pair[1]

  block:
    const Keyword = "{}"
    newLineTestInNimCase8(Keyword)
  block:
    const Keyword = "[]"
    newLineTestInNimCase8(Keyword)
  block:
    const Keyword = "()"
    newLineTestInNimCase8(Keyword)

suite "Editor: keyEnter: Enable autoindent in C":
  proc newLineTestInCcase1(pair: string) =
    ## Enable autoindent
    ## currentColumn is 1
    ## Line break test when the current line ends with pair of paren.

    # Generate test title
    let testTitle = "Case 1: When the current line ends with " & pair & " in C"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[pair.toRunes])
      status.bufStatus[0].language = SourceLanguage.langC
      status.bufStatus[0].mode = Mode.insert
      status.mainWindow.currentMainWindowNode.currentColumn = 1

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 3
      check $currentBufStatus.buffer[0] == $(pair[0])
      check $currentBufStatus.buffer[1] == "  "
      check $currentBufStatus.buffer[2] == $(pair[1])

  block:
    const Keyword = "{}"
    newLineTestInCcase1(Keyword)
  block:
    const Keyword = "[]"
    newLineTestInCcase1(Keyword)
  block:
    const Keyword = "()"
    newLineTestInCcase1(Keyword)

  proc newLineTestInCcase2(pair: string) =
    ## Enable autoindent
    ## currentColumn is 0
    ## Line break test when the current line ends with pair of paren.

    # Generate test title
    let testTitle = "Case 2: When the current line ends with " & pair & " in C"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[pair.toRunes])
      status.bufStatus[0].language = SourceLanguage.langC
      status.bufStatus[0].mode = Mode.insert

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check $currentBufStatus.buffer[0] == ""
      check $currentBufStatus.buffer[1] == pair

  block:
    const Keyword = "{}"
    newLineTestInCcase2(Keyword)
  block:
    const Keyword = "[]"
    newLineTestInCcase2(Keyword)
  block:
    const Keyword = "()"
    newLineTestInCcase2(Keyword)

  proc newLineTestInCcase3(pair: string) =
    ## Enable autoindent
    ## currentColumn is 1
    ## Line break test when the current line ends with the close paren.

    # Generate test title
    let testTitle = "Case 3: When the current line ends with " & pair & " in C"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = pair[0] & "a" & pair[1]
      status.bufStatus[0].buffer = initGapBuffer(@[buffer.toRunes])
      status.bufStatus[0].language = SourceLanguage.langC
      status.bufStatus[0].mode = Mode.insert
      status.mainWindow.currentMainWindowNode.currentColumn = 1

      const IsAutoIndent = true
      status.bufStatus[0].keyEnter(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 3
      check $currentBufStatus.buffer[0] == $`pair`[0]
      check $currentBufStatus.buffer[1] == "  a"
      check $currentBufStatus.buffer[2] == $`pair`[1]

  block:
    const keyword = "{}"
    newLineTestInCcase3(keyword)
  block:
    const keyword = "[]"
    newLineTestInCcase3(keyword)
  block:
    const keyword = "()"
    newLineTestInCcase3(keyword)

suite "Editor: keyEnter: Enable autoindent in Yaml":
  test "Auto indent if finish th current line with ':' in Yaml":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test:"])
    currentBufStatus.language = SourceLanguage.langYaml
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const IsAutoIndent = true
    status.bufStatus[0].keyEnter(
      currentMainWindowNode,
      IsAutoIndent,
      status.settings.standard.tabStop)


    check status.bufStatus[0].buffer[0] == ru"test:"
    check status.bufStatus[0].buffer[1] == ru"  "

suite "Editor: keyEnter and autoindent in Python":
  test "Auto indent if finish th current line with ':' in Python":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"if true:"])
    currentBufStatus.language = SourceLanguage.langPython
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const IsAutoIndent = true
    status.bufStatus[0].keyEnter(
      currentMainWindowNode,
      IsAutoIndent,
      status.settings.standard.tabStop)

    check status.bufStatus[0].buffer[0] == ru"if true:"
    check status.bufStatus[0].buffer[1] == ru"  "

  test "Auto indent if finish th current line with 'and' in Python":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"if true and"])
    currentBufStatus.language = SourceLanguage.langPython
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const IsAutoIndent = true
    status.bufStatus[0].keyEnter(
      currentMainWindowNode,
      IsAutoIndent,
      status.settings.standard.tabStop)

    check status.bufStatus[0].buffer[0] == ru"if true and"
    check status.bufStatus[0].buffer[1] == ru"  "

  test "Auto indent if finish th current line with 'or' in Python":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"if true or"])
    currentBufStatus.language = SourceLanguage.langPython
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const IsAutoIndent = true
    status.bufStatus[0].keyEnter(
      currentMainWindowNode,
      IsAutoIndent,
      status.settings.standard.tabStop)

    check currentBufStatus.buffer[0] == ru"if true or"
    check currentBufStatus.buffer[1] == ru"  "

  test "Insert a new line in Nim (Fix #1450)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  const a = 0"])
    currentBufStatus.language = SourceLanguage.langNim
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = currentBufStatus.buffer[1].len

    const IsAutoIndent = true
    for i in 0 ..< 2:
      currentBufStatus.keyEnter(
        currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

suite "Delete character before cursor":
  test "Delete one character":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"tes"

  test "Delete one character 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test test2"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 7

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  testtest2"

  test "Delete current Line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test", ru""])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 0

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 2

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"   test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 3

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"    test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 1

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru" test"

  test "Delete tab 5":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      AutoCloseParen = true
      TabStop = 2
    status.bufStatus[0].keyBackspace(
      currentMainWindowNode,
      AutoCloseParen,
      TabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  tst"

suite "Editor: Delete inside paren":
  test "delete inside double quotes":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru """abc "def" "ghi""""])
    currentMainWindowNode.currentColumn = 6

    var registers: registers.Registers

    let settings = initEditorSettings()
    currentBufStatus.deleteInsideOfParen(
      currentMainWindowNode,
      registers,
      ru'"',
      settings)

    check currentBufStatus.buffer[0] == ru """abc "" "ghi""""

suite "Editor: insertLinesFromRegister":
  test "Insert the empty line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const
      Register = Register(buffer: @[ru""], isLine: true)
      Position = 1
    currentBufStatus.insertLinesFromRegister(Position, Register)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer.toSeqRunes == @[ru"abc", ru""]

  test "Insert lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const
      Register = Register(buffer: @[ru"def", ru"ghi"], isLine: true)
      Position = 0
    currentBufStatus.insertLinesFromRegister(Position, Register)

    check currentBufStatus.buffer.len == 3
    check currentBufStatus.buffer.toSeqRunes == @[ru"def", ru"ghi", ru"abc"]

suite "Editor: insertRunesFromRegister":
  test "Nothing to do":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const
      Register = Register(buffer: @[ru""])
      Position = BufferPosition(line: 0, column: 0)
    currentBufStatus.insertRunesFromRegister(Position, Register)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc"]
    check currentBufStatus.countChange == 0
    check not currentBufStatus.isUpdate

  test "Insert words to the empty line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.resize(100, 100)
    status.update

    const
      Register = Register(buffer: @[ru"abc"])
      Position = BufferPosition(line: 0, column: 0)
    currentBufStatus.insertRunesFromRegister(Position, Register)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc"]
    check currentBufStatus.countChange == 1
    check currentBufStatus.isUpdate

  test "Insert the word to end of the line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const
      Register = Register(buffer: @[ru"def"])
      Position = BufferPosition(line: 0, column: 3)
    currentBufStatus.insertRunesFromRegister(Position, Register)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abcdef"]
    check currentBufStatus.countChange == 1
    check currentBufStatus.isUpdate

  test "Insert the word to the mid of the line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const
      Register = Register(buffer: @[ru"def"])
      Position = BufferPosition(line: 0, column: 1)
    currentBufStatus.insertRunesFromRegister(Position, Register)

    check currentBufStatus.buffer.toSeqRunes == @[ru"adefbc"]
    check currentBufStatus.countChange == 1
    check currentBufStatus.isUpdate

suite "Editor: pasteAfterCursor":
  test "Nothing to do":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    # Add a empty buffer to No name register.
    status.registers.addRegister(ru"", status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc"]
    check currentBufStatus.countChange == 0

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste words 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"abc", status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Paste words 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc "])
    currentMainWindowNode.currentColumn = 3

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"def ghi", status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc def ghi"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 10

  test "Paste words 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc ghi"])
    currentMainWindowNode.currentColumn = 3

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"def ", status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc def ghi"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 7

  test "Paste words 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 2

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"d", status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abcd"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 3

  test "Paste words 5":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"acd"])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"b", status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abcd"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "Paste words 6":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"a", status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"a"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"line1"])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(@[ru"line2", ru"line3"], status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[
      ru"line1",
      ru"line2",
      ru"line3"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Paste lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"line1"])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(@[ru"  line2"], status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[
      ru"line1",
      ru"  line2"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 2

  test "Paste lines 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"line1", ru"line3"])
    currentMainWindowNode.currentLine = 0

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(@[ru"line2"], status.settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[
      ru"line1",
      ru"line2",
      ru"line3"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

suite "Editor: pasteBeforeCursor":
  test "Nothing to do":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    # Add a empty buffer to No name register.
    status.registers.addRegister(ru"", status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc"]
    check currentBufStatus.countChange == 0

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste words 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"abc", status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Paste words 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru" ghi"])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"abc def", status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc def ghi"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 6

  test "Paste words 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc ghi"])
    currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"def ", status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abc def ghi"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 7

  test "Paste words 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"bcd"])
    currentMainWindowNode.currentColumn = 0

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"a", status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abcd"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste words 5":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"acd"])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"b", status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"abcd"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "Paste words 6":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(ru"a", status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[ru"a"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"line3"])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(@[ru"line1", ru"line2"], status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[
      ru"line1",
      ru"line2",
      ru"line3"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"line2"])

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(@[ru"  line1"], status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[
      ru"  line1",
      ru"line2"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Paste lines 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"line1", ru"line3"])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    # Add buffer to No name register.
    status.registers.addRegister(@[ru"line2"], status.settings)

    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

    check currentBufStatus.buffer.toSeqRunes == @[
      ru"line1",
      ru"line2",
      ru"line3"]
    check currentBufStatus.countChange == 1

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

if isXselAvailable():
  suite "Editor: Yank characters":
    test "Yank a string with name in the empty line":
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru ""])

      const
        Length = 1
        Name = "a"
        IsDelete = false
      currentBufStatus.yankCharacters(
        status.registers,
        currentMainWindowNode,
        status.commandline,
        status.settings,
        Length,
        Name,
        IsDelete)

      check status.registers.noNameRegisters.buffer.len == 0

if isXselAvailable():
  suite "Editor: Yank words":
    test "Yank a word":
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru "abc def"])

      const Loop = 1
      currentBufStatus.yankWord(
        status.registers,
        currentMainWindowNode,
        Loop,
        status.settings)

      check status.registers.noNameRegisters ==  registers.Register(
        buffer: @[ru "abc "],
        isLine: false,
        name: "")

      # Check clipboad
      let p = initPlatform()
      if p == Platforms.linux or p == Platforms.wsl:
        let
          cmd =
            if p == Platforms.linux:
              execCmdEx("xsel -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0

        const Str = "abc "
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == Str
        else:
          # On the WSL
          check output[0 .. output.high - 2] == Str

suite "Editor: Modify the number string under the cursor":
  test "Increment the number string":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "1"])

    const Amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      Amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "2"

  test "Increment the number string 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru " 1 "])
    currentMainWindowNode.currentColumn = 1

    const Amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      Amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru " 2 "

  test "Increment the number string 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "9"])

    const Amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      Amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "10"

  test "Decrement the number string":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "1"])

    const Amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      Amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "0"

  test "Decrement the number string 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "0"])

    const Amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      Amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "-1"

  test "Decrement the number string 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "10"])

    const Amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      Amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "9"

  test "Do nothing":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const Amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      Amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

suite "Editor: Delete from the previous blank line to the current line":
  test "Delete lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "", ru "def", ru "ghi"])
    currentMainWindowNode.currentLine = 3

    const RegisterName = ""
    currentBufStatus.deleteTillPreviousBlankLine(
      status.registers,
      currentMainWindowNode,
      RegisterName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegisters == registers.Register(
      buffer: @[ru "", ru "def"],
      isLine: true)

  test "Delete lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[
      "abc",
      "",
      "def",
      "ghi"].toSeqRunes)
    currentMainWindowNode.currentLine = 3
    currentMainWindowNode.currentColumn = 1

    const RegisterName = ""
    currentBufStatus.deleteTillPreviousBlankLine(
      status.registers,
      currentMainWindowNode,
      RegisterName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "hi"

    check status.registers.noNameRegisters == registers.Register(
      buffer: @[ru "", ru "def", ru "g"],
      isLine: true)

suite "Editor: Delete from the current line to the next blank line":
  test "Delete lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[
      "abc",
      "def",
      "",
      "ghi"].toSeqRunes)

    const RegisterName = ""
    currentBufStatus.deleteTillNextBlankLine(
      status.registers,
      currentMainWindowNode,
      RegisterName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegisters == registers.Register(
      buffer: @[ru "abc", ru "def"],
      isLine: true)

  test "Delete lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[
      "abc",
      "def",
      "","ghi"].toSeqRunes)
    currentMainWindowNode.currentColumn = 1

    const RegisterName = ""
    currentBufStatus.deleteTillNextBlankLine(
      status.registers,
      currentMainWindowNode,
      RegisterName,
      status.settings)

    check currentBufStatus.buffer.len == 3
    check currentBufStatus.buffer[0] == ru "a"
    check currentBufStatus.buffer[1] == ru ""
    check currentBufStatus.buffer[2] == ru "ghi"

    check status.registers.noNameRegisters == registers.Register(
      buffer: @[ru "bc", ru "def"],
      isLine: true)

suite "Editor: Replace characters":
  test "Repace a character":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      AutoIndent = false
      AutoDeleteParen = false
      TabStop = 2
      Loop = 1
      Character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      AutoIndent,
      AutoDeleteParen,
      TabStop,
      Loop,
      Character)

    check currentBufStatus.buffer[0] == ru "zbcdef"
    check currentMainWindowNode.currentColumn == 0

  test "Repace characters":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      AutoIndent = false
      AutoDeleteParen = false
      TabStop = 2
      Loop = 3
      Character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      AutoIndent,
      AutoDeleteParen,
      TabStop,
      Loop,
      Character)

    check currentBufStatus.buffer[0] == ru "zzzdef"
    check currentMainWindowNode.currentColumn == 2

  test "Repace characters 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      AutoIndent = false
      AutoDeleteParen = false
      TabStop = 2
      Loop = 10
      Character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      AutoIndent,
      AutoDeleteParen,
      TabStop,
      Loop,
      Character)

    check currentBufStatus.buffer[0] == ru "zzzzzz"
    check currentMainWindowNode.currentColumn == 5

  test "Repace characters 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      AutoIndent = false
      AutoDeleteParen = false
      TabStop = 2
      Loop = 1
    let character = toRune(KEY_ENTER)

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      AutoIndent,
      AutoDeleteParen,
      TabStop,
      Loop,
      character)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "bcdef"

  test "Repace characters 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      AutoIndent = false
      AutoDeleteParen = false
      TabStop = 2
      Loop = 3
    let character = toRune(KEY_ENTER)

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      AutoIndent,
      AutoDeleteParen,
      TabStop,
      Loop,
      character)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "def"

  test "Fix #1384":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])
    currentMainWindowNode.currentColumn = 2

    const
      AutoIndent = false
      AutoDeleteParen = false
      TabStop = 2
      Loop = 1
    let character = toRune('z')

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      AutoIndent,
      AutoDeleteParen,
      TabStop,
      Loop,
      character)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abzdef"

suite "Editor: Toggle characters":
  test "Toggle a character":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const Loop = 1
    currentBufStatus.toggleCharacters(currentMainWindowNode, Loop)

    check currentBufStatus.buffer[0] == ru "Abcdef"
    check currentMainWindowNode.currentColumn == 1

  test "Toggle characters":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const Loop = 3
    currentBufStatus.toggleCharacters(currentMainWindowNode, Loop)

    check currentBufStatus.buffer[0] == ru "ABCdef"
    check currentMainWindowNode.currentColumn == 3

  test "Do nothing":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru " abcde"])

    const Loop = 1
    currentBufStatus.toggleCharacters(currentMainWindowNode, Loop)

    check currentBufStatus.buffer[0] == ru " abcde"
    check currentMainWindowNode.currentColumn == 0

suite "Editor: Open the blank line below":
  proc openLineBelowTestCase1(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## open the blank line below in some languages

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 1: Enable autoindent: Open the blank line below in " & langStr
        else: "Case 1: Disable autoindent: Open the blank line below in " & langStr

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru "  test"])
      status.bufStatus[0].language = lang

      status.bufStatus[0].openBlankLineBelow(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let
        currentBufStatus = status.bufStatus[0]
        currentMainWindowNode = status.mainWindow.currentMainWindowNode

      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru "  test"

      if isAutoIndent:
        check currentBufStatus.buffer[1] == ru "  "

        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 2
      else:
        check currentBufStatus.buffer[1] == ru ""

        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      openLineBelowTestCase1(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      openLineBelowTestCase1(l, IsAutoIndent)

  proc openLineBelowTestCase2(keyword: string) =
    ## Enable autoindent
    ## open the blank line below in Nim
    ## keywords: "var", "let", "const"

    # Generate test title
    let testTitle = "Case 2: if the current line is " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[keyword.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim

      const IsAutoIndent = true
      status.bufStatus[0].openBlankLineBelow(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 2
      check $currentBufStatus.buffer[0] == keyword
      check currentBufStatus.buffer[1] == ru "  "

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 2

  block:
    const Keyword = "var"
    openLineBelowTestCase2(Keyword)
  block:
    const Keyword = "let"
    openLineBelowTestCase2(Keyword)
  block:
    const Keyword = "const"
    openLineBelowTestCase2(Keyword)

  proc openLineBelowTestCase3(keyword: string) =
    ## Enable autoindent
    ## open the blank line below in Nim
    ## When the current line ends with "or", "and", ':', "object", '='.

    # Generate test title
    let testTitle = "Case 3: if the current line end with " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = "test " & keyword
      status.bufStatus[0].buffer = initGapBuffer(@[buffer.toRunes])
      status.bufStatus[0].language = SourceLanguage.langNim

      const IsAutoIndent = true
      status.bufStatus[0].openBlankLineBelow(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check $currentBufStatus.buffer[0] == buffer
      check currentBufStatus.buffer[1] == ru"  "

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == currentBufStatus.buffer[1].len

  block:
    const Keyword = "or"
    openLineBelowTestCase3(Keyword)
  block:
    const Keyword = "and"
    openLineBelowTestCase3(Keyword)
  block:
    const Keyword = ":"
    openLineBelowTestCase3(Keyword)
  block:
    const Keyword = "object"
    openLineBelowTestCase3(Keyword)
  block:
    const Keyword = "="
    openLineBelowTestCase3(Keyword)

  proc openLineBelowTestCase4(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## the current line is empty

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 4: Enable autoindent: Open the blank line below in " & langStr
        else: "Case 4: Disable autoindent: Open the blank line below in " & langStr

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru ""])
      status.bufStatus[0].language = lang

      status.bufStatus[0].openBlankLineBelow(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let
        currentBufStatus = status.bufStatus[0]
        currentMainWindowNode = status.mainWindow.currentMainWindowNode

      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru ""
      check currentBufStatus.buffer[1] == ru ""

      if isAutoIndent:
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0
      else:
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      openLineBelowTestCase4(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      openLineBelowTestCase4(l, IsAutoIndent)

  proc openLineBelowTestCase5(keyword: string) =
    ## Enable autoindent
    ## open the blank line below in Python
    ## When the current line ends with "or", "and", ':'.

    # Generate test title
    let testTitle = "Case 5: if the current line end with " & keyword & " in Python"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = "test " & keyword
      status.bufStatus[0].buffer = initGapBuffer(@[buffer.toRunes])
      status.bufStatus[0].language = SourceLanguage.langPython

      const IsAutoIndent = true
      status.bufStatus[0].openBlankLineBelow(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check $currentBufStatus.buffer[0] == buffer
      check currentBufStatus.buffer[1] == ru"  "

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == currentBufStatus.buffer[1].len

  block:
    const Keyword = "or"
    openLineBelowTestCase5(Keyword)
  block:
    const Keyword = "and"
    openLineBelowTestCase5(Keyword)
  block:
    const Keyword = ":"
    openLineBelowTestCase5(Keyword)

suite "Editor: Open the blank line abave":
  proc openLineAboveTestCase1(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## open the blank line abave in some languages

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 1: Enable autoindent: Open the blank line abave in " & langStr
        else: "Case 1: Disable autoindent: Open the blank line abave in " & langStr

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru "test"])
      status.bufStatus[0].language = lang

      status.bufStatus[0].openBlankLineAbove(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let
        currentBufStatus = status.bufStatus[0]
        currentMainWindowNode = status.mainWindow.currentMainWindowNode

      check currentBufStatus.buffer.len == 2
      check currentBufStatus.buffer[0] == ru ""
      check currentBufStatus.buffer[1] == ru "test"

      check currentMainWindowNode.currentLine == 0
      check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      openLineAboveTestCase1(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      openLineAboveTestCase1(l, IsAutoIndent)

  proc openLineAboveTestCase2(lang: SourceLanguage, isAutoIndent: bool) =
    ## Enable/Disable autoindent
    ## open the blank line abave in some languages

    # Generate test title
    let
      langStr = sourceLangToStr(lang)
      testTitle =
        if isAutoIndent: "Case 2: Enable autoindent: Open the blank line abave in " & langStr
        else: "Case 2: Disable autoindent: Open the blank line abave in " & langStr

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[ru "  test", ru ""])
      status.bufStatus[0].language = lang

      status.mainWindow.currentMainWindowNode.currentLine = 1

      status.bufStatus[0].openBlankLineAbove(
        status.mainWindow.currentMainWindowNode,
        isAutoIndent,
        status.settings.standard.tabStop)

      let
        currentBufStatus = status.bufStatus[0]
        currentMainWindowNode = status.mainWindow.currentMainWindowNode

      check currentBufStatus.buffer.len == 3
      check currentBufStatus.buffer[0] == ru "  test"
      check currentBufStatus.buffer[2] == ru ""

      check currentMainWindowNode.currentLine == 1

      if isAutoIndent:
        check currentBufStatus.buffer[1] == ru "  "
        check currentMainWindowNode.currentColumn == 2
      else:
        check currentBufStatus.buffer[1] == ru ""
        check currentMainWindowNode.currentColumn == 0

  for l in SourceLanguage:
    block:
      const IsAutoIndent = false
      openLineAboveTestCase2(l, IsAutoIndent)
    block:
      const IsAutoIndent = true
      openLineAboveTestCase2(l, IsAutoIndent)

  proc openLineAboveTestCase3(keyword: string) =
    ## Enable autoindent
    ## open the blank line above in Nim
    ## keywords: "var", "let", "const"

    # Generate test title
    let testTitle = "Case 3: if the current line is " & keyword & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      status.bufStatus[0].buffer = initGapBuffer(@[keyword, ""].toSeqRunes)
      status.bufStatus[0].language = SourceLanguage.langNim

      status.mainWindow.currentMainWindowNode.currentLine = 1

      const IsAutoIndent = true
      status.bufStatus[0].openBlankLineAbove(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 3
      check $currentBufStatus.buffer[0] == keyword
      check currentBufStatus.buffer[1] == ru "  "

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == 2

  block:
    const Keyword = "var"
    openLineAboveTestCase3(Keyword)
  block:
    const Keyword = "let"
    openLineAboveTestCase3(Keyword)
  block:
    const Keyword = "const"
    openLineAboveTestCase3(Keyword)

  proc openLineAboveTestCase4(keyword: string) =
    ## Enable autoindent
    ## open the blank line above in Nim
    ## When the current line ends with "or", "and", ':', "object", "=".

    # Generate test title
    let testTitle = "Case 4: if the current line end with " & `keyword` & " in Nim"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = @["test " & keyword, ""].toSeqRunes
      status.bufStatus[0].buffer = initGapBuffer(buffer)
      status.bufStatus[0].language = SourceLanguage.langNim

      status.mainWindow.currentMainWindowNode.currentLine = 1

      const IsAutoIndent = true
      status.bufStatus[0].openBlankLineAbove(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]

      check currentBufStatus.buffer.len == 3

      check currentBufStatus.buffer[0] == buffer[0]
      check currentBufStatus.buffer[1] == ru "  "
      check currentBufStatus.buffer[2] == ru ""

      let currentMainWindowNode = status.mainWindow.currentMainWindowNode
      check currentMainWindowNode.currentLine == 1
      check currentMainWindowNode.currentColumn == currentBufStatus.buffer[1].len

  block:
    const Keyword = "or"
    openLineAboveTestCase4(Keyword)
  block:
    const Keyword = "and"
    openLineAboveTestCase4(Keyword)
  block:
    const Keyword = ":"
    openLineAboveTestCase4(Keyword)
  block:
    const Keyword = "object"
    openLineAboveTestCase4(Keyword)
  block:
    const Keyword = "="
    openLineAboveTestCase4(Keyword)

  proc openLineAboveTestCase5(keyword: string) =
    ## Enable autoindent
    ## open the blank line above in Python
    ## When the current line ends with "or", "and", ':'.

    # Generate test title
    let testTitle = "Case 5: if the current line end with " & keyword & " in Python"

    test testTitle:
      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get

      let buffer = @["test " & keyword, ""].toSeqRunes
      status.bufStatus[0].buffer = initGapBuffer(buffer)
      status.bufStatus[0].language = SourceLanguage.langPython

      status.mainWindow.currentMainWindowNode.currentLine = 1

      const IsAutoIndent = true
      status.bufStatus[0].openBlankLineAbove(
        status.mainWindow.currentMainWindowNode,
        IsAutoIndent,
        status.settings.standard.tabStop)

      let currentBufStatus = status.bufStatus[0]
      check currentBufStatus.buffer.len == 3

      check currentBufStatus.buffer[0] == buffer[0]
      check currentBufStatus.buffer[1] == ru"  "
      check currentBufStatus.buffer[2] == ru""

      check status.mainWindow.currentMainWindowNode.currentLine == 1
      check status.mainWindow.currentMainWindowNode.currentColumn ==
        currentBufStatus.buffer[1].len

  block:
    const Keyword = "or"
    openLineAboveTestCase5(Keyword)
  block:
    const Keyword = "and"
    openLineAboveTestCase5(Keyword)
  block:
    const Keyword = ":"
    openLineAboveTestCase5(Keyword)

suite "Editor: Indent":
  block:
    proc indentTestCase1(lang: SourceLanguage) =
      ## Indenet with a empty buffer in some languages
      ## Run at first of line.

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 1: Indenet in " & langStr

      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru""])
        status.bufStatus[0].language = lang

        status.bufStatus[0].indent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 1
        check currentBufStatus.buffer[0] == ru"  "

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      indentTestCase1(l)

  block:
    proc indentTestCase2(lang: SourceLanguage) =
      ## Indenet with a only spaces buffer in some languages
      ## Run at end of line.

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 2: Indenet in " & langStr

      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  "])
        status.bufStatus[0].language = lang

        status.bufStatus[0].indent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        check status.bufStatus[0].buffer.len == 1
        check status.bufStatus[0].buffer[0] == ru"    "

        check status.mainWindow.currentMainWindowNode.currentLine == 0
        check status.mainWindow.currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      indentTestCase2(l)

  block:
    proc indentTestCase3(lang: SourceLanguage) =
      ## Indenet in some languages

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 3: Indenet in " & langStr

      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
        status.bufStatus[0].language = lang

        status.bufStatus[0].indent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 1
        check currentBufStatus.buffer[0] == ru"    test"

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      indentTestCase3(l)

  block:
    proc indentTestCase4(lang: SourceLanguage) =
      ## Indenet in some languages

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 4: Indenet in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  "])
        status.bufStatus[0].language = lang

        status.mainWindow.currentMainWindowNode.currentColumn = 1

        status.bufStatus[0].indent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 1
        check currentBufStatus.buffer[0] == ru"    "

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 1

    for l in SourceLanguage:
      indentTestCase4(l)

  block:
    proc indentTestCase5(lang: SourceLanguage) =
      ## Indenet in some languages

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 5: Indenet in " & langStr

      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  ", ru"", ru"  "])
        status.bufStatus[0].language = lang

        status.mainWindow.currentMainWindowNode.currentLine = 1

        status.bufStatus[0].indent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 3
        check currentBufStatus.buffer[0] == ru"  "
        check currentBufStatus.buffer[1] == ru"  "
        check currentBufStatus.buffer[2] == ru"  "

        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      indentTestCase5(l)

suite "Editor: Unindent":
  block:
    proc unindentTestCase1(lang: SourceLanguage) =
      ## Unindenet with a only spaces buffer in some languages
      ## Run at first of line.

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 1: Unindenet in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  "])
        status.bufStatus[0].language = lang

        status.bufStatus[0].unindent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 1
        check currentBufStatus.buffer[0] == ru""

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      unindentTestCase1(l)

  block:
    proc unindentTestCase2(lang: SourceLanguage) =
      ## Unindenet with a only spaces buffer in some languages
      ## Run at end of line.

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 2: Unindenet in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  "])
        status.bufStatus[0].language = lang

        status.mainWindow.currentMainWindowNode.currentColumn = 1

        status.bufStatus[0].unindent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 1
        check currentBufStatus.buffer[0] == ru""

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      unindentTestCase2(l)

  block:
    proc unindentTestCase3(lang: SourceLanguage) =
      ## Unindenet in some languages

      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = "Case 3: Unindenet in " & langStr

      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
        status.bufStatus[0].language = `lang`

        status.mainWindow.currentMainWindowNode.currentColumn = 5

        status.bufStatus[0].unindent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 1
        check currentBufStatus.buffer[0] == ru"test"

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 3

    for l in SourceLanguage:
      unindentTestCase3(l)

  block:
    proc unindentTestCase4(lang: SourceLanguage) =
      ## Nothing to do in the empty line.

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 4: Unindenet in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru""])
        status.bufStatus[0].language = lang

        status.bufStatus[0].unindent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 1
        check currentBufStatus.buffer[0].len == 0

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      unindentTestCase4(l)

  block:
    proc unindentTestCase5(lang: SourceLanguage) =
      ## Nothing to do in the empty line.

      # Generate test title
      let
        langStr = sourceLangToStr(lang)
        testTitle = "Case 5: Unindenet in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  ", ru"", ru"  "])
        status.bufStatus[0].language = lang

        status.mainWindow.currentMainWindowNode.currentLine = 1

        status.bufStatus[0].unindent(
          status.mainWindow.currentMainWindowNode,
          status.settings.standard.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 3
        check currentBufStatus.buffer[0] == ru"  "
        check currentBufStatus.buffer[1] == ru""
        check currentBufStatus.buffer[2] == ru"  "

        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

    for l in SourceLanguage:
      unindentTestCase5(l)

suite "Editor: replaceAll":
  test "Basic":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abc abc xyz", "abc"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 1)
    const
      Sub = ru"abc"
      By = ru"xyz"
    b.replaceAll(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"xyz xyz xyz", ru"xyz"]

  test "Basic 2":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abcabc", ""].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 1)
    const
      Sub = ru"abc"
      By = ru"xyz"
    b.replaceAll(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"xyzxyz", ru""]

  test "Basic 3":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abcAbc", "ABC"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 1)
    const
      Sub = ru"Abc"
      By = ru"xyz"
    b.replaceAll(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"abcxyz", ru"ABC"]

  test "With NewLine":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abc", "abc", "xyz", "abc", "abc"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 4)
    const
      Sub = "abc\nabc".toRunes
      By = ru"xyz"
    b.replaceAll(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"xyz", ru"xyz", ru"xyz"]

  test "With NewLine 2":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abc", "abc", "xyz", "abc", "abc"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 4)
    const
      Sub = "abc\nabc".toRunes
      By = "xyz\nxyz".toRunes
    b.replaceAll(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @["xyz", "xyz", "xyz", "xyz", "xyz"].toSeqRunes

suite "Editor: replaceOnlyFirstWordInLines":
  test "Basic":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abc abc xyz", "abc"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 1)
    const
      Sub = ru"abc"
      By = ru"xyz"
    b.replaceOnlyFirstWordInLines(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"xyz abc xyz", ru"xyz"]

  test "Basic 2":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abcabc", ""].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 1)
    const
      Sub = ru"abc"
      By = ru"xyz"
    b.replaceOnlyFirstWordInLines(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"xyzabc", ru""]

  test "Basic 3":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abcAbc", "ABC"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 1)
    const
      Sub = ru"Abc"
      By = ru"xyz"
    b.replaceOnlyFirstWordInLines(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"abcxyz", ru"ABC"]

  test "With NewLine":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abc", "abc", "xyz", "abc", "abc"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 4)
    const
      Sub = "abc\nabc".toRunes
      By = ru"xyz"
    b.replaceOnlyFirstWordInLines(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @[ru"xyz", ru"xyz", ru"xyz"]

  test "With NewLine 2":
    var b = initBufferStatus(Mode.normal).get
    b.buffer = @["abc", "abc", "xyz", "abc", "abc"].toSeqRunes.toGapBuffer

    let lineRange = Range(first: 0, last: 4)
    const
      Sub = "abc\nabc".toRunes
      By = "xyz\nxyz".toRunes
    b.replaceOnlyFirstWordInLines(lineRange, Sub, By)

    check b.buffer.toSeqRunes == @["xyz", "xyz", "xyz", "xyz", "xyz"].toSeqRunes
