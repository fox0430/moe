import unittest
import moepkg/ui, moepkg/highlight, moepkg/editorstatus, moepkg/editorview, moepkg/gapbuffer, moepkg/unicodeext, moepkg/insertmode, moepkg/normalmode

test "Add new buffer":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.addNewBuffer("")
  status.resize(100, 100)
  check(status.bufStatus.len == 2)

test "Vertical split window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.verticalSplitWindow

test "Horizontal split window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.horizontalSplitWindow

test "Close window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.verticalSplitWindow
  status.closeWindow(status.currentMainWindowNode)

test "resize 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.currentMainWindowNode.view = initEditorView(status.bufStatus[0].buffer, 1, 1)
  status.resize(0, 0)

test "resize 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.currentMainWindowNode.view= initEditorView(status.bufStatus[0].buffer, 20, 4)
  status.resize(20, 4)
  status.bufStatus[0].currentColumn = 1
  status.changeMode(Mode.insert)
  for i in 0 ..< 10:
    status.bufStatus[0].keyEnter(status.currentMainWindowNode, status.settings.autoCloseParen)
    status.update

test "Highlight of a pair of paren 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)

  block:
    status.bufStatus[0].buffer = initGapBuffer(@[ru"()"])
    status.updateHighlight
    status.update

    check(status.bufStatus[0].highlight[0].color == EditorColorPair.defaultChar and status.bufStatus[0].highlight[0].firstColumn == 0)
    check(status.bufStatus[0].highlight[1].color == EditorColorPair.parenText and status.bufStatus[0].highlight[1].firstColumn == 1)

  block:
    status.bufStatus[0].buffer = initGapBuffer(@[ru"[]"])
    status.updateHighlight
    status.update

    check(status.bufStatus[0].highlight[0].color == EditorColorPair.defaultChar and status.bufStatus[0].highlight[0].firstColumn == 0)
    check(status.bufStatus[0].highlight[1].color == EditorColorPair.parenText and status.bufStatus[0].highlight[1].firstColumn == 1)

  block:
    status.bufStatus[0].buffer = initGapBuffer(@[ru"{}"])
    status.updateHighlight
    status.update

    check(status.bufStatus[0].highlight[0].color == EditorColorPair.defaultChar and status.bufStatus[0].highlight[0].firstColumn == 0)
    check(status.bufStatus[0].highlight[1].color == EditorColorPair.parenText and status.bufStatus[0].highlight[1].firstColumn == 1)

  block:
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(()"])
    status.updateHighlight
    status.update

    check(status.bufStatus[0].highlight[0].color == EditorColorPair.defaultChar and status.bufStatus[0].highlight[0].firstColumn == 0 and status.bufStatus[0].highlight[0].lastColumn == 2)

test "Highlight of a pair of paren 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)

  status.bufStatus[0].buffer = initGapBuffer(@[ru"(())"])
  status.updateHighlight
  status.update

  check(status.bufStatus[0].highlight[0].color == EditorColorPair.defaultChar and status.bufStatus[0].highlight[0].firstColumn == 0 and status.bufStatus[0].highlight[0].lastColumn == 2)
  check(status.bufStatus[0].highlight[1].color == EditorColorPair.parenText and status.bufStatus[0].highlight[1].firstColumn == 3)

test "Highlight of a pair of paren 3":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)

  status.bufStatus[0].buffer = initGapBuffer(@[ru"(", ru")"])
  status.updateHighlight
  status.update

  check(status.bufStatus[0].highlight[0].color == EditorColorPair.defaultChar and status.bufStatus[0].highlight[0].firstRow == 0)
  check(status.bufStatus[0].highlight[1].color == EditorColorPair.parenText and status.bufStatus[0].highlight[1].firstRow == 1)

test "Highlight of a pair of paren 4":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)

  status.bufStatus[0].buffer = initGapBuffer(@[ru"(", ru")"])
  status.updateHighlight
  status.update

  status.bufStatus[0].keyDown
  status.changeMode(Mode.insert)
  status.bufStatus[0].keyEnter(status.currentMainWindowNode, status.settings.autoIndent)

  status.updateHighlight
  status.update

test "Auto delete paren 1":
  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"()"])
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"()"])
    status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"")

test "Auto delete paren 2":
  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(())"])
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(())"])
    status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(())"])
    for i in 0 ..< 2: status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(())"])
    for i in 0 ..< 3: status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"()")

test "Auto delete paren 3":
  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(()"])
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(()"])
    status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"(")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(()"])
    for i in 0 ..< 2: status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"(")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"())"])
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru")")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"())"])
    status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru")")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"())"])
    for i in 0 ..< 3: status.bufStatus[0].keyRight
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"()")

test "Auto delete paren 4":
  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(", ru")"])
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"" and status.bufStatus[0].buffer[1] == ru"")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(", ru")"])
    status.bufStatus[0].keyDown
    status.bufStatus[0].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"" and status.bufStatus[0].buffer[1] == ru"")

test "Auto delete paren 5":
  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"()"])
    status.changeMode(Mode.insert)
    status.bufStatus[0].keyRight
    status.bufStatus[0].keyBackspace(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"()"])
    status.changeMode(Mode.insert)
    for i in 0 ..< 2: status.bufStatus[0].keyRight
    status.bufStatus[0].keyBackspace(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"")

test "Auto delete paren 6":
  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(a(a))"])
    status.changeMode(Mode.insert)
    for i in 0 ..< 5: status.bufStatus[0].keyRight
    status.bufStatus[0].keyBackspace(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"(aa)")

  block:
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"(a(a))"])
    status.changeMode(Mode.insert)
    for i in 0 ..< 6: status.bufStatus[0].keyRight
    status.bufStatus[0].keyBackspace(status.settings.autoDeleteParen, status.currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"a(a)")
