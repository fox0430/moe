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

import std/[strutils, sequtils, strformat, options]
import syntax/highlite
import ui, gapbuffer, unicodeext, windownode, bufferstatus, movement, messages,
       settings, registers, commandline, independentutils, searchutils,
       completion

proc correspondingCloseParen(c: char): char =
  case c
    of '(': return ')'
    of '{': return '}'
    of '[': return ']'
    of '"': return  '\"'
    of '\'': return '\''
    else: doAssert(false, fmt"Invalid parentheses: {c}")

proc isOpenParen(ch: char): bool {.inline.} = ch in {'(', '{', '[', '\"', '\''}

proc isCloseParen(ch: char): bool {.inline.} = ch in {')', '}', ']', '\"', '\''}

proc nextRuneIs(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  c: Rune): bool =

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn

    if bufStatus.buffer[currentLine].len > currentColumn:
      result = bufStatus.buffer[currentLine][currentColumn] == c

proc isEmptyLine(
  bufStatus: BufferStatus,
  windowNode: WindowNode): bool {.inline.} =
    # Return true if the buffer of the current line is empty.

    bufStatus.buffer[windowNode.currentLine].len == 0

proc getRegister(r: var Registers, name: string = ""): Register =
  ## Return no named, named or number or small delete or clipboard register.

  if name.len == 0: return r.getNoNamedRegister
  elif name.isNamedRegisterName: return r.getNamedRegister(name)
  elif name.isNumberRegisterName: return r.getNumberRegister(name)
  elif name.isSmallDeleteRegisterName: return r.getSmallDeleteRegister
  elif name.isClipBoardRegisterName: return r.getClipBoardRegister

proc insertCharacter*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoCloseParen: bool,
  c: Rune) =

    let oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]

    template insert = newLine.insert(c, windowNode.currentColumn)

    template moveRight = inc(windowNode.currentColumn)

    template inserted =
      if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine
      inc(bufStatus.countChange)
      bufStatus.isUpdate = true

    if autoCloseParen and canConvertToChar(c):
      let ch = c.toChar
      if isCloseParen(ch) and bufStatus.nextRuneIs(windowNode, c):
        moveRight()
        inserted()
      elif isOpenParen(ch):
        insert()
        moveRight()
        newLine.insert(correspondingCloseParen(ch).ru, windowNode.currentColumn)
        inserted()
      else:
        insert()
        moveRight()
        inserted()
    else:
      insert()
      moveRight()
      inserted()

proc selectedLineNumbers*(selectedArea: SelectedArea): seq[int] =
  ## Return line numbers in selected area.

  for lineNum in selectedArea.startLine .. selectedArea.endLine:
    result.add lineNum

proc bufferPositionsForMultipleEdit*(
  selectedArea: SelectedArea, column: int): seq[BufferPosition] =
    ## Return positions for multiple positions edtting.

    for lineNum in selectedArea.startLine .. selectedArea.endLine:
      result.add BufferPosition(line: lineNum, column: column)

proc bufferPositionsForMultipleEdit*(
  bufStatus: BufferStatus,
  column: int): seq[BufferPosition] {.inline.} =
    ## Return positions for multiple positions edtting.

    bufferPositionsForMultipleEdit(bufStatus.selectedArea.get, column)

proc insertMultiplePositions*(
  bufStatus: var BufferStatus,
  positions: seq[BufferPosition],
  r: Runes | Rune) =
    ## Insert runes to multiple positions.
    ## positions should be sorted.
    ## Cannot insert new lines.

    let runes = r.toRunes
    var
      isChanged = false
      addedCol = 0
      beforeLine = -1

    for i, p in positions:
      if beforeLine != p.line: addedCol = 0

      let
        colNum = p.column + addedCol

      if p.line <= bufStatus.buffer.len and
         colNum <= bufStatus.buffer[p.line].len:

           var newLine = bufStatus.buffer[p.line]
           newLine.insert(runes, colNum)
           if bufStatus.buffer[p.line] != newLine:
             bufStatus.buffer[p.line] = newLine
             addedCol += runes.len
             if not isChanged: isChanged = true

           beforeLine = p.line

    if isChanged:
      bufStatus.countChange.inc
      if not bufStatus.isUpdate: bufStatus.isUpdate = true

proc deleteParen*(
  bufStatus: var BufferStatus,
  currentLine, currentColumn: int,
  currentChar: Rune) =

    let buffer = bufStatus.buffer

    if isOpenParen(currentChar):
      var depth = 1
      let
        openParen = currentChar
        closeParen = correspondingCloseParen(openParen)
      for i in currentLine ..< buffer.len:
        for j in currentColumn ..< buffer[i].len:
          if buffer[i][j] == openParen: inc(depth)
          elif buffer[i][j] == closeParen: dec(depth)
          if depth == 0:
            var line = bufStatus.buffer[i]
            line.delete(j)
            bufStatus.buffer[i] = line
            return
    elif isCloseParen(currentChar):
      var depth = 1
      let
        closeParen = currentChar
        openParen = correspondingOpenParen(closeParen)
      for i in countdown(currentLine, 0):
        let startColumn = if i == currentLine: currentColumn - 1
                          else: buffer[i].high
        for j in countdown(startColumn, 0):
          if buffer[i][j] == closeParen: inc(depth)
          elif buffer[i][j] == openParen: dec(depth)
          if depth == 0:
            var line = bufStatus.buffer[i]
            line.delete(j)
            bufStatus.buffer[i] = line
            return

proc currentLineDeleteCharacterBeforeCursor(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoDeleteParen: bool) =

    if windowNode.currentLine == 0 and windowNode.currentColumn == 0: return

    dec(windowNode.currentColumn)
    let
      currentChar = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
      oldLine     = bufStatus.buffer[windowNode.currentLine]
    var newLine   = bufStatus.buffer[windowNode.currentLine]
    newLine.delete(windowNode.currentColumn)

    if oldLine != newLine:
      bufStatus.buffer[windowNode.currentLine] = newLine

    if autoDeleteParen:
      bufStatus.deleteParen(windowNode.currentLine,
                            windowNode.currentColumn,
                            currentChar)

    if(bufStatus.mode == Mode.insert and
       windowNode.currentColumn > bufStatus.buffer[windowNode.currentLine].len):
      windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine].len

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc currentLineDeleteLineBreakBeforeCursor*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoDeleteParen : bool) =

    if windowNode.currentLine == 0 and windowNode.currentColumn == 0: return

    windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine - 1].len

    let oldLine = bufStatus.buffer[windowNode.currentLine - 1]
    var newLine = bufStatus.buffer[windowNode.currentLine - 1]
    newLine &= bufStatus.buffer[windowNode.currentLine]
    bufStatus.buffer.delete(windowNode.currentLine, windowNode.currentLine)
    if oldLine != newLine: bufStatus.buffer[windowNode.currentLine - 1] = newLine

    dec(windowNode.currentLine)

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc countSpaceBeginOfLine(line: Runes, tabStop, currentColumn: int): int =
  for i in 0 ..< min(line.len, currentColumn):
    if isWhiteSpace(line[i]): result.inc
    else: break

proc deleteMultiplePositions*(
  bufStatus: var BufferStatus,
  positions: seq[BufferPosition],
  numOfDelete: int) =
    ## Delete runes from multiple positions. Similar behavior to Backspace key.
    ## positions should be sorted.
    ## Cannot delete new lines.

    var
      isChanged = false
      deletedCol = 0
      beforeLine = -1

    for i, p in positions:
      if beforeLine != p.line: deletedCol = 0

      if p.column > 0 and bufStatus.buffer[p.line].len > 0:
        var newLine = bufStatus.buffer[p.line]
        let
          colNum = p.column - deletedCol
          first = max(0, colNum - numOfDelete)
          last = min(bufStatus.buffer[p.line].len, colNum - 1)

        if last < newLine.len:
          newLine.delete(first .. last)
          if bufStatus.buffer[p.line] != newLine:
            bufStatus.buffer[p.line] = newLine
            deletedCol += last - first + 1
            if not isChanged: isChanged = true

          beforeLine = p.line

    if isChanged:
      bufStatus.countChange.inc
      if not bufStatus.isUpdate: bufStatus.isUpdate = true

