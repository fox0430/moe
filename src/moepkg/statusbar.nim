import terminal, strformat
import editorstatus, ui, gapbuffer

proc writeStatusBar*(status: var EditorStatus) =
  status.statusWindow.erase

  if status.mode == Mode.filer:
    status.statusWindow.write(0, 0, " FILER ", ColorPair.blackWhite)
    status.statusWindow.refresh
    return

  status.statusWindow.write(0, 0,  if status.mode == Mode.normal: " NORMAL " else: " INSERT ", ColorPair.blackWhite)
  status.statusWindow.append(status.filename, ColorPair.blackGreen)
  if status.filename == "No name":  status.statusWindow.append(" [+]", ColorPair.blackGreen)

  status.statusWindow.write(0, terminalWidth()-13, fmt"{status.currentLine+1}/{status.buffer.len}", Colorpair.blackWhite)
  status.statusWindow.write(0, terminalWidth()-6, fmt"{status.currentColumn}/{status.buffer[status.currentLine].len}", ColorPair.blackWhite)
  status.statusWindow.refresh
