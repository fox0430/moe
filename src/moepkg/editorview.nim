import deques, sequtils, strutils, math, algorithm
import gapbuffer, ui, unicodeext

type EditorView* = object
  height*, width*, widthOfLineNum*: int
  lines*: Deque[seq[Rune]]
  originalLine*, start*, length*: Deque[int]
  updated*: bool

proc reload*(view: var EditorView, buffer: GapBuffer[seq[Rune]], topLine: int) =
  ## topLineがEditorViewの一番上のラインとして表示されるようにバッファからEditorViewに対してリロードを行う.
  ## EditorView全体を更新するため計算コストはやや高め.バッファの内容とEditorViewの内容を同期させる時やEditorView全体が全く異なるような内容になるような処理をした後等に使用することが想定されている.

  view.updated = true

  let
    height = view.height
    width = view.width

  for x in view.originalLine.mitems: x = -1
  for s in view.lines.mitems: s = ru""
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

    view.originalLine[y] = lineNumber
    view.start[y] = start
    while start + view.length[y] < buffer[lineNumber].len and view.lines[y].width + width(buffer[lineNumber][start + view.length[y]]) <= width:
      view.lines[y].add(buffer[lineNumber][start + view.length[y]])
      inc(view.length[y])

    start += view.length[y]
    if start >= buffer[lineNumber].len:
      inc(lineNumber)
      start = 0

proc initEditorView*(buffer: GapBuffer[seq[Rune]], height, width: int): EditorView =
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

proc resize*(view: var EditorView, buffer: GapBuffer[seq[Rune]], height, width, widthOfLineNum: int) =
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

proc scrollUp(view: var EditorView, buffer: GapBuffer[seq[Rune]]) =
  ## EditorView表示を1ライン上にずらす

  view.updated = true

  view.lines.popLast
  view.originalLine.popLast
  view.start.popLast
  view.length.popLast

  if view.start[0] > 0:
    view.originalLine.addFirst(view.originalLine[0])
    view.start.addFirst(view.start[0])
  else:
    view.originalLine.addFirst(view.originalLine[0]-1)
    view.start.addFirst(buffer[view.originalLine[0]].len)

  let
    line = view.originalLine[0]
    last = max(view.start[0]-1, 0)
  var str = ru""
  while 0 <= last - str.len and last-str.len <= buffer[line].high and str.width + width(buffer[line][last-str.len]) <= view.width:
    str.add(buffer[line][last-str.len])
    dec(view.start[0])

  view.length.addFirst(str.len)
  view.lines.addFirst(reversed(str))

proc scrollDown(view: var EditorView, buffer: GapBuffer[seq[Rune]]) =
  ## EditorViewの表示を1ライン下にずらす

  view.updated = true

  let height = view.height
  view.lines.popFirst
  view.originalLine.popFirst
  view.start.popFirst
  view.length.popFirst

  if view.start[height-2]+view.length[height-2] == buffer[view.originalLine[height-2]].len:
    if view.originalLine[height-2] == -1 or view.originalLine[height-2]+1 == buffer.len:
      view.originalLine.addLast(-1)
      view.start.addLast(0)
    else:
      view.originalLine.addLast(view.originalLine[height-2]+1)
      view.start.addLast(0)
  else:
    view.originalLine.addLast(view.originalLine[height-2])
    view.start.addLast(view.start[height-2]+view.length[height-2])

  let line = view.originalLine[height-1]
  view.lines.addLast(ru"")
  view.length.addLast(0)
  while view.start[height-1] + view.lines[height-1].len < buffer[line].len and view.lines[height-1].width+width(buffer[line][view.start[height-1]+view.lines[height-1].len]) <= view.width:
    view.lines[height-1].add(buffer[line][view.start[height-1]+view.lines[height-1].len])
    inc(view.length[height-1])

proc writeLineNum(view: EditorView, win: var Window, y, line: int, colorPair: ColorPair) =
  let width = view.widthOfLineNum
  win.write(y, 0, repeat(' ', width))
  win.write(y, width-(line+1).intToStr.len-1, (line+1).intToStr, colorPair)

proc writeLine(view: EditorView, win: var Window, y: int, str: seq[Rune], colorPair: ColorPair) =
  win.write(y, view.widthOfLineNum, str, colorPair)

proc writeAllLines*(view: var EditorView, win: var Window, buffer: GapBuffer[seq[Rune]], currentLine: int) =
  win.erase
  view.widthOfLineNum = buffer.len.intToStr.len+1
  for y in 0..view.height-1:
    if view.originalLine[y] == -1:
      win.write(y, 0, repeat(' ', view.width))
      continue
    if view.start[y] == 0: view.writeLineNum(win, y, view.originalLine[y], if view.originalLine[y]  == currentLine: ColorPair.brightGreenDefault else: ColorPair.grayDefault)
    view.writeLine(win, y, view.lines[y], if view.originalLine[y] == currentLine: ColorPair.brightGreenDefault else: brightWhiteDefault)
  win.refresh

proc update*(view: var EditorView, win: var Window, buffer: GapBuffer[seq[Rune]], currentLine: int) =
  # if not view.updated: return
  let widthOfLineNum = buffer.len.intToStr.len+1
  if widthOfLineNum != view.widthOfLineNum: view.resize(buffer, view.height, view.width+view.widthOfLineNum-widthOfLineNum, widthOfLineNum)
  view.writeAllLines(win, buffer, currentLine)
  view.updated = false

proc seekCursor*(view: var EditorView, buffer: GapBuffer[seq[Rune]], currentLine, currentColumn: int) =
  while currentLine < view.originalLine[0] or (currentLine == view.originalLine[0] and view.length[0] > 0 and currentColumn < view.start[0]): view.scrollUp(buffer)
  while (view.originalLine[view.height-1] != -1 and currentLine > view.originalLine[view.height-1]) or (currentLine == view.originalLine[view.height-1] and view.length[view.height-1] > 0 and currentColumn >= view.start[view.height-1]+view.length[view.height-1]): view.scrollDown(buffer)
