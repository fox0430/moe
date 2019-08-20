import terminal, strutils, sequtils, strformat
import editorstatus, editorview, ui, unicodeext

type
  ExModeViewStatus = tuple[buffer: seq[Rune], prompt: string, cursorY, cursorX, currentPosition, startPosition: int]

proc writeMessageOnCommandWindow(cmdWin: var Window, message: string, color: EditorColorPair) =
  cmdWin.erase
  cmdWin.write(0, 0, message, color)
  cmdWin.refresh

proc writeNoWriteError*(cmdWin: var Window) =
  cmdWin.writeMessageOnCommandWindow("Error: No write since last change", EditorColorPair.errorMessage)

proc writeSaveError*(cmdWin: var Window) =
  cmdWin.writeMessageOnCommandWindow("Error: Failed to save the file", EditorColorPair.errorMessage)

proc writeRemoveFileError*(cmdWin: var Window) =
  cmdWin.writeMessageOnCommandWindow("Error: can not remove file", EditorColorPair.errorMessage)

proc writeRemoveDirError*(cmdWin: var Window) =
  cmdWin.writeMessageOnCommandWindow("Error: can not remove directory", EditorColorPair.errorMessage)

proc writeCopyFileError*(cmdWin: var Window) =
  cmdWin.writeMessageOnCommandWindow("Error: can not copy file", EditorColorPair.errorMessage)

proc writeFileOpenError*(cmdWin: var Window, fileName: string) =
  cmdWin.writeMessageOnCommandWindow("Error: can not open: " & fileName, EditorColorPair.errorMessage)

proc writeCreateDirError*(cmdWin: var Window) =
  cmdWin.writeMessageOnCommandWindow("Error: : can not create direcotry", EditorColorPair.errorMessage)

proc writeMessageDeletedFile*(cmdWin: var Window, filename: string) =
  cmdWin.writeMessageOnCommandWindow("Deleted: " & filename, EditorColorPair.commandBar)

proc writeNoFileNameError*(cmdWin: var Window) =
  cmdWin.writeMessageOnCommandWindow("Error: No file name" , EditorColorPair.errorMessage)

proc writeMessageYankedLine*(cmdWin: var Window, numOfLine: int) =
  cmdWin.writeMessageOnCommandWindow(fmt"{numOfLine} line yanked" , EditorColorPair.commandBar)

proc writeMessageYankedCharactor*(cmdWin: var Window, numOfChar: int) =
  cmdWin.writeMessageOnCommandWindow(fmt"{numOfChar} charactor yanked" , EditorColorPair.commandBar)

proc writeMessageAutoSave*(cmdWin: var Window, filename: seq[Rune]) =
  cmdWin.writeMessageOnCommandWindow(fmt"Auto saved {filename}" , EditorColorPair.commandBar)

proc writeNotEditorCommandError*(cmdWin: var Window, command: seq[seq[Rune]]) =
  var cmd = ""
  for i in 0 ..< command.len: cmd = cmd & $command[i] & " "
  cmdWin.writeMessageOnCommandWindow(fmt"Error: Not an editor command: {cmd}" , EditorColorPair.errorMessage)

proc writeMessageSaveFile*(cmdWin: var Window, filename: seq[Rune]) =
  cmdWin.writeMessageOnCommandWindow(fmt"Saved {filename}" , EditorColorPair.commandBar)

proc removeSuffix(r: seq[seq[Rune]], suffix: string): seq[seq[Rune]] =
  for i in 0 .. r.high:
    var string = $r[i]
    string.removeSuffix(suffix)
    if i == 0: result = @[string.toRunes]
    else: result.add(string.toRunes)

proc splitQout(s: string): seq[seq[Rune]]=
  result = @[ru""]
  var quotIn = false
  var backSlash = false

  for i in 0 .. s.high:
    if s[i] == '\\':
      backSlash = true
    elif backSlash:
      backSlash = false 
      result[result.high].add(($s[i]).toRunes)
    elif i > 0 and s[i - 1] == '\\':
      result[result.high].add(($s[i]).toRunes)
    elif not quotIn and s[i] == '"':
      quotIn = true
      result.add(ru"")
    elif quotIn and s[i] == '"':
      quotIn = false
      if i != s.high:  result.add(ru"")
    else:
      result[result.high].add(($s[i]).toRunes)

  return result.removeSuffix(" ")

proc splitCommand(command: string): seq[seq[Rune]] =
  if (command).contains('"'):
    return splitQout(command)
  else:
    return strutils.splitWhitespace(command).map(proc(s: string): seq[Rune] = toRunes(s))

proc writeExModeView(commandWindow: var Window, exStatus: ExModeViewStatus, color: EditorColorPair) =
  let buffer = ($exStatus.buffer).substr(exStatus.startPosition, exStatus.buffer.len)

  commandWindow.erase
  commandWindow.write(exStatus.cursorY, 0, fmt"{exStatus.prompt}{buffer}", color)
  commandWindow.moveCursor(0, exStatus.cursorX)
  commandWindow.refresh

