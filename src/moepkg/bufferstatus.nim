import highlite, tables, times
import gapbuffer, unicodeext

type Mode* = enum
  normal,
  insert,
  visual,
  visualBlock,
  replace,
  ex,
  filer,
  bufManager,
  logViewer,
  help,
  recentFile,
  quickRun,
  history,
  diff

type SelectArea* = object
  startLine*: int
  startColumn*: int
  endLine*: int
  endColumn*: int

type BufferStatus* = object
  buffer*: GapBuffer[seq[Rune]]
  language*: SourceLanguage
  selectArea*: SelectArea
  isSearchHighlight*: bool
  path*: seq[Rune]
  openDir: seq[Rune]
  positionRecord*: Table[int, tuple[line, column, expandedColumn: int]]
  countChange*: int
  cmdLoop*: int
  mode* : Mode
  prevMode* : Mode
  lastSaveTime*: DateTime

proc isFilerMode*(mode, prevMode: Mode): bool =
  (mode == Mode.filer) or (mode == Mode.ex and prevMode == Mode.filer)

proc isHistoryManagerMode*(mode, prevMode: Mode): bool =
  (mode == Mode.history) or (mode == Mode.ex and prevMode == Mode.history)

proc isDiffViewerMode*(mode, prevMode: Mode): bool =
  (mode == Mode.diff) or (mode == ex and prevMode == Mode.diff)
