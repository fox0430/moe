import terminal
import editorstatus, ui, unicodeext

proc bufferListView*(status: var EditorStatus) =
  status.mainWindow[status.currentMainWindow].erase

  for i in 0 .. status.bufStatus.high:
    let filename = $status.bufStatus[i].filename
    status.mainWindow[status.currentMainWindow].write(i, 0, $i & ": " & filename.substr(0, terminalWidth()), brightWhiteDefault)
