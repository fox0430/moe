import std/[tables, times, options]
import syntax/highlite
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
  diff,
  config,
  debug

type SelectArea* = object
  startLine*: int
  startColumn*: int
  endLine*: int
  endColumn*: int

type BufferStatus* = object
  buffer*: GapBuffer[seq[Rune]]
  isUpdate*: bool
  characterEncoding*: CharacterEncoding
  language*: SourceLanguage
  selectArea*: SelectArea
  path*: seq[Rune]
  openDir*: seq[Rune]
  positionRecord*: Table[int, tuple[line, column, expandedColumn: int]]
  countChange*: int
  cmdLoop*: int
  mode* : Mode
  prevMode* : Mode
  lastSaveTime*: DateTime
  isReadonly*: bool

proc initBufferStatus*(path: seq[Rune], mode: Mode): BufferStatus {.inline.} =
  BufferStatus(isUpdate: true, path: path, mode: mode, lastSaveTime: now())

proc isVisualMode*(mode: Mode): bool {.inline.} =
  mode == Mode.visual or mode == Mode.visualBlock

proc isFilerMode*(mode: Mode): bool {.inline.} = mode == Mode.filer

proc isFilerMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.filer) or (mode == Mode.ex and prevMode == Mode.filer)

proc isHistoryManagerMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.history) or (mode == Mode.ex and prevMode == Mode.history)

proc isDiffViewerMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.diff) or (mode == Mode.ex and prevMode == Mode.diff)

proc isConfigMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.config) or (mode == Mode.ex and prevMode == Mode.config)

proc isNormalMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.normal) or (mode == Mode.ex and prevMode == Mode.normal)

proc isInsertMode*(mode: Mode): bool {.inline.} = mode == Mode.insert

proc isReplaceMode*(mode: Mode): bool {.inline.} = mode == Mode.replace

proc isDebugMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.debug) or (mode == Mode.ex and prevMode == Mode.debug)

proc isQuickRunMode*(mode: Mode): bool {.inline.} = mode == Mode.quickRun

proc isLogViewerMode*(mode: Mode): bool {.inline.} = mode == Mode.logViewer

proc isBufferManagerMode*(mode: Mode): bool {.inline.} = mode == Mode.bufManager

proc isVisualBlockMode*(mode: Mode): bool {.inline.} = mode == Mode.visualBlock

proc checkBufferExist*(bufStatus: seq[BufferStatus], path: seq[Rune]): Option[int] =
  for index, buf in bufStatus:
    if buf.path == path:
      return some(index)
