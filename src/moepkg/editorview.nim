import std/[deques, strutils, math, strformat, logging]
import termtools
import gapbuffer, ui, unicodeext, independentutils, color, settings,
       bufferstatus, highlight

type EditorView* = object
  y*, x*, height*, width*, widthOfLineNum*: int
  lines*: Deque[seq[Rune]]
  originalLine*, start*, length*: Deque[int]
  updated*: bool

type ViewLine = object
  line: seq[Rune]
  originalLine, start, length: int

proc loadSingleViewLine[T](
  view: EditorView,
  buffer: T,
  originalLine,
  start: int): ViewLine =

  result.line = ru""
  result.originalLine = originalLine
  result.start = start
  let bufferLine = buffer[originalLine]
  template isRemaining: bool = start+result.length < bufferLine.len
  template calcNextWidth: int =
    if isRemaining(): unicodeext.width(bufferLine[start+result.length]) else: 0
  var
    totalWidth = 0
    nextWidth = calcNextWidth()
  while isRemaining() and totalWidth+nextWidth <= view.width:
    result.line.add(bufferLine[start+result.length])
    result.length.inc
    totalWidth += nextWidth
    nextWidth = calcNextWidth

## NOTE
## EN: Reload the EditorView from the buffer so that topLine appears as the top line of the EditorView.
## The calculation cost is a little high because the entire EditorView is updated.
## It is supposed to be used when synchronizing the contents of the buffer and the contents of the EditorView,
## or after processing so that the contents of the entire EditorView are completely different.
##
## JP: topLineがEditorViewの一番上のラインとして表示されるようにバッファからEditorViewに対してリロードを行う.
## EditorView全体を更新するため計算コストはやや高め.
## バッファの内容とEditorViewの内容を同期させる時やEditorView全体が全く異なるような内容になるような処理をした後等に使用することが想定されている.
proc reload*[T](view: var EditorView, buffer: T, topLine: int) =

  view.updated = true

  let height = view.height

  const empty = ru""
  for x in view.originalLine.mitems: x = -1
  for s in view.lines.mitems: s = empty
  for x in view.length.mitems: x = 0

  var
    lineNumber = topLine
    start = 0
  for y in 0 ..< height:
    if lineNumber >= buffer.len: break
    if buffer[lineNumber].len == 0:
      view.originalLine[y] = lineNumber
      view.start[y] = 0
      view.length[y] = 0
      inc(lineNumber)
      continue

    let singleLine = loadSingleViewLine(view, buffer, lineNumber, start)
    view.lines[y] = singleLine.line
    view.originalLine[y] = singleLine.originalLine
    view.start[y] = singleLine.start
    view.length[y] = singleLine.length

    start += view.length[y]
    if start >= buffer[lineNumber].len:
      inc(lineNumber)
      start = 0

## NOTE
## EN: Initialize EditorView with width/height and load from the 0th line 0th character of the buffer.
## width is not the screen width. The number of characters in one line of EditorView.
## You don't have to consider the length of the line number.
##
## JP: width/heightでEditorViewを初期化し,バッファの0行0文字目からロードする.
## widthは画面幅ではなくEditorViewの1ラインの文字数である(行番号分の長さは考慮しなくてよい).
proc initEditorView*[T](buffer: T, y, x, height, width: int): EditorView =

  result.y = y
  result.x = x
  result.height = height
  result.width = width
  result.widthOfLineNum = buffer.len.intToStr.len+1

  result.lines = initDeque[seq[Rune]]()
  for i in 0..height-1: result.lines.addLast(ru"")

  result.originalLine = initDeque[int]()
  for i in 0..height-1: result.originalLine.addLast(-1)
  result.start = initDeque[int]()
  for i in 0..height-1: result.start.addLast(-1)
  result.length = initDeque[int]()
  for i in 0..height-1: result.length.addLast(-1)

  result.reload(buffer, 0)

## NOTE
## EN: Update the EditorView with the specified width/height.
## Make the displayed part the same as before resizing as much as possible.
##
## JP: 指定されたwidth/heightでEditorViewを更新する.
## 表示される部分はなるべくリサイズ前と同じになるようになっている.
proc resize*[T](
  view: var EditorView,
  buffer: T,
  y, x, height, width, widthOfLineNum: int) =
  let topline = view.originalLine[0]

  view.lines = initDeque[seq[Rune]]()
  for i in 0..height-1: view.lines.addlast(ru"")

  view.y = y
  view.x = x
  view.height = height
  view.width = width
  view.widthOfLineNum = widthOfLineNum

  view.originalLine = initDeque[int]()
  for i in 0..height-1: view.originalLine.addlast(-1)
  view.start = initDeque[int]()
  for i in 0..height-1: view.start.addlast(-1)
  view.length = initDeque[int]()
  for i in 0..height-1: view.length.addlast(-1)

  view.updated = true
  view.reload(buffer, topLine)