proc deleteCurrentMultiplePositions*(
  bufStatus: var BufferStatus,
  positions: seq[BufferPosition],
  numOfDelete: int) =
    ## Delete runes from multiple positions. Similar behavior to Delete key.
    ## positions should be sorted.
    ## Cannot delete new lines.

    var
      isChanged = false
      deletedCol = 0
      beforeLine = -1

    for i, p in positions:
      if beforeLine != p.line: deletedCol = 0

      if bufStatus.buffer[p.line].len > 0:
        let colNum = p.column - deletedCol
        var newLine = bufStatus.buffer[p.line]
        let
          num = min(newLine.len, numOfDelete)
          first = colNum
          last = colNum + num - 1

        if last < newLine.len:
          newLine.delete(first .. last)

          if bufStatus.buffer[p.line] != newLine:
            bufStatus.buffer[p.line] = newLine
            deletedCol += num

          beforeLine = p.line

    if isChanged:
      bufStatus.countChange.inc
      if not bufStatus.isUpdate: bufStatus.isUpdate = true

proc keyBackspace*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoDeleteParen: bool,
  tabStop: int) =

    if windowNode.currentColumn == 0:
      currentLineDeleteLineBreakBeforeCursor(
        bufStatus,
        windowNode,
        autoDeleteParen)
    else:
      let
        currentLine = windowNode.currentLine
        currentColumn = windowNode.currentColumn

        line = bufStatus.buffer[currentLine]
        numOfSpsce = line.countSpaceBeginOfLine(tabStop, currentColumn)
        numOfDelete =
          if numOfSpsce == 0 or currentColumn > numOfSpsce: 1
          elif numOfSpsce mod tabStop != 0: numOfSpsce mod tabStop
          else: tabStop

      for i in 0 ..< numOfDelete:
        currentLineDeleteCharacterBeforeCursor(
          bufStatus,
          windowNode,
          autoDeleteParen)

proc deleteBeforeCursorToFirstNonBlank*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode) =

    if windowNode.currentColumn == 0: return

    let firstNonBlank = bufStatus.getFirstNonBlankOfLineOrFirstColumn(
      windowNode)
    for _ in firstNonBlank..max(0, windowNode.currentColumn-1):
      bufStatus.currentLineDeleteCharacterBeforeCursor(windowNode, false)

proc isWhiteSpaceLine(line: Runes): bool =
  result = true
  for r in line:
    if not isWhiteSpace(r): return false

proc deleteAllCharInLine(line: var Runes) =
  for i in 0 ..< line.len: line.delete(0)

