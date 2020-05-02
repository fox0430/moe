import packages/docutils/highlite, tables, times
import gapbuffer, unicodeext

type Mode* = enum
  normal, insert, visual, visualBlock, replace, ex, filer, search, bufManager, logViewer

type SelectArea* = object
  startLine*: int
  startColumn*: int
  endLine*: int
  endColumn*: int

type BufferStatus* = object
  buffer*: GapBuffer[seq[Rune]]
  language*: SourceLanguage
  selectArea*: SelectArea
  isHighlight*: bool
  filename*: seq[Rune]
  openDir: seq[Rune]
  positionRecord*: Table[int, tuple[line, column, expandedColumn: int]]
  countChange*: int
  cmdLoop*: int
  mode* : Mode
  prevMode* : Mode
  lastSaveTime*: DateTime
