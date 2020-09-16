import osproc, highlite, terminal, times
import unicodeext, settings, bufferstatus, gapbuffer, messages, ui,
       editorstatus, movement, window, workspace, fileutils

proc generateCommand(bufStatus: BufferStatus,
                     settings: QuickRunSettings): string =

  let filename = $bufStatus.path

  result = "timeout " & $settings.timeout & " "
  if bufStatus.language == SourceLanguage.langNim:
    let
      advancedCommand = settings.nimAdvancedCommand
      options = settings.NimOptions
    result &= "nim " & advancedCommand & " -r " & options & " " & filename
  elif bufStatus.language == SourceLanguage.langC:
    result &= "gcc " & settings.ClangOptions & " " & filename & " && ./a.out"
  elif bufStatus.language == SourceLanguage.langCpp:
    result &= "g++ " & settings.CppOptions & " " & filename & " && ./a.out"
  elif bufStatus.language == SourceLanguage.langShell:
    if bufStatus.buffer[0] == ru"#!/bin/bash":
      result &= "bash " & settings.bashOptions & " " & filename
    else:
      result &= "sh " & settings.shOptions & " "  & filename
  else:
    result = ""

proc getQuickRunBufferIndex*(bufStatus: seq[BufferStatus],
                             workspace: WorkSpace): int =

  result = -1
  let allBufferIndex = workspace.mainWindowNode.getAllBufferIndex
  for index in allBufferIndex:
    if bufStatus[index].mode == Mode.quickRun: return index

proc runQuickRun*(bufStatus: var BufferStatus,
                  cmdWin: var Window,
                  messageLog: var seq[seq[Rune]],
                  settings: EditorSettings): seq[seq[Rune]] =

  if bufStatus.path.len == 0: return @[ru""]

  let filename = bufStatus.path

  if settings.quickRunSettings.saveBufferWhenQuickRun:
    saveFile(filename, bufStatus.buffer.toRunes, bufStatus.characterEncoding)
    bufStatus.countChange = 0

  let command = bufStatus.generateCommand(settings.quickRunSettings)
  if command == "": return @[ru""]

  cmdWin.writeRunQuickRunMessage(settings.notificationSettings, messageLog)
  let cmdResult = execCmdEx(command)
  cmdWin.erase

  result = @[ru""]

  case cmdResult.exitCode:
    of 124:
      cmdWin.writeRunQuickRunTimeoutMessage(messageLog)
    else:
      for i in 0 ..< cmdResult.output.len:
        if cmdResult.output[i] == '\n': result.add(@[ru""])
        else: result[^1].add(toRunes($cmdResult.output[i])[0])

proc isQuickRunMode(status: Editorstatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    index = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex

  return status.bufStatus[index].mode == Mode.quickRun

proc quickRunMode*(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  status.resize(terminalHeight(), terminalWidth())

  while status.isQuickRunMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.update

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('g'):
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == 'g':
        status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
