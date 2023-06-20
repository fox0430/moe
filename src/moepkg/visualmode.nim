#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[strutils, sequtils]
import editorstatus, ui, gapbuffer, unicodeext, windownode, movement, editor,
       bufferstatus, settings, register, messages, commandline,
       independentutils, viewhighlight

proc initSelectedArea*(startLine, startColumn: int): SelectedArea =
  result.startLine = startLine
  result.startColumn = startColumn
  result.endLine = startLine
  result.endColumn = startColumn

proc updateSelectedArea*(
  area: var SelectedArea,
  currentLine, currentColumn: int) {.inline.} =

    area.endLine = currentLine
    area.endColumn = currentColumn

proc swapSelectedArea*(area: var SelectedArea) =
  if area.startLine == area.endLine:
    if area.endColumn < area.startColumn:
      swap(area.startColumn, area.endColumn)
  elif area.endLine < area.startLine:
    swap(area.startLine, area.endLine)
    swap(area.startColumn, area.endColumn)

proc swapSelectedAreaVisualLine(
  area: var SelectedArea,
  bufStatus: BufferStatus) =

    if area.endLine < area.startLine:
      swap(area.startLine, area.endLine)

    area.startColumn = 0
    area.endColumn =
      if bufStatus.buffer[area.endLine].high > 0:
        bufStatus.buffer[area.endLine].high
      else:
        0

proc yankBuffer(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  area: SelectedArea,
  settings: EditorSettings) =

    var
      yankedBuffer: seq[seq[Rune]]
      isLine = true

    if area.startLine == area.endLine:
      if bufStatus.buffer[windowNode.currentLine].len < 1:
          # Yank the empty string if the empty line
          yankedBuffer.add(@[ru ""])
      else:
        # Yank the text in the line.
        isLine = false
        var runes = ru ""
        let
          endColumn =
            if area.endColumn > bufStatus.buffer[area.startLine].high:
              bufStatus.buffer[area.startLine].high
            else:
              area.endColumn
        for j in area.startColumn .. endColumn:
          runes.add(bufStatus.buffer[area.startLine][j])
        yankedBuffer = @[runes]
    else:
      for i in area.startLine .. area.endLine:
        if i == area.startLine and area.startColumn > 0:
          yankedBuffer.add(ru"")
          for j in area.startColumn ..< bufStatus.buffer[area.startLine].len:
            yankedBuffer[^1].add(bufStatus.buffer[area.startLine][j])
        elif i == area.endLine and
             area.endColumn < bufStatus.buffer[area.endLine].len:
          yankedBuffer.add(ru"")
          for j in 0 .. area.endColumn:
            yankedBuffer[^1].add(bufStatus.buffer[area.endLine][j])
        else:
          yankedBuffer.add(bufStatus.buffer[i])

    registers.addRegister(yankedBuffer, isLine, settings)

proc yankBufferBlock(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  area: SelectedArea,
  settings: EditorSettings) =

    if bufStatus.buffer.len == 1 and
       bufStatus.buffer[windowNode.currentLine].len < 1: return

    var yankedBuffer: seq[seq[Rune]]

    for i in area.startLine .. area.endLine:
      yankedBuffer.add(@[ru ""])
      for j in area.startColumn .. min(bufStatus.buffer[i].high, area.endColumn):
        yankedBuffer[^1].add(bufStatus.buffer[i][j])

    registers.addRegister(yankedBuffer, settings)

