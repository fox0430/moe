import sequtils, strutils, os, terminal
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview

proc getCommand*(commandWindow: var Window, updateCommandWindow: proc (window: var Window, command: string)): seq[string] =
  var command = ""
  while true:
    updateCommandWindow(commandWindow, command)
 
    let key = commandWindow.getkey
    
    if isResizeKey(key): continue
    if isEnterKey(key): break
    if isBackspaceKey(key):
      if command.len > 0: command.delete(command.high, command.high)
      continue
    if not key in 0..255: continue
 
    command &= chr(key)
 
  return command.splitWhitespace

proc writeNoWriteError(commandWindow: var Window) =
  commandWindow.erase
  commandWindow.write(0, 0, "Error: No write since last change", ColorPair.redDefault)
  commandWindow.refresh

proc writeSaveError(commandWindow: var Window) =
  commandWindow.erase
  commandWindow.write(0, 0, "Error: Failed to save the file", ColorPair.redDefault)
  commandWindow.refresh

proc isJumpCommand(status: EditorStatus, command: seq[string]): bool =
  return command.len == 1 and isDigit(command[0]) and status.prevMode == Mode.normal

proc isEditCommand(command: seq[string]): bool =
  return command.len == 2 and command[0] == "e"

proc isWriteCommand(status: EditorStatus, command: seq[string]): bool =
  return command.len in {1, 2} and command[0] == "w" and status.prevMode == Mode.normal

proc isQuitCommand(command: seq[string]): bool =
  return command.len == 1 and command[0] == "q"

proc isWriteAndQuitCommand(status: EditorStatus, command: seq[string]): bool =
  return command.len == 1 and command[0] == "wq" and status.prevMode == Mode.normal

proc isForceQuitCommand(command: seq[string]): bool =
  return command.len == 1 and command[0] == "q!"

proc isShellCommand(command: seq[string]): bool =
  return command.len >= 1 and command[0][0] == '!'

proc jumpCommand(status: var EditorStatus, line: int) =
  jumpLine(status, line)
  status.changeMode(Mode.normal)

proc editCommand(status: var EditorStatus, filename: string) =
  if status.countChange != 0:
    writeNoWriteError(status.commandWindow)
    status.changeMode(Mode.normal)
    return
  if existsFile(filename):
    status = initEditorStatus()
    status.filename = filename
    status.buffer = openFile(status.filename)
    status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-status.buffer.len.intToStr.len-2)
  elif existsDir(filename):
    setCurrentDir(filename)
    status.changeMode(Mode.filer)
  else:
    status = initEditorStatus()
    status.filename = filename
    status.buffer = newFile()
    status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-status.buffer.len.intToStr.len-2)

proc writeCommand(status: var EditorStatus, filename: string) =
  if filename == nil:
    status.commandWindow.erase
    status.commandWindow.write(0, 0, "Error: No file name", ColorPair.redDefault)
    status.commandWindow.refresh
    status.changeMode(Mode.normal)
    return

  try:
    saveFile(filename, status.buffer)
    status.filename = filename
    status.countChange = 0
  except IOError:
    writeSaveError(status.commandWindow)

  status.changeMode(Mode.normal)

proc quitCommand(status: var EditorStatus) =
  if status.countChange == 0: status.changeMode(Mode.quit)
  else:
    writeNoWriteError(status.commandWindow)
    status.changeMode(Mode.normal)

proc writeAndQuitCommand(status: var EditorStatus) =
  try:
    saveFile(status.filename, status.buffer)
    status.changeMode(Mode.quit)
  except IOError:
    writeSaveError(status.commandWindow)
    status.changeMode(Mode.normal)

proc forceQuitCommand(status: var EditorStatus) =
  status.changeMode(Mode.quit)

proc shellCommand(status: var EditorStatus, shellCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  discard execShellCmd(shellCommand)
  discard execShellCmd("printf \"\nPress Enter\"")
  discard execShellCmd("read _")

  restoreTerminalModes()
  status.commandWindow.erase
  status.commandWindow.refresh

proc exMode*(status: var EditorStatus) =
  let command = getCommand(status.commandWindow, proc (window: var Window, command: string) =
    window.erase
    window.write(0, 0, ":"&command)
    window.refresh
  )

  if isJumpCommand(status, command):
    var line = command[0].parseInt-1
    if line < 0: line = 0
    if line >= status.buffer.len: line = status.buffer.high
    jumpCommand(status, line)
  elif isEditCommand(command):
    editCommand(status, command[1])
  elif isWriteCommand(status, command):
    writeCommand(status, if command.len < 2: status.filename else: command[1])
  elif isQuitCommand(command):
    quitCommand(status)
  elif isWriteAndQuitCommand(status, command):
    writeAndQuitCommand(status)
  elif isForceQuitCommand(command):
    forceQuitCommand(status)
  elif isShellCommand(command):
    shellCommand(status, command.join(" ").substr(1))
  else:
    status.changeMode(status.prevMode)
