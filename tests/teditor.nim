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
