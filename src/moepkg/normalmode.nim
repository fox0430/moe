import ncurses
import editorstatus, statusbar, editorview, cursor

const escKey = 27

proc normalMode*(status: var EditorStatus) =
  status.cmdLoop = 0
  status.mode = Mode.normal
  
  noecho()

  while true:
    writeStatusBar(status)

    status.view.updated = true
    status.view.update(status.mainWindow, status.buffer, status.currentLine)
    status.cursor.update(status.view, status.currentLine, status.currentColumn)

    let key = getch()
    if key == escKey: break
