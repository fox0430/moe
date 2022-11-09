import std/options

import editorstatus
import ui
import movement
import editor
import bufferstatus
import gapbuffer
import window
import settings
import unicodeext

# For undo/redo in the replace mode.
var undoLastSuitId: Option[int]

proc moveRight(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  bufStatus.keyRight(windowNode)

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    undoLastSuitId = some(bufStatus.buffer.lastSuitId)

proc moveLeft(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  windowNode.keyLeft

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    undoLastSuitId = some(bufStatus.buffer.lastSuitId)

proc moveUp(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  bufStatus.keyUp(windowNode)

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    undoLastSuitId = some(bufStatus.buffer.lastSuitId)

proc moveDown(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  bufStatus.keyDown(windowNode)

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    undoLastSuitId = some(bufStatus.buffer.lastSuitId)

# Repace the current chracter or insert the character and move to the right
proc replaceCurrentCharacter(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  settings: EditorSettings,
  key: Rune) =

    if windowNode.currentColumn < bufStatus.buffer[windowNode.currentLine].len:
      let
        currentLine = windowNode.currentLine
        currentColumn = windowNode.currentColumn
        oldLine = bufStatus.buffer[currentLine]
      var newLine = bufStatus.buffer[currentLine]
      newLine[currentColumn] = key

      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    else:
      insertCharacter(bufStatus, windowNode, settings.autoCloseParen, key)

    bufStatus.keyRight(windowNode)

proc undoOrMoveCursor(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  # Can undo until you enter Replace mode
  # Do not undo if the cursor is moved and re-enable undo if the character is replaced
  if bufStatus.buffer.lastSuitId > undoLastSuitId.get:
    bufStatus.undo(windowNode)
  else:
    if windowNode.currentColumn == 0 and
       windowNode.currentLine > 0:
      # Jump to the end of the above line
      bufStatus.keyUp(windowNode)
      bufStatus.moveToLastOfLine(windowNode)
    else:
      # Move to left once
      windowNode.keyLeft

proc isReplaceModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if pressCtrlC or command.len == 1:
    return InputState.Valid

# TODO: Fix replace mode
proc execReplaceModeCommand*(status: var EditorStatus, command: Runes) =
  if undoLastSuitId.isNone:
    # Init undo/redo history for the replace mode.
    undoLastSuitId = some(currentBufStatus.buffer.lastSuitId)

  let key = command[0]

  if isControlC(key) or isEscKey(key) or isControlSquareBracketsRight(key):
    undoLastSuitId = none(int)
    status.changeMode(currentBufStatus.prevMode)
  elif isRightKey(key):
    currentBufStatus.moveRight(currentMainWindowNode)
  elif isLeftKey(key):
    currentBufStatus.moveLeft(currentMainWindowNode)
  elif isUpKey(key):
    currentBufStatus.moveUp(currentMainWindowNode)
  elif isDownKey(key):
    currentBufStatus.moveDown(currentMainWindowNode)
  elif isEnterKey(key):
    currentBufStatus.keyEnter(
      currentMainWindowNode,
      status.settings.autoIndent,
      status.settings.tabStop)

  elif isBackspaceKey(key):
    currentBufStatus.undoOrMoveCursor(currentMainWindowNode)
  else:
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      key)