proc basicNewLine(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    var startOfCopy = max(
      countRepeat(bufStatus.buffer[windowNode.currentLine], Whitespace, 0),
      windowNode.currentColumn)
    startOfCopy += countRepeat(
      bufStatus.buffer[windowNode.currentLine],
      Whitespace, startOfCopy)

    block:
      let oldLine = bufStatus.buffer[windowNode.currentLine + 1]
      var newLine = bufStatus.buffer[windowNode.currentLine + 1]

      let
        line = windowNode.currentLine
        startCol = startOfCopy
        endCol = bufStatus.buffer[windowNode.currentLine].len

      newLine &= bufStatus.buffer[line][startCol ..< endCol]

      if oldLine != newLine:
        bufStatus.buffer[windowNode.currentLine + 1] = newLine

    block:
      let
        first = windowNode.currentColumn
        last = bufStatus.buffer[windowNode.currentLine].high
      if first <= last:
        let oldLine = bufStatus.buffer[windowNode.currentLine]
        var newLine = bufStatus.buffer[windowNode.currentLine]
        for _ in first .. last:
          newLine.delete(first)
        if oldLine != newLine:
          bufStatus.buffer[windowNode.currentLine] = newLine

    inc(windowNode.currentLine)

    if autoIndent:
      block:
        let line = bufStatus.buffer[windowNode.currentLine]
        windowNode.currentColumn = countRepeat(line, Whitespace, 0)

      # Delete all characters in the previous line if only whitespaces.
      if windowNode.currentLine > 0 and
         isWhiteSpaceLine(bufStatus.buffer[windowNode.currentLine - 1]):

        let oldLine = bufStatus.buffer[windowNode.currentLine - 1]
        var newLine = bufStatus.buffer[windowNode.currentLine - 1]
        newLine.deleteAllCharInLine
        if newLine != oldLine:
          bufStatus.buffer[windowNode.currentLine - 1] = newLine
    else:
      windowNode.currentColumn = 0
      windowNode.expandedColumn = 0

proc basicInsrtIndent(
  bufStatus: var BufferStatus,
  windowNode: WindowNode) =

    let
      currentLine = windowNode.currentLine
      count = countRepeat(bufStatus.buffer[currentLine], Whitespace, 0)
      indent = min(count, windowNode.currentColumn)
      oldLine = bufStatus.buffer[currentLine + 1]
    var newLine = bufStatus.buffer[currentLine + 1]

    newLine &= repeat(' ', indent).toRunes
    if oldLine != newLine:
      bufStatus.buffer[currentLine + 1] = newLine

proc insertIndentWhenPairOfParen(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    let
      currentLine = windowNode.currentLine
      line = bufStatus.buffer[currentLine]
      count = countRepeat(line, Whitespace, 0) + tabStop
      openParen = line[windowNode.currentColumn - 1]

    let oldLine = bufStatus.buffer[windowNode.currentLine + 1]
    var newLine = bufStatus.buffer[currentLine + 1]
    newLine &= repeat(' ', count).toRunes
    if oldLine != newLine:
      bufStatus.buffer[currentLine + 1] = newLine

    bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

    # Add the new line and move the close paren if finish the next line with the close paren.
    # If Nim or Python, Don't insert the new line.
    if bufStatus.language != SourceLanguage.langNim and
       bufStatus.language != SourceLanguage.langPython:
      let nextLine = bufStatus.buffer[currentLine + 1]
      if isCloseParen(nextLine[^1]) and
         isCorrespondingParen(openParen, nextLine[^1]):
        let closeParen = nextLine[^1]
        # Delete the close paren in the nextLine
        block:
          let oldLine = nextLine
          var newLine = nextLine
          newLine = oldLine[0 .. newLine.high - 1]
          if oldLine != newLine:
            bufStatus.buffer[currentLine + 1] = newLine
        # Add the close paren in the buffer[nextLine + 1]
        block:
          let count = countRepeat(line, Whitespace, 0)
          var newLine = repeat(' ', count).toRunes & closeParen
          bufStatus.buffer.insert(newLine, windowNode.currentLine + 1)

proc insertIndentInNimForKeyEnter(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    proc splitWhitespace(runes: Runes): seq[Runes] {.inline.} =
      ## Remove empty entries
      runes.splitWhitespace(true)

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      line = bufStatus.buffer[currentLine]

    if line.len > 0:
      # Auto indent if the current line are "var", "let", "const".
      # And, if finish the current line with ':', "object"
      if currentColumn == line.len and (
          (line.len > 2 and
            line.splitWhitespace == @[ru"var"] or
            line.splitWhitespace == @[ru"let"]) or
          (line.len > 4 and
            line.splitWhitespace == @[ru"const"]) or
          (line.len > 4 and
          line.splitWhitespace.len > 0 and
          line.splitWhitespace[^1] == (ru"object")) or
          line[^1] == (ru ':') or
          line[^1] == (ru '=')
        ):
        let
          count = countRepeat(line, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[windowNode.currentLine + 1]
        var newLine = bufStatus.buffer[currentLine + 1]
        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLine + 1] = newLine

        bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

      # Auto indent if finish the current line with "or", "and"
      elif (currentColumn == line.len) and
           ((line.len > 2 and line[line.len - 2 .. ^1] == ru "or") or
           (line.len > 3 and line[line.len - 3 .. ^1] == ru "and")):
        let
          count = countRepeat(line, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[windowNode.currentLine + 1]
        var newLine = bufStatus.buffer[currentLine + 1]
        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLine + 1] = newLine

        bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

      # if previous col is the unclosed paren.
      elif currentColumn > 0 and isOpenParen(line[currentColumn - 1]):
        bufStatus.insertIndentWhenPairOfParen(windowNode, autoIndent, tabStop)
      else:
        bufStatus.basicInsrtIndent(windowNode)
        bufStatus.basicNewLine(windowNode, autoIndent, tabStop)
    else:
      bufStatus.basicInsrtIndent(windowNode)
      bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

proc insertIndentInPythonForKeyEnter(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    let
      currentLine = windowNode.currentLine
      line = bufStatus.buffer[currentLine]

    if line.len > 0:
      # if finish the current line with ':', the unclosed paren.
      if isOpenParen(line[^1]) or line[^1] == ru ':':
        let
          count = countRepeat(line, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[windowNode.currentLine + 1]
        var newLine = bufStatus.buffer[currentLine + 1]
        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLine + 1] = newLine

      # Auto indent if finish the current line with "or" and "and" in Python
      elif (line.len > 2 and line[line.len - 2 .. ^1] == ru "or") or
           (line.len > 3 and line[line.len - 3 .. ^1] == ru "and"):
        let
          count = countRepeat(line, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[windowNode.currentLine + 1]
        var newLine = bufStatus.buffer[currentLine + 1]
        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLine + 1] = newLine
    else:
      bufStatus.basicInsrtIndent(windowNode)

    bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

proc insertIndentInClangForKeyEnter(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      line = bufStatus.buffer[currentLine]

    if currentColumn > 0 :
      # if previous col is the unclosed paren.
      if line.len > 0 and isOpenParen(line[currentColumn - 1]):
        bufStatus.insertIndentWhenPairOfParen(windowNode, autoIndent, tabStop)
      else:
        bufStatus.basicInsrtIndent(windowNode)
        bufStatus.basicNewLine(windowNode, autoIndent, tabStop)
    else:
        bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

proc insertIndentInYamlForKeyEnter(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    let
      currentLine = windowNode.currentLine
      line = bufStatus.buffer[currentLine]

    if line.len > 0:
      # if finish the current line with ':'.
      if line[^1] == ru ':':
        let
          count = countRepeat(line, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[windowNode.currentLine + 1]
        var newLine = bufStatus.buffer[currentLine + 1]
        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLine + 1] = newLine

    bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

proc insertIndentInPlainTextForKeyEnter(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    let
      currentLine = windowNode.currentLine
      count = countRepeat(bufStatus.buffer[currentLine], Whitespace, 0)
      indent = min(count, windowNode.currentColumn)

      oldLine = bufStatus.buffer[currentLine + 1]
    var newLine = bufStatus.buffer[currentLine + 1]

    newLine &= repeat(' ', indent).toRunes
    if oldLine != newLine:
     bufStatus.buffer[currentLine + 1] = newLine

    bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

proc insertIndentForKeyEnter(
  bufStatus: var BufferStatus,
  winNode: WindowNode,
  autoIndent:bool,
  tabStop: int) =
    ## Insert indent to the next line

    case bufStatus.language:
      of SourceLanguage.langNim:
        bufStatus.insertIndentInNimForKeyEnter(winNode, autoIndent, tabStop)
      of SourceLanguage.langC:
        bufStatus.insertIndentInClangForKeyEnter(winNode, autoIndent, tabStop)
      of SourceLanguage.langCpp:
        bufStatus.insertIndentInClangForKeyEnter(winNode, autoIndent, tabStop)
      of SourceLanguage.langCsharp:
        bufStatus.insertIndentInClangForKeyEnter(winNode, autoIndent, tabStop)
      of SourceLanguage.langJava:
        bufStatus.insertIndentInClangForKeyEnter(winNode, autoIndent, tabStop)
      of SourceLanguage.langJavaScript:
        bufStatus.insertIndentInClangForKeyEnter(winNode, autoIndent, tabStop)
      of SourceLanguage.langPython:
        bufStatus.insertIndentInPythonForKeyEnter(winNode, autoIndent, tabStop)
      of SourceLanguage.langYaml:
        bufStatus.insertIndentInYamlForKeyEnter(winNode, autoIndent, tabStop)
      else:
        bufStatus.insertIndentInPlainTextForKeyEnter(
          winNode,
          autoIndent,
          tabStop)

proc keyEnter*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent: bool,
  tabStop: int) =

    bufStatus.buffer.insert(ru"", windowNode.currentLine + 1)

    if autoIndent:
      bufStatus.insertIndentForKeyEnter(windowNode, autoIndent, tabStop)
    else:
      bufStatus.basicNewLine(windowNode, autoIndent, tabStop)

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc insertTab*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  tabStop: int,
  autoCloseParen: bool) {.inline.} =

    for i in 0 ..< tabStop:
      bufStatus.insertCharacter(windowNode, autoCloseParen, ru' ')

proc insertCharacterBelowCursor*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode) =

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      buffer = bufStatus.buffer

    if currentLine == bufStatus.buffer.high: return
    if currentColumn > buffer[currentLine + 1].high: return

    let
      copyRune = buffer[currentLine + 1][currentColumn]
      oldLine = buffer[currentLine]
    var newLine = buffer[currentLine]

    newLine.insert(copyRune, currentColumn)
    if newLine != oldLine:
      bufStatus.buffer[currentLine] = newLine
      inc windowNode.currentColumn

proc insertCharacterAboveCursor*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode) =

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      buffer = bufStatus.buffer

    if currentLine == 0: return
    if currentColumn > buffer[currentLine - 1].high: return

    let
      copyRune = buffer[currentLine - 1][currentColumn]
      oldLine = buffer[currentLine]
    var newLine = buffer[currentLine]

    newLine.insert(copyRune, currentColumn)
    if newLine != oldLine:
      bufStatus.buffer[currentLine] = newLine
      inc windowNode.currentColumn

proc deleteWord*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  loop: int,
  withSpace: bool,
  registers: var Registers,
  registerName: string,
  settings: EditorSettings) =
    ## Delete the current word.
    ## If `withSpace` is true, delete spaces after the word.

    var deletedBuffer: Runes

    for i in 0 ..< loop:
      if bufStatus.buffer.len == 1 and
         bufStatus.buffer[windowNode.currentLine].len < 1: return
      elif bufStatus.buffer.len > 1 and
           windowNode.currentLine < bufStatus.buffer.high and
           bufStatus.buffer[windowNode.currentLine].len < 1:
        bufStatus.buffer.delete(windowNode.currentLine, windowNode.currentLine + 1)

        if windowNode.currentLine > bufStatus.buffer.high:
          windowNode.currentLine = bufStatus.buffer.high
      elif windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].high:
        let oldLine = bufStatus.buffer[windowNode.currentLine]
        var newLine = bufStatus.buffer[windowNode.currentLine]
        deletedBuffer = @[oldLine[windowNode.currentColumn]]
        newLine.delete(windowNode.currentColumn)

        if oldLine != newLine:
          bufStatus.buffer[windowNode.currentLine] = newLine

        if windowNode.currentColumn > 0: dec(windowNode.currentColumn)
      else:
        let
          currentLine = windowNode.currentLine
          currentColumn = windowNode.currentColumn
          startWith =
            if bufStatus.buffer[currentLine].len == 0: ru'\n'
            else: bufStatus.buffer[currentLine][currentColumn]
          isSkipped =
            if unicodeext.isPunct(startWith): unicodeext.isPunct
            elif unicodeext.isAlpha(startWith): unicodeext.isAlpha
            elif unicodeext.isDigit(startWith): unicodeext.isDigit
            else: nil

        if isSkipped == nil:
          (windowNode.currentLine, windowNode.currentColumn) =
            bufStatus.buffer.next(currentLine, currentColumn)
        else:
          while true:
            inc(windowNode.currentColumn)
            if windowNode.currentColumn >= bufStatus.buffer[windowNode.currentLine].len:
              break
            if not isSkipped(bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]):
              break

        while true:
          if windowNode.currentColumn > bufStatus.buffer[windowNode.currentLine].high:
            break
          let curr =
            bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
          if isPunct(curr) or isAlpha(curr) or isDigit(curr) or (not withSpace and isSpace(curr)): break
          inc(windowNode.currentColumn)

        let oldLine = bufStatus.buffer[currentLine]
        var
          newLine = bufStatus.buffer[currentLine]
        for i in currentColumn ..< windowNode.currentColumn:
          deletedBuffer.add newLine[currentColumn]
          newLine.delete(currentColumn)
        if oldLine != newLine:
          bufStatus.buffer[currentLine] = newLine

        windowNode.expandedColumn = currentColumn
        windowNode.currentColumn = currentColumn

    if registerName.isNamedRegisterName:
      registers.setNamedRegister(deletedBuffer, registerName[0])
    else:
      registers.setDeletedRegister(deletedBuffer)

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc deleteWordBeforeCursor*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  registers: var Registers,
  registerName: string,
  loop: int,
  settings: EditorSettings) =

    if windowNode.currentLine == 0 and windowNode.currentColumn == 0: return


    if windowNode.currentColumn == 0:
      let isAutoDeleteParen = false
      bufStatus.keyBackspace(
        windowNode,
        isAutoDeleteParen,
        settings.standard.tabStop)
    else:
      bufStatus.moveToBackwardWord(windowNode)

      const WithSpace = true
      bufStatus.deleteWord(
        windowNode,
        loop,
        WithSpace,
        registers,
        registerName,
        settings)

