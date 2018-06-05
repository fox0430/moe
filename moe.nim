import ncurses, posix, system, os

proc startCurses() =
  discard setLocale(LC_ALL, "")
  initscr()
  cbreak()
  curs_set(1)

proc exitCurses() =
  endwin()
  quit()
  
if isMainModule:
  startCurses()
  if paramCount() = 0:
  else:
