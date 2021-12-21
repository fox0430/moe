import std/[unittest, macros]
import moepkg/register
include moepkg/[editor, editorstatus, ui, platform]

proc sourceLangToStr(lang: SourceLanguage): string =
  case lang:
    of SourceLanguage.langNim:
      "Nim"
    of SourceLanguage.langC:
      "C"
    of SourceLanguage.langCpp:
      "C++"
    of SourceLanguage.langCsharp:
      "C#"
    of SourceLanguage.langJava:
      "Java"
    of SourceLanguage.langYaml:
      "Yaml"
    of SourceLanguage.langPython:
      "Python"
    of SourceLanguage.langJavaScript:
      "JavaScript"
    of SourceLanguage.langShell:
      "Shell"
    of SourceLanguage.langMarkDown:
      "Markdown"
    else:
      "Plain text"

suite "Editor: Auto indent":
  test "Auto indent in current Line":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  a", ru"b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"  a")
    check(status.bufStatus[0].buffer[1] == ru"  b")

  test "Auto indent in current Line 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 3":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"  b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(
      currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 4":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru""])

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"")

suite "Editor: Delete trailing spaces":
  test "Delete trailing spaces 1":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d  ", ru"efg"])

    status.bufStatus[0].deleteTrailingSpaces

    check status.bufStatus[0].buffer.len == 3
    check status.bufStatus[0].buffer[0] == ru"abc"
    check status.bufStatus[0].buffer[1] == ru"d"
    check status.bufStatus[0].buffer[2] == ru"efg"

suite "Editor: Delete word":
  test "Fix #842":
    var status = initEditorStatus()
    status.addNewBuffer

    currentBufStatus.buffer = initGapBuffer(@[ru"block:", ru"  "])
    currentMainWindowNode.currentLine = 1

    let settings = initEditorSettings()
    const
      loop = 2
      registerName = ""
    currentBufStatus.deleteWord(
      currentMainWindowNode,
      loop,
      status.registers,
      registerName,
      settings)

suite "Editor: keyEnter":
  test "Delete all characters in the previous line if only whitespaces":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  "])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 2

    const isAutoIndent = true
    for i in 0 ..< 2:
      status.bufStatus[0].keyEnter(currentMainWindowNode,
                                   isAutoIndent,
                                   status.settings.tabStop)

    check status.bufStatus[0].buffer[0] == ru"block:"
    check status.bufStatus[0].buffer[1] == ru""
    check status.bufStatus[0].buffer[2] == ru""
    check status.bufStatus[0].buffer[3] == ru"  "

  test "Fix #1370":
    var status = initEditorStatus()
    status.addNewBuffer

    currentBufStatus.buffer = initGapBuffer(@[ru""])
    currentBufStatus.mode = Mode.insert

    const isAutoIndent = false
    currentBufStatus.keyEnter(
      currentMainWindowNode,
      isAutoIndent,
      status.settings.tabStop)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru ""

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  # Generate test code
  # Enable/Disable autoindent
  # Newline in some languages
  macro newLineTestCase1(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 1: Enable autoindent: Newline in " & langStr
                    else: "Case 1: Disable autoindent: Newline in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
        status.bufStatus[0].language = `lang`
        status.bufStatus[0].mode = Mode.insert

        block:
          let buffer = status.bufStatus[0].buffer
          status.mainWindow.currentMainWindowNode.currentColumn = buffer[0].len

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru"test"
        check currentBufStatus.buffer[1] == ru""

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      newLineTestCase1(l, isAutoIndent)
    block:
      const isAutoIndent = true
      newLineTestCase1(l, isAutoIndent)

  # Generate test code
  # Enable/Disable autoindent
  # Newline in some language.
  macro newLineTestCase2(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 2: Enable autoindent: Newline in " & langStr
                    else: "Case 2: Disable autoindent: Newline in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
        status.bufStatus[0].language = `lang`
        status.bufStatus[0].mode = Mode.insert

        status.mainWindow.currentMainWindowNode.currentColumn = 2

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru"te"
        check currentBufStatus.buffer[1] == ru"st"

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      newLineTestCase2(l, isAutoIndent)
    block:
      const isAutoIndent = true
      newLineTestCase2(l, isAutoIndent)

  # Generate test code
  # Enable/Disable autoindent
  # Newline in some languages
  macro newLineTestCase3(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 3: Enable autoindent: Newline in " & langStr
                    else: "Case 3: Disable autoindent: Newline in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
        status.bufStatus[0].language = `lang`
        status.bufStatus[0].mode = Mode.insert

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru""
        check currentBufStatus.buffer[1] == ru"test"

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      newLineTestCase3(l, isAutoIndent)
    block:
      const isAutoIndent = true
      newLineTestCase3(l, isAutoIndent)

  # Generate test code
  # Enable/Disable autoindent
  # Newline in some languages
  macro newLineTestCase4(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 4: Enable autoindent: Newline in " & langStr
                    else: "Case 4: Disable autoindent: Newline in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru""])
        status.bufStatus[0].language = `lang`
        status.bufStatus[0].mode = Mode.insert

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru""
        check currentBufStatus.buffer[1] == ru""

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      newLineTestCase4(l, isAutoIndent)
    block:
      const isAutoIndent = true
      newLineTestCase4(l, isAutoIndent)

  # Generate test code
  # Disable autoindent
  # Line break test that case there is an indent on the current line.
  macro newLineTestDisableAutoindent1(lang: SourceLanguage): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = "Case 5: Disable autoindent: Newline in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
        status.bufStatus[0].language = `lang`
        status.bufStatus[0].mode = Mode.insert
        block:
          let buffer = status.bufStatus[0].buffer
          status.mainWindow.currentMainWindowNode.currentColumn = buffer[0].len

        const isAutoIndent = false
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru"  test"
        check currentBufStatus.buffer[1] == ru""

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  # Generate test code by macro
  for l in SourceLanguage:
    newLineTestDisableAutoindent1(l)

suite "Editor: keyEnter: Enable autoindent in Nim":

  # Generate test code
  # Disable autoindent
  # Line break test that case there is some keyword on the current line.
  # keywords: "var", "let", "const"
  macro newLineTestInNimCase1(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 1: if the current line is " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[keyword.ru])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert
        block:
          let lineLen = status.bufStatus[0].buffer[0].len
          status.mainWindow.currentMainWindowNode.currentColumn = lineLen

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru `keyword`
        check currentBufStatus.buffer[1] == ru "  "

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == status.settings.tabStop

  # Generate test code by macro
  block:
    const keyword = "var"
    newLineTestInNimCase1(keyword)
  block:
    const keyword = "let"
    newLineTestInNimCase1(keyword)
  block:
    const keyword = "const"
    newLineTestInNimCase1(keyword)

  # Generate test code
  # Disable autoindent
  # Line break test that case there are some keyword and an indent on the current line.
  # keywords: "var", "let", "const"
  macro newLineTestInNimCase2(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 2: if the current line is " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const
          indent = "  "
          buffer = indent & `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert
        block:
          let lineLen = status.bufStatus[0].buffer[0].len
          status.mainWindow.currentMainWindowNode.currentColumn = lineLen

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check $currentBufStatus.buffer[0] == indent & `keyword`
        check currentBufStatus.buffer[1] == ru "    "

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == "    ".len

  # Generate test code by macro
  block:
    const keyword = "var"
    newLineTestInNimCase2(keyword)
  block:
    const keyword = "let"
    newLineTestInNimCase2(keyword)
  block:
    const keyword = "const"
    newLineTestInNimCase2(keyword)

  # Generate test code
  # Disable autoindent
  # currentColumn is 0
  # Line break test that case there are some keyword and an indent on the current line.
  # keywords: "var", "let", "const"
  macro newLineTestInNimCase3(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 3: if the current line is " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru ""
        check $currentBufStatus.buffer[1] == `keyword`

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 0

  # Generate test code by macro
  block:
    const keyword = "var"
    newLineTestInNimCase3(keyword)
  block:
    const keyword = "let"
    newLineTestInNimCase3(keyword)
  block:
    const keyword = "const"
    newLineTestInNimCase3(keyword)

  # Generate test code
  # Enable autoindent
  # Line break test when the current line ends with "or", "and", ':', "object".
  macro newLineTestInNimCase4(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 4: When the current line ends with " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = "test " & `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert
        block:
          let lineLen = status.bufStatus[0].buffer[0].len
          status.mainWindow.currentMainWindowNode.currentColumn = lineLen

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check $currentBufStatus.buffer[0] == buffer
        check currentBufStatus.buffer[1] == ru"  "

  # Generate test code
  block:
    const keyword = "or"
    newLineTestInNimCase4(keyword)
  block:
    const keyword = "and"
    newLineTestInNimCase4(keyword)
  block:
    const keyword = ":"
    newLineTestInNimCase4(keyword)
  block:
    const keyword = "object"
    newLineTestInNimCase4(keyword)
  block:
    const keyword = "="
    newLineTestInNimCase4(keyword)

  # Generate test code
  # Enable autoindent
  # currentColumn is 0
  # Line break test when the current line ends with "or", "and", ':', "object".
  macro newLineTestInNimCase5(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 5: When the current line ends with " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = "test " & `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer[0] == ru ""
        check currentBufStatus.buffer[1] == ru buffer

  # Generate test code
  block:
    const keyword = "or"
    newLineTestInNimCase5(keyword)
  block:
    const keyword = "and"
    newLineTestInNimCase5(keyword)
  block:
    const keyword = ":"
    newLineTestInNimCase5(keyword)
  block:
    const keyword = "object"
    newLineTestInNimCase5(keyword)
  block:
    const keyword = "="
    newLineTestInNimCase5(keyword)

  # Generate test code
  # Enable autoindent
  # currentColumn is 1
  # Line break test when the current line ends with pair of paren.
  macro newLineTestInNimCase6(pair: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 6: When the current line ends with " & `pair` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `pair`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert
        status.mainWindow.currentMainWindowNode.currentColumn = 1

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check $currentBufStatus.buffer[0] == $(`pair`[0])
        check $currentBufStatus.buffer[1] == "  " & $(`pair`[1])

  # Generate test code
  block:
    const keyword = "{}"
    newLineTestInNimCase6(keyword)
  block:
    const keyword = "[]"
    newLineTestInNimCase6(keyword)
  block:
    const keyword = "()"
    newLineTestInNimCase6(keyword)

  # Generate test code
  # Enable autoindent
  # currentColumn is 0
  # Line break test when the current line ends with pair of paren.
  macro newLineTestInNimCase7(pair: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 7: When the current line ends with " & `pair` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `pair`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check $currentBufStatus.buffer[0] == ""
        check $currentBufStatus.buffer[1] == `pair`

  # Generate test code
  block:
    const keyword = "{}"
    newLineTestInNimCase7(keyword)
  block:
    const keyword = "[]"
    newLineTestInNimCase7(keyword)
  block:
    const keyword = "()"
    newLineTestInNimCase7(keyword)

  # Generate test code
  # Enable autoindent
  # currentColumn is 1
  # Line break test when the current line ends with the close paren.
  macro newLineTestInNimCase8(pair: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 8: When the current line ends with " & `pair` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `pair`[0] & "a" & `pair`[1]
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim
        status.bufStatus[0].mode = Mode.insert
        status.mainWindow.currentMainWindowNode.currentColumn = 1

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check $currentBufStatus.buffer[0] == $`pair`[0]
        check $currentBufStatus.buffer[1] == "  a" & `pair`[1]

  # Generate test code
  block:
    const keyword = "{}"
    newLineTestInNimCase8(keyword)
  block:
    const keyword = "[]"
    newLineTestInNimCase8(keyword)
  block:
    const keyword = "()"
    newLineTestInNimCase8(keyword)

suite "Editor: keyEnter: Enable autoindent in C":
  # Generate test code
  # Enable autoindent
  # currentColumn is 1
  # Line break test when the current line ends with pair of paren.
  macro newLineTestInCcase1(pair: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 1: When the current line ends with " & `pair` & " in C"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `pair`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langC
        status.bufStatus[0].mode = Mode.insert
        status.mainWindow.currentMainWindowNode.currentColumn = 1

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 3
        check $currentBufStatus.buffer[0] == $(`pair`[0])
        check $currentBufStatus.buffer[1] == "  "
        check $currentBufStatus.buffer[2] == $(`pair`[1])

  # Generate test code
  block:
    const keyword = "{}"
    newLineTestInCcase1(keyword)
  block:
    const keyword = "[]"
    newLineTestInCcase1(keyword)
  block:
    const keyword = "()"
    newLineTestInCcase1(keyword)

  # Generate test code
  # Enable autoindent
  # currentColumn is 0
  # Line break test when the current line ends with pair of paren.
  macro newLineTestInCcase2(pair: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 2: When the current line ends with " & `pair` & " in C"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `pair`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langC
        status.bufStatus[0].mode = Mode.insert

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check $currentBufStatus.buffer[0] == ""
        check $currentBufStatus.buffer[1] == `pair`

  # Generate test code
  block:
    const keyword = "{}"
    newLineTestInCcase2(keyword)
  block:
    const keyword = "[]"
    newLineTestInCcase2(keyword)
  block:
    const keyword = "()"
    newLineTestInCcase2(keyword)

  # Generate test code
  # Enable autoindent
  # currentColumn is 1
  # Line break test when the current line ends with the close paren.
  macro newLineTestInCcase3(pair: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 3: When the current line ends with " & `pair` & " in C"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `pair`[0] & "a" & `pair`[1]
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langC
        status.bufStatus[0].mode = Mode.insert
        status.mainWindow.currentMainWindowNode.currentColumn = 1

        const isAutoIndent = true
        status.bufStatus[0].keyEnter(status.mainWindow.currentMainWindowNode,
                                     isAutoIndent,
                                     status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 3
        check $currentBufStatus.buffer[0] == $`pair`[0]
        check $currentBufStatus.buffer[1] == "  a"
        check $currentBufStatus.buffer[2] == $`pair`[1]

  # Generate test code
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
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test:"])
    currentBufStatus.language = SourceLanguage.langYaml
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)


    check status.bufStatus[0].buffer[0] == ru"test:"
    check status.bufStatus[0].buffer[1] == ru"  "

suite "Editor: keyEnter and autoindent in Python":
  test "Auto indent if finish th current line with ':' in Python":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"if true:"])
    currentBufStatus.language = SourceLanguage.langPython
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)


    check status.bufStatus[0].buffer[0] == ru"if true:"
    check status.bufStatus[0].buffer[1] == ru"  "

  test "Auto indent if finish th current line with 'and' in Python":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"if true and"])
    currentBufStatus.language = SourceLanguage.langPython
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)


    check status.bufStatus[0].buffer[0] == ru"if true and"
    check status.bufStatus[0].buffer[1] == ru"  "

  test "Auto indent if finish th current line with 'or' in Python":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"if true or"])
    currentBufStatus.language = SourceLanguage.langPython
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = status.bufStatus[0].buffer[0].len

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)


    check currentBufStatus.buffer[0] == ru"if true or"
    check currentBufStatus.buffer[1] == ru"  "

  test "Insert a new line in Nim (Fix #1450)":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  const a = 0"])
    currentBufStatus.language = SourceLanguage.langNim
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = currentBufStatus.buffer[1].len

    const isAutoIndent = true
    for i in 0 ..< 2:
      currentBufStatus.keyEnter(currentMainWindowNode,
                                isAutoIndent,
                                status.settings.tabStop)

suite "Delete character before cursor":
  test "Delete one character":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"tes"

  test "Delete one character 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test test2"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 7

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  testtest2"

  test "Delete current Line":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test", ru""])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 0

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 2

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"   test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 3

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 3":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"    test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 4":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 1

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru" test"

  test "Delete tab 5":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  tst"

suite "Editor: Delete inside paren":
  test "delete inside double quotes":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru """abc "def" "ghi""""])
    currentMainWindowNode.currentColumn = 6

    var registers: register.Registers

    let settings = initEditorSettings()
    currentBufStatus.deleteInsideOfParen(
      currentMainWindowNode,
      registers,
      ru'"',
      settings)

    check currentBufStatus.buffer[0] == ru """abc "" "ghi""""

suite "Editor: Paste lines":
  test "Paste the single line":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    var registers: Registers
    let settings = initEditorSettings()
    registers.addRegister(ru "def", settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru"adefbc"

  test "Paste lines when the last line is empty":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    var registers: Registers
    let settings = initEditorSettings()
    registers.addRegister(@[ru "def", ru ""], settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer.len == 3
    check currentBufStatus.buffer[0] == ru"abc"
    check currentBufStatus.buffer[1] == ru"def"
    check currentBufStatus.buffer[2] == ru""

suite "Editor: Paste a string":
  test "Paste a string before cursor":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    var registers: Registers
    let settings = initEditorSettings()
    registers.addRegister(ru "def", settings)
    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer[0] == ru "defabc"

suite "Editor: Yank characters":
  test "Yank a string with name in the empty line":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru ""])

    const
      length = 1
      name = "a"
      isDelete = false
    currentBufStatus.yankCharacters(
      status.registers,
      currentMainWindowNode,
      status.commandline,
      status.messageLog,
      status.settings,
      length,
      name,
      isDelete)

    check status.registers.noNameRegister.buffer.len == 0

suite "Editor: Yank words":
  test "Yank a word":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def"])

    const loop = 1
    currentBufStatus.yankWord(status.registers,
                              currentMainWindowNode,
                              loop,
                              status.settings)

    check status.registers.noNameRegister ==  register.Register(
      buffer: @[ru "abc "],
      isLine: false,
      name: "")

    let p = initPlatform()
    # Check clipboad
    if (p == Platforms.linux or
        p == Platforms.wsl):
      let
        cmd = if p == Platforms.linux:
                execCmdEx("xsel -o")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0

      const str = "abc "
      if p == Platforms.linux:
        check output[0 .. output.high - 1] == str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == str

suite "Editor: Modify the number string under the cursor":
  test "Increment the number string":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "1"])

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "2"

  test "Increment the number string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru " 1 "])
    currentMainWindowNode.currentColumn = 1

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru " 2 "

  test "Increment the number string 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "9"])

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "10"

  test "Decrement the number string":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "1"])

    const amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "0"

  test "Decrement the number string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "0"])

    const amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "-1"

  test "Decrement the number string 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "10"])

    const amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "9"

  test "Do nothing":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

