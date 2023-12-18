#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[deques, strutils, math, strformat, options, sequtils]
import gapbuffer, ui, unicodeext, independentutils, color, highlight, git,
       syntaxcheck, theme, bufferstatus

type
  Sidebar = object
    buffer: seq[Runes]
    highlights: seq[seq[EditorColorPairIndex]]

  EditorViewConfig* = object
    colorMode*: ColorMode
    isCursorLine*: bool
    isLineNumber*: bool
    isIndentationLines*: bool
    isHighlightCurrentLine*: bool
    isHighlightCurrentLineNumber*: bool
    tabStop*: int

  EditorView* = object
    height*: int
    width*: int
    widthOfLineNum*: int
    sidebarWidth*: int
    lines*: Deque[Runes]
    originalLine*: Deque[int]
    start*: Deque[int]
    length*: Deque[int]
    selectedRange*: Range
    updated*: bool
    editorMode*: Mode
    isCurrentWin*: bool
    sidebar*: Option[Sidebar]
    config*: EditorViewConfig

  ViewLine = object
    line: Runes
    originalLine: int
    start: int
    length: int

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

proc reload*[T](view: var EditorView, buffer: T, topLine: int) =
  ## Reload from the buffer to the EditorView so that topLine is displayed as the top line of the EditorView.
  ##
  ## The computational cost is somewhat high because the entire EditorView is updated.
  ##
  ## It is intended to be used to synchronize the contents of a buffer with the contents of an EditorView,
  ## or after the entire EditorView has become completely different.

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
  ## Initialize EditorView with `width`/`height` and
  ## load from the first character of the first line of the buffer.
  ## `width` is not the screen width but the number of characters per line of the EditorView.
  ## So the length of the line number need not be considered.

  result.height = height
  result.width = width
  result.widthOfLineNum = buffer.len.intToStr.len+1

  result.lines = initDeque[Runes]()
  for i in 0..height-1: result.lines.addLast(ru"")

  result.originalLine = initDeque[int]()
  for i in 0..height-1: result.originalLine.addLast(-1)
  result.start = initDeque[int]()
  for i in 0..height-1: result.start.addLast(-1)
  result.length = initDeque[int]()
  for i in 0..height-1: result.length.addLast(-1)

  result.reload(buffer, 0)

proc initSidebar*(view: var EditorView, width: int = 2) =
  ## Initialize EditorView.sidebar.

  view.sidebar = Sidebar(
    buffer: view.height.newSeqWith(ru' '.repeat(width)),
    highlights: view.height.newSeqWith(
      EditorColorPairIndex.default.repeat(width))).some

  view.sidebarWidth = width

proc clearSidebar*(view: var EditorView) {.inline.} =
  ## Clear the sidebr buffer and highlights.

  let
    height = view.height
    width = view.sidebar.get.buffer.len

  view.sidebar.get.buffer = height.newSeqWith(ru' '.repeat(width))
  view.sidebar.get.highlights = height.newSeqWith(
    EditorColorPairIndex.default.repeat(width))

proc updateSidebarBuffer*(view: var EditorView, buffer: seq[Runes]) {.inline.} =
  view.sidebar.get.buffer = buffer

proc overwriteSidebarBuffer*(
  view: var EditorView,
  position: Position,
  r: Rune) {.inline.} =

    view.sidebar.get.buffer[position.y][position.x] = r

proc overwriteSidebarBuffer*(
  view: var EditorView,
  lineNumber: int,
  line: Runes) {.inline.} =

    view.sidebar.get.buffer[lineNumber] = line

proc updateSidebarHighlights*(
  view: var EditorView,
  h: seq[seq[EditorColorPairIndex]]) {.inline.} =

    view.sidebar.get.highlights = h

proc overwriteSidebarHighlights*(
  view: var EditorView,
  position: Position,
  highlight: EditorColorPairIndex) {.inline.} =

    view.sidebar.get.highlights[position.y][position.x] = highlight

proc overwriteSidebarHighlights*(
  view: var EditorView,
  line: int,
  highlight: seq[EditorColorPairIndex]) {.inline.} =

    view.sidebar.get.highlights[line] = highlight