proc deleteWordBeforeCursor*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  registers: var Registers,
  loop: int,
  settings: EditorSettings) =

    const RegisterName = ""
    bufStatus.deleteWordBeforeCursor(
      windowNode,
      registers,
      RegisterName,
      loop,
      settings)

proc countSpaceOfBeginningOfLine(line: Runes): int =
  for r in line:
    if r != ru' ': break
    else: result.inc

proc indent*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  tabStop: int) =
    ## Indent in the current line.

    let oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]

    let
      numOfSpace = countSpaceOfBeginningOfLine(oldLine)
      numOfInsertSpace =
        if numOfSpace mod tabStop != 0: numOfSpace mod tabStop
        else: tabStop

    newLine.insert(newSeqWith(numOfInsertSpace, ru' '), 0)
    if oldLine != newLine:
      bufStatus.buffer[windowNode.currentLine] = newLine
      inc(bufStatus.countChange)

    bufStatus.isUpdate = true

proc unindent*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  tabStop: int) =
    ## Unindent in the current line.

    let
      oldLine = bufStatus.buffer[windowNode.currentLine]
      numOfSpace = countSpaceOfBeginningOfLine(oldLine)
      numOfDeleteSpace =
        if numOfSpace > 0 and numOfSpace mod tabStop != 0:
          numOfSpace mod tabStop
        elif numOfSpace > 0:
          tabStop
        else:
          0

    if numOfDeleteSpace > 0:
      var newLine = bufStatus.buffer[windowNode.currentLine]

      for i in 0 ..< numOfDeleteSpace: newLine.delete(0)

      if oldLine != newLine:
        bufStatus.buffer[windowNode.currentLine] = newLine
        inc(bufStatus.countChange)
        bufStatus.isUpdate = true

        let newLine = bufStatus.buffer[windowNode.currentLine]

        if newLine.high < windowNode.currentColumn:
          windowNode.currentColumn =
            if newLine.high == -1: 0
            else: newLine.high

proc deleteCharactersBeforeCursorInCurrentLine*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    if windowNode.currentColumn == 0: return

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]

    for _ in 0 ..< currentColumn:
      newLine.delete(0)

    if newLine != oldLine: bufStatus.buffer[currentLine] = newLine

proc indentInCurrentLine*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  tabStop: int) =

    bufStatus.indent(windowNode, tabStop)
    windowNode.currentColumn += tabStop

proc unIndentInCurrentLine*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  tabStop: int) =

    let oldLine = bufStatus.buffer[windowNode.currentLine]

    bufStatus.unindent(windowNode, tabStop)

    if oldLine != bufStatus.buffer[windowNode.currentLine] and
       windowNode.currentColumn >= tabStop:
      windowNode.currentColumn -= tabStop

proc deleteCharacter*(
  bufStatus: var BufferStatus,
  line, colmun: int,
  autoDeleteParen: bool) =

    let
      currentLine = line
      currentColumn = colmun

    if currentLine >= bufStatus.buffer.high and
       currentColumn > bufStatus.buffer[currentLine].high: return

    if currentColumn == bufStatus.buffer[currentLine].len:
      let oldLine = bufStatus.buffer[line]
      var newLine = bufStatus.buffer[line]
      newLine.insert(bufStatus.buffer[currentLine + 1], currentColumn)
      if oldLine != newLine:
        bufStatus.buffer[line] = newLine

      bufStatus.buffer.delete(currentLine + 1, currentLine + 1)
    else:
      let
        currentChar = bufStatus.buffer[currentLine][currentColumn]
        oldLine = bufStatus.buffer[line]
      var newLine = bufStatus.buffer[line]
      newLine.delete(currentColumn)
      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine

      if autoDeleteParen and currentChar.isParen:
        bufStatus.deleteParen(
          line,
          colmun,
          currentChar)

proc deleteCharacters*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  registerName: string,
  line, colmun, loop: int,
  settings: EditorSettings) =
    ## Delete characters in the line

    if line >= bufStatus.buffer.high and
       colmun > bufStatus.buffer[line].high: return

    let oldLine = bufStatus.buffer[line]
    var newLine = bufStatus.buffer[line]

    var
      currentColumn = colmun

      deletedBuffer: Runes

    for i in 0 ..< loop:
      if newLine.len == 0: break

      let deleteChar = newLine[currentColumn]
      newLine.delete(currentColumn)

      deletedBuffer.add deleteChar

      if currentColumn > newLine.high: currentColumn = newLine.high

      if settings.standard.autoDeleteParen and deleteChar.isParen:
        bufStatus.deleteParen(
          line,
          colmun,
          deleteChar)

    if oldLine != newLine:
      bufStatus.buffer[line] = newLine

      if registerName.isNamedRegisterName:
        registers.setNamedRegister(deletedBuffer, registerName[0])
      else:
        registers.setDeletedRegister(deletedBuffer)

      inc(bufStatus.countChange)
      bufStatus.isUpdate = true