## NOTE
## EN: Move the display of EditorView up one line.
##
## JP: EditorView表示を1ライン上にずらす.
proc scrollUp*[T](view: var EditorView, buffer: T) =
  view.updated = true

  view.lines.popLast
  view.originalLine.popLast
  view.start.popLast
  view.length.popLast

  var originalLine, last: int
  if view.start[0] > 0:
    originalLine = view.originalLine[0]
    last = view.start[0]-1
  else:
    originalLine = view.originalLine[0]-1
    last = buffer[originalLine].high

  var start = 0
  while true:
    let singleLine = loadSingleViewLine(view, buffer, originalLine, start)
    start += singleLine.length
    if start > last:
      view.lines.addFirst(singleLine.line)
      view.originalLine.addFirst(singleLine.originalLine)
      view.start.addFirst(singleLine.start)
      view.length.addFirst(singleLine.length)
      break

## NOTE
## EN: Move the display of EditorView down one line.
##
## JP: EditorViewの表示を1ライン下にずらす.
proc scrollDown*[T](view: var EditorView, buffer: T) =
  view.updated = true

  let height = view.height
  view.lines.popFirst
  view.originalLine.popFirst
  view.start.popFirst
  view.length.popFirst

  var originalLine, start: int
  if view.start[height-2]+view.length[height-2] == buffer[view.originalLine[height-2]].len:
    originalLine = if view.originalLine[height-2] == -1 or
                      view.originalLine[height-2]+1 == buffer.len: -1
                   else: view.originalLine[height-2]+1
    start = 0
  else:
    originalLine = view.originalLine[height-2]
    start = view.start[height-2]+view.length[height-2]

  if originalLine == -1:
    view.lines.addLast(ru"")
    view.originalLine.addLast(-1)
    view.start.addLast(0)
    view.length.addLast(0)
  else:
    let singleLine = loadSingleViewLine(view, buffer, originalLine, start)
    view.lines.addLast(singleLine.line)
    view.originalLine.addLast(singleLine.originalLine)
    view.start.addLast(singleLine.start)
    view.length.addLast(singleLine.length)

# TODO: Remove?
#proc write(
#  view: EditorView,
#  y, x: int,
#  buf: seq[Rune],
#  color: ColorPair) {.inline.} =
#
#  # TODO: use settings file (tab size)
#  const tab = "    "
#  let str = $buf
#  write(view.x + x, view.y + y, str.replace("\t", tab), color)

proc currentLineWithColor(
  view: EditorView,
  highlight: Highlight,
  theme: ColorTheme,
  str: seq[Rune],
  y, i, last: int,
  mode, prevMode: Mode,
  viewSettings: EditorViewSettings): string =

  # TODO: Enable underline
  #if viewSettings.cursorLine:
    # Enable underline
    #win.attron(Attributes.underline)

  if viewSettings.highlightCurrentLine and
     not (isVisualMode(mode) or isConfigMode(mode, prevMode)):

    block:
      let color =
        # Reserse fg color and bg color.
        if i > -1 and i < highlight.len: highlight[i].color.reverse
        # Default terminal color
        else: initColorPair()

      result = withColor($str, color)

    if last == view.lines[y].high:
      # Spaces after text in the current line.
      let
        spaces = " ".repeat(view.width - view.lines[y].width)
        color = ColorThemeTable[currentColorTheme].EditorColorPair.currentLine
      result.add spaces.withColor(color)
  else:
    # TODO: use settings file (tab size)
    const tab = "    "
    let buf = ($str).replace("\t", tab)
    return buf.withColor(highlight[i].color)

  # TODO: Fix
  #if viewSettings.cursorLine:
    # Disable underline
    #win.attroff(Attributes.underline)

