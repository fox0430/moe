import editorview

type CursorPosition* = object
  y*, x*: int
  updated*: bool

proc updatePosition(cursor: var CursorPosition, view: EditorView, line, column: int) =
  for y in 0..high(view.height):
    if view.originalLine[y] != line: continue
    if view.start[y] <= column and column < view.start[y]+view.length[y]:
      cursor.y = y
      cursor.x = x = column-view.start[y]
      return
    if (y == view.height-1 || view.originalLine[y] != view.originalLine[y+1]) and view.start[y]+view.length[y] == column
      cursor.y = y
      cursor.x = column-view.start[y]
      if cursor.x == view.width:
        inc(cursor.y)
        cursor.x = 0
      return
  doAssert(false, "Failed to update cursorPosition")

proc update*(cursor: var CursorPosition, view: EditorView, line, column: int) =
  if not cursor.updated: return
  cursor.updatePosition(view, line, column)
  cursor.updated = false
