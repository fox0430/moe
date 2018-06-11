import deques, sequtils, strutils, gapbuffer, ui

type EditorView* = object
  height, width, widthOfLineNum: int
  lines: Deque[string]
  originalLine, start, length: Deque[int]
  updated: bool

proc initEditorView*(buffer: GapBuffer, height, width: int): EditorView =
  ## width/heightでEditorViewを初期化し,バッファの0行0文字目からロードする.widthは画面幅ではなくEditorViewの1ラインの文字数である(従って行番号分の長さは考慮しなくてよい).

  result.height = height
  result.width = width
  result.widthOfLineNum = $(buffer.len)

  result.lines = initDeque[string](height)

  result.originalLine = initDeque[string](height)
  result.start = initDeque[int](height)
  result.length = initDeque[int](height)

  result.reloadEditorView(buffer, 0)

proc reload*(view: var EditorView, buffer: GapBuffer, topLine: int) =
  ## topLineがEditorViewの一番上のラインとして表示されるようにバッファからEditorViewに対してリロードを行う.
  ## EditorView全体を更新するため計算コストはやや高め.バッファの内容とEditorViewの内容を同期させる時やEditorView全体が全く異なるような内容になるような処理をした後等に使用することが想定されている.

  let
    height = view.height
    width = view.width

  # apply(view.originalLine, proc(x: var int) = x = -1)
  # apply(view.lines, proc(s: var string ) = s = "")
  for x in view.originalLine.mitems: x = -1
  for s in view.lines.mitems: s = ""

  var
    lineNumber = topLine
    start = 0
  for y in 0..height-1:
    if lineNumber >= buffer.len: break
    if buffer[lineNumber].len == 0:
      view.originalLine[y] = lineNumber
      view.start[y] = 0
      view.length[y] = 0
      inc(lineNumber)
      continue

    view.originalLine[y] = lineNumber
    view.start[y] = start
    view.length[y] = min(width, buffer[lineNumber].len-start)
    view.lines[y] = buffer[lineNumber][view.start[y]..view.start[y]+view.length[y]-1]

    start += width
    if start >= buffer[lineNumber].len:
      inc(lineNumber)
      start = 0

proc resize*(view: var EditorView, buffer: GapBuffer[string], height, width, widthOfLineNum: int) =
  ## 指定されたwidth/heightでEditorViewを更新する.表示される部分はなるべくリサイズ前と同じになるようになっている.

  let topline = view.originalLine[0]
  view.lines = initDeque[string](height)
  view.height = height
  view.width = width
  view.widthOfLineNum = widthOfLineNum
  view.originalLine = initDeque[int](height)
  view.start = initDeque[int](height)
  view.length = initDeque[int](height)
  view.updated = true
  view.reload(buffer, topLine)

proc scrollUp(view: var EditorView, buffer: GapBuffer) =
  ## EditorView表示を1ライン上にずらす

  view.updated = true

  let height = view.height
  view.lines.popLast
  view.originalLine.popLast
  view.start.popLast
  view.length.popLast

  if view.start[1] > 0:
    view.originalLine.addFirst(view.originaLine[1])
    view.start.addFirst(view.start[1]-view.width)
    view.length.addFirst(view.width)
  else:
    view.orignalLine.addFirst(view.originalLine[1]-1)
    view.start.addFirst(view.width*((buffer[view.originalLine[0]].len-1) div view.width))
    view.length.addFirst(if buffer[view.originaLine[0]].len == 0: 0 else: (buffer[view.originalLine[0]].len-1) mod view.width +1)

  view.lines.addFirst(buffer[view.originalLine[0]][view.start[0]..view.start[0]+view.length[0]-1])

proc scrollDown(view: var EditorView, buffer: GapBuffer) =
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
      view.length.addLast(0)
    else:
      view.originalLine.addLast(view.originalLine[height-2]+1)
      view.start.addLast(0)
      view.length.addLast(min(view.width, buffer[view.originalLine[height-1]].len))
  else:
    view.originalLine.addLast(view.originalLine[height-2])
    view.start.addLast(view.start[height-2]+view.length[height-2])
    view.length.addLast(min(view.width, buffer[view.originalLine[height-1]].len-view.start[height-1]))


  view.addLast(buffer[view.originalLine[height-1]][view.start[height-1]..view.start[height-1]+view.length[height-1]-1])

proc writeLineNum(view: EditorView, win: Window, y, line: int, colorPair: ColorPair) =
  let width = view.widthOfLineNum
  win.write(y, 0, repeat(' ', width))
  win.write(y, width-(line+1).intToStr.len-1, (line+1).intToStr, colorPair)

proc writeLine(view: EditorView, win: Window, y: int, str: string) =
  win.write(y, view.widthOfLineNum, str, ColorPair.brightWhiteDefault)

proc writeAllLines(view: var EditorView, win: Window, buffer: GapBuffer, currentLine: int) =
  win.erase
  view.widthOfLineNum = buffer.len.intToStr.len+1
  for y in 0..view.height-1:
    if view.originalLine[y] == -1:
      win.write(y, 0, repeat(' ', view.width))
      continue
    if view.start[y] == 0: view.writeLineNum(win, y, view.originalLine[y], if view.originalLine[y]  == currentLine: ColorPair.brightGreenDefault else: ColorPair.grayDefault)
    view.writeLine(win, y, view.lines[y])
  win.refresh

proc update*(view: var EditorView, win: Window, buffer: GapBuffer[string], currentLine: int) =
  if not view.updated: return
  let widthOfLineNum = buffer.len.intToStr.len+1
  if widthOfLineNum != view.widthOfLineNum: view.resize(buffer, view.height, view.width+view.widthOfLineNum-widthOfLineNum, widthOfLineNum)
  view.writeAllLines(win, buffer, currentLine)
  view.updated = false


proc seekCursor*(view: var EditorView, buffer: GapBuffer, currentLine, currentColumn: int) =
  view.updated = true
  while currentLine < view.originalLine[0] or (currentLine == view.originalLine[0] and view.length[0] > 0 and currentColumn < view.start[0]): view.scrollUp(buffer)
  while (view.originalLine[view.height-1] != -1 and currentLine > view.originalLine[view.height-1]) or (currentLine == view.originalLine[view.height-1] and view.length[view.height-1] > 0 and currentColumn >= view.start[view.height-1]+view.length[view.height-1]): view.scrollDown(buffer)
