import unicodeext, strformat, sequtils
import ui, editorstatus, gapbuffer, normalmode

type
  SearchResult = tuple[line: int, column: int]

proc getKeyword(commandWindow: var Window, updateCommandWindow: proc (window: var Window, command: seq[Rune])): seq[Rune] =
  var command = ru""
  while true:
    updateCommandWindow(commandWindow, command)
 
    let key = commandWindow.getkey
    
    if isResizeKey(key): continue
    if isEnterKey(key): break
    if isEscKey(key): return "".toRunes
    if isBackspaceKey(key):
      if command.len > 0: command.delete(command.high, command.high)
      continue
    if validateUtf8(key.toUTF8) != -1: continue
 
    command &= key
 
  return ($command).toRunes

proc searchText(line: seq[Rune], keyword: seq[Rune]): int =
  result = -1
  for startPostion in 0 .. (line.len - keyword.len):
    let endPosition = startPostion + keyword.len
    if line[startPostion ..< endPosition] == keyword:
      return startPostion

proc searchBuffer(status: var EditorStatus, keyword: seq[Rune]): SearchResult =
  result = (-1, -1)
  for line in status.currentLine ..< status.buffer.len:
    if line == status.currentLine:
      let position = searchText(status.buffer[line][status.currentColumn ..< status.buffer[line].len], keyword)
      if position > -1:
        return (line, position + status.currentColumn)
    else:
      let position = searchText(status.buffer[line], keyword)
      if position > -1:
        return (line, position)

proc smartSearch(status: var EditorStatus) =
  let command = getKeyword(status.commandWindow, proc (window: var Window, command: seq[Rune]) =
    window.erase
    window.write(0, 0, fmt"/{$command}")
    window.refresh
  )
  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
    return
  let searchResult = searchBuffer(status, command)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column:
      keyRight(status)

proc searchMode*(status: var EditorStatus) =
  smartSearch(status)
  status.changeMode(status.prevMode)
