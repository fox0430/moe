import deques, strformat
import editorview, unicodetext

type CursorPosition* = object
  y*, x*: int

proc findCursorPosition*(view: EditorView,
                         line, column: int): tuple[success: bool, y, x: int] =

  for y in 0..view.height-1:
    if view.originalLine[y] != line: continue
    if view.start[y] <= column and column < view.start[y]+view.length[y]:
      let x = if view.start[y] == column: 0
              else: width(view.lines[y][0 .. column-view.start[y]-1])
      return (true, y, x)
    if (y == view.height-1 or view.originalLine[y] != view.originalLine[y+1]) and
        view.start[y]+view.length[y] == column:
      var cursorY, cursorX: int
      cursorY = y
      cursorX = if view.start[y] == column: 0
                else: width(view.lines[y][0 .. column-view.start[y]-1])
      if cursorX == view.width:
        inc(cursorY)
        cursorX = 0
      return (true, cursorY, cursorX)

proc updatePosition(cursor: var CursorPosition,
                    view: EditorView,
                    line, column: int) =
  var success: bool
  let mess = fmt"Failed to update cursorPosition: (y, x) = ({line}, {column}), originalLine = {view.originalLine}, start = {view.start}, length = {view.length}, lines = {view.lines}, height = {view.height}, width = {view.width}"
  (success, cursor.y, cursor.x) = findCursorPosition(view, line, column)
  doAssert(success, mess)

proc update*(cursor: var CursorPosition, view: EditorView, line, column: int) {.inline.} =
  cursor.updatePosition(view, line, column)