proc resize(s: var Sidebar, size: Size) =
  ## Reszie buffer and highlights.

  var
    newBuffer = size.h.newSeqWith(" ".repeat(size.w).toRunes)
    newHighlights: seq[seq[EditorColorPairIndex]] = size.h.newSeqWith(
      size.w.newSeqWith(EditorColorPairIndex.default))

  for i in 0 .. min(newBuffer.high, s.buffer.high):
    for j in 0 .. min(newBuffer[i].high, s.buffer[i].high):
      newBuffer[i][j] = s.buffer[i][j]
      newHighlights[i][j] = s.highlights[i][j]

  s.buffer = newBuffer
  s.highlights = newHighlights

proc resize*[T](
  view: var EditorView,
  buffer: T,
  height, width, widthOfLineNum: int) =
    ## Update EditorView with width/height.
    ## The displayed content is as similar as possible to that before the resizing.

    let topLine = view.originalLine[0]

    view.lines = initDeque[Runes]()
    for i in 0..height-1: view.lines.addLast(ru"")

    view.height = height
    view.width = width
    view.widthOfLineNum = widthOfLineNum

    view.originalLine = initDeque[int]()
    for i in 0..height-1: view.originalLine.addLast(-1)
    view.start = initDeque[int]()
    for i in 0..height-1: view.start.addLast(-1)
    view.length = initDeque[int]()
    for i in 0..height-1: view.length.addLast(-1)

    if view.sidebar.isSome:
      view.sidebar.get.resize(Size(h: height, w: view.sidebarWidth))

    view.updated = true
    view.reload(buffer, topLine)

proc scrollUp*[T](view: var EditorView, buffer: T) =
  ## Shift the EditorView display up one line.

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
  ## Shift the EditorView display down one line.

  view.updated = true

  let height = view.height
  view.lines.popFirst
  view.originalLine.popFirst
  view.start.popFirst
  view.length.popFirst

  var originalLine, start: int
  if view.start[height-2]+view.length[height-2] == buffer[view.originalLine[height-2]].len:
    originalLine =
      if view.originalLine[height-2] == -1 or
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

proc writeSidebarLine(view: EditorView, win: var Window, y: int) =
  ## Write one line to a sidebar.
  ## The sidebar displays to the left of the EditorView body.

  let
    line = view.sidebar.get.buffer[y][0 .. view.sidebarWidth - 1]
    highlight = view.sidebar.get.highlights[y]
  for x, r in line:
    win.write(y, x, $r, highlight[x].int16, Attribute.normal, false)

proc writeLineNum(
  view: EditorView,
  win: var Window,
  y, line: int,
  colorPair: EditorColorPairIndex) =

    const
      rightMargin = " "
      storeX = false
    let
      x = view.sidebarWidth
      buffer =
        strutils.align($(line + 1), view.widthOfLineNum - 1) & rightMargin

    win.write(y, x, buffer, colorPair.int16, Attribute.normal, storeX)

proc write(
  view: EditorView,
  win: var Window,
  y, x: int,
  runes: Runes,
  color: EditorColorPairIndex | int16,
  attribute: Attribute = Attribute.normal) {.inline.} =

    # TODO: use settings file
    const tab = "    "
    win.write(y, x, replace($runes, "\t", tab), color.int16, attribute, false)

proc writeCurrentLine(
  win: var Window,
  view: EditorView,
  highlight: Highlight,
  runes: Runes,
  currentLineColorPair: var int,
  y, x, i, last: int) =

    if view.config.isHighlightCurrentLine and not view.editorMode.isVisualMode:

      # Change background color to white if background color is editorBg
      let
        originalColorPair =
          if i >= 0 and i < highlight.len:
            themeColors[highlight[i].color]
          else:
            themeColors[EditorColorPairIndex.default]

        attribute =
          if view.config.isCursorLine: Attribute.underline
          elif i > -1 and i < highlight.len: highlight[i].attribute
          else: Attribute.normal

      # Init colors for the current line buffer
      let
        bufferFg = originalColorPair.foreground

        originalBgRgb = backgroundRgb(EditorColorPairIndex.default)
        bufferBg =
          if originalColorPair.background.rgb == originalBgRgb:
            themeColors[EditorColorPairIndex.currentLineBg].background
          else:
            originalColorPair.background

      # TODO: Return `Result` type.
      discard currentLineColorPair.initColorPair(
        view.config.colorMode,
        bufferFg,
        bufferBg)

      view.write(win, y, x, runes, currentLineColorPair.int16, attribute)

      currentLineColorPair.inc

      # Write spaces after text in the current line
      let
        afterFg = themeColors[EditorColorPairIndex.default].foreground
        afterBg = themeColors[EditorColorPairIndex.currentLineBg].background
      # TODO: Return `Result` type.
      discard currentLineColorPair.initColorPair(
        view.config.colorMode,
        afterFg,
        afterBg)

      let
        spaces = ru" ".repeat(view.width - view.lines[y].width)
        x = view.sidebarWidth + view.widthOfLineNum + view.lines[y].width

      view.write(win, y, x, spaces, currentLineColorPair.int16, attribute)

      currentLineColorPair.inc

    else:
      view.write(win, y, x, runes, highlight[i].color.int16)

