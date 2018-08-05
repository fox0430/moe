import deques
import editorview, unicodeext

type CursorPosition* = object
  y*, x*: int

proc updatePosition(cursor: var CursorPosition, view: EditorView, line, column: int) =
  for y in 0..view.height-1:
    if view.originalLine[y] != line: continue
    if view.start[y] <= column and column < view.start[y]+view.length[y]:
      cursor.y = y
      cursor.x = if view.start[y] == column: 0 else: width(view.lines[y][0 .. column-view.start[y]-1])
      return
    if (y == view.height-1 or view.originalLine[y] != view.originalLine[y+1]) and view.start[y]+view.length[y] == column:
      cursor.y = y
      cursor.x = if view.start[y] == column: 0 else: width(view.lines[y][0 .. column-view.start[y]-1])
      if cursor.x == view.width:
        inc(cursor.y)
        cursor.x = 0
      return
  doAssert(false, "Failed to update cursorPosition")

proc update*(cursor: var CursorPosition, view: EditorView, line, column: int) =
  cursor.updatePosition(view, line, column)
