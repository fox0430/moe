import ncurses
import editorstatus, statusbar

const escKey = 27

proc normalMode*(status: var EditorStatus) =
  status.cmdLoop = 0
  status.mode = Mode.normal
  
  noecho()

  while true:
    writeStatusBar(status)

    let key = getch()
    if key == escKey: break
