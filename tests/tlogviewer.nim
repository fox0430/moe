import std/unittest
import moepkg/[editorstatus, logviewer, bufferstatus, unicodeext, ui]

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "Log viewer":
  test "Open the log viewer (Fix #1455)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    status.messageLog = @[ru "test"]

    status.verticalSplitWindow
    status.resize(100, 100)
    status.moveNextWindow

    status.addNewBufferInCurrentWin
    status.changeCurrentBuffer(status.bufStatus.high)
    status.changeMode(bufferstatus.Mode.logviewer)

    # In the log viewer
    currentBufStatus.path = ru"Log viewer"

    status.resize(100, 100)
    status.update

    status.update

  test "Exit viewer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("Log viewer", Mode.logViewer)

    status.resize(100, 100)
    status.update

    status.exitLogViewer

    status.resize(100, 100)
