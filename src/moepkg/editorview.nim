import std/[deques, strutils, math, strformat]
import gapbuffer, ui, unicodeext, independentutils, color, settings,
       bufferstatus, highlight

type EditorView* = object
  height*, width*, widthOfLineNum*: int
  lines*: Deque[seq[Rune]]
  originalLine*, start*, length*: Deque[int]
  updated*: bool

type ViewLine = object
  line: seq[Rune]
  originalLine, start, length: int

proc loadSingleViewLine[T](view: EditorView,
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

proc reload*[T](view: var EditorView, buffer: T, topLine: int) =
  ## topLineがEditorViewの一番上のラインとして表示されるようにバッファからEditorViewに対してリロードを行う.
  ## EditorView全体を更新するため計算コストはやや高め.バッファの内容とEditorViewの内容を同期させる時やEditorView全体が全く異なるような内容になるような処理をした後等に使用することが想定されている.

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

proc initEditorView*[T](buffer: T, height, width: int): EditorView =
  ## width/heightでEditorViewを初期化し,バッファの0行0文字目からロードする.widthは画面幅ではなくEditorViewの1ラインの文字数である(従って行番号分の長さは考慮しなくてよい).

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

proc resize*[T](view: var EditorView,
                buffer: T,
                height, width, widthOfLineNum: int) =
  ## 指定されたwidth/heightでEditorViewを更新する.表示される部分はなるべくリサイズ前と同じになるようになっている.

  let topline = view.originalLine[0]

  view.lines = initDeque[seq[Rune]]()
  for i in 0..height-1: view.lines.addlast(ru"")

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

proc scrollUp*[T](view: var EditorView, buffer: T) =
  ## EditorView表示を1ライン上にずらす

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

proc scrollDown*[T](view: var EditorView, buffer: T) =
  ## EditorViewの表示を1ライン下にずらす

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

proc writeLineNum(view: EditorView, win: var Window, y, line: int, colorPair: EditorColorPair) {.inline.} =
  win.write(y, 0, strutils.align($(line+1), view.widthOfLineNum-1), colorPair, false)

proc write(view: EditorView,
           win: var Window,
           y, x: int,
           str: seq[Rune],
           color: EditorColorPair | int) {.inline.} =

  # TODO: use settings file
  const tab = "    "
  win.write(y, x, ($str).replace("\t", tab), color, false)

proc writeCurrentLine(win: var Window,
                      view: EditorView,
                      highlight: Highlight,
                      theme: ColorTheme,
                      str: seq[Rune],
                      currentLineColorPair: var int,
                      y, x, i, last: int,
                      mode, prevMode: Mode,
                      viewSettings: EditorViewSettings) =

  if viewSettings.cursorLine:
    # Enable underline
    win.attron(Attributes.underline)

  if viewSettings.highlightCurrentLine and
     not (isVisualMode(mode) or isConfigMode(mode, prevMode)):
    # Change background color to white if background color is editorBg
    let
      defaultCharColor = EditorColorPair.defaultChar
      colors = if i > -1 and i < highlight.len:
                 theme.getColorFromEditorColorPair(highlight[i].color)
               else:
                 theme.getColorFromEditorColorPair(defaultCharColor)

      theme = ColorThemeTable[theme]

    block:
      let
        fg = colors[0]
        bg = if colors[1] == theme.EditorColor.editorBg:
               theme.EditorColor.currentLineBg
             else:
               colors[1]

      setColorPair(currentLineColorPair, fg, bg)

    view.write(win, y, x, str, currentLineColorPair)

    currentLineColorPair.inc

    # Write spaces after text in the current line
    block:
      let
        fg = theme.EditorColor.defaultChar
        bg = theme.EditorColor.currentLineBg

      setColorPair(currentLineColorPair, fg, bg)
    let
      spaces = ru" ".repeat(view.width - view.lines[y].width)
      x = view.widthOfLineNum + view.lines[y].width

    view.write(win, y, x, spaces, currentLineColorPair)

    currentLineColorPair.inc

  else:
    view.write(win, y, x, str, highlight[i].color)

  if viewSettings.cursorLine:
    # Disable underline
    win.attroff(Attributes.underline)

proc writeAllLines*[T](view: var EditorView,
                       win: var Window,
                       viewSettings: EditorViewSettings,
                       isCurrentWin: bool,
                       mode, prevMode: Mode,
                       buffer: T,
                       highlight: Highlight,
                       theme: ColorTheme,
                       currentLine, startSelectedLine, endSelectedLine: int,
                       currentLineColorPair: var int) =

  win.erase
  view.widthOfLineNum = if viewSettings.lineNumber: buffer.len.numberOfDigits + 1
                        else: 0

  var
    indents          = 0
    lastOriginalLine = -1
    lineStart        = 0
  let
    start = (view.originalLine[0], view.start[0])
    useHighlight = highlight.len > 0 and
                   (highlight[0].firstRow, highlight[0].firstColumn) <= start and
                   start <= (highlight[^1].lastRow, highlight[^1].lastColumn)

  var i = if useHighlight: highlight.indexOf(view.originalLine[0], view.start[0])
          else: -1
  for y in 0 ..< view.height:
    if view.originalLine[y] == -1: break

    let isCurrentLine = view.originalLine[y] == currentLine
    if viewSettings.lineNumber and view.start[y] == 0:
      let lineNumberColor = if isCurrentLine and isCurrentWin and
                               viewSettings.currentLineNumber:
                              EditorColorPair.currentLineNum
                            else:
                              EditorColorPair.lineNum
      view.writeLineNum(win, y, view.originalLine[y], lineNumberColor)

    var x = view.widthOfLineNum
    if view.length[y] == 0:
      if isVisualMode(mode) and
         (view.originalLine[y] >= startSelectedLine and
         endSelectedLine >= view.originalLine[y]):
        view.write(win, y, x, ru" ", EditorColorPair.visualMode)
      else:
        if viewSettings.highlightCurrentLine and isCurrentLine and
           currentLine < buffer.len:
          writeCurrentLine(win,
                           view,
                           highlight,
                           theme,
                           ru"",
                           currentLineColorPair,
                           y, x, i, 0,
                           mode, prevMode,
                           viewSettings)
        else:
          view.write(win, y, x, view.lines[y], EditorColorPair.defaultChar)
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
        writeCurrentLine(win,
                         view,
                         highlight,
                         theme,
                         str,
                         currentLineColorPair,
                         y, x, i, last,
                         mode, prevMode,
                         viewSettings)
      else:
        view.write(win, y, x, str, highlight[i].color)
      x += width(str)
      if last == highlight[i].lastColumn - view.start[y]: inc(i) # consumed a whole segment
      else: break

    if viewSettings.indentationLines:
      for i in 0..<indents:
        view.write(win,
                   y,
                   lineStart+(viewSettings.tabStop*i),
                   ru("┊"),
                   EditorColorPair.whitespace)

  win.refresh

proc update*[T](view: var EditorView,
                win: var Window,
                viewSettings: EditorViewSettings,
                isCurrentWin: bool,
                mode, prevMode: Mode,
                buffer: T,
                highlight: Highlight,
                theme: ColorTheme,
                currentLine, startSelectedLine, endSelectedLine: int,
                currentLineColorPair: var int) =

  let widthOfLineNum = buffer.len.intToStr.len + 1
  if viewSettings.lineNumber and widthOfLineNum != view.widthOfLineNum:
    view.resize(buffer,
                view.height,
                view.width + view.widthOfLineNum - widthOfLineNum,
                widthOfLineNum)

  view.writeAllLines(win,
                     viewSettings,
                     isCurrentWin,
                     mode,
                     prevMode,
                     buffer,
                     highlight,
                     theme,
                     currentLine,
                     startSelectedLine,
                     endSelectedLine,
                     currentLineColorPair)

  view.updated = false

proc seekCursor*[T](view: var EditorView,
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