suite "Editor: Delete from the previous blank line to the current line":
  test "Delete lines":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "", ru "def", ru "ghi"])
    currentMainWindowNode.currentLine = 3

    const registerName = ""
    currentBufStatus.deleteTillPreviousBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "", ru "def"],
      isLine: true)

  test "Delete lines 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "", ru "def", ru "ghi"])
    currentMainWindowNode.currentLine = 3
    currentMainWindowNode.currentColumn = 1

    const registerName = ""
    currentBufStatus.deleteTillPreviousBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "hi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "", ru "def", ru "g"],
      isLine: true)

suite "Editor: Delete from the current line to the next blank line":
  test "Delete lines":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "def", ru "", ru "ghi"])

    const registerName = ""
    currentBufStatus.deleteTillNextBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "abc", ru "def"],
      isLine: true)

  test "Delete lines 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "def", ru "", ru "ghi"])
    currentMainWindowNode.currentColumn = 1

    const registerName = ""
    currentBufStatus.deleteTillNextBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 3
    check currentBufStatus.buffer[0] == ru "a"
    check currentBufStatus.buffer[1] == ru ""
    check currentBufStatus.buffer[2] == ru "ghi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "bc", ru "def"],
      isLine: true)

suite "Editor: Replace characters":
  test "Repace a character":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 1
      character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer[0] == ru "zbcdef"
    check currentMainWindowNode.currentColumn == 0

  test "Repace characters":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 3
      character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer[0] == ru "zzzdef"
    check currentMainWindowNode.currentColumn == 2

  test "Repace characters 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 10
      character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer[0] == ru "zzzzzz"
    check currentMainWindowNode.currentColumn == 5

  test "Repace characters 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 1
    let character = toRune(KEY_ENTER)

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "bcdef"

  test "Repace characters 4":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 3
    let character = toRune(KEY_ENTER)

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "def"

  test "Fix #1384":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])
    currentMainWindowNode.currentColumn = 2

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 1
    let character = toRune('z')

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abzdef"

