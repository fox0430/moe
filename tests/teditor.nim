import unittest
include moepkg/[editor, editorstatus]

suite "editor.nim":
  test "Auto indent in current Line":
    var status = initEditorStatus()
    status.addNewBuffer("")
  
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  a", ru"b"])

    status.workSpace[0].currentMainWindowNode.currentLine = 1
  
    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"  a")
    check(status.bufStatus[0].buffer[1] == ru"  b")

  test "Auto indent in current Line 2":
    var status = initEditorStatus()
    status.addNewBuffer("")
  
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    status.workSpace[0].currentMainWindowNode.currentLine = 1
  
    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 3":
    var status = initEditorStatus()
    status.addNewBuffer("")
  
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"  b"])

    status.workSpace[0].currentMainWindowNode.currentLine = 1
  
    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 4":
    var status = initEditorStatus()
    status.addNewBuffer("")
  
    status.bufStatus[0].buffer = initGapBuffer(@[ru""])
  
    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"")

  test "Delete trailing spaces":
    var status = initEditorStatus()
    status.addNewBuffer("")
  
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc",
                                                 ru"d  ",
                                                 ru"efg"])

    status.bufStatus[0].deleteTrailingSpaces

    check status.bufStatus[0].buffer.len == 3
    check status.bufStatus[0].buffer[0] == ru"abc"
    check status.bufStatus[0].buffer[1] == ru"d"
    check status.bufStatus[0].buffer[2] == ru"efg"
