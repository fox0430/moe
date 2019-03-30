import unicodeext, strformat, sequtils, system
import ui, editorstatus, gapbuffer, highlight, commandview

type
  SearchResult* = tuple[line: int, column: int]

proc searchBuffer*(status: var EditorStatus, keyword: seq[Rune]): SearchResult
proc searchBufferReversely*(status: var EditorStatus, keyword: seq[Rune]): SearchResult

import normalmode

proc searchLine(line: seq[Rune], keyword: seq[Rune]): int =
  result = -1
  for startPostion in 0 .. (line.len - keyword.len):
    let endPosition = startPostion + keyword.len
    if line[startPostion ..< endPosition] == keyword:
      return startPostion

proc searchBuffer(status: var EditorStatus, keyword: seq[Rune]): SearchResult =
  result = (-1, -1)
  let startLine = status.currentLine
  for i in 0 ..< status.buffer.len:
    let
      line = (startLine + i) mod status.buffer.len
      begin = if line == startLine and i == 0: status.currentColumn else: 0
      position = searchLine(status.buffer[line][begin ..< status.buffer[line].len], keyword)
    if position > -1:  return (line, begin + position)

proc searchLineReversely(line: seq[Rune], keyword: seq[Rune]): int =
  result = -1
  for startPostion in countdown((line.len - keyword.len), 0):
    let endPosition = startPostion + keyword.len
    if line[startPostion ..< endPosition] == keyword:
      return startPostion

proc searchBufferReversely(status: var EditorStatus, keyword: seq[Rune]): SearchResult =
  result = (-1, -1)
  let startLine = status.currentLine
  for i in 0 ..< status.buffer.len + 1:
    var line = (startLine - i) mod status.buffer.len
    if line < 0: line = status.buffer.len - i
    let
      endPosition = if line == startLine and i == 0: status.currentColumn else: status.buffer[line].len 
      position = searchLineReversely(status.buffer[line][0 ..< endPosition], keyword)
    if position > -1:  return (line, position)

proc searchAllOccurrence*(buffer: GapBuffer[seq[Rune]], keyword: seq[Rune]): seq[SearchResult] =
  for line in 0 ..< buffer.len:
    var begin = 0
    while begin < buffer[line].len:
      let position = searchLine(buffer[line][begin ..< buffer[line].len], keyword)
      if position == -1: break
      result.add((line, begin + position))
      begin += position + keyword.len

proc searchFirstOccurrence(status: var EditorStatus) =
  let keyword = getKeyword(status, "/")

  if keyword.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
    return

  status.searchHistory.add(keyword)
  status.isHighlight = true

  let searchResult = searchBuffer(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column:
      keyRight(status)

proc searchMode*(status: var EditorStatus) =
  searchFirstOccurrence(status)
  status.updateHighlight
  status.changeMode(status.prevMode)