suite "Editor: Toggle characters":
  test "Toggle a character":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const loop = 1
    currentBufStatus.toggleCharacters(currentMainWindowNode, loop)

    check currentBufStatus.buffer[0] == ru "Abcdef"
    check currentMainWindowNode.currentColumn == 1

  test "Toggle characters":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const loop = 3
    currentBufStatus.toggleCharacters(currentMainWindowNode, loop)

    check currentBufStatus.buffer[0] == ru "ABCdef"
    check currentMainWindowNode.currentColumn == 3

  test "Do nothing":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru " abcde"])

    const loop = 1
    currentBufStatus.toggleCharacters(currentMainWindowNode, loop)

    check currentBufStatus.buffer[0] == ru " abcde"
    check currentMainWindowNode.currentColumn == 0

suite "Editor: Open the blank line below":
  # Generate test code
  # Enable/Disable autoindent
  # open the blank line below in some languages
  macro openLineBelowTestCase1(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 1: Enable autoindent: Open the blank line below in " & langStr
                    else: "Case 1: Disable autoindent: Open the blank line below in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru "  test"])
        status.bufStatus[0].language = `lang`

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].openBlankLineBelow(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

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

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      openLineBelowTestCase1(l, isAutoIndent)
    block:
      const isAutoIndent = true
      openLineBelowTestCase1(l, isAutoIndent)

  # Generate test code
  # Enable autoindent
  # open the blank line below in Nim
  # keywords: "var", "let", "const"
  macro openLineBelowTestCase2(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 2: if the current line is " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim

        const isAutoIndent = true
        status.bufStatus[0].openBlankLineBelow(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 2
        check $currentBufStatus.buffer[0] == `keyword`
        check currentBufStatus.buffer[1] == ru "  "

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 2

  # Generate test code by macro
  block:
    const keyword = "var"
    openLineBelowTestCase2(keyword)
  block:
    const keyword = "let"
    openLineBelowTestCase2(keyword)
  block:
    const keyword = "const"
    openLineBelowTestCase2(keyword)

  # Generate test code
  # Enable autoindent
  # open the blank line below in Nim
  # When the current line ends with "or", "and", ':', "object", '='.
  macro openLineBelowTestCase3(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 3: if the current line end with " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = "test " & `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langNim

        const isAutoIndent = true
        status.bufStatus[0].openBlankLineBelow(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check $currentBufStatus.buffer[0] == buffer
        check currentBufStatus.buffer[1] == ru"  "

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == currentBufStatus.buffer[1].len

  # Generate test code by macro
  block:
    const keyword = "or"
    openLineBelowTestCase3(keyword)
  block:
    const keyword = "and"
    openLineBelowTestCase3(keyword)
  block:
    const keyword = ":"
    openLineBelowTestCase3(keyword)
  block:
    const keyword = "object"
    openLineBelowTestCase3(keyword)
  block:
    const keyword = "="
    openLineBelowTestCase3(keyword)

  # Generate test code
  # Enable/Disable autoindent
  # the current line is empty
  macro openLineBelowTestCase4(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 4: Enable autoindent: Open the blank line below in " & langStr
                    else: "Case 4: Disable autoindent: Open the blank line below in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru ""])
        status.bufStatus[0].language = `lang`

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].openBlankLineBelow(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

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

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      openLineBelowTestCase4(l, isAutoIndent)
    block:
      const isAutoIndent = true
      openLineBelowTestCase4(l, isAutoIndent)

  # Generate test code
  # Enable autoindent
  # open the blank line below in Python
  # When the current line ends with "or", "and", ':'.
  macro openLineBelowTestCase5(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 5: if the current line end with " & `keyword` & " in Python"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = "test " & `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer])
        status.bufStatus[0].language = SourceLanguage.langPython

        const isAutoIndent = true
        status.bufStatus[0].openBlankLineBelow(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check $currentBufStatus.buffer[0] == buffer
        check currentBufStatus.buffer[1] == ru"  "

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == currentBufStatus.buffer[1].len

  # Generate test code by macro
  block:
    const keyword = "or"
    openLineBelowTestCase5(keyword)
  block:
    const keyword = "and"
    openLineBelowTestCase5(keyword)
  block:
    const keyword = ":"
    openLineBelowTestCase5(keyword)

suite "Editor: Open the blank line abave":
  # Generate test code
  # Enable/Disable autoindent
  # open the blank line abave in some languages
  macro openLineAboveTestCase1(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 1: Enable autoindent: Open the blank line abave in " & langStr
                    else: "Case 1: Disable autoindent: Open the blank line abave in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru "test"])
        status.bufStatus[0].language = `lang`

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].openBlankLineAbove(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

        let
          currentBufStatus = status.bufStatus[0]
          currentMainWindowNode = status.mainWindow.currentMainWindowNode

        check currentBufStatus.buffer.len == 2
        check currentBufStatus.buffer[0] == ru ""
        check currentBufStatus.buffer[1] == ru "test"

        check currentMainWindowNode.currentLine == 0
        check currentMainWindowNode.currentColumn == 0

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      openLineAboveTestCase1(l, isAutoIndent)
    block:
      const isAutoIndent = true
      openLineAboveTestCase1(l, isAutoIndent)

  # Generate test code
  # Enable/Disable autoindent
  # open the blank line abave in some languages
  macro openLineAboveTestCase2(lang: SourceLanguage, isAutoIndent: bool): untyped =
    quote do:
      # Generate test title
      let
        langStr = sourceLangToStr(`lang`)
        testTitle = if `isAutoIndent`: "Case 2: Enable autoindent: Open the blank line abave in " & langStr
                    else: "Case 2: Disable autoindent: Open the blank line abave in " & langStr

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        status.bufStatus[0].buffer = initGapBuffer(@[ru "  test", ru ""])
        status.bufStatus[0].language = `lang`

        status.mainWindow.currentMainWindowNode.currentLine = 1

        const isAutoIndent = `isAutoIndent`
        status.bufStatus[0].openBlankLineAbove(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

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

  # Generate test code by macro
  for l in SourceLanguage:
    block:
      const isAutoIndent = false
      openLineAboveTestCase2(l, isAutoIndent)
    block:
      const isAutoIndent = true
      openLineAboveTestCase2(l, isAutoIndent)

  # Generate test code
  # Enable autoindent
  # open the blank line above in Nim
  # keywords: "var", "let", "const"
  macro openLineAboveTestCase3(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 3: if the current line is " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer, ru ""])
        status.bufStatus[0].language = SourceLanguage.langNim

        status.mainWindow.currentMainWindowNode.currentLine = 1

        const isAutoIndent = true
        status.bufStatus[0].openBlankLineAbove(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 3
        check $currentBufStatus.buffer[0] == `keyword`
        check currentBufStatus.buffer[1] == ru "  "

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == 2

  # Generate test code by macro
  block:
    const keyword = "var"
    openLineAboveTestCase3(keyword)
  block:
    const keyword = "let"
    openLineAboveTestCase3(keyword)
  block:
    const keyword = "const"
    openLineAboveTestCase3(keyword)

  # Generate test code
  # Enable autoindent
  # open the blank line above in Nim
  # When the current line ends with "or", "and", ':', "object", "=".
  macro openLineAboveTestCase4(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 4: if the current line end with " & `keyword` & " in Nim"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = "test " & `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer, ru ""])
        status.bufStatus[0].language = SourceLanguage.langNim

        status.mainWindow.currentMainWindowNode.currentLine = 1

        const isAutoIndent = true
        status.bufStatus[0].openBlankLineAbove(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]

        check currentBufStatus.buffer.len == 3

        check $currentBufStatus.buffer[0] == buffer
        check currentBufStatus.buffer[1] == ru "  "
        check currentBufStatus.buffer[2] == ru ""

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == currentBufStatus.buffer[1].len

  # Generate test code by macro
  block:
    const keyword = "or"
    openLineAboveTestCase4(keyword)
  block:
    const keyword = "and"
    openLineAboveTestCase4(keyword)
  block:
    const keyword = ":"
    openLineAboveTestCase4(keyword)
  block:
    const keyword = "object"
    openLineAboveTestCase4(keyword)
  block:
    const keyword = "="
    openLineAboveTestCase4(keyword)

  # Generate test code
  # Enable autoindent
  # open the blank line above in Python
  # When the current line ends with "or", "and", ':'.
  macro openLineAboveTestCase5(keyword: string): untyped =
    quote do:
      # Generate test title
      let testTitle = "Case 5: if the current line end with " & `keyword` & " in Python"

      # Generate test code
      test testTitle:
        var status = initEditorStatus()
        status.addNewBuffer

        const buffer = "test " & `keyword`
        status.bufStatus[0].buffer = initGapBuffer(@[ru buffer, ru ""])
        status.bufStatus[0].language = SourceLanguage.langPython

        status.mainWindow.currentMainWindowNode.currentLine = 1

        const isAutoIndent = true
        status.bufStatus[0].openBlankLineAbove(
          status.mainWindow.currentMainWindowNode,
          isAutoIndent,
          status.settings.tabStop)

        let currentBufStatus = status.bufStatus[0]
        check currentBufStatus.buffer.len == 3
        check $currentBufStatus.buffer[0] == buffer
        check currentBufStatus.buffer[1] == ru"  "
        check currentBufStatus.buffer[2] == ru""

        let currentMainWindowNode = status.mainWindow.currentMainWindowNode
        check currentMainWindowNode.currentLine == 1
        check currentMainWindowNode.currentColumn == currentBufStatus.buffer[1].len

  # Generate test code by macro
  block:
    const keyword = "or"
    openLineAboveTestCase5(keyword)
  block:
    const keyword = "and"
    openLineAboveTestCase5(keyword)
  block:
    const keyword = ":"
    openLineAboveTestCase5(keyword)
