import ui, editorstatus, editorview, cursor

proc insertMode*(status: var EditorStatus) =
  while status.mode == Mode.insert:
    writeStatusBar(status)
    
    status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)
    status.view.update(status.mainWindow, status.buffer, status.currentLine)
    status.cursor.update(status.view, status.currentLine, status.currentColumn)

    status.mainWindow.write(status.cursor.y, status.view.widthOfLineNum+status.cursor.x, "")
    status.mainWindow.refresh

    let key = getKey(status.mainWindow)
    
    if isEscKey(key):
      if status.currentColumn > 0: dec(status.currentColumn)
      status.expandedColumn = status.currentColumn
      status.mode = Mode.normal
