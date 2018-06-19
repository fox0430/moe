import strutils
import editorstatus, ui

proc getCommand(commandWindow: var Window): seq[string] =
 var command = ""
 while true:
   commandWindow.erase
   commandWindow.write(0, 0, ":"&command)
   commandWindow.refresh

   let key = commandWindow.getkey

   if isEnterKey(key): break
   if isBackspaceKey(key):
     if command.len > 0: command.delete(command.high, command.high)
     continue
   if not key in 0..255: continue

   command &= chr(key)

 return command.splitWhitespace

proc exMode*(status: var EditorStatus) =
  let command = getCommand(status.commandWindow)
  if command.len == 1 and command[0] == "q":
    status.mode = Mode.quit
  else:
    status.mode = Mode.normal

  status.commandWindow.erase
  status.commandWindow.refresh
