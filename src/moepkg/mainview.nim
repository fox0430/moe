import terminal
import editorstatus, ui, unicodeext

proc bufferListView*(status: var EditorStatus) =
  status.mainWindow.erase

  for i in 0 .. status.bufStatus.high:
    let filename = $status.bufStatus[i].filename
    status.mainWindow.write(i, 0, $i & ": " & filename.substr(0, terminalWidth()), brightWhiteDefault)
