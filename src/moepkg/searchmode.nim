
import unicodeext, strformat, sequtils
import ui, editorstatus, gapbuffer

type
  SearchResult* = tuple[line: int, column: int]

proc searchBuffer*(status: var EditorStatus, keyword: seq[Rune]): SearchResult

import normalmode

proc getKeyword(commandWindow: var Window, history: seq[seq[Rune]], updateCommandWindow: proc (window: var Window, keyword: seq[Rune])): seq[Rune] =
  var keyword = ru""
  var historyIndex = history.len
  while true:
    updateCommandWindow(commandWindow, keyword)
 
    let key = commandWindow.getkey
    
    if isResizeKey(key): continue
    if isEnterKey(key): break
    if isEscKey(key): return "".toRunes
    if isBackspaceKey(key):
      if keyword.len > 0: keyword.delete(keyword.high, keyword.high)
      continue
    if validateUtf8(key.toUTF8) != -1: continue
    if isUpKey(key):
      if historyIndex > 0:
        historyIndex.dec
        keyword = history[historyIndex]
      continue
    if isDownKey(key):
      if historyIndex < history.high:
        historyIndex.inc
        keyword = history[historyIndex]
      continue
 
    keyword &= key
 
  return ($keyword).toRunes

proc searchLine(line: seq[Rune], keyword: seq[Rune]): int =
  result = -1
  for startPostion in 0 .. (line.len - keyword.len):
    let endPosition = startPostion + keyword.len
    if line[startPostion ..< endPosition] == keyword:
      return startPostion

proc searchBuffer(status: var EditorStatus, keyword: seq[Rune]): SearchResult =
  result = (-1, -1)
  let startLine = status.currentLine
  for line in startLine ..< status.buffer.len:
    let begin = if line == status.currentLine: status.currentColumn else: 0
    let position = searchLine(status.buffer[line][begin ..< status.buffer[line].len], keyword)
    if position > -1:
        return (line, begin + position)
  for line in 0 ..< startLine:
    let begin = if line == status.currentLine: status.currentColumn else: 0
    let position = searchLine(status.buffer[line][begin ..< status.buffer[line].len], keyword)
    if position > -1:
        return (line, begin + position)
    

proc searchFirstOccurrence(status: var EditorStatus) =
  let keyword = getKeyword(status.commandWindow, status.searchHistory, proc (window: var Window, keyword: seq[Rune]) =
    window.erase
    window.write(0, 0, fmt"/{$keyword}")
    window.refresh
  )
  if keyword.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
    return

  status.searchHistory.add(keyword)
  let searchResult = searchBuffer(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column:
      keyRight(status)

proc searchMode*(status: var EditorStatus) =
  if status.searchHistory.len == 0:
    status.searchHistory = @[]
  searchFirstOccurrence(status)
  status.changeMode(status.prevMode)