proc writeAllLines*[T](
  view: var EditorView,
  viewSettings: EditorViewSettings,
  isCurrentWin: bool,
  mode, prevMode: Mode,
  buffer: T,
  highlight: Highlight,
  theme: ColorTheme,
  currentLine, startSelectedLine, endSelectedLine: int) =

  view.widthOfLineNum =
    if viewSettings.lineNumber: buffer.len.numberOfDigits + 1
    else: 0

  var
    indents          = 0
    lastOriginalLine = -1
    lineStart        = 0
  let
    start = (view.originalLine[0], view.start[0])
    useHighlight = highlight.len > 0 and
                   (highlight[0].firstrow, highlight[0].firstcolumn) <= start and
                   start <= (highlight[^1].lastRow, highlight[^1].lastColumn)

  var i = if useHighlight: highlight.indexOf(view.originalLine[0], view.start[0])
          else: -1
  for y in 0 ..< view.height:
    # Add lines with colors to `displayBuffer`.
    var line = ""

    if view.originalLine[y] == -1: break

    let isCurrentLine = view.originalLine[y] == currentLine
    if viewSettings.lineNumber and view.start[y] == 0:
      let lineNumberColor =
        if isCurrentLine and isCurrentWin and viewSettings.currentLineNumber:
          ColorThemeTable[currentColorTheme].EditorColorPair.currentLineNum
        else:
          ColorThemeTable[currentColorTheme].EditorColorPair.lineNum
      let buf = strutils.align($(view.originalLine[y] + 1), view.widthOfLineNum - 1)  & " "
      line = buf.withColor(lineNumberColor)

    var x = view.widthOfLineNum
    if view.length[y] == 0:
      if isVisualMode(mode) and
         (view.originalLine[y] >= startSelectedLine and
         endSelectedLine >= view.originalLine[y]):
          let color = ColorThemeTable[currentColorTheme].EditorColorPair.visualMode
          line.add " ".withColor(color)
      else:
        if viewSettings.highlightCurrentLine and isCurrentLine and
           currentLine < buffer.len:
          line.add currentLineWithColor(
            view,
            highlight,
            theme,
            ru"",
            y, i, 0,
            mode, prevMode,
            viewSettings)
        else:
          let color = ColorThemeTable[currentColorTheme].EditorColorPair.defaultChar
          line.add $view.lines[y].withColor(color)

      displayBuffer.add line
      continue

    if viewSettings.indentationLines and not isConfigMode(mode, prevMode):
      let currentOriginalLine = view.originalLine[y]
      if currentOriginalLine != lastOriginalLine:
        let line = if buffer.len() > currentOriginalLine:
                     buffer[currentOriginalLine]
                   else: ru""
        lineStart = x
        var numSpaces = 0
        for i in 0..<line.len:
          if line[i] != Rune(' '):
            numSpaces = i+1
            break
          inc numSpaces
        indents = int(numSpaces / viewSettings.tabStop)
      else:
        # Line wrapping
        indents = 0
      lastOriginalLine = view.originalLine[y]

    while i < highlight.len and highlight[i].firstRow < view.originalLine[y]: inc(i)

    while i < highlight.len and highlight[i].firstRow == view.originalLine[y]:
      if (highlight[i].firstRow, highlight[i].firstColumn) > (highlight[i].lastRow, highlight[i].lastColumn):
        # Skip an empty segment
        break
      let
        first = max(highlight[i].firstColumn-view.start[y], 0)
        last = min(highlight[i].lastColumn-view.start[y], view.lines[y].high)

      if first > last: break

      block:
        let
          lastStr = $last
          lineStr = $view.lines[y]
        assert(last <= view.lines[y].high,
               fmt"last = {lastStr}, view.lines[y] = {lineStr}")
        assert(first <= last, fmt"first = {first}, last = {last}")

      let str = view.lines[y][first .. last]

      if isCurrentLine:
        line.add currentLineWithColor(
          view,
          highlight,
          theme,
          str,
          y, i, last,
          mode, prevMode,
          viewSettings)
      else:
        line.add $str.withColor(highlight[i].color)

      x += width(str)
      if last == highlight[i].lastColumn - view.start[y]: inc(i) # consumed a whole segment
      else: break

    # TODO: Fix
    #if viewSettings.indentationLines:
    #  for i in 0 ..< indents:
    #    let
    #      x = lineStart + (viewSettings.tabStop * i)
    #      color = ColorThemeTable[currentColorTheme].EditorColorPair.whitespace
    #    write(x, y, "┊".withColor(color))

    displayBuffer.add line

proc update*[T](
  view: var EditorView,
  viewSettings: EditorViewSettings,
  isCurrentWin: bool,
  mode, prevMode: Mode,
  buffer: T,
  highlight: Highlight,
  theme: ColorTheme,
  currentLine, startSelectedLine, endSelectedLine: int) =

  let widthOfLineNum = buffer.len.intToStr.len + 1
  if viewSettings.lineNumber and widthOfLineNum != view.widthOfLineNum:
    view.resize(
      buffer,
      view.y,
      view.x,
      view.height,
      view.width + view.widthOfLineNum - widthOfLineNum,
      widthOfLineNum)

  view.writeAllLines(
    viewSettings,
    isCurrentWin,
    mode,
    prevMode,
    buffer,
    highlight,
    theme,
    currentLine,
    startSelectedLine,
    endSelectedLine)

  view.updated = false

proc seekCursor*[T](
  view: var EditorView,
  buffer: T,
  currentLine, currentColumn: int) =

  while currentLine < view.originalLine[0] or
        (currentLine == view.originalLine[0] and
        view.length[0] > 0 and
        currentColumn < view.start[0]): view.scrollUp(buffer)

  while (view.originalLine[view.height - 1] != -1 and
         currentLine > view.originalLine[view.height - 1]) or
         (currentLine == view.originalLine[view.height - 1] and
         view.length[view.height - 1] > 0 and
         currentColumn >= view.start[view.height - 1]+view.length[view.height - 1]):
     view.scrollDown(buffer)

proc rangeOfOriginalLineInView*(view: EditorView): (int, int) =
  var
    startLine = 0
    endLine = 0
  for index, lineNum in view.originalLine:
    if index == 0: startLine = lineNum
    elif lineNum == -1: break
    else: endLine = lineNum

  return (startLine, endLine)