proc writeAllLines*[T](
  view: var EditorView,
  win: var Window,
  buffer: T,
  highlight: Highlight,
  currentLine: int,
  currentLineColorPair: var int) =

    win.erase

    view.widthOfLineNum =
      if view.config.isLineNumber: buffer.len.numberOfDigits + 1
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

      if view.sidebar.isSome:
        view.writeSidebarLine(win, y)

      let isCurrentLine = view.originalLine[y] == currentLine
      if view.config.isLineNumber and view.start[y] == 0:
        let lineNumberColor =
          if isCurrentLine and
             view.isCurrentWin and
             view.config.isHighlightCurrentLineNumber:
               EditorColorPairIndex.currentLineNum
           else:
            EditorColorPairIndex.lineNum
        view.writeLineNum(win, y, view.originalLine[y], lineNumberColor)

      var x = view.sidebarWidth + view.widthOfLineNum
      if view.length[y] == 0:
        if view.editorMode.isVisualMode and
           (view.originalLine[y] >= view.selectedRange.first and
           view.selectedRange.last >= view.originalLine[y]):
             view.write(win, y, x, ru" ", EditorColorPairIndex.visualMode)
        else:
          view.write(win, y, x, view.lines[y], EditorColorPairIndex.default)

          if view.config.isHighlightCurrentLine and isCurrentLine and
             currentLine < buffer.len:
               writeCurrentLine(
                 win,
                 view,
                 highlight,
                 ru"",
                 currentLineColorPair,
                 y, x, i, 0)
          else:
            view.write(win, y, x, view.lines[y], EditorColorPairIndex.default)
        continue

      if view.config.isIndentationLines and not view.editorMode.isConfigMode:
        let currentOriginalLine = view.originalLine[y]
        if currentOriginalLine != lastOriginalLine:
          let line =
            if buffer.len() > currentOriginalLine: buffer[currentOriginalLine]
            else: ru""
          lineStart = x
          var numSpaces = 0
          for i in 0..<line.len:
            if line[i] != Rune(' '):
              numSpaces = i+1
              break
            inc numSpaces
          indents = int(numSpaces / view.config.tabStop)
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

          assert(
            last <= view.lines[y].high,
            fmt"last = {lastStr}, view.lines[y] = {lineStr}")
          assert(
            first <= last,
            fmt"first = {first}, last = {last}")

        let str = view.lines[y][first .. last]

        view.write(win, y, x, str, highlight[i].color)
        if isCurrentLine:
          win.writeCurrentLine(
            view,
            highlight,
            str,
            currentLineColorPair,
            y, x, i, last)
        else:
          view.write(
            win,
            y, x,
            str,
            highlight[i].color, highlight[i].attribute)
        x += width(str)
        if last == highlight[i].lastColumn - view.start[y]: inc(i) # consumed a whole segment
        else: break

      if view.config.isIndentationLines:
        # Write indentation lines.
        for i in 0 ..< indents:
          view.write(
            win,
            y, lineStart + (view.config.tabStop * i),
            ru("┊"),
            EditorColorPairIndex.whitespace)

proc update*[T](
  view: var EditorView,
  win: var Window,
  buffer: T,
  highlight: Highlight,
  currentLine: int,
  currentLineColorPair: var int) =

    let widthOfLineNum = buffer.len.intToStr.len + 1
    if view.config.isLineNumber and widthOfLineNum != view.widthOfLineNum:
      view.resize(
        buffer,
        view.height,
        view.width + view.widthOfLineNum - widthOfLineNum,
        widthOfLineNum)

    view.writeAllLines(
      win,
      buffer,
      highlight,
      currentLine,
      currentLineColorPair)

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

