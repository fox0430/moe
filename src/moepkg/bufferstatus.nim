import std/[tables, times, options, os]
import syntax/highlite
import gapbuffer, unicodeext, fileutils, highlight

type
  Mode* = enum
    normal
    insert
    visual
    visualBlock
    replace
    ex
    filer
    bufManager
    logViewer
    help
    recentFile
    quickRun
    backup
    diff
    config
    debug
    searchForward
    searchBackward

  SelectArea* = object
    startLine*: int
    startColumn*: int
    endLine*: int
    endColumn*: int

  BufferStatus* = object
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

proc isExMode*(mode: Mode): bool = mode == Mode.ex

proc isExMode*(b: BufferStatus): bool {.inline.} = b.mode == Mode.ex

proc isVisualMode*(mode: Mode): bool =
  mode == Mode.visual or mode == Mode.visualBlock

proc isVisualMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.visual or b.mode == Mode.visualBlock

proc isFilerMode*(mode: Mode): bool = mode == Mode.filer

proc isFilerMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.filer or
  (b.isExMode and b.prevMode == Mode.filer)

proc isFilerMode*(mode, prevMode: Mode): bool =
  (mode == Mode.filer) or (mode == Mode.ex and prevMode == Mode.filer)

proc isBackupManagerMode*(mode, prevMode: Mode): bool =
  (mode == Mode.backup) or (mode == Mode.ex and prevMode == Mode.backup)

proc isBackupManagerMode*(bufStatus: BufferStatus): bool {.inline.} =
  (bufStatus.mode == Mode.backup) or
  (bufStatus.mode == Mode.ex and bufStatus.prevMode == Mode.backup)

proc isDiffViewerMode*(mode, prevMode: Mode): bool =
  (mode == Mode.diff) or (mode == Mode.ex and prevMode == Mode.diff)

proc isDiffViewerMode*(bufStatus: BufferStatus): bool {.inline.} =
  (bufStatus.mode == Mode.diff) or
  (bufStatus.mode == Mode.ex and bufStatus.prevMode == Mode.diff)

proc isConfigMode*(mode, prevMode: Mode): bool =
  (mode == Mode.config) or (mode == Mode.ex and prevMode == Mode.config)

proc isConfigMode*(b: BufferStatus): bool {.inline.} =
  (b.mode == Mode.config) or
  (b.isExMode and b.prevMode == Mode.config)

proc isSearchForwardMode*(mode: Mode): bool =
  mode == Mode.searchForward

proc isSearchForwardMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.searchForward

proc isSearchBackwardMode*(mode: Mode): bool =
  mode == Mode.searchBackward

proc isSearchBackwardMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.searchBackward

proc isSearchMode*(mode: Mode): bool =
  isSearchForwardMode(mode) or isSearchBackwardMode(mode)

proc isSearchMode*(b: BufferStatus): bool {.inline.} =
  b.isSearchForwardMode or b.isSearchBackwardMode

proc isNormalMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.normal) or
  (mode.isExMode and prevMode == Mode.normal) or
  (mode.isSearchMode and prevMode == Mode.normal)

proc isNormalMode*(b: BufferStatus): bool {.inline.} =
  (b.mode == Mode.normal) or
  (b.isExMode and b.prevMode == Mode.normal) or
  (b.isSearchMode and b.prevMode == Mode.normal)

proc isInsertMode*(mode: Mode): bool = mode == Mode.insert

proc isInsertMode*(b: BufferStatus): bool {.inline.} = b.mode == Mode.insert

proc isReplaceMode*(mode: Mode): bool = mode == Mode.replace

proc isReplaceMode*(b: BufferStatus): bool {.inline.} = b.mode == Mode.replace

proc isDebugMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.debug) or
  (mode == Mode.ex and prevMode == Mode.debug)

proc isDebugMode*(b: BufferStatus): bool {.inline.} =
  (b.mode == Mode.debug) or (b.isExMode and b.prevMode == Mode.debug)

proc isQuickRunMode*(mode: Mode): bool = mode == Mode.quickRun

proc isQuickRunMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.quickRun

proc isLogViewerMode*(mode: Mode): bool = mode == Mode.logViewer

proc isLogViewerMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.logViewer

proc isBufferManagerMode*(mode: Mode): bool = mode == Mode.bufManager

proc isBufferManagerMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.bufManager

proc isVisualBlockMode*(mode: Mode): bool = mode == Mode.visualBlock

proc isVisualBlockMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.visualBlock

# Modes for editing text
proc isEditMode*(mode, prevMode: Mode): bool =
  isNormalMode(mode, prevMode) or
  isInsertMode(mode) or
  isVisualMode(mode) or
  isReplaceMode(mode)

# Modes for editing text
proc isEditMode*(b: BufferStatus): bool {.inline.} =
  b.isNormalMode or
  b.isInsertMode or
  b.isVisualMode or
  b.isReplaceMode

proc checkBufferExist*(
  bufStatus: seq[BufferStatus],
  path: Runes): Option[int] =
    for index, buf in bufStatus:
      if buf.path == path:
        return some(index)

proc absolutePath*(bufStatus: BufferStatus): Runes =
  if isAbsolute($bufStatus.path):
    bufStatus.path
  else:
    bufStatus.openDir / bufStatus.path

proc initBufferStatus*(
  path: string,
  mode: Mode): BufferStatus {.raises: [IOError, OSError, ValueError].} =

    result.isUpdate = true
    result.openDir = getCurrentDir().toRunes
    result.mode = mode
    result.lastSaveTime = now()

    if isFilerMode(result.mode):
      result.path = absolutePath(path).toRunes
      result.buffer = initGapBuffer(@[ru ""])
    else:
      result.path = path.toRunes

      if not fileExists($result.path):
        result.buffer = newFile()
      else:
        let textAndEncoding = openFile(result.path)
        result.buffer = textAndEncoding.text.toGapBuffer
        result.characterEncoding = textAndEncoding.encoding

      result.language = detectLanguage($result.path)

proc initBufferStatus*(
  mode: Mode): BufferStatus {.raises: [OSError].} =

    result.isUpdate = true
    result.openDir = getCurrentDir().toRunes
    result.mode = mode
    result.lastSaveTime = now()

    result.path = "".toRunes
    result.path = "".toRunes

    if mode.isFilerMode:
      result.buffer = initGapBuffer(@[ru ""])
    else:
      result.buffer = newFile()

proc initBufferStatus*(
  p: string): BufferStatus {.inline, raises: [IOError, OSError, ValueError].} =
    initBufferStatus(p, Mode.normal)

proc changeMode*(bufStatus: var BufferStatus, mode: Mode) =
  let currentMode = bufStatus.mode

  bufStatus.prevMode = currentMode
  bufStatus.mode = mode
