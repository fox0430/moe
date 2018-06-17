import strutils
import editorstatus, ui

proc exMode*(status: var EditorStatus) =
  var command = ""
  while true:
    status.commandWindow.erase
    status.commandWindow.write(0, 0, ":"&command)
    status.commandWindow.refresh

    let key = status.commandWindow.getkey

    if isEnterKey(key): break
    if isBackspaceKey(key):
      if command.len > 0: command.delete(command.high, command.high)
      continue
    if not key in 0..255: continue

    command &= chr(key)

  let args = command.splitWhitespace
  if args.len == 1 and args[0] == "q":
    status.mode = Mode.quit
  else:
    status.mode = Mode.normal

  status.commandWindow.erase
  status.commandWindow.refresh