proc deleteCharacters*(
  bufStatus: var BufferStatus,
  autoDeleteParen: bool,
  line, colmun, loop: int) =
    ## No yank buffer

    if line >= bufStatus.buffer.high and
       colmun > bufStatus.buffer[line].high: return

    let oldLine = bufStatus.buffer[line]
    var newLine = bufStatus.buffer[line]

    var
      currentColumn = colmun

      deletedBuffer: Runes

    for i in 0 ..< loop:
      if newLine.len == 0: break

      let deleteChar = newLine[currentColumn]
      newLine.delete(currentColumn)

      deletedBuffer.add deleteChar

      if currentColumn > newLine.high: currentColumn = newLine.high

      if autoDeleteParen and deleteChar.isParen:
        bufStatus.deleteParen(
          line,
          colmun,
          deleteChar)

    if oldLine != newLine:
      bufStatus.buffer[line] = newLine

      inc(bufStatus.countChange)
      bufStatus.isUpdate = true

proc insertIndentNimForOpenBlankLine(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  tabStop: int) =
    ## Add the new line and insert indent in Nim

    proc splitWhitespace(runes: Runes): seq[Runes] {.inline.} =
      ## Remove empty entries
      runes.splitWhitespace(true)

    let
      currentLineNum = windowNode.currentLine
      aboveLine = bufStatus.buffer[currentLineNum - 1]

    if aboveLine.len > 0:
      # Auto indent if the current line are "var", "let", "const".
      # And, if finish the current line with ':', "object, '='"
      if (aboveLine.splitWhitespace == @[ru"var"] or
         aboveLine.splitWhitespace == @[ru"let"] or
         aboveLine.splitWhitespace == @[ru"const"] or
         aboveLine.splitWhitespace[^1] == (ru"object") or
         aboveLine[^1] == (ru ':') or
         aboveLine[^1] == (ru '=')):
        let
          count = countRepeat(aboveLine, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[currentLineNum]
        var newLine = bufStatus.buffer[currentLineNum]

        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLineNum] = newLine
      elif ((aboveLine.len > 2 and aboveLine.splitWhitespace[^1] == ru "or") or
           (aboveLine.len > 3 and aboveLine.splitWhitespace[^1] == ru "and")):
        # Auto indent if finish the current line with "or", "and"
        let
          count = countRepeat(aboveLine, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[currentLineNum]
        var newLine = bufStatus.buffer[currentLineNum]

        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLineNum] = newLine
      else:
        let
          count = countRepeat(aboveLine, Whitespace, 0)
          oldLine = bufStatus.buffer[currentLineNum]
        var newLine = bufStatus.buffer[currentLineNum]

        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLineNum] = newLine

proc insertIndentInPythonForOpenBlankLine(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  tabStop: int) =

    proc splitWhitespace(runes: Runes): seq[Runes] {.inline.} =
      ## Remove empty entries
      runes.splitWhitespace(true)

    let
      currentLineNum = windowNode.currentLine
      aboveLine = bufStatus.buffer[currentLineNum - 1]

    if aboveLine.len > 0:
      # if finish the current line with ':', "or", "and" in Python
      if (aboveLine.len > 2 and (aboveLine.splitWhitespace)[^1] == ru "or") or
         (aboveLine.len > 3 and (aboveLine.splitWhitespace)[^1] == ru "and") or
         (aboveLine[^1] == ru ':'):
        let
          count = countRepeat(aboveLine, Whitespace, 0) + tabStop
          oldLine = bufStatus.buffer[currentLineNum]
        var newLine = bufStatus.buffer[currentLineNum]

        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLineNum] = newLine

      else:
        let
          count = countRepeat(aboveLine, Whitespace, 0)
          oldLine = bufStatus.buffer[currentLineNum]
        var newLine = bufStatus.buffer[currentLineNum]

        newLine &= repeat(' ', count).toRunes
        if oldLine != newLine:
          bufStatus.buffer[currentLineNum] = newLine

proc insertIndentPlainTextForOpenBlankLine(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  tabStop: int) =
    ## Add the new line and insert indent in the plain text

    let
      currentLineNum = windowNode.currentLine
      aboveLine = bufStatus.buffer[currentLineNum - 1]
      count = countRepeat(aboveLine, Whitespace, 0)
      oldLine = bufStatus.buffer[currentLineNum]
    var newLine = bufStatus.buffer[currentLineNum]

    newLine &= repeat(' ', count).toRunes
    if oldLine != newLine:
      bufStatus.buffer[currentLineNum] = newLine
      windowNode.currentColumn = bufStatus.buffer[currentLineNum].high

proc insertIndentForOpenBlankLine(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  tabStop: int) =

    case bufStatus.language:
      of SourceLanguage.langNim:
        bufStatus.insertIndentNimForOpenBlankLine(windowNode, tabStop)
      of SourceLanguage.langPython:
        bufStatus.insertIndentInPythonForOpenBlankLine(windowNode, tabStop)
      else:
        bufStatus.insertIndentPlainTextForOpenBlankLine(windowNode, tabStop)

proc openBlankLineBelow*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  autoIndent: bool,
  tabStop: int) =

    bufStatus.buffer.insert(ru "", windowNode.currentLine + 1)
    inc(windowNode.currentLine)

    if autoIndent:
      bufStatus.insertIndentForOpenBlankLine(windowNode, tabStop)

    if bufStatus.buffer[windowNode.currentLine].high > 0:
      windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine].len
    else:
      windowNode.currentColumn = 0

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc openBlankLineAbove*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  autoIndent: bool,
  tabStop: int) =

    bufStatus.buffer.insert(ru "", windowNode.currentLine)

    if autoIndent and windowNode.currentLine > 0:
      bufStatus.insertIndentForOpenBlankLine(windowNode, tabStop)

    windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine].len

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc deleteLines*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  registerName: string,
  startLine, loop: int,
  settings: EditorSettings) =
    ## Delete lines and store lines to the register

    let endLine = min(startLine + loop, bufStatus.buffer.high)

    # Store lines to the register before delete them
    block:
      let buffer = bufStatus.buffer

      var deleteLines: seq[Runes]

      for i in startLine .. endLine: deleteLines.add(buffer[i])

      if registerName.isNamedRegisterName:
        registers.setNamedRegister(deleteLines, registerName[0])
      else:
        registers.setDeletedRegister(deleteLines)

    bufStatus.buffer.delete(startLine, endLine)

    if bufStatus.buffer.len == 0: bufStatus.buffer.insert(ru"", 0)

    if startLine < windowNode.currentLine: dec(windowNode.currentLine)
    if windowNode.currentLine >= bufStatus.buffer.len:
      windowNode.currentLine = bufStatus.buffer.high

    windowNode.currentColumn = 0
    windowNode.expandedColumn = 0

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc deleteCharacterUntilEndOfLine*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  registerName: string,
  windowNode: WindowNode,
  settings: EditorSettings) =

    let
      currentLine = windowNode.currentLine
      startColumn = windowNode.currentColumn
      loop = bufStatus.buffer[currentLine].len - startColumn

    bufStatus.deleteCharacters(
      registers,
      registerName,
      currentLine,
      startColumn,
      loop,
      settings)

proc deleteCharacterBeginningOfLine*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: var WindowNode,
  registerName: string,
  settings: EditorSettings) =

    let
      currentLine = windowNode.currentLine
      startColumn = 0
      loop = windowNode.currentColumn

    bufStatus.deleteCharacters(
      registers,
      registerName,
      currentLine,
      startColumn,
      loop,
      settings)

    windowNode.currentColumn = 0
    windowNode.expandedColumn = 0

