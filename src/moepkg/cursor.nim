import deques
import editorview

type CursorPosition* = object
  y*, x*: int

proc updatePosition(cursor: var CursorPosition, view: EditorView, line, column: int) =
  for y in 0..view.height-1:
    if view.originalLine[y] != line: continue
    if view.start[y] <= column and column < view.start[y]+view.length[y]:
      cursor.y = y
      cursor.x = column-view.start[y]
      return
    if (y == view.height-1 or view.originalLine[y] != view.originalLine[y+1]) and view.start[y]+view.length[y] == column:
      cursor.y = y
      cursor.x = column-view.start[y]
      if cursor.x == view.width:
        inc(cursor.y)
        cursor.x = 0
      return
  doAssert(false, "Failed to update cursorPosition")

proc update*(cursor: var CursorPosition, view: EditorView, line, column: int) =
  cursor.updatePosition(view, line, column)
