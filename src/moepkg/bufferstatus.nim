import packages/docutils/highlite, tables, times
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
  recentFile

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
  filename*: seq[Rune]
  openDir: seq[Rune]
  positionRecord*: Table[int, tuple[line, column, expandedColumn: int]]
  countChange*: int
  cmdLoop*: int
  mode* : Mode
  prevMode* : Mode
  lastSaveTime*: DateTime