proc deleteCharactersAfterBlankInLine*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: var WindowNode,
  registerName: string,
  settings: EditorSettings) =
    ## Delete characters after blank in the current line

    let
      currentLine = windowNode.currentLine
      firstNonBlankCol = getFirstNonBlankOfLineOrFirstColumn(
        bufStatus,
        windowNode)
      loop = bufStatus.buffer[currentLine].len - firstNonBlankCol

    bufStatus.deleteCharacters(
      registers,
      registerName,
      currentLine,
      firstNonBlankCol,
      loop,
      settings)

    windowNode.currentColumn = firstNonBlankCol
    windowNode.expandedColumn = firstNonBlankCol

proc deleteTillPreviousBlankLine*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  registerName: string,
  settings: EditorSettings) =
    ## Delete from the previous blank line to the current line

    var deletedBuffer: seq[Runes]

    block:
      # Delete lines before the currentLine
      let blankLine = bufStatus.findPreviousBlankLine(windowNode.currentLine)

      for i in blankLine ..< windowNode.currentLine:
        deletedBuffer.add bufStatus.buffer[i]

      bufStatus.buffer.delete(blankLine, windowNode.currentLine - 1)

    block:
      # Delete characters before the cursor in the currentLine
      let
        currentLine = min(bufStatus.buffer.high, windowNode.currentLine)
        currentColumn = windowNode.currentColumn

      let oldLine = bufStatus.buffer[currentLine]
      var newLine = bufStatus.buffer[currentLine]

      if currentColumn > 0:
        var deletedLine: Runes
        for i in 0 ..< currentColumn: deletedLine.add oldLine[i]
        if deletedLine.len > 0: deletedBuffer.add deletedLine

        for _ in 0 ..< currentColumn:
          newLine.delete(0)

        if oldLine != newLine: bufStatus.buffer[currentLine] = newLine

    if registerName.isNamedRegisterName:
      registers.setNamedRegister(deletedBuffer, registerName[0])
    else:
      registers.setDeletedRegister(deletedBuffer)

    windowNode.currentLine = min(bufStatus.buffer.high, windowNode.currentLine)
    windowNode.currentColumn = 0

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc deleteTillNextBlankLine*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  registerName: string,
  settings: EditorSettings) =
    ## Delete from the current line to the next blank line

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
    var blankLine = bufStatus.findNextBlankLine(currentLine)
    if blankLine < 0: blankLine = bufStatus.buffer.len

    var deletedBuffer: seq[Runes]

    block:
      # Delete characters after the cursor in the currentLine
      let oldLine = bufStatus.buffer[currentLine]
      var newLine = bufStatus.buffer[currentLine]

      if currentColumn > 0:
        var deletedLine: Runes
        for i in currentColumn ..< oldLine.len : deletedLine.add oldLine[i]

        for _ in currentColumn .. oldLine.high:
          newLine.delete(currentColumn)

        if oldLine != newLine:
          bufStatus.buffer[currentLine] = newLine
          deletedBuffer.add deletedLine

    block:
      # Delete to the next blank line
      let startLine = if currentColumn == 0: currentLine else: currentLine + 1
      for i in startLine ..< blankLine:
        deletedBuffer.add bufStatus.buffer[i]

      bufStatus.buffer.delete(startLine, blankLine - 1)

    if registerName.isNamedRegisterName:
      registers.setNamedRegister(deletedBuffer, registerName[0])
    else:
      registers.setDeletedRegister(deletedBuffer)

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc yankLines*(
  bufStatus: BufferStatus,
  registers: var Registers,
  commandLine: var CommandLine,
  notificationSettings: NotificationSettings,
  first, last: int,
  registerName: string,
  isDelete: bool,
  settings: EditorSettings) =
    ## name is the register name

    var yankedBuffer: seq[Runes]
    for i in first .. last:
      yankedBuffer.add bufStatus.buffer[i]

    if registerName.isNamedRegisterName:
      registers.setNamedRegister(yankedBuffer, registerName[0])
    else:
      registers.setYankedRegister(yankedBuffer)

    commandLine.writeMessageYankedLine(
      yankedBuffer.len,
      notificationSettings)

proc yankLines*(
  bufStatus: BufferStatus,
  registers: var Registers,
  commandLine: var CommandLine,
  notificationSettings: NotificationSettings,
  first, last: int,
  isDelete: bool,
  settings: EditorSettings) =

    const Name = ""
    bufStatus.yankLines(
      registers,
      commandLine,
      notificationSettings,
      first, last,
      Name,
      isDelete,
      settings)

proc yankLines*(
  bufStatus: BufferStatus,
  registers: var Registers,
  commandLine: var CommandLine,
  notificationSettings: NotificationSettings,
  first, last: int,
  name: string,
  settings: EditorSettings) =

    const IsDelete = false
    bufStatus.yankLines(
      registers,
      commandLine,
      notificationSettings,
      first, last,
      name,
      IsDelete,
      settings)

proc yankLines*(
  bufStatus: BufferStatus,
  registers: var Registers,
  commandLine: var CommandLine,
  notificationSettings: NotificationSettings,
  first, last: int,
  settings: EditorSettings) =

    const
      Name = ""
      IsDelete = false
    bufStatus.yankLines(
      registers,
      commandLine,
      notificationSettings,
      first, last,
      Name,
      IsDelete,
      settings)

proc yankCharacters*(
  bufStatus: BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  commandLine: var CommandLine,
  settings: EditorSettings,
  length: int,
  registerName: string,
  isDelete: bool) =

    var yankedBuffer: Runes

    if bufStatus.buffer[windowNode.currentLine].len > 0:
      for i in 0 ..< length:
        let
          col = windowNode.currentColumn + i
          line = windowNode.currentLine
        yankedBuffer.add bufStatus.buffer[line][col]

    if registerName.isNamedRegisterName:
      registers.setNamedRegister(yankedBuffer, registerName[0])
    else:
      registers.setYankedRegister(yankedBuffer)

    commandLine.writeMessageYankedCharacter(
      yankedBuffer.len,
      settings.notification)

proc yankWord*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  loop: int,
  registerName: string,
  isDelete: bool,
  settings: EditorSettings) =

    var yankedBuffer: Runes

    let line = bufStatus.buffer[windowNode.currentLine]
    var startColumn = windowNode.currentColumn

    for i in 0 ..< loop:
      if line.len < 1:
        yankedBuffer = ru""
        return
      if isPunct(line[startColumn]):
        yankedBuffer.add line[startColumn]
        return

      for j in startColumn ..< line.len:
        let rune = line[j]
        if isWhiteSpace(rune):
          for k in j ..< line.len:
            if isWhiteSpace(line[k]): yankedBuffer.add rune
            else:
              startColumn = k
              break
          break
        elif not isAlpha(rune) or isPunct(rune) or isDigit(rune):
          startColumn = j
          break
        else: yankedBuffer.add rune

    if registerName.isNamedRegisterName:
      registers.setNamedRegister(yankedBuffer, registerName[0])
    else:
      registers.setYankedRegister(yankedBuffer)

proc yankWord*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  loop: int,
  isDelete: bool,
  settings: EditorSettings) =

    const Name = ""
    bufStatus.yankWord(
      registers,
      windowNode,
      loop,
      Name,
      isDelete,
      settings)

proc yankWord*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  loop: int,
  name: string,
  settings: EditorSettings) =

  const IsDelete = false
  bufStatus.yankWord(
    registers,
    windowNode,
    loop,
    name,
    IsDelete,
    settings)

proc yankWord*(
  bufStatus: var BufferStatus,
  registers: var Registers,
  windowNode: WindowNode,
  loop: int,
  settings: EditorSettings) =

  const
    Name = ""
    IsDelete = false
  bufStatus.yankWord(
    registers,
    windowNode,
    loop,
    Name,
    IsDelete,
    settings)

proc yankCharactersOfLines*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  registers: var Registers,
  isDelete: bool,
  registerName: string,
  settings: EditorSettings) =

    let line: Runes = bufStatus.buffer[windowNode.currentLine]

    if registerName.isNamedRegisterName:
      registers.setNamedRegister(line, registerName[0])
    else:
      registers.setYankedRegister(line)