proc initExModeViewStatus(prompt: string): ExModeViewStatus =
  result.buffer = ru""
  result.prompt = prompt
  result.cursorY = 0
  result.cursorX = 1

proc moveLeft(commandWindow: Window, exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition > 0:
    dec(exStatus.currentPosition)
    if exStatus.cursorX > exStatus.prompt.len: dec(exStatus.cursorX)
    else: dec(exStatus.startPosition)

proc moveRight(exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition < exStatus.buffer.len:
    inc(exStatus.currentPosition)
    if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
    else: inc(exStatus.startPosition)

proc moveTop(exStatus: var ExModeViewStatus) =
  exStatus.cursorX = exStatus.prompt.len
  exStatus.currentPosition = 0
  exStatus.startPosition = 0

proc moveEnd(exStatus: var ExModeViewStatus) =
  exStatus.currentPosition = exStatus.buffer.len - 1
  if exStatus.buffer.len > terminalWidth():
    exStatus.startPosition = exStatus.buffer.len - terminalWidth()
    exStatus.cursorX = terminalWidth()
  else:
    exStatus.startPosition = 0
    exStatus.cursorX = exStatus.prompt.len + exStatus.buffer.len - 1

proc deleteCommandBuffer(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0:
    if exStatus.buffer.len < terminalWidth(): dec(exStatus.cursorX)
    exStatus.buffer.delete(exStatus.currentPosition - 1, exStatus.currentPosition - 1)
    dec(exStatus.currentPosition)

proc deleteCommandBufferCurrentPosition(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0 and exStatus.currentPosition < exStatus.buffer.len:
    exStatus.buffer.delete(exStatus.cursorX - 1, exStatus.cursorX - 1)
    if exStatus.currentPosition > exStatus.buffer.len: dec(exStatus.currentPosition)

proc insertCommandBuffer(exStatus: var ExModeViewStatus, c: Rune) =
  exStatus.buffer.insert(c, exStatus.currentPosition)
  inc(exStatus.currentPosition)
  if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
  else: inc(exStatus.startPosition)

proc getKeyword*(status: var EditorStatus, prompt: string): seq[Rune] =
  var exStatus = initExModeViewStatus(prompt)
  while true:
    writeExModeView(status.commandWindow, exStatus, EditorColorPair.commandBar)

    var key = getKey(status.commandWindow)

    if isEnterKey(key) or isEscKey(key): break
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): moveLeft(status.commandWindow, exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key): deleteCommandBuffer(exStatus)
    elif isDcKey(key): deleteCommandBufferCurrentPosition(exStatus)
    else: insertCommandBuffer(exStatus, key)

  return exStatus.buffer

proc suggestMode(status: var Editorstatus, exStatus: var ExModeViewStatus, key: var Rune) =
  const exCommandList = [
    ru"!",
    ru"b",
    ru"bd",
    ru"bfirst",
    ru"blast",
    ru"bnext",
    ru"bprev",
    ru"buf",
    ru"cursorLine",
    ru"e",
    ru"indent",
    ru"linenum",
    ru"livereload",
    ru"ls",
    ru"noh",
    ru"paren",
    ru"q",
    ru"q!",
    ru"qa",
    ru"qa!",
    ru"statusbar",
    ru"syntax",
    ru"tabstop",
    ru"theme",
    ru"vs",
    ru"wq",
    ru"wqa",
  ]
  
  var suggestIndex = 0
  if exStatus.buffer.len == 0:
    while isTabkey(key):
      exStatus.buffer = ru""
      exStatus.currentPosition = 0
      exStatus.cursorX = 1

      for rune in exCommandList[suggestIndex]: exStatus.insertCommandBuffer(rune)
      writeExModeView(status.commandWindow, exStatus, EditorColorPair.commandBar)

      if suggestIndex < exCommandList.high: inc(suggestIndex)
      else: suggestIndex = 0

      key = getKey(status.commandWindow)
  
proc getCommand*(status: var EditorStatus, prompt: string): seq[seq[Rune]] =
  var exStatus = initExModeViewStatus(prompt)
  status.resize(terminalHeight(), terminalWidth())

  while true:
    writeExModeView(status.commandWindow, exStatus, EditorColorPair.commandBar)

    var key = getKey(status.commandWindow)

    if isTabkey(key): suggestMode(status, exStatus, key)

    if isEnterKey(key): break
    elif isEscKey(key):
      status.commandWindow.erase
      return @[ru""]
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): moveLeft(status.commandWindow, exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key): deleteCommandBuffer(exStatus)
    elif isDcKey(key): deleteCommandBufferCurrentPosition(exStatus)
    else: insertCommandBuffer(exStatus, key)

  return splitCommand($exStatus.buffer)