proc deleteBuffer(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  area: SelectedArea,
  settings: EditorSettings,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    if bufStatus.buffer.len == 1 and
       bufStatus.buffer[windowNode.currentLine].len < 1: return

    bufStatus.yankBuffer(registers, windowNode, area, settings)

    var currentLine = area.startLine
    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[currentLine]
      var newLine = bufStatus.buffer[currentLine]

      if area.startLine == area.endLine:
        if area.endColumn == bufStatus.buffer[area.startLine].len or
           bufStatus.isVisualLineMode:
             # Delete the single line
             bufStatus.buffer.delete(currentLine, currentLine)
        elif oldLine.len > 0:
          # Delete the text in the line.
          for j in area.startColumn .. area.endColumn:
            newLine.delete(area.startColumn)
          if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
        else:
          # Delete the single char
          bufStatus.buffer.delete(currentLine, currentLine)
      elif i == area.startLine and 0 < area.startColumn:
        for j in area.startColumn .. bufStatus.buffer[currentLine].high:
          newLine.delete(area.startColumn)
        if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
        inc(currentLine)
      elif i == area.endLine and area.endColumn < bufStatus.buffer[currentLine].high:
        for j in 0 .. area.endColumn: newLine.delete(0)
        if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
      else: bufStatus.buffer.delete(currentLine, currentLine)

    if bufStatus.buffer.len < 1: bufStatus.buffer.add(ru"")

    if area.startLine > bufStatus.buffer.high:
      windowNode.currentLine = bufStatus.buffer.high
    else: windowNode.currentLine = area.startLine
    let column = if bufStatus.buffer[currentLine].high > area.startColumn:
                   area.startColumn
                 elif area.startColumn > 0:
                   area.startColumn - 1
                 else: 0

    windowNode.currentColumn = column
    windowNode.expandedColumn = column

    inc(bufStatus.countChange)

    bufStatus.isUpdate = true

proc deleteBufferBlock(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  area: SelectedArea,
  settings: EditorSettings,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    if bufStatus.buffer.len == 1 and
       bufStatus.buffer[windowNode.currentLine].len < 1: return
    bufStatus.yankBufferBlock(registers,
                              windowNode,
                              area,
                              settings)

    if area.startLine == area.endLine and bufStatus.buffer[area.startLine].len < 1:
      bufStatus.buffer.delete(area.startLine, area.startLine + 1)
    else:
      var currentLine = area.startLine
      for i in area.startLine .. area.endLine:
        let oldLine = bufStatus.buffer[i]
        var newLine = bufStatus.buffer[i]
        for j in area.startColumn.. min(area.endColumn, bufStatus.buffer[i].high):
          newLine.delete(area.startColumn)
          inc(currentLine)
        if oldLine != newLine: bufStatus.buffer[i] = newLine

    windowNode.currentLine = min(area.startLine, bufStatus.buffer.high)
    windowNode.currentColumn = area.startColumn

    inc(bufStatus.countChange)

    bufStatus.isUpdate = true

proc addIndent(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  area: SelectedArea,
  tabStop: int,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    windowNode.currentLine = area.startLine
    for i in area.startLine .. area.endLine:
      bufStatus.indent(windowNode, tabStop)
      inc(windowNode.currentLine)

    windowNode.currentLine = area.startLine

proc deleteIndent(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  area: SelectedArea,
  tabStop: int,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    windowNode.currentLine = area.startLine
    for i in area.startLine .. area.endLine:
      bufStatus.unindent(windowNode, tabStop)
      inc(windowNode.currentLine)

    windowNode.currentLine = area.startLine

proc insertIndent(
  bufStatus: var BufferStatus,
  area: SelectedArea,
  tabStop: int,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      newLine.insert(ru' '.repeat(tabStop),
                     min(area.startColumn,
                     bufStatus.buffer[i].high))
      if oldLine != newLine: bufStatus.buffer[i] = newLine

proc replaceCharacter(
  bufStatus: var BufferStatus,
  area: SelectedArea,
  ch: Rune,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      if area.startLine == area.endLine:
        for j in area.startColumn .. area.endColumn: newLine[j] = ch
      elif i == area.startLine:
        for j in area.startColumn .. bufStatus.buffer[i].high: newLine[j] = ch
      elif i == area.endLine:
        for j in 0 .. area.endColumn: newLine[j] = ch
      else:
        for j in 0 .. bufStatus.buffer[i].high: newLine[j] = ch
      if oldLine != newLine: bufStatus.buffer[i] = newLine

    inc(bufStatus.countChange)

proc replaceCharacterBlock(
  bufStatus: var BufferStatus,
  area: SelectedArea,
  ch: Rune,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high):
        newLine[j] = ch
      if oldLine != newLine: bufStatus.buffer[i] = newLine

proc joinLines(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  area: SelectedArea,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      windowNode.currentLine = area.startLine
      bufStatus.joinLine(windowNode)

proc toLowerString(
  bufStatus: var BufferStatus,
  area: SelectedArea,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      if oldLine.len == 0: discard
      elif area.startLine == area.endLine:
        for j in area.startColumn .. area.endColumn:
          newLine[j] = oldLine[j].toLower
      elif i == area.startLine:
        for j in area.startColumn .. bufStatus.buffer[i].high:
          newLine[j] = oldLine[j].toLower
      elif i == area.endLine:
        for j in 0 .. area.endColumn: newLine[j] = oldLine[j].toLower
      else:
        for j in 0 .. bufStatus.buffer[i].high: newLine[j] = oldLine[j].toLower
      if oldLine != newLine: bufStatus.buffer[i] = newLine

    inc(bufStatus.countChange)

proc toLowerStringBlock(
  bufStatus: var BufferStatus,
  area: SelectedArea,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high):
        newLine[j] = oldLine[j].toLower
      if oldLine != newLine: bufStatus.buffer[i] = newLine

proc toUpperString(
  bufStatus: var BufferStatus,
  area: SelectedArea,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      if oldLine.len == 0: discard
      elif area.startLine == area.endLine:
        for j in area.startColumn .. area.endColumn:
          newLine[j] = oldLine[j].toUpper
      elif i == area.startLine:
        for j in area.startColumn .. bufStatus.buffer[i].high:
          newLine[j] = oldLine[j].toUpper
      elif i == area.endLine:
        for j in 0 .. area.endColumn: newLine[j] = oldLine[j].toUpper
      else:
        for j in 0 .. bufStatus.buffer[i].high: newLine[j] = oldLine[j].toUpper
      if oldLine != newLine: bufStatus.buffer[i] = newLine

    inc(bufStatus.countChange)

proc toUpperStringBlock(
  bufStatus: var BufferStatus,
  area: SelectedArea,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high):
        newLine[j] = oldLine[j].toUpper
      if oldLine != newLine: bufStatus.buffer[i] = newLine

# TODO: Remove
proc getInsertBuffer(status: var EditorStatus): seq[Rune] =
  while true:
    status.update

    var key = ERR_KEY
    while key == ERR_KEY:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    if isEscKey(key):
      break
    if isResizeKey(key):
      status.resize
    elif isEnterKey(key):
      currentBufStatus.keyEnter(
        currentMainWindowNode,
        status.settings.autoIndent,
        status.settings.tabStop)
      break
    elif isDcKey(key):
      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn,
        status.settings.autoDeleteParen)
      break
    elif isBackspaceKey(key):
      currentBufStatus.keyBackspace(
        currentMainWindowNode,
        status.settings.autoDeleteParen,
        status.settings.tabStop)
      if result.len > 0:
        result.delete(result.high)
    elif isTabKey(key):
      result.add(key)
      insertTab(currentBufStatus,
                currentMainWindowNode,
                status.settings.tabStop,
                status.settings.autoCloseParen)
    else:
      result.add(key)
      currentBufStatus.insertCharacter(
        currentMainWindowNode,
        status.settings.autoCloseParen,
        key)

proc enterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    currentMainWindowNode.currentLine = currentBufStatus.selectedArea.startLine
    currentMainWindowNode.currentColumn = 0
    status.changeMode(Mode.insert)

proc insertCharBlock(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  insertBuffer: seq[Rune],
  area: SelectedArea,
  tabStop: int,
  autoCloseParen: bool,
  commandLine: var CommandLine) =

    if bufStatus.isReadonly:
      commandLine.writeReadonlyModeWarning
      return

    if area.startLine == area.endLine: return

    let beforeLine = windowNode.currentLine

    for i in area.startLine + 1 .. area.endLine:
      windowNode.currentLine = i
      windowNode.currentColumn = area.startColumn

      if bufStatus.buffer[i].high >= area.startColumn:
        for c in insertBuffer:
          if isTabKey(c):
            insertTab(bufStatus,
                      windowNode,
                      tabStop,
                      autoCloseParen)
          else:
            bufStatus.insertCharacter(windowNode,
                                      autoCloseParen,
                                      c)
    windowNode.currentLine = beforeLine

proc changeModeToNormalMode(status: var EditorStatus) =
  setBlinkingBlockCursor()
  status.changeMode(Mode.normal)

proc exitVisualMode(status: var EditorStatus) =
    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings,
      status.colorMode)

    status.changeModeToNormalMode

proc visualCommand(
  status: var EditorStatus,
  area: var SelectedArea, key: Rune) =

    if currentBufStatus.isVisualLineMode:
      area.swapSelectedAreaVisualLine(currentBufStatus)
    else:
      area.swapSelectedArea

    if key == ord('y') or isDcKey(key):
      currentBufStatus.yankBuffer(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings)
    elif key == ord('x') or key == ord('d'):
      currentBufStatus.deleteBuffer(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings,
        status.commandLine)
    elif key == ord('>'):
      currentBufStatus.addIndent(
        currentMainWindowNode,
        area,
        status.settings.tabStop,
        status.commandLine)
    elif key == ord('<'):
      currentBufStatus.deleteIndent(
        currentMainWindowNode,
        area,
        status.settings.tabStop,
        status.commandLine)
    elif key == ord('J'):
      currentBufStatus.joinLines(currentMainWindowNode, area, status.commandLine)
    elif key == ord('u'):
      currentBufStatus.toLowerString(area, status.commandLine)
    elif key == ord('U'):
      currentBufStatus.toUpperString(area, status.commandLine)
    elif key == ord('r'):
      let ch = currentMainWindowNode.getKey
      if not isEscKey(ch):
        currentBufStatus.replaceCharacter(area, ch, status.commandLine)
    elif key == ord('I'):
      status.enterInsertMode

    if currentBufStatus.isVisualMode:
      status.changeMode(currentBufStatus.prevMode)

proc insertCharacterMultipleLines(
  status: var EditorStatus,
  area: SelectedArea) =

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    let prevMode =  currentBufStatus.prevMode

    currentBufStatus.changeMode(Mode.insert)

    currentMainWindowNode.currentLine = area.startLine
    currentMainWindowNode.currentColumn = area.startColumn
    let insertBuffer = status.getInsertBuffer

    if insertBuffer.len > 0:
      currentBufStatus.insertCharBlock(
        currentMainWindowNode,
        insertBuffer,
        area,
        status.settings.tabStop,
        status.settings.autoCloseParen,
        status.commandLine)
    else:
      currentMainWindowNode.currentLine = area.startLine
      currentMainWindowNode.currentColumn = area.startColumn

    currentBufStatus.prevMode = prevMode
    currentBufStatus.mode = currentBufStatus.prevMode

proc visualBlockCommand(
  status: var EditorStatus,
  area: var SelectedArea, key: Rune) =

    area.swapSelectedArea

    if key == ord('y') or isDcKey(key):
      currentBufStatus.yankBufferBlock(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings)
    elif key == ord('x') or key == ord('d'):
      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings,
        status.commandLine)
    elif key == ord('>'):
      currentBufStatus.insertIndent(
        area,
        status.settings.tabStop,
        status.commandLine)
    elif key == ord('<'):
      currentBufStatus.deleteIndent(
        currentMainWindowNode,
        area,
        status.settings.tabStop,
        status.commandLine)
    elif key == ord('J'):
      currentBufStatus.joinLines(currentMainWindowNode, area, status.commandLine)
    elif key == ord('u'):
      currentBufStatus.toLowerStringBlock(area, status.commandLine)
    elif key == ord('U'):
      currentBufStatus.toUpperStringBlock(area, status.commandLine)
    elif key == ord('r'):
      let ch = currentMainWindowNode.getKey
      if not isEscKey(ch):
        currentBufStatus.replaceCharacterBlock(area, ch, status.commandLine)
    elif key == ord('I'):
      status.insertCharacterMultipleLines(area)

    if currentBufStatus.isVisualBlockMode:
      status.changeMode(currentBufStatus.prevMode)

proc isVisualModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 0:
    return InputState.Continue
  elif command.len == 1:
    let c = command[0]
    if isControlC(c) or isEscKey(c) or isControlSquareBracketsRight(c) or
       c == ord('h') or isLeftKey(c) or isBackspaceKey(c) or
       c == ord('l') or isRightKey(c) or
       c == ord('k') or isUpKey(c) or
       c == ord('j') or isDownKey(c) or isEnterKey(c) or
       c == ord('^') or
       c == ord('0') or isHomeKey(c) or
       c == ord('$') or isEndKey(c) or
       c == ord('w') or
       c == ord('b') or
       c == ord('e') or
       c == ord('G') or
       c == ord('g') or
       c == ord('{') or
       c == ord('}') or
       c == ord('y') or isDcKey(c) or
       c == ord('x') or c == ord('d') or
       c == ord('>') or
       c == ord('<') or
       c == ord('J') or
       c == ord('u') or
       c == ord('U') or
       c == ord('r') or
       c == ord('I'):
         return InputState.Valid

# Execute the visual command and change the mode to a previous mode.
proc execVisualModeCommand*(status: var EditorStatus, command: Runes) =
  let key = command[0]

  if isControlC(key) or isEscKey(key) or isControlSquareBracketsRight(key):
    status.exitVisualMode
  elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    currentMainWindowNode.keyLeft
  elif key == ord('l') or isRightKey(key):
    currentBufStatus.keyRight(currentMainWindowNode)
  elif key == ord('k') or isUpKey(key):
    currentBufStatus.keyUp(currentMainWindowNode)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    currentBufStatus.keyDown(currentMainWindowNode)
  elif key == ord('^'):
    currentBufStatus.moveToFirstNonBlankOfLine(currentMainWindowNode)
  elif key == ord('0') or isHomeKey(key):
    currentMainWindowNode.moveToFirstOfLine
  elif key == ord('$') or isEndKey(key):
    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
  elif key == ord('w'):
    currentBufStatus.moveToForwardWord(currentMainWindowNode)
  elif key == ord('b'):
    currentBufStatus.moveToBackwardWord(currentMainWindowNode)
  elif key == ord('e'):
    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
  elif key == ord('G'):
    currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif key == ord('g') and command.len == 2:
    if command[1] == ord('g'):
      currentBufStatus.moveToFirstLine(currentMainWindowNode)
  elif key == ord('{'):
    currentBufStatus.moveToPreviousBlankLine(currentMainWindowNode)
  elif key == ord('}'):
    currentBufStatus.moveToNextBlankLine(currentMainWindowNode)
  else:
    if isVisualBlockMode(currentBufStatus.mode):
      status.visualBlockCommand(currentBufStatus.selectedArea, key)
    else:
      status.visualCommand(currentBufStatus.selectedArea, key)