proc insertRunesFromRegister(
  bufStatus: var BufferStatus,
  position: BufferPosition,
  register: Register) =
    ## Get buffer from the register.

    let oldLine = bufStatus.buffer[position.line]
    var newLine = bufStatus.buffer[position.line]

    newLine.insert(register.buffer[^1], position.column)

    if oldLine != newLine:
      bufStatus.buffer[position.line] = newLine

      bufStatus.countChange.inc
      bufStatus.isUpdate = true

proc insertLinesFromRegister(
  bufStatus: var BufferStatus,
  position: int,
  register: Register) =
    ## Get buffer from the register.

    let beforeBufferLen = bufStatus.buffer.len

    for i in 0 ..< register.buffer.len:
      bufStatus.buffer.insert(
        register.buffer[i],
        position + i)

    if bufStatus.buffer.len > beforeBufferLen:
      bufStatus.countChange.inc
      bufStatus.isUpdate = true

proc pasteAfterCursor*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  register: Register) =
    ## Paste buffer after the current cursor position.
    ## The buffer get from the register.
    ## if runes, Move the cursor position to the end of the runes.
    ## if lines, Move the cursor position to the first word of the inserted
    ## lines.

    if register.buffer.len > 0:
      if register.isLine:
        let beforeBufferLen = bufStatus.buffer.len
        bufStatus.insertLinesFromRegister(windowNode.currentLine + 1, register)
        if bufStatus.buffer.len > beforeBufferLen:
          # Move to a first word of the next line.
          windowNode.moveToFirstWordOfNextLine(bufStatus)
      else:
        let
          beforeCountChange = bufStatus.countChange
          insertColumn =
            if bufStatus.isEmptyLine(windowNode): 0
            else: windowNode.currentColumn + 1
          position = BufferPosition(
            line: windowNode.currentLine,
            column: insertColumn)

        bufStatus.insertRunesFromRegister(position, register)
        if bufStatus.countChange > beforeCountChange:
          # Move to end of the word.
          if insertColumn == 0:
            windowNode.currentColumn += register.buffer[^1].len - 1
          else:
            windowNode.currentColumn += register.buffer[^1].len

proc pasteAfterCursor*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  registers: var Registers,
  registerName: string = "") =
    ## The buffer get from the named register.

    let r = registers.getRegister(registerName)
    if not r.buffer.isEmpty:
      bufStatus.pasteAfterCursor(windowNode, r)

proc pasteBeforeCursor*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  register: Register) =
    ## Paste buffer lines before the current cursor position.
    ## The buffer get from the register.
    ## if runes, Move the cursor position to the end of the runes.
    ## if lines, Move the cursor position to the first of the inserted lines.

    if register.buffer.len > 0:
      if register.isLine:
        let beforeBufferLen = bufStatus.buffer.len
        bufStatus.insertLinesFromRegister(windowNode.currentLine, register)
        if bufStatus.buffer.len > beforeBufferLen and
           bufStatus.buffer[windowNode.currentLine].len > 0:
             # Move to a first word of the currentLine line.
             let
               currentLine = windowNode.currentLine
               currentColumn = windowNode.currentColumn
             if isWhiteSpace(bufStatus.buffer[currentLine][currentColumn]):
               bufStatus.moveToForwardWord(windowNode)
      else:
        let beforeCountChange = bufStatus.countChange
        bufStatus.insertRunesFromRegister(windowNode.bufferPosition, register)
        if bufStatus.countChange > beforeCountChange:
          # Move to end of the word.
          windowNode.currentColumn += register.buffer[^1].len - 1

proc pasteBeforeCursor*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  registers: var Registers,
  registerName: string = "") =
    ## The buffer get from the register.

    let r = registers.getRegister(registerName)
    if not r.buffer.isEmpty:
      bufStatus.pasteBeforeCursor(windowNode, r)

proc replaceCharacters*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  autoIndent, autoDeleteParen: bool,
  tabStop, loop: int,
  character: Rune) =
    ## Replace characters and move to the right
    ## For 'r' command.

    if isEnterKey(character):
      let
        line = bufStatus.buffer[windowNode.currentLine]
        currentLine = windowNode.currentLine
        currentColumn = windowNode.currentColumn
      for _ in windowNode.currentColumn ..< min(line.len, loop):
        bufStatus.deleteCharacter(currentLine, currentColumn, autoDeleteParen)
      keyEnter(bufStatus, windowNode, autoIndent, tabStop)
    else:
      let oldLine = bufStatus.buffer[windowNode.currentLine]
      var newLine = bufStatus.buffer[windowNode.currentLine]

      block:
        let currentColumn = windowNode.currentColumn
        for i in currentColumn ..< min(newLine.len, currentColumn + loop):
          newLine[i] = character

      if oldLine != newLine:
        bufStatus.buffer[windowNode.currentLine] = newLine

        let currentColumn = windowNode.currentColumn
        windowNode.currentColumn = min(newLine.high, currentColumn + loop - 1)

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc replaceAll*(b: var BufferStatus, lineRange: Range, sub, by: Runes) =
  ## Replaces all words.

  if sub.len < 1 or by.len < 1: return

  var isChanged = false

  if sub.contains(ru'\n') or by.contains(ru'\n'):
    let r = b.buffer.toRunes.searchAll(sub, false, false)
    if r.len > 0:
      let oldBuffer = b.buffer.toRunes

      let diff = by.high - sub.high
      # if including Newline, Convert the buffer to `Runes` and replace runes.
      var newBuffer = b.buffer.toRunes
      for i, position in r:
        let start = position + (diff * i)
        newBuffer.delete(start .. start + sub.high)
        newBuffer.insert(by, start)

      if oldBuffer != newBuffer:
        b.buffer = newBuffer.splitLines.toGapBuffer
        if not isChanged: isChanged = true
  else:
    for i in lineRange.first .. lineRange.last:
      let r = b.buffer[i].searchAll(sub, false, false)
      if r.len > 0:
        let oldLine = b.buffer[i]

        let diff = by.high - sub.high
        var newLine = b.buffer[i]
        for i, position in r:
          let start = position + (diff * i)
          newLine.delete(start .. start + sub.high)
          newLine.insert(by, start)

        if oldLine != newLine:
          b.buffer[i] = newLine
          if not isChanged: isChanged = true

  if isChanged and not b.isUpdate:
    b.isUpdate = true
    b.countChange.inc

proc replaceOnlyFirstWordInLines*(
  b: var BufferStatus,
  lineRange: Range,
  sub, by: Runes) =
    ## Replaces words in only first positions in lines.
    ## If contains NewLine in `sub` or `by`, change to `replaceAll`.

    if sub.len < 1 or by.len < 1: return

    if sub.contains(ru'\n') or by.contains(ru'\n'):
      b.replaceAll(lineRange, sub, by)
    else:
      var isChanged = false

      for i in lineRange.first .. lineRange.last:
        let r = b.buffer[i].search(sub, false, false)
        if r.isSome:
          let oldLine = b.buffer[i]

          var newLine = b.buffer[i]
          newLine.delete(r.get .. r.get + sub.high)
          newLine.insert(by, r.get)

          if oldLine != newLine:
            b.buffer[i] = newLine
            if not isChanged: isChanged = true

      if isChanged and not b.isUpdate:
        b.isUpdate = true
        b.countChange.inc

proc toggleCharacters*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  loop: int) =

    let oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]

    for i in windowNode.currentColumn ..< min(newLine.len, loop):
      newLine[i] = toggleCase(oldLine[i])

    if oldLine != newLine:
      bufStatus.buffer[windowNode.currentLine] = newLine

      windowNode.currentColumn = min(newLine.len, loop)

      inc(bufStatus.countChange)
      bufStatus.isUpdate = true

