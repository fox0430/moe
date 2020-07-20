import osproc, packages/docutils/highlite, terminal, times
import unicodeext, settings, bufferstatus, gapbuffer, messages, ui,
       editorstatus, movement, window, workspace

type Language = enum
  None = 0
  Nim = 1
  C = 2
  Cpp = 3
  Shell = 4

proc generateCommand(bufStatus: BufferStatus,
                     language: Language,
                     settings: QuickRunSettings): string =

  let filename = $bufStatus.filename

  result = "timeout " & $settings.timeout & " "
  if language == Language.Nim:
    let
      advancedCommand = settings.nimAdvancedCommand
      options = settings.NimOptions
    result &= "nim " & advancedCommand & " -r " & options & " " & filename
  elif language == Language.C:
    result &= "gcc " & settings.ClangOptions & " " & filename & " && ./a.out"
  elif language == Language.Cpp:
    result &= "g++ " & settings.CppOptions & " " & filename & " && ./a.out"
  elif language == Language.Shell:
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

proc runQuickRun*(bufStatus: BufferStatus,
                  cmdWin: var Window,
                  settings: EditorSettings): seq[seq[Rune]] =

  let
    filename = bufStatus.filename
    sourceLang = bufStatus.language
    language = if sourceLang == SourceLanguage.langNim: Language.Nim
               elif sourceLang == SourceLanguage.langC: Language.C
               elif sourceLang == SourceLanguage.langCpp: Language.Cpp
               elif filename.len > 3 and
                    filename[filename.len - 3 .. filename.high] == ru".sh":
                      Language.Shell
               else: Language.None

  let
    command = bufStatus.generateCommand(language, settings.quickRunSettings)
  if command == "": return @[ru""]

  cmdWin.writeRunQuickRunMessage
  let cmdResult = execCmdEx(command)
  cmdWin.erase

  result = @[ru""]

  case cmdResult.exitCode:
    of 0:
      for i in 0 ..< cmdResult.output.len:
        if cmdResult.output[i] == '\n': result.add(@[ru""])
        else: result[^1].add(toRunes($cmdResult.output[i])[0])
    of 124:
      cmdWin.writeRunQuickRunTimeoutMessage
    else:
      cmdWin.writeRunQuickRunFailedMessage

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

    var key: Rune = ru'\0'
    while key == ru'\0':
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