proc rangeOfOriginalLineInView*(view: EditorView): Range =
  var
    firstLine = 0
    lastLine = 0
  for index, lineNum in view.originalLine:
    if index == 0: firstLine = lineNum
    elif lineNum == -1: break
    else: lastLine = lineNum

  return Range(first: firstLine, last: lastLine)

proc firstOriginLine*(view: EditorView): int {.inline.} =
  ## Return the first original line number in EditorView.originalLine.
  return view.originalLine[0]

proc lastOriginLine*(view: EditorView): int =
  ## Return the last original line number in EditorView.originalLine.

  if view.originalLine[^1] == -1:
    for index, lineNum in view.originalLine:
      if lineNum == -1:
        return index - 1
  else:
    return view.originalLine[^1]

proc updateSidebarBufferForChangedLine*(
  view: var EditorView,
  changedLines: seq[Diff]) =
    ## Update (Overwrite) a sidebar buffer for git diff. It's on left side of EditorView.

    template buffer: var seq[Runes] = view.sidebar.get.buffer
    template highlights: var seq[seq[EditorColorPairIndex]] =
      view.sidebar.get.highlights

    proc inRange(v: EditorView, d: Diff): bool =
      case d.operation:
        of deleted, changedAndDeleted:
          # Only use the firstline.
          v.firstOriginLine <= d.firstLine
        else:
          v.firstOriginLine <= d.firstLine or v.firstOriginLine <= d.lastLine

    # 2 or more width required.
    if view.sidebar.get.buffer.len < 2: return

    for d in changedLines:
      if view.inRange(d):
        for y, lineNum in view.originalLine:
          case d.operation:
            of deleted:
              # Only use the firstLine.
              if lineNum >= d.firstLine and lineNum <= d.firstLine:
                buffer[y] = ru"_ "
                highlights[y] = EditorColorPairIndex.sidebarGitDeletedSign.repeat(
                 2)
            of changedAndDeleted:
              # Only use the firstLine.
              if lineNum >= d.firstLine and lineNum <= d.firstLine:
                buffer[y] = ru"~_"
                highlights[y] = EditorColorPairIndex.sidebarGitChangedSign.repeat(
                  2)
            of changed:
              if lineNum >= d.firstLine and lineNum <= d.lastLine:
                buffer[y] = ru"~ "
                highlights[y] = EditorColorPairIndex.sidebarGitChangedSign.repeat(
                  2)
            of OperationType.added:
              if lineNum >= d.firstLine and lineNum <= d.lastLine:
                buffer[y] = ru"+ "
                highlights[y] = EditorColorPairIndex.sidebarGitAddedSign.repeat(
                  2)

proc updateSidebarBufferForSyntaxChecker*(
  view: var EditorView,
  syntaxCheckResults: seq[SyntaxError]) =
    ## Update (Overwrite) a sidebar buffer for syntax checker reuslts.
    ## It's on left side of EditorView.

    template highlights: var seq[seq[EditorColorPairIndex]] =
      view.sidebar.get.highlights

    proc inRange(v: EditorView, se: SyntaxError): bool {.inline.} =
      v.firstOriginLine <= se.position.line and
      v.lastOriginLine >= se.position.line

    # 2 or more width required.
    if view.sidebar.get.buffer.len < 2: return

    for syntaxErr in syntaxCheckResults:
      if view.inRange(syntaxErr):
        let y = max(syntaxErr.position.line - view.firstOriginLine, 0)
        case syntaxErr.messageType:
          of SyntaxCheckMessageType.info:
            view.sidebar.get.buffer[y] = ru"⚠ "
            highlights[y] =
              EditorColorPairIndex.sidebarSyntaxCheckWarnSign.repeat(2)
          of SyntaxCheckMessageType.hint:
            view.sidebar.get.buffer[y] = ru"⚠ "
            highlights[y] =
              EditorColorPairIndex.sidebarSyntaxCheckWarnSign.repeat(2)
          of SyntaxCheckMessageType.warning:
            view.sidebar.get.buffer[y] = ru"⚠ "
            highlights[y] =
              EditorColorPairIndex.sidebarSyntaxCheckWarnSign.repeat(2)
          of SyntaxCheckMessageType.error:
            view.sidebar.get.buffer[y] = ru">>"
            highlights[y] =
              EditorColorPairIndex.sidebarSyntaxCheckErrSign.repeat(2)