proc autoIndentCurrentLine*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    let currentLine = windowNode.currentLine

    if currentLine == 0 or bufStatus.buffer[currentLine].len == 0: return

    # Check prev line indent
    var prevLineIndent = 0
    for r in bufStatus.buffer[currentLine - 1]:
      if r == ru' ': inc(prevLineIndent)
      else: break

    # Set indent in current line
    let
      indent = ru' '.repeat(prevLineIndent)
      oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]

    # Delete current indent
    for i in 0 ..< oldLine.len:
      if oldLine[i] == ru' ':
        newLine.delete(0)
      else: break

    newLine.insert(indent, 0)

    if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

    # Update column in current line
    windowNode.currentColumn = prevLineIndent

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc joinLine*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if windowNode.currentLine == bufStatus.buffer.len - 1 or
     bufStatus.buffer[windowNode.currentLine + 1].len < 1: return

  let oldLine = bufStatus.buffer[windowNode.currentLine]
  var newLine = bufStatus.buffer[windowNode.currentLine]
  newLine.add(bufStatus.buffer[windowNode.currentLine + 1])
  if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

  bufStatus.buffer.delete(windowNode.currentLine + 1,
                          windowNode.currentLine + 1)

  inc(bufStatus.countChange)
  bufStatus.isUpdate = true

proc deleteTrailingSpaces*(bufStatus: var BufferStatus) =
  var isChanged = false
  for i in 0 ..< bufStatus.buffer.len:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    for j in countdown(newLine.high, 0):
      if newLine[j] == ru' ': newLine.delete(newLine.high)
      else: break

    if oldLine != newLine:
      bufStatus.buffer[i] = newLine
      isChanged = true

  if isChanged:
    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc undo*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if not bufStatus.buffer.canUndo: return

  bufStatus.buffer.undo
  windowNode.revertPosition(
    bufStatus.positionRecord,
    bufStatus.buffer.lastSuitId)

  if (bufStatus.mode.isInsertMode or bufStatus.mode.isReplaceMode) and
     windowNode.currentColumn > bufStatus.buffer[windowNode.currentLine].len and
     windowNode.currentColumn > 0:
    (windowNode.currentLine, windowNode.currentColumn) =
      bufStatus.buffer.prev(windowNode.currentLine,
      windowNode.currentColumn + 1)
  # if Other than replace mode and insert mode
  elif (not bufStatus.mode.isInsertMode and not bufStatus.mode.isReplaceMode) and
       windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].len and
       windowNode.currentColumn > 0:
    (windowNode.currentLine, windowNode.currentColumn) =
      bufStatus.buffer.prev(windowNode.currentLine,
      windowNode.currentColumn)

  inc(bufStatus.countChange)
  bufStatus.isUpdate = true

proc redo*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if not bufStatus.buffer.canRedo: return

  bufStatus.buffer.redo
  windowNode.revertPosition(
    bufStatus.positionRecord,
    bufStatus.buffer.lastSuitId)

  inc(bufStatus.countChange)
  bufStatus.isUpdate = true

proc deleteInsideOfParen*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  registers: var Registers,
  registerName: string,
  rune: Rune,
  settings: EditorSettings) =
    ## If cursor is inside of paren, delete inside paren in the current line

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      oldLine = bufStatus.buffer[currentLine]
      openParen =
        if isCloseParen(rune): correspondingOpenParen(rune)
        else: rune
      closeParen =
        if isOpenParen(rune): correspondingCloseParen(rune)
        else: rune

    var
      openParenPosition = -1
      closeParenPosition = -1

    # Check open paren position
    for i in countdown(currentColumn, 0):
      if oldLine[i] == openParen:
        openParenPosition = i
        break

    # Check close paren position
    for i in openParenPosition + 1 ..< oldLine.len:
      if oldLine[i] == closeParen:
        closeParenPosition = i
        break

    if openParenPosition > 0 and closeParenPosition > 0:
      var
        newLine = bufStatus.buffer[currentLine]
        deleteBuffer = ru ""

      for i in 0 ..< closeParenPosition - openParenPosition - 1:
        deleteBuffer.add newLine[openParenPosition + 1]
        newLine.delete(openParenPosition + 1)

      if oldLine != newLine:
        if registerName.isNamedRegisterName:
          registers.setNamedRegister(deleteBuffer, registerName[0])
        else:
          registers.setDeletedRegister(deleteBuffer)

        bufStatus.buffer[currentLine] = newLine
        windowNode.currentColumn = openParenPosition

proc deleteInsideOfParen*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  registers: var Registers,
  rune: Rune,
  settings: EditorSettings) =
    ## If cursor is inside of paren, delete inside paren in the current line

    const RegisterName = ""
    bufStatus.deleteInsideOfParen(
      windowNode,
      registers,
      RegisterName,
      rune,
      settings)

proc getWordUnderCursor*(
  bufStatus: BufferStatus,
  windowNode: WindowNode): (int, Runes) =
    ## Return the column and word

    let line = bufStatus.buffer[windowNode.currentLine]
    if line.len <= windowNode.currentColumn:
      return

    let atCursorRune = line[windowNode.currentColumn]
    if not atCursorRune.isAlpha and not (char(atCursorRune) in '0'..'9'):
      return

    var
      beginCol = -1
      endCol = -1
    for i in countdown(windowNode.currentColumn, 0):
      if not line[i].isAlpha and not (char(line[i]) in '0'..'9'):
        break
      beginCol = i
    for i in windowNode.currentColumn..line.len()-1:
      if not line[i].isAlpha and not (char(line[i]) in '0'..'9'):
        break
      endCol = i
    if endCol == -1 or beginCol == -1:
      (-1, Runes.default)
    else:
      return (beginCol, line[beginCol..endCol])

proc getCharacterUnderCursor*(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Rune =

    let line = bufStatus.buffer[windowNode.currentLine]
    if line.len() <= windowNode.currentColumn:
      return

    line[windowNode.currentColumn]

proc modifyNumberTextUnderCurosr*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  amount: int) =
    ## Increment/Decrement the number string under the cursor

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn

    if not isDigit(bufStatus.buffer[currentLine][currentColumn]): return

    let
      wordUnderCursor = bufStatus.getWordUnderCursor(windowNode)
      word = wordUnderCursor[1]

    let
      num = parseInt(word)
      oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]

    # Delete the current number string from newLine
    block:
      var col = currentColumn
      while newLine.len > 0 and isDigit(newLine[col]):
        newLine.delete(col)
        if col > newLine.high: col = newLine.high

    # Insert the new number string to newLine
    block:
      let newNumRunes= toRunes(num + amount)
      newLine.insert(newNumRunes, currentColumn)

    # Update bufStatus.buffer
    if newLine != oldLine:
      bufStatus.buffer[currentLine] = newLine

    inc(bufStatus.countChange)
    bufStatus.isUpdate = true

proc replaceCurrentCharAndMoveToRight*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  isAutoDeleteParen: bool,
  r: Rune) =
    ## Replace the current character or insert the character and move to the
    ## right.

    if windowNode.currentColumn < bufStatus.buffer[windowNode.currentLine].len:
      let
        currentLine = windowNode.currentLine
        currentColumn = windowNode.currentColumn
        oldLine = bufStatus.buffer[currentLine]
      var newLine = bufStatus.buffer[currentLine]
      newLine[currentColumn] = r

      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    else:
      bufStatus.insertCharacter(windowNode, isAutoDeleteParen, r)

    bufStatus.keyRight(windowNode)

    bufStatus.countChange.inc
    bufStatus.isUpdate = true
