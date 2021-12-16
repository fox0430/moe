import std/unittest
import moepkg/[editorstatus, logviewer, bufferstatus, unicodeext]

suite "Log viewer":
  test "Open the log viewer (Fix #1455)":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    status.messageLog = @[ru "test"]

    status.verticalSplitWindow
    status.resize(100, 100)
    status.moveNextWindow

    status.addNewBuffer
    status.changeCurrentBuffer(status.bufStatus.high)
    status.changeMode(bufferstatus.Mode.logviewer)

    # In the log viewer
    currentBufStatus.path = ru"Log viewer"

    status.resize(100, 100)
    status.update

    let currentBufferIndex = status.bufferIndexInCurrentWindow

    status.update

  test "Exit viewer":
    var status = initEditorStatus()
    status.addNewBuffer("Log viewer", Mode.logViewer)

    status.resize(100, 100)
    status.update

    status.exitLogViewer(100, 100)

    status.resize(100, 100)
