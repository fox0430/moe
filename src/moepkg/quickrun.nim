import std/[osproc, terminal, times]
import syntax/highlite
import unicodeext, settings, bufferstatus, gapbuffer, messages, ui,
       editorstatus, movement, window, fileutils, commandviewutils

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
                             mainWindowNode: WindowNode): int =

  result = -1
  let allBufferIndex = mainWindowNode.getAllBufferIndex
  for index in allBufferIndex:
    if bufStatus[index].mode == Mode.quickRun: return index

proc runQuickRun*(bufStatus: var BufferStatus,
                  commandLine: var CommandLine,
                  messageLog: var seq[seq[Rune]],
                  settings: EditorSettings): seq[seq[Rune]] =

  if bufStatus.path.len == 0: return @[ru""]

  let filename = bufStatus.path

  if settings.quickRunSettings.saveBufferWhenQuickRun:
    saveFile(filename, bufStatus.buffer.toRunes, bufStatus.characterEncoding)
    bufStatus.countChange = 0

  let command = bufStatus.generateCommand(settings.quickRunSettings)
  if command == "": return @[ru""]

  commandLine.writeRunQuickRunMessage(settings.notificationSettings, messageLog)
  let cmdResult = execCmdEx(command)
  commandLine.clear

  result = @[ru""]

  case cmdResult.exitCode:
    of 124:
      commandLine.writeRunQuickRunTimeoutMessage(messageLog)
    else:
      for i in 0 ..< cmdResult.output.len:
        if cmdResult.output[i] == '\n': result.add(@[ru""])
        else: result[^1].add(toRunes($cmdResult.output[i])[0])

proc quickRunMode*(status: var Editorstatus) =
  status.resize(terminalHeight(), terminalWidth())

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  while isQuickRunMode(currentBufStatus.mode) and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    status.update

    var key = NONE_KEY
    while key == NONE_KEY:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    #if isResizekey(key):
    #  status.resize(terminalHeight(), terminalWidth())
    if isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if secondKey == 'g':
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
