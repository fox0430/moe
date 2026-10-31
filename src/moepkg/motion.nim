#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## Command executor with text object support
##
## This module extends the command executor to handle text objects
## like iw, aw, i", a", i(, a(, etc.

import std/[options, unicode]

import pkg/results

import
  cursor_util, types, unicode_utils, char_class, logger, render_utils, modes,
  wanted_column
import buffer/[core, edit, fold, undo]
import visible_rows

type
  # Motion command with count
  MotionCommand* = object
    motion*: Motion
    count*: int
    targetChar*: string # For find/till commands
    repeat*: bool ## `;`/`,` repeating f/F/t/T

  MotionType* = enum
    ## How an operator takes the text up to where a motion lands
    mtExclusive ## Up to the place, not including it (w b h l 0 ^ | F T { } ` n *)
    mtInclusive ## Up to and including it (e ge $ g_ f t % gn)
    mtLinewise ## Whole lines (j k gg G H M L + - ')

  MotionLanding* = object
    ## Where a motion lands and how an operator takes the text up to there, as
    ## Vim's motion commands fill in the operator's arguments
    pos*: BufferPosition
    motionType*: MotionType
    failed*: bool
      ## The motion failed (Vim beeps), and a waiting operator does nothing.
      ## It may still have moved part of the way (`3b` near the start).
    useRegOne*: bool
      ## A delete over it goes to register 1 even within a line (Vim's
      ## use_reg_one)
    screenCell*: Option[int]
      ## After gj and gk with lines wrapped, the screen cell they aim for
      ## (`screenCellOf`), or LineEnd after `$`, as Vim's nv_screengo leaves
      ## curswant

  # Motion executor - handles only motion logic
  MotionExecutor* = ref object
    buffer*: core.TextBuffer

  # Viewport manager - handles viewport updates
  ViewportManager* = ref object
    viewport*: ViewPort
    wrapCountCache*: WrapCountCache
      # Bound to the active window's cache by syncActiveWindow.

  # Cursor manager - handles cursor positioning and clamping
  CursorManager* = ref object
    state*: EditorState

  # Main motion controller - coordinates between components
  MotionController* = ref object
    executor*: MotionExecutor
    viewportManager*: ViewportManager
    cursorManager*: CursorManager

const tagScanInitialRadius = 128
  ## Initial half-window (in lines) scanned around the cursor for it/at. The
  ## window quadruples until the enclosing pair is found, so the common case
  ## touches only nearby lines instead of flattening the whole buffer.

proc newMotionExecutor*(buffer: core.TextBuffer): MotionExecutor =
  MotionExecutor(buffer: buffer)

proc lineContentNoNewline(buffer: TextBuffer, lineIdx: int): string =
  ## Get the content of a line excluding any trailing newline.
  ## Returns empty string when lineIdx is out of range.
  if lineIdx < 0 or lineIdx >= buffer.len:
    return ""
  let line = buffer.getLine(lineIdx)
  if line.len > 0 and line[^1] == '\n':
    line[0 ..< ^1]
  else:
    line

proc lineRunesNoNl*(buffer: TextBuffer, line: int): seq[Rune] =
  ## The line's characters with any trailing newline stripped, in the column
  ## model buffer positions use. Out-of-range lines yield an empty seq.
  lineContentNoNewline(buffer, line).toCharRunes()

proc moveLeft(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  result = currentPos
  logDebug(
    "motion",
    "moveLeft: currentPos=(" & $currentPos.y & "," & $currentPos.x & ") count=" & $count,
  )

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    # Move left by character count, not byte count
    let newX = max(0, currentPos.x - count)
    logDebug("motion", "moveLeft: newX=" & $newX)
    result.x = newX

proc moveRight(
    e: MotionExecutor,
    currentPos: CursorPosition,
    count: int,
    mode: EditorMode = EditorMode.Normal,
): CursorPosition =
  result = currentPos
  logDebug(
    "motion",
    "moveRight: currentPos=(" & $currentPos.y & "," & $currentPos.x & ") count=" & $count &
      " bufLen=" & $e.buffer.len,
  )

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    let lineCharLen = line.charLen
    let lineByteLen = line.len
    logDebug(
      "motion",
      "moveRight: line='" & line & "' charLen=" & $lineCharLen & " byteLen=" &
        $lineByteLen,
    )

    # Move right by character count, not byte count.
    let maxPos = maxCursorColumn(lineCharLen, mode)
    let newX = min(currentPos.x + count, maxPos)
    logDebug(
      "motion",
      "moveRight: currentPos.x=" & $currentPos.x & " newX=" & $newX & " maxPos=" &
        $maxPos,
    )
    result.x = newX
  else:
    logDebug("motion", "moveRight: buffer bounds check failed")

proc linesDown*(buffer: TextBuffer, line, count: int): int =
  ## The line `count` lines below `line`, a closed fold counting as one line,
  ## as Vim's cursor_down_inner: the last line when there are fewer, and the
  ## start of a closed fold it lands in. `line` itself when there is no line
  ## below.
  let last = buffer.len - 1
  if last < 0:
    return 0
  if line + count >= last:
    return buffer.foldStart(last)
  if buffer.foldState.folds.len == 0:
    return line + count
  result = line
  for _ in 1 .. count:
    if result >= last:
      break
    result = buffer.foldEnd(result) + 1
  result = buffer.foldStart(min(result, last))

proc linesUp*(buffer: TextBuffer, line, count: int): int =
  ## The line `count` lines above `line`, a closed fold counting as one line,
  ## as Vim's cursor_up_inner: the first line when there are fewer, and the
  ## start of a closed fold it lands in. `line` itself when there is no line
  ## above.
  if buffer.len == 0 or count > line:
    return 0
  if buffer.foldState.folds.len == 0:
    return line - count
  result = buffer.foldStart(line)
  for _ in 1 .. count:
    if result <= 0:
      break
    result = buffer.foldStart(result - 1)

proc moveUp(e: MotionExecutor, currentPos: CursorPosition, count: int): CursorPosition =
  result = currentPos
  result.y = e.buffer.linesUp(currentPos.y, count)

proc moveDown(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  result = currentPos
  result.y = e.buffer.linesDown(currentPos.y, count)

proc moveBackspace(
    e: MotionExecutor,
    currentPos: CursorPosition,
    count: int,
    mode: EditorMode = EditorMode.Normal,
): CursorPosition =
  ## <BS> in Normal/Visual, like Left but wraps to the previous line (Vim 'whichwrap' b).
  result = currentPos
  if e.buffer.isNil or e.buffer.len == 0:
    return
  if currentPos.y < 0 or currentPos.y >= e.buffer.len:
    return
  var remaining = max(1, count)
  while remaining > 0:
    if result.x > 0:
      if result.x >= remaining:
        result.x -= remaining
        remaining = 0
      elif result.y <= 0:
        result.x = 0
        remaining = 0
      else:
        let prev = e.buffer.linesUp(result.y, 1)
        remaining -= result.x + 1
        result.y = prev
        result.x = maxCursorColumn(e.buffer.lineRunesNoNl(prev).len, mode)
    else:
      if result.y <= 0:
        break
      let prev = e.buffer.linesUp(result.y, 1)
      result.y = prev
      result.x = maxCursorColumn(e.buffer.lineRunesNoNl(prev).len, mode)
      dec remaining

proc moveHome(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  result = currentPos
  result.x = 0

proc moveFirstNonBlank(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  ## Move to the first non-blank character on the current line (^ command)
  result = currentPos
  result.x = 0

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    result.x = firstNonBlankColumn(e.buffer.getLine(currentPos.y))

proc moveLastNonBlank(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  ## Move to the last non-whitespace character on the current line (g_ command)
  result = currentPos
  result.x = 0

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    let runes = line.toCharRunes()

    # Find last non-whitespace character by scanning backwards
    for i in countdown(runes.len - 1, 0):
      if not isSpaceOrBreak(runes[i]):
        result.x = i
        break

proc moveEnd(
    e: MotionExecutor, currentPos: CursorPosition, mode: EditorMode = EditorMode.Normal
): CursorPosition =
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let lineCharLen = e.buffer.getLine(currentPos.y).charLen
    result.x = maxCursorColumn(lineCharLen, mode)

func screenColumnCell(count: int): int =
  ## The 0-based screen column `[count]|` aims for; no count is the first.
  max(0, count - 1)

proc moveToScreenColumn(
    e: MotionExecutor,
    currentPos: CursorPosition,
    targetCell: int,
    tabStop: int,
    mode: EditorMode = EditorMode.Normal,
): CursorPosition =
  ## Move to the screen column `targetCell` (0-based) on the current line, as
  ## Vim's `|` (nv_pipe) does: tabs and wide characters occupy their display
  ## cells, and the column past the line end clamps to the line end.
  result = currentPos
  if currentPos.y < 0 or currentPos.y >= e.buffer.len:
    return
  result.x = e.buffer.getLine(currentPos.y).columnAtCell(targetCell, tabStop, mode)

proc moveNextLineFirstNonBlank(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to next line's first non-whitespace character (Enter/+ key in normal mode)
  ## This is like pressing j followed by ^
  result = e.moveDown(currentPos, count)

  # Move to first non-blank character on the new line
  result.x = 0
  if result.y >= 0 and result.y < e.buffer.len:
    result.x = firstNonBlankColumn(e.buffer.getLine(result.y))

proc movePreviousLineFirstNonBlank(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to previous line's first non-whitespace character (- key in normal mode)
  ## This is like pressing k followed by ^
  result = e.moveUp(currentPos, count)

  # Move to first non-blank character on the new line
  result.x = 0
  if result.y >= 0 and result.y < e.buffer.len:
    result.x = firstNonBlankColumn(e.buffer.getLine(result.y))

proc moveFirstLine(
    e: MotionExecutor, currentPos: CursorPosition, count: int = 1
): CursorPosition =
  ## Bare gg and 1gg both go to the first line, so count 1 is the default.
  ## Lands on the first non-blank, as Vim's 'startofline' does.
  result = currentPos
  if e.buffer.len == 0:
    return
  result.y = clamp(count - 1, 0, e.buffer.len - 1)
  result.x = firstNonBlankColumn(e.buffer.getLine(result.y))

proc moveLastLine(
    e: MotionExecutor, currentPos: CursorPosition, count: int = 0
): CursorPosition =
  ## count == 0 means "no explicit prefix — go to last line" (bare G).
  ## count >= 1 means "go to line `count` (1-indexed, clamped)".
  result = currentPos
  if e.buffer.len == 0:
    return
  if count <= 0:
    result.y = e.buffer.len - 1
  else:
    result.y = min(count - 1, e.buffer.len - 1)
  result.x = firstNonBlankColumn(e.buffer.getLine(result.y))

proc searchChar(
    e: MotionExecutor, currentPos: CursorPosition, cmd: MotionCommand
): Option[CursorPosition] =
  ## f/F/t/T as Vim's searchc: none when the line has no `count`-th match.
  ## t/T stop next to it, and repeated by `;`/`,` with no count they step past
  ## the match they stand next to (Vim's 'cpoptions' without `;`).
  if currentPos.y < 0 or currentPos.y >= e.buffer.len:
    return none(CursorPosition)
  let target = cmd.targetChar.toCharRunes
  if target.len != 1:
    return none(CursorPosition)
  let
    forward = cmd.motion in {Motion.FindChar, Motion.TillChar}
    till = cmd.motion in {Motion.TillChar, Motion.TillCharBackward}
    step = if forward: 1 else: -1
    runes = e.buffer.lineRunesNoNl(currentPos.y)
  var
    col = currentPos.x
    skip = cmd.repeat and till and cmd.count == 1
  for _ in 1 .. cmd.count:
    while true:
      col += step
      if col < 0 or col >= runes.len:
        return none(CursorPosition)
      if runes[col] == target[0] and not skip:
        break
      skip = false
  if till:
    col -= step
  some(CursorPosition(x: col, y: currentPos.y))

type WordWalker = object
  ## Steps through a buffer as Vim's inc_cursor/dec_cursor do: the end of a
  ## line is a place of its own, after its last character
  buffer: TextBuffer
  pos: BufferPosition
  runes: seq[Rune]
  bigword: bool ## Vim's cls_bigword: steps over WORDs (`W`, `B`, `E`, `gE`)

proc initWordWalker(
    buffer: TextBuffer, pos: BufferPosition, bigword = false
): WordWalker =
  WordWalker(
    buffer: buffer, pos: pos, runes: buffer.lineRunesNoNl(pos.line), bigword: bigword
  )

proc class(w: WordWalker): int =
  ## Vim's cls(): the character's utf_class(), 0 at the end of a line. A
  ## composing character has the class of the one it is part of. With
  ## `bigword` every non-blank is 1.
  if w.pos.column >= w.runes.len:
    return 0
  let c = utfClass(w.runes[w.runes.baseColumn(w.pos.column)])
  if c != 0 and w.bigword: 1 else: c

proc onEmptyLine(w: WordWalker): bool =
  w.runes.len == 0

proc onNonWhite(w: WordWalker): bool =
  ## On a character other than a space or a tab, so on an ideographic space too.
  w.pos.column < w.runes.len and not w.runes[w.runes.baseColumn(w.pos.column)].isVimWhite

proc inc(w: var WordWalker): int =
  ## One step forward: 0 within the line, 2 onto its end, 1 onto the next line,
  ## -1 at the end of the buffer (no move).
  if w.pos.column < w.runes.len:
    w.pos.column += 1
    return (if w.pos.column < w.runes.len: 0 else: 2)
  if w.pos.line + 1 < w.buffer.len:
    w.pos = BufferPosition(line: w.pos.line + 1, column: 0)
    w.runes = w.buffer.lineRunesNoNl(w.pos.line)
    return 1
  -1

proc dec(w: var WordWalker): int =
  ## One step back: 0 within the line, 1 onto the end of the line before, -1
  ## at the start of the buffer (no move).
  if w.pos.column > 0:
    w.pos.column -= 1
    return 0
  if w.pos.line > 0:
    w.pos.line -= 1
    w.runes = w.buffer.lineRunesNoNl(w.pos.line)
    w.pos.column = w.runes.len
    return 1
  -1

proc toFoldEnd(w: var WordWalker, mode: EditorMode) =
  ## In a closed fold, on to the last character of its last line, as Vim's
  ## fwd_word and end_word do before each word.
  let fold = w.buffer.foldState.getCollapsedFoldAt(w.pos.line)
  if fold.isNone:
    return
  let line = min(fold.get.endLine, w.buffer.len - 1)
  w.runes = w.buffer.lineRunesNoNl(line)
  let column =
    if mode.restsPastLineEnd:
      w.runes.len
    else:
      max(w.runes.len - 1, 0)
  w.pos = BufferPosition(line: line, column: column)

proc toFoldStart(w: var WordWalker) =
  ## In a closed fold, back to the start of its first line, as Vim's bck_word
  ## does before each word.
  let fold = w.buffer.foldState.getCollapsedFoldAt(w.pos.line)
  if fold.isNone:
    return
  w.pos = BufferPosition(line: fold.get.startLine, column: 0)
  w.runes = w.buffer.lineRunesNoNl(w.pos.line)

proc skipClass(w: var WordWalker, class: int, forward: bool): bool =
  ## Vim's skip_chars: step over characters of `class`; true when the buffer
  ## ends first.
  while w.class == class:
    if (if forward: w.inc else: w.dec) == -1:
      return true
  false

proc fwdWord(w: var WordWalker, count: int, eol: bool, mode: EditorMode): bool =
  ## Vim's fwd_word: on to the start of the `count`-th word, stopping at an
  ## empty line. With `eol` (an operator waits) the last word stops at the end
  ## of its line instead of going on to the next. False when it started at the
  ## last character of the buffer.
  for n in countdown(count - 1, 0):
    w.toFoldEnd(mode)
    let
      startClass = w.class
      lastLine = w.pos.line == w.buffer.len - 1
    var i = w.inc
    if i == -1 or (i >= 1 and lastLine):
      return false
    if i >= 1 and eol and n == 0:
      return true
    if startClass != 0:
      while w.class == startClass:
        i = w.inc
        if i == -1 or (i >= 1 and eol and n == 0):
          return true
    while w.class == 0:
      if w.pos.column == 0 and w.onEmptyLine:
        break
      i = w.inc
      if i == -1 or (i >= 1 and eol and n == 0):
        return true
  true

proc bckWord(w: var WordWalker, count: int, stop = false): bool =
  ## Vim's bck_word: back to the start of the `count`-th word, stopping at an
  ## empty line. With `stop` the first stays on the word it stands at the
  ## start of. False when it started at the start of the buffer.
  var stop = stop
  for _ in 1 .. count:
    w.toFoldStart()
    let startClass = w.class
    if w.dec == -1:
      return false
    block finished:
      if not stop or startClass == w.class or startClass == 0:
        while w.class == 0:
          if w.pos.column == 0 and w.onEmptyLine:
            break finished
          if w.dec == -1:
            return true
        if w.skipClass(w.class, forward = false):
          return true
      discard w.inc # overshot
    stop = false
  true

proc endWord(
    w: var WordWalker, count: int, stop: bool, mode: EditorMode, empty = false
): bool =
  ## Vim's end_word: on to the end of the `count`-th word. With `stop` (`cw`)
  ## the first stays on the word it stands at the end of, and with `empty` it
  ## stops at an empty line. False when the buffer ends first.
  var stop = stop
  for _ in 1 .. count:
    w.toFoldEnd(mode)
    let startClass = w.class
    if w.inc == -1:
      return false
    block finished:
      if w.class == startClass and startClass != 0:
        if w.skipClass(startClass, forward = true):
          return false
      elif not stop or startClass == 0:
        while w.class == 0:
          if empty and w.pos.column == 0 and w.onEmptyLine:
            break finished
          if w.inc == -1:
            return false
        if w.skipClass(w.class, forward = true):
          return false
      discard w.dec # overshot
    stop = false
  true

proc bckendWord(w: var WordWalker, count: int, eol = false): bool =
  ## Vim's bckend_word: back to the end of the `count`-th word, stopping at an
  ## empty line, and with `eol` at the end of the line before. False when it
  ## started at the start of the buffer.
  for _ in 1 .. count:
    let startClass = w.class
    var i = w.dec
    if i == -1:
      return false
    if eol and i == 1:
      return true
    if startClass != 0:
      while w.class == startClass:
        i = w.dec
        if i == -1 or (eol and i == 1):
          return true
    while w.class == 0:
      if w.pos.column == 0 and w.onEmptyLine:
        break
      i = w.dec
      if i == -1 or (eol and i == 1):
        return true
  true

proc landWord(
    w: WordWalker, start: BufferPosition, motionType: MotionType, mode: EditorMode
): MotionLanding =
  ## Vim's adjust_cursor: a word motion that went forward onto the end of a
  ## line steps back onto its last character, which an operator then takes.
  ## Insert, Replace and Visual may rest there.
  result = MotionLanding(pos: w.pos, motionType: motionType)
  if start < w.pos and w.pos.column > 0 and w.pos.column >= w.runes.len and
      not mode.restsPastLineEnd:
    result.pos.column -= 1
    result.motionType = mtInclusive

proc wordForward(
    buffer: TextBuffer,
    start: BufferPosition,
    count: int,
    operator: Option[OperatorType],
    mode: EditorMode,
    bigword: bool,
): MotionLanding =
  ## `w` and `W`, as Vim's nv_wordcmd: `cw` on anything but a space or a tab
  ## changes up to the end of a word as `ce` does, and with an operator the
  ## last word stops at the end of its line (`dw` keeps the line break).
  ## Without an operator it fails from the last character of the buffer.
  var w = initWordWalker(buffer, start, bigword)
  if operator == some(OpChange) and w.onNonWhite:
    discard w.endWord(count, stop = true, mode)
    return w.landWord(start, mtInclusive, mode)
  let ok = w.fwdWord(count, eol = operator.isSome, mode)
  result = w.landWord(start, mtExclusive, mode)
  result.failed = not ok and operator.isNone

proc wordEnd(
    buffer: TextBuffer,
    start: BufferPosition,
    count: int,
    operator: Option[OperatorType],
    mode: EditorMode,
    bigword: bool,
): MotionLanding =
  ## `e` and `E`, as Vim's nv_wordcmd: they fail when the buffer ends first,
  ## but not with an operator, which then takes up to the last character.
  var w = initWordWalker(buffer, start, bigword)
  let ok = w.endWord(count, stop = false, mode)
  result = w.landWord(start, mtInclusive, mode)
  result.failed = not ok and operator.isNone

proc wordBackward(
    buffer: TextBuffer, start: BufferPosition, count: int, bigword: bool
): MotionLanding =
  ## `b` and `B`: fail at the start of the buffer.
  var w = initWordWalker(buffer, start, bigword)
  let ok = w.bckWord(count)
  MotionLanding(pos: w.pos, motionType: mtExclusive, failed: not ok)

proc wordEndBackward(
    buffer: TextBuffer, start: BufferPosition, count: int, bigword: bool
): MotionLanding =
  ## `ge` and `gE`: fail at the start of the buffer.
  var w = initWordWalker(buffer, start, bigword)
  let ok = w.bckendWord(count)
  MotionLanding(pos: w.pos, motionType: mtInclusive, failed: not ok)

proc isBlankLine(line: string): bool =
  ## Check if a line is blank (empty or contains only whitespace)
  let content =
    if line.len > 0 and line[^1] == '\n':
      line[0 ..< ^1]
    else:
      line

  if content.len == 0:
    return true

  # Check if all characters are whitespace
  for (r, _) in content.chars:
    if not isSpaceOrBreak(r):
      return false
  return true

proc isParagraphBoundary(buffer: TextBuffer, line: int): bool =
  ## Vim's startPS for `{`/`}`: an empty line, not one of blanks.
  buffer.lineContentNoNewline(line).len == 0

proc findParagraph(
    buffer: TextBuffer, start: BufferPosition, count: int, forward: bool
): MotionLanding =
  ## `}`/`{` as Vim's findpar: to the `count`-th empty line past a paragraph,
  ## or the buffer's edge for the last; fails in place when the edge comes with
  ## paragraphs still to go. `}` to the edge goes to the last character, which
  ## an operator then takes.
  let dir = if forward: 1 else: -1
  var curr = start.line
  for n in countdown(count - 1, 0):
    var
      skipped = false
      first = true
    while true:
      let boundary = buffer.isParagraphBoundary(curr)
      if not boundary:
        skipped = true
      if not first and skipped and boundary:
        break
      curr += dir
      if curr < 0 or curr >= buffer.len:
        if n > 0:
          return MotionLanding(pos: start, motionType: mtExclusive, failed: true)
        curr -= dir
        break
      first = false
  if forward and curr == buffer.len - 1:
    let lineLen = buffer.lineRunesNoNl(curr).len
    if lineLen > 0:
      return MotionLanding(
        pos: BufferPosition(line: curr, column: lineLen - 1), motionType: mtInclusive
      )
  MotionLanding(pos: BufferPosition(line: curr, column: 0), motionType: mtExclusive)

proc moveToMatchingBracket(
    e: MotionExecutor, currentPos: CursorPosition
): CursorPosition =
  ## Move to matching bracket (% motion)
  ## Finds the matching bracket for (, ), {, }, [, ]. Off a bracket, starts
  ## from the first one at or after the cursor on the line, as Vim does.
  result = currentPos

  # Bounds check
  if currentPos.y < 0 or currentPos.y >= e.buffer.len:
    return

  let lineRunes = e.buffer.getLine(currentPos.y).toCharRunes
  var startX = max(currentPos.x, 0)
  while startX < lineRunes.len and not lineRunes[startX].isBracket:
    startX += 1
  if startX >= lineRunes.len:
    return

  let currentRune = lineRunes[startX]
  let bracketPos = CursorPosition(x: startX, y: currentPos.y)

  if currentRune.isOpenBracket:
    # Search forward for closing bracket
    let closeBracket = correspondingCloseBracket(currentRune)
    var depth = 1
    var lineIdx = bracketPos.y
    var colIdx = bracketPos.x + 1

    while lineIdx < e.buffer.len:
      # Index a one-time rune copy of the line instead of a skip scan plus a
      # sliced toCharRunes copy per line.
      let runes = e.buffer.getLine(lineIdx).toCharRunes
      var charPos = if lineIdx == bracketPos.y: colIdx else: 0

      while charPos < runes.len:
        let r = runes[charPos]
        if r == currentRune:
          depth += 1
        elif r == closeBracket:
          depth -= 1
          if depth == 0:
            result.y = lineIdx
            result.x = charPos
            return
        charPos += 1

      lineIdx += 1
      colIdx = 0
  else:
    # Search backward for opening bracket
    let openBracket = correspondingOpenBracket(currentRune)
    var depth = 1
    var lineIdx = bracketPos.y
    var colIdx = bracketPos.x - 1

    while lineIdx >= 0:
      # Index a one-time rune copy of the line instead of rescanning from the
      # start per column (avoids O(n^2) on long lines).
      let runes = e.buffer.getLine(lineIdx).toCharRunes

      # Set starting column
      if lineIdx != bracketPos.y:
        colIdx = runes.len - 1

      # Search backward for matching bracket
      while colIdx >= 0:
        let targetRune = runes[colIdx]
        if targetRune == currentRune:
          depth += 1
        elif targetRune == openBracket:
          depth -= 1
          if depth == 0:
            result.y = lineIdx
            result.x = colIdx
            return

        colIdx -= 1

      lineIdx -= 1

proc viewportLayout(e: MotionExecutor, rl: RowLayout): RowLayout =
  ## `rl`, or one row a line when there is none.
  if rl.buffer.isNil:
    initRowLayout(e.buffer, nil, false, 1, 8)
  else:
    rl

proc onViewportLine(
    e: MotionExecutor, currentPos: CursorPosition, line: int
): CursorPosition =
  ## `line` at its first non-blank, as Vim's H, M and L go on with
  ## beginline(BL_SOL | BL_FIX), also on a line in a closed fold.
  result = currentPos
  result.y = clamp(line, 0, e.buffer.len - 1)
  result.x = firstNonBlankColumn(e.buffer.getLine(result.y))

proc viewportHighLine(e: MotionExecutor, top, botline, count: int): int =
  ## H: the [count]th line from the window's `top`, as Vim's nv_scroll. With
  ## folds, a closed one counts as one line and the count stops at the last
  ## line shown whole, above `botline`.
  if e.buffer.foldState.folds.len == 0:
    return top + count - 1
  result = top
  for _ in 1 ..< count:
    if result >= botline - 1:
      break
    result = e.buffer.foldEnd(result) + 1

proc viewportMiddleLine(
    e: MotionExecutor, rl: RowLayout, top, wholeRows, height: int
): int =
  ## M: the line half the `wholeRows` the lines shown whole take down, as
  ## Vim's nv_scroll. A line counts its rows up to the window's `height`, a
  ## closed fold one.
  let half = (wholeRows + 1) div 2
  var
    used = 0
    n = 0
  while top + n < e.buffer.len - 1:
    used += min(rl.rowsOf(top + n), height)
    if used >= half:
      break
    n = e.buffer.foldEnd(top + n) - top + 1
  if n > 0 and used > height:
    dec n
  top + n

proc viewportLowLine(e: MotionExecutor, top, botline, count: int): int =
  ## L: the [count]th line up from the last one shown whole, above
  ## `botline`, as Vim's nv_scroll. With folds, a closed one counts as one
  ## line and the count stops at the window's `top`.
  result = botline - 1
  if count - 1 >= botline:
    return 0
  if e.buffer.foldState.folds.len == 0:
    return result - (count - 1)
  for _ in 1 ..< count:
    if result <= top:
      break
    result = e.buffer.foldStart(result)
    if result > top:
      dec result

func intoWindow(line, top, botline, lineCount: int): int =
  ## `line` brought onto the lines from the window's `top` to the last one
  ## shown whole, as Vim's cursor_correct does with 'scrolloff' 0.
  let last = botline - 1
  if last <= top:
    top
  elif line < top and top > 0:
    top
  elif line > last and botline < lineCount:
    last
  else:
    line

proc rightForOperator(
    buffer: TextBuffer, start: BufferPosition, count: int
): MotionLanding =
  ## `l` with an operator, as Vim's nv_right: past the last character it takes
  ## that one, and on an empty line it takes nothing (`cl` still inserts).
  let lineLen = buffer.lineRunesNoNl(start.line).len
  if lineLen == 0:
    MotionLanding(pos: start, motionType: mtExclusive)
  elif start.column + count >= lineLen:
    MotionLanding(
      pos: BufferPosition(line: start.line, column: lineLen - 1),
      motionType: mtInclusive,
    )
  else:
    MotionLanding(
      pos: BufferPosition(line: start.line, column: start.column + count),
      motionType: mtExclusive,
    )

const WideWordMotions = {
  Motion.WideWordForward, Motion.WideWordBackward, Motion.WideWordEnd,
  Motion.WideWordEndBackward,
} ## `W`, `B`, `E` and `gE`, which step over WORDs (Vim's cls_bigword).

const ScreenLineMotions = {Motion.ScreenLineDown, Motion.ScreenLineUp}
  ## gj and gk, which move over the rows of wrapped lines.

proc screenLineLanding(
    rl: RowLayout,
    start: BufferPosition,
    aim: int,
    forward: bool,
    count: int,
    win: EditorWindow,
): MotionLanding =
  ## gj and gk with lines wrapped, as Vim's nv_screengo: `count` rows down or
  ## up from `start`, the cursor of `win`, aiming for the screen cell `aim`
  ## (`screenCellOf`), or with LineEnd for the last cell of each row. A closed
  ## fold is one row. At the first or last row it fails as far as it went,
  ## still onto the cell it aims for.
  let
    buffer = rl.buffer
    width = rl.maxWidth
    last = buffer.len - 1
    atEnd = aim == LineEnd
  var
    line = start.line
    want = aim
  if atEnd:
    let cell = rl.screenCellOf(line, start.column, win.cursorOnTabEnd(start))
    want = cell div width * width + width - 1
  else:
    want = min(want, rl.lineRows(line) * width - 1)
  for _ in 1 .. count:
    let folded = buffer.foldState.getCollapsedFoldAt(line).isSome
    if forward:
      if want + width < rl.lineRows(line) * width and not folded:
        want += width
        continue
      if line >= last:
        result.failed = true
        break
      # As Vim's cursor_down_inner: to the last line even inside a fold.
      line =
        if line + 1 >= last:
          last
        elif folded:
          min(buffer.foldEnd(line) + 1, last)
        else:
          line + 1
      want = want mod width
    else:
      if want >= width and not folded:
        want -= width
        continue
      if line <= 0:
        result.failed = true
        break
      line = buffer.linesUp(line, 1)
      want += (rl.lineRows(line) - 1) * width
  var column = rl.columnAtScreenCell(line, want, win.mode)
  if column > 0:
    # A character shown past the cell, as a tab or one too wide for the row
    # it would start on, gives way to the one before it when the cell is in
    # the right half of the row.
    let shown = rl.screenCellOf(
      line, column, win.cursorOnTabEnd(BufferPosition(line: line, column: column))
    )
    if shown > want and want mod width > width div 2:
      for g in buffer.getLine(line).glyphsOf(rl.tabStop):
        if column - 1 < g.next:
          column = g.column
          break
  result.pos = BufferPosition(line: line, column: column)
  result.motionType = if atEnd: mtInclusive else: mtExclusive
  result.screenCell = some(if atEnd: LineEnd else: want)

proc landMotion*(
    e: MotionExecutor,
    currentPos: CursorPosition,
    cmd: MotionCommand,
    viewportHeight: int = 24,
    viewportTopLine: int = 0,
    reservedLines: int = steadyBottomAreaHeight(),
    mode: EditorMode = EditorMode.Normal,
    rowLayout: RowLayout = RowLayout(),
    viewportTopWrapOffset: int = 0,
    operator = none(OperatorType),
): MotionLanding =
  ## Where `cmd` takes the cursor from `currentPos`, how `operator`, when one
  ## waits, takes the text up to there, and whether the motion fails.
  ## `visibleRows` is used for viewport-relative motions. gj and gk are `j`
  ## and `k`: the controller lands them over wrapped rows (`screenLineLanding`).
  let
    visibleRows = max(1, viewportHeight - max(0, reservedLines))
    viewportTop = (line: viewportTopLine, offset: viewportTopWrapOffset)
    start = BufferPosition(line: currentPos.y, column: currentPos.x)
    bigword = cmd.motion in WideWordMotions

  proc at(pos: CursorPosition, motionType: MotionType): MotionLanding =
    MotionLanding(
      pos: BufferPosition(line: pos.y, column: pos.x), motionType: motionType
    )

  proc stuck(motionType: MotionType): MotionLanding =
    MotionLanding(pos: start, motionType: motionType, failed: true)

  proc sideways(pos: CursorPosition): MotionLanding =
    ## `h` and `l` fail when they cannot move at all, as Vim's nv_left and
    ## nv_right beep, but not with an operator (`dh` at a line's start).
    if pos == currentPos and operator.isNone:
      stuck(mtExclusive)
    else:
      at(pos, mtExclusive)

  proc usingRegOne(landing: MotionLanding): MotionLanding =
    ## `landing` marked so a delete over it goes to register 1, as Vim's
    ## nv_percent and nv_findpar set use_reg_one.
    result = landing
    result.useRegOne = true

  proc offLine(pos: CursorPosition): MotionLanding =
    ## A line motion fails when there is no line to go to (`k` on the first).
    if pos.y == currentPos.y:
      stuck(mtLinewise)
    else:
      at(pos, mtLinewise)

  proc countLinesDown(): Option[CursorPosition] =
    ## The line `count - 1` lines down, as Vim's cursor_down goes for `$` and
    ## `_`: as far as there are lines, and none from the last line.
    let n = cmd.count - 1
    if n <= 0:
      return some(currentPos)
    let pos = e.moveDown(currentPos, n)
    if pos.y == currentPos.y:
      none(CursorPosition)
    else:
      some(pos)

  case cmd.motion
  of Motion.Left:
    sideways(e.moveLeft(currentPos, cmd.count))
  of Motion.Backspace:
    sideways(e.moveBackspace(currentPos, cmd.count, mode))
  of Motion.Right:
    if operator.isSome:
      e.buffer.rightForOperator(start, cmd.count)
    else:
      sideways(e.moveRight(currentPos, cmd.count, mode))
  of Motion.Up, Motion.ScreenLineUp:
    offLine(e.moveUp(currentPos, cmd.count))
  of Motion.Down, Motion.ScreenLineDown:
    offLine(e.moveDown(currentPos, cmd.count))
  of Motion.Home:
    at(e.moveHome(currentPos), mtExclusive)
  of Motion.FirstNonBlank:
    at(e.moveFirstNonBlank(currentPos), mtExclusive)
  of Motion.LinewiseFirstNonBlank:
    let down = countLinesDown()
    if down.isNone:
      stuck(mtLinewise)
    elif operator == some(OpYank):
      # As Vim's nv_lineop, a yank leaves the cursor's column.
      at(down.get, mtLinewise)
    else:
      at(e.moveFirstNonBlank(down.get), mtLinewise)
  of Motion.LastNonBlank:
    let down = countLinesDown()
    if down.isNone:
      stuck(mtInclusive)
    else:
      at(e.moveLastNonBlank(down.get), mtInclusive)
  of Motion.End:
    let down = countLinesDown()
    if down.isNone:
      stuck(mtInclusive)
    else:
      at(e.moveEnd(down.get, mode), mtInclusive)
  of Motion.FirstLine:
    at(e.moveFirstLine(currentPos, cmd.count), mtLinewise)
  of Motion.LastLine:
    at(e.moveLastLine(currentPos, cmd.count), mtLinewise)
  of Motion.FindChar, Motion.FindCharBackward, Motion.TillChar, Motion.TillCharBackward:
    let
      found = e.searchChar(currentPos, cmd)
      motionType =
        if cmd.motion in {Motion.FindChar, Motion.TillChar}:
          mtInclusive
        else:
          mtExclusive
    if found.isNone:
      stuck(motionType)
    else:
      at(found.get, motionType)
  of Motion.WordForward, Motion.WideWordForward:
    e.buffer.wordForward(start, cmd.count, operator, mode, bigword)
  of Motion.WordBackward, Motion.WideWordBackward:
    e.buffer.wordBackward(start, cmd.count, bigword)
  of Motion.WordEnd, Motion.WideWordEnd:
    e.buffer.wordEnd(start, cmd.count, operator, mode, bigword)
  of Motion.WordEndBackward, Motion.WideWordEndBackward:
    e.buffer.wordEndBackward(start, cmd.count, bigword)
  of Motion.ParagraphForward:
    e.buffer.findParagraph(start, cmd.count, forward = true).usingRegOne
  of Motion.ParagraphBackward:
    e.buffer.findParagraph(start, cmd.count, forward = false).usingRegOne
  of Motion.ViewportHigh, Motion.ViewportMiddle, Motion.ViewportLow:
    if e.buffer.len == 0:
      return at(currentPos, mtLinewise)
    let
      rl = e.viewportLayout(rowLayout)
      (botline, wholeRows) =
        rl.botline(viewportTop.line, viewportTop.offset, visibleRows)
    var line =
      case cmd.motion
      of Motion.ViewportHigh:
        e.viewportHighLine(viewportTop.line, botline, cmd.count)
      of Motion.ViewportMiddle:
        e.viewportMiddleLine(rl, viewportTop.line, wholeRows, visibleRows)
      else:
        e.viewportLowLine(viewportTop.line, botline, cmd.count)
    # Vim keeps the cursor in the window, but not where an operator goes.
    if operator.isNone:
      line = intoWindow(line, viewportTop.line, botline, e.buffer.len)
    at(e.onViewportLine(currentPos, line), mtLinewise)
  of Motion.NextLineFirstNonBlank:
    offLine(e.moveNextLineFirstNonBlank(currentPos, cmd.count))
  of Motion.PreviousLineFirstNonBlank:
    offLine(e.movePreviousLineFirstNonBlank(currentPos, cmd.count))
  of Motion.MatchBracket:
    let pos = e.moveToMatchingBracket(currentPos)
    if pos == currentPos:
      stuck(mtInclusive)
    else:
      at(pos, mtInclusive).usingRegOne
  of Motion.ScreenColumn:
    at(
      e.moveToScreenColumn(
        currentPos, cmd.count.screenColumnCell, rowLayout.tabStop, mode
      ),
      mtExclusive,
    )
  of Motion.RepeatFind, Motion.RepeatFindReverse:
    # Must be resolved to a concrete motion before reaching here.
    raiseAssert "RepeatFind must be resolved before landMotion"

proc calculateNewPosition*(
    e: MotionExecutor,
    currentPos: CursorPosition,
    cmd: MotionCommand,
    viewportHeight: int = 24,
    viewportTopLine: int = 0,
    reservedLines: int = steadyBottomAreaHeight(),
    mode: EditorMode = EditorMode.Normal,
    rowLayout: RowLayout = RowLayout(),
    viewportTopWrapOffset: int = 0,
): CursorPosition =
  ## New cursor position after motion (no state change). A failed motion
  ## leaves the cursor as far as it went.
  let landing = e.landMotion(
    currentPos, cmd, viewportHeight, viewportTopLine, reservedLines, mode, rowLayout,
    viewportTopWrapOffset,
  )
  CursorPosition(x: landing.pos.column, y: landing.pos.line)

proc newCursorManager*(state: EditorState): CursorManager =
  CursorManager(state: state)

proc clampPosition*(
    mgr: CursorManager,
    pos: CursorPosition,
    buf: core.TextBuffer,
    mode = none(EditorMode),
): CursorPosition =
  ## Ensure cursor position is within valid bounds.
  ##
  ## `mode` decides whether the cursor may rest one past the last character,
  ## and defaults to the active window's mode; pass it when clamping another
  ## window, or its Insert cursor moves a column.
  result = pos

  # Clamp line - don't allow cursor beyond last actual line
  if buf.len == 0:
    result.y = 0
    result.x = 0
    return

  # Vim behavior: cursor can't go beyond the last line with content
  if result.y >= buf.len:
    result.y = buf.len - 1
  elif result.y < 0:
    result.y = 0

  # As Vim's foldAdjustCursor: in a closed fold, on to its first line, the
  # column kept.
  let collapsedFold = buf.foldState.getCollapsedFoldAt(result.y)
  if collapsedFold.isSome:
    result.y = collapsedFold.get.startLine

  # Clamp column - ensure line index is valid before accessing
  if result.y >= 0 and result.y < buf.len:
    let lineCharLen = buf.getLine(result.y).charLen # character count, not bytes
    let maxCol =
      maxCursorColumn(lineCharLen, if mode.isSome: mode.get else: mgr.state.mode)
    if result.x > maxCol:
      result.x = maxCol
    elif result.x < 0:
      result.x = 0

proc newViewportManager*(viewport: ViewPort): ViewportManager =
  ViewportManager(viewport: viewport)

proc updateViewport(
    mgr: ViewportManager,
    cursorPos: CursorPosition,
    lineCount: int,
    showStatusLine: bool = true,
    reservedLines: int = -1, # -1 means auto-calculate
    lineWrap: bool = false,
    buffer: core.TextBuffer = nil,
    viewportOffset: int = 0,
    tabStop: int = 4,
    onTabEnd = false,
) =
  ## Keep cursor visible; scrolls viewport as needed.

  # Ensure we have valid data
  if lineCount <= 0:
    mgr.viewport.resetViewportTop()
    return

  let
    # Ensure cursor position is within valid bounds
    clampedCursorY = max(0, min(cursorPos.y, lineCount - 1))
    clampedCursorX = max(0, cursorPos.x)

    # Use the explicit parameter, or fall back to the steady bottom reserve
    actualReservedLines =
      if reservedLines >= 0:
        reservedLines
      else:
        steadyBottomAreaHeight()

  let visibleHeight = max(1, mgr.viewport.height - actualReservedLines)
  if buffer.isNil:
    if clampedCursorY < mgr.viewport.topLine:
      mgr.viewport.resetViewportTop(clampedCursorY)
    elif clampedCursorY >= mgr.viewport.topLine + visibleHeight:
      let
        newTopLine = clampedCursorY - visibleHeight + 1
        maxTopLine = max(0, lineCount - visibleHeight)
      mgr.viewport.resetViewportTop(max(0, min(maxTopLine, newTopLine)))
  else:
    let maxWidth = wrapWidthFor(mgr.viewport.width, viewportOffset)
    initRowLayout(buffer, mgr.wrapCountCache, lineWrap, maxWidth, tabStop)
      .scrollViewportToCursor(
        mgr.viewport, clampedCursorY, clampedCursorX, visibleHeight, onTabEnd
      )

proc updateViewport*(
    mgr: ViewportManager,
    state: EditorState,
    buffer: core.TextBuffer,
    pos: BufferPosition,
) =
  ## Keep `pos` of `buffer`, where the cursor of the active window goes, in
  ## view, with the window's settings from `state`.
  mgr.updateViewport(
    CursorPosition(x: pos.column, y: pos.line),
    buffer.len,
    state.showStatusLine,
    state.motionReservedLines(),
    state.effectiveLineWrap(),
    buffer,
    viewportOffsetFor(buffer, state),
    state.tabStop,
    not state.activeWindow.isNil and state.activeWindow.cursorOnTabEnd(pos),
  )

proc newMotionController*(
    buf: core.TextBuffer, state: EditorState, viewport: ViewPort
): MotionController =
  MotionController(
    executor: newMotionExecutor(buf),
    viewportManager: viewport.newViewportManager,
    cursorManager: newCursorManager(state),
  )

proc rowLayout*(controller: MotionController): RowLayout =
  ## The rows of the active window, as motions and scrolls count them.
  let state = controller.cursorManager.state
  initRowLayout(
    controller.executor.buffer,
    controller.viewportManager.wrapCountCache,
    state.effectiveLineWrap(),
    wrapWidthFor(
      controller.viewportManager.viewport.width,
      viewportOffsetFor(controller.executor.buffer, state),
    ),
    state.tabStop,
  )

const
  VerticalMotions = {Motion.Up, Motion.Down}
    ## Motions that aim for the wanted column (Vim's curswant).
  LineEdgeMotions = {
    Motion.Home, Motion.FirstNonBlank, Motion.LinewiseFirstNonBlank,
    Motion.LastNonBlank, Motion.FirstLine, Motion.LastLine, Motion.ViewportHigh,
    Motion.ViewportMiddle, Motion.ViewportLow, Motion.NextLineFirstNonBlank,
    Motion.PreviousLineFirstNonBlank,
  } ## Motions onto a line's start or end, other than `$`.

proc unwrapped(controller: MotionController, cmd: MotionCommand): MotionCommand =
  ## `cmd`, with gj and gk as `j` and `k` when lines do not wrap, as Vim's
  ## nv_g_cmd.
  result = cmd
  if cmd.motion in ScreenLineMotions and
      not controller.cursorManager.state.effectiveLineWrap():
    result.motion = if cmd.motion == Motion.ScreenLineDown: Motion.Down else: Motion.Up

proc opensFoldOn(motion: Motion, start: BufferPosition, landing: MotionLanding): bool =
  ## Whether `motion` from `start` opens the closed folds it lands in, as with
  ## Vim's default 'foldopen': `hor` and `block` when they move or succeed,
  ## and `percent` onto another line. Vim's ge, gE, g_ and | open none.
  case motion
  of Motion.Home, Motion.FirstNonBlank:
    true
  of Motion.Left, Motion.Right, Motion.Backspace:
    landing.pos != start
  of Motion.WordForward, Motion.WordBackward, Motion.WordEnd, Motion.WideWordForward,
      Motion.WideWordBackward, Motion.WideWordEnd, Motion.FindChar,
      Motion.FindCharBackward, Motion.TillChar, Motion.TillCharBackward,
      Motion.ParagraphForward, Motion.ParagraphBackward, Motion.End:
    not landing.failed
  of Motion.MatchBracket:
    not landing.failed and landing.pos.line != start.line
  else:
    false

proc screenAim(
    controller: MotionController, rl: RowLayout, start: BufferPosition
): int =
  ## The screen cell gj and gk aim for from `start`, the cursor, on the rows
  ## of `rl`, as Vim's curswant with 'wrap': the one kept, LineEnd after `$`,
  ## the one the column vertical moves want stands for on its line, else the
  ## cell it shows on (`aimInFold` in a closed fold).
  let
    win = controller.cursorManager.state.activeWindow
    wanted = win.wanted
  if start == win.cursor and wanted.screenCell >= 0:
    wanted.screenCell
  elif wanted.cell == LineEnd:
    LineEnd
  elif wanted.cell >= 0:
    rl.screenCellOfLineCell(start.line, wanted.cell)
  elif start == win.cursor:
    let inFold = win.aimInFold
    if inFold.isSome:
      inFold.get
    else:
      rl.screenCellOf(start.line, start.column, win.aimsAtTabEnd)
  else:
    rl.screenCellOf(start.line, start.column, win.cursorOnTabEnd(start))

proc landMotion*(
    controller: MotionController,
    cmd: MotionCommand,
    start: BufferPosition,
    operator = none(OperatorType),
    aimedColumn = -1,
    openFolds = false,
): MotionLanding =
  ## Where `cmd` takes the cursor from `start`, how `operator`, when one
  ## waits, takes the text up to there, and whether the motion fails. A
  ## vertical motion aims for the screen cell `aimedColumn`, or for the cell
  ## `start` begins at when it is -1; gj and gk aim as `screenAim`. Leaves the
  ## viewport alone. Only a cursor move is kept on the line and out of closed
  ## folds, or with `openFolds` opens the closed folds it lands in when
  ## `opensFoldOn` says so; an operator widens over folds itself.
  let
    cmd = controller.unwrapped(cmd)
    rl = controller.rowLayout()
  if cmd.motion in ScreenLineMotions and rl.lineCount > 0:
    result = rl.screenLineLanding(
      start,
      controller.screenAim(rl, start),
      cmd.motion == Motion.ScreenLineDown,
      cmd.count,
      controller.cursorManager.state.activeWindow,
    )
  else:
    result = controller.executor.landMotion(
      CursorPosition(x: start.column, y: start.line),
      cmd,
      controller.viewportManager.viewport.height,
      controller.viewportManager.viewport.topLine,
      controller.cursorManager.state.motionReservedLines(),
      controller.cursorManager.state.mode,
      rl,
      controller.viewportManager.viewport.topWrapOffset,
      operator,
    )
  # A vertical motion that failed stays where it started, off the aimed column.
  let buffer = controller.executor.buffer
  if cmd.motion in VerticalMotions and not result.failed and
      result.pos.line in 0 ..< buffer.len and start.line in 0 ..< buffer.len:
    let
      state = controller.cursorManager.state
      aimed =
        if aimedColumn >= 0:
          aimedColumn
        else:
          buffer.getLine(start.line).cursorCell(
            start.column, state.tabStop, onTabEnd = false
          )
    result.pos.column =
      buffer.getLine(result.pos.line).columnAtCell(aimed, state.tabStop, state.mode)
  if operator.isNone:
    if openFolds and opensFoldOn(cmd.motion, start, result) and
        buffer.foldState.openFoldsInRange(result.pos.line, result.pos.line):
      controller.cursorManager.state.activeWindow.noteFoldOpened()
    let clamped = controller.cursorManager.clampPosition(
      CursorPosition(x: result.pos.column, y: result.pos.line),
      controller.executor.buffer,
    )
    result.pos = BufferPosition(line: clamped.y, column: clamped.x)

proc executeMotion*(
    controller: MotionController,
    cmd: MotionCommand,
    currentCursorPos: BufferPosition,
    updateViewport: bool = true,
    aimedColumn = -1,
    openFolds = false,
): MotionLanding =
  ## Execute motion and return where the cursor goes. A failed motion leaves
  ## the cursor as far as it went. A vertical motion aims for the screen cell
  ## `aimedColumn`, or for the cell `currentCursorPos` begins at when it is -1.
  result = controller.landMotion(
    cmd, currentCursorPos, aimedColumn = aimedColumn, openFolds = openFolds
  )
  if updateViewport:
    controller.viewportManager.updateViewport(
      controller.cursorManager.state, controller.executor.buffer, result.pos
    )

proc keepScreenAim*(
    controller: MotionController, state: EditorState, landing: MotionLanding
) =
  ## Keep the screen cell gj or gk landing at `landing` aims for, with the
  ## column it stands for on the cursor's line, as Vim's nv_screengo leaves
  ## curswant even when it fails. Nothing for another motion.
  if landing.screenCell.isNone:
    return
  let cell = landing.screenCell.get
  if cell == LineEnd:
    state.preferredColumn = LineEnd
  else:
    state.wanted = WantedColumn(
      cell: controller.rowLayout.lineCellOfScreenCell(state.cursor.line, cell),
      screenCell: cell,
    )

proc moveCursorByMotion*(
    controller: MotionController,
    state: EditorState,
    cmd: MotionCommand,
    updateViewport: bool = true,
    openFolds = false,
): MotionLanding =
  ## Move the cursor of `state` by `cmd`; the landing says whether it failed.
  ## With `openFolds` it opens the closed folds it lands in as `landMotion`.
  ## A vertical motion keeps the column it aimed for, as Vim keeps curswant.
  ## `$` makes vertical moves stick to line ends, even when its count goes past
  ## the last line, as Vim's nv_dollar; `g_` does too only then. `|` aims for
  ## its screen column, as Vim's nv_pipe does. Another motion drops the column
  ## when it moves the cursor, or even in place onto a line's start or end, as
  ## Vim's beginline does; one that fails in place keeps it (`2_` on the last
  ## line). gj and gk keep the screen cell they aim for, even when they fail,
  ## as Vim's nv_screengo.
  let
    cmd = controller.unwrapped(cmd)
    start = state.cursor
    aimed = state.aim
    landing =
      controller.executeMotion(cmd, start, updateViewport, aimed.cell, openFolds)
  state.cursor = landing.pos
  if cmd.motion in VerticalMotions:
    state.wanted = aimed
  elif landing.screenCell.isSome:
    controller.keepScreenAim(state, landing)
  elif cmd.motion == Motion.End or (
    cmd.motion == Motion.LastNonBlank and landing.failed
  ):
    state.preferredColumn = LineEnd
  elif cmd.motion == Motion.ScreenColumn:
    state.preferredColumn = cmd.count.screenColumnCell
  elif landing.pos != start or (cmd.motion in LineEdgeMotions and not landing.failed):
    state.preferredColumn = -1
  landing

proc extractRangeText*(buffer: TextBuffer, range: OperatorRange): string =
  ## Extract text from the given range
  ## Used for yank operations

  if range.isEmpty:
    # An empty range (e.g. the inner of <a></a>) spans no characters.
    return ""

  var text = ""

  if range.isLinewise:
    text = buffer.linewiseText(range.start.line, range.endPos.line)
  else:
    # Extract character range
    if range.start.line == range.endPos.line:
      # Single line extraction
      let line = buffer.getLine(range.start.line)
      let lineLen = line.charLen
      let startCol = min(range.start.column, lineLen)
      let endCol = min(range.endPos.column, lineLen)
      if endCol >= lineLen:
        # Range reaches the line end: include the trailing newline so the yanked
        # text matches what buffer.deleteRange removes (it joins the next line).
        if startCol < lineLen:
          text.add(line.charSubStr(startCol))
        text.add("\n")
      elif startCol < lineLen:
        # Inclusive range to match buffer.deleteRange behavior.
        text.add(line.charSubStr(startCol, endCol - startCol + 1))
    else:
      # Multi-line extraction
      for lineIdx in range.start.line .. range.endPos.line:
        if lineIdx < buffer.len:
          let line = buffer.getLine(lineIdx)
          if lineIdx == range.start.line:
            # First line: from startCol to end
            if range.start.column < line.charLen:
              text.add(line.charSubStr(range.start.column))
            text.add("\n")
          elif lineIdx == range.endPos.line:
            # Last line: from start to endPos.column (inclusive). When the range
            # reaches the line end, include the trailing newline so the yanked
            # text matches what buffer.deleteRange removes (it joins the lines).
            let lineLen = line.charLen
            let endCol = min(range.endPos.column, lineLen)
            if endCol >= lineLen:
              text.add(line)
              text.add("\n")
            else:
              text.add(line.charSubStr(0, endCol + 1))
          else:
            # Middle lines: entire line
            text.add(line)
            if line.len == 0 or line[^1] != '\n':
              text.add("\n")

  return text

proc deleteLinesInRange(buffer: TextBuffer, range: OperatorRange): Result[(), string] =
  ## Delete every line the linewise range covers, keeping the buffer at one line.
  if range.start.line == 0 and range.endPos.line >= buffer.len - 1:
    return buffer.deleteAllLines()
  for i in 0 .. (range.endPos.line - range.start.line):
    if range.start.line < buffer.len:
      let deleteResult = buffer.deleteLine(range.start.line)
      if deleteResult.isErr:
        return err(deleteResult.error)
  ok(())

proc deleteRange*(buffer: TextBuffer, range: OperatorRange): Result[(), string] =
  ## Delete text in the given range
  ## Used for delete and change operations

  if range.isEmpty:
    # An empty range deletes nothing (e.g. `cit`/`dit` on <a></a>).
    return ok(())

  if range.isLinewise:
    # Delete entire lines
    let lineCount = range.endPos.line - range.start.line + 1

    # Group the per-line deletes into one undo unit, unless the caller already
    # owns a transaction (beginTransaction rejects a nested one).
    if lineCount > 1 and not buffer.inTransaction:
      let txr = withTransaction(buffer, "delete " & $lineCount & " lines"):
        let r = buffer.deleteLinesInRange(range)
        if r.isErr:
          return err(r.error)
      if txr.isErr:
        return err(txr.error)
    else:
      let r = buffer.deleteLinesInRange(range)
      if r.isErr:
        return err(r.error)
  else:
    # Delete character range using buffer.deleteRange
    let deleteResult = buffer.deleteRange(range.start, range.endPos)
    if deleteResult.isErr:
      return err(deleteResult.error)

  return ok(())

## Text object range calculation

proc isEscaped(runes: seq[Rune], idx: int): bool =
  ## Check if the character at idx is escaped by counting preceding backslashes
  var backslashCount = 0
  var i = idx - 1
  while i >= 0 and runes[i] == Rune('\\'):
    backslashCount.inc
    i.dec
  # Odd number of backslashes means the character is escaped
  return backslashCount mod 2 == 1

proc findQuotedBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, quoteChar: char, inner: bool
): Result[TextObjectRange, string] =
  ## Find quoted string boundaries for i" or a"
  ## inner=true: content inside quotes
  ## inner=false: content + quotes
  ##
  ## Vim behavior:
  ## - If cursor is inside quotes, select that quoted region
  ## - If cursor is on a quote, select the region containing that quote
  ## - If cursor is outside quotes, search forward for next quote pair on the line

  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let line = buffer.getLine(cursor.line)
  let runes = line.toCharRunes()

  if runes.len == 0:
    return err("Empty line")

  let cursorCol = min(cursor.column, runes.len - 1)

  # Collect all unescaped quote positions on the line
  var quotePositions: seq[int] = @[]
  for i in 0 ..< runes.len:
    if runes[i] == Rune(quoteChar) and not isEscaped(runes, i):
      quotePositions.add(i)

  if quotePositions.len < 2:
    return err("No quote pair found")

  # Find which quote pair contains the cursor, or the next pair after cursor
  var startCol = -1
  var endCol = -1

  # Check each consecutive pair (0-1, 2-3, 4-5, ...)
  var pairIdx = 0
  while pairIdx + 1 < quotePositions.len:
    let pairStart = quotePositions[pairIdx]
    let pairEnd = quotePositions[pairIdx + 1]

    # Cursor is inside or on this pair
    if cursorCol >= pairStart and cursorCol <= pairEnd:
      startCol = pairStart
      endCol = pairEnd
      break

    # Cursor is before this pair - use this pair (Vim forward search behavior)
    if cursorCol < pairStart:
      startCol = pairStart
      endCol = pairEnd
      break

    pairIdx += 2

  if startCol < 0 or endCol < 0:
    return err("No quote pair found for cursor position")

  if inner:
    # Inner: content only (exclude quotes)
    if endCol <= startCol + 1:
      # Empty quotes like "": vim's `ci"` still enters Insert mode between
      # the quotes, so return an empty (no-op) range there.
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol + 1),
          endPos: BufferPosition(line: cursor.line, column: startCol + 1),
          isLinewise: false,
          isEmpty: true,
        )
      )
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol + 1),
        endPos: BufferPosition(line: cursor.line, column: endCol - 1),
        isLinewise: false,
      )
    )
  else:
    # Around: content + quotes (deleteRange is inclusive, so endCol is correct)
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol),
        endPos: BufferPosition(line: cursor.line, column: endCol),
        isLinewise: false,
      )
    )

proc incl(w: var WordWalker): int =
  ## Vim's incl: one step forward, over the end of a non-empty line.
  result = w.inc
  if result >= 1 and w.pos.column > 0:
    result = w.inc

proc decl(w: var WordWalker): int =
  ## Vim's decl: one step back, over the end of a non-empty line.
  result = w.dec
  if result == 1 and w.pos.column > 0:
    result = w.dec

proc inIndent(w: WordWalker): bool =
  ## Vim's inindent(1): on a blank before the line's first non-blank.
  var blanks = 0
  while blanks < w.runes.len and w.runes[blanks].isVimWhite:
    blanks += 1
  blanks >= w.pos.column + 1

proc oneLeft(w: var WordWalker): bool =
  ## Vim's oneleft: one character left within the line.
  if w.pos.column == 0:
    return false
  w.pos.column -= 1
  true

proc backInLine(w: var WordWalker) =
  ## Vim's back_in_line: back to the start of the word or the blanks the
  ## walker is on, within its line.
  let startClass = w.class
  while w.pos.column > 0:
    w.pos.column -= 1
    if w.class != startClass:
      w.pos.column += 1
      break

type WordObject* = object
  ## What Vim's current_word finds, or how far it went when it failed
  found*: bool
  start*: BufferPosition ## Where the operated text starts, or the Visual anchor
  cursor*: BufferPosition ## The other end, where the cursor goes
  inclusive*: bool

proc currentWord(
    buffer: TextBuffer,
    cursor: BufferPosition,
    count: int,
    around, bigword: bool,
    mode: EditorMode,
    anchor = none(BufferPosition),
): WordObject =
  ## iw aw iW aW as Vim's current_word: the word or the blanks under the
  ## cursor, and `count - 1` more of either. `around` adds the blanks after a
  ## word, or before it when none follow and they are not an indent. A Visual
  ## selection (`anchor`) wider than a character grows toward the cursor's
  ## side instead. Fails when the buffer ends before `count` are found.
  if cursor.line notin 0 ..< buffer.len:
    return WordObject(start: anchor.get(cursor), cursor: cursor)
  var
    w = initWordWalker(buffer, cursor, bigword)
    startPos = cursor
    left = max(1, count)
    includeWhite = false
  w.pos.column = min(w.pos.column, w.runes.len)
  result = WordObject(start: anchor.get(cursor), inclusive: true)

  template fail() =
    result.cursor = w.pos
    return

  if anchor.isNone or anchor.get == cursor:
    w.backInLine
    startPos = w.pos
    if (w.class == 0) == around:
      if not w.endWord(1, stop = true, mode, empty = true):
        fail()
    else:
      discard w.fwdWord(1, eol = true, mode)
      # Back off the start of the next word, or the line break before it.
      if not w.oneLeft:
        discard w.decl
      includeWhite = around
    result.start = startPos
    left -= 1

  while left > 0:
    result.inclusive = true
    if anchor.isSome and w.pos < result.start:
      if w.decl == -1:
        fail()
      if around != (w.class != 0):
        if not w.bckWord(1, stop = true):
          fail()
      else:
        if not w.bckendWord(1, eol = true):
          fail()
        discard w.incl
    else:
      if w.incl == -1:
        fail()
      if around != (w.class == 0):
        if not w.fwdWord(1, eol = true, mode) and left > 1:
          fail()
        # Not past a line break onto the next line's first character.
        if not w.oneLeft:
          result.inclusive = false
      else:
        if not w.endWord(1, stop = true, mode, empty = true):
          fail()
    left -= 1

  if includeWhite and (w.class != 0 or (w.pos.column == 0 and not result.inclusive)):
    # No blanks after the last word: take those before the first, but not an
    # indent.
    var before = initWordWalker(buffer, startPos, bigword)
    if before.oneLeft:
      before.backInLine
      if before.class == 0 and before.pos.column > 0:
        result.start = before.pos
  result.cursor = w.pos
  result.found = true

proc currentWord*(
    buffer: TextBuffer,
    cursor: BufferPosition,
    count: int,
    kind: TextObjectKind,
    modifier: TextObjectModifier,
    mode: EditorMode,
    anchor = none(BufferPosition),
): WordObject =
  ## The word object `kind` (toWord or toWideWord) with `modifier`.
  buffer.currentWord(
    cursor,
    count,
    around = modifier == tomAround,
    bigword = kind == toWideWord,
    mode,
    anchor,
  )

proc findUnmatched(
    buffer: TextBuffer, start: BufferPosition, target, other: Rune, forward: bool
): Option[BufferPosition] =
  ## Vim's findmatch for a bracket: the first `target` from `start`, not
  ## counting the character there, that no `other` passed on the way pairs
  ## with. Brackets in quotes count; escaped ones do not ('cpoptions' with `%`
  ## and without `M`).
  var
    w = initWordWalker(buffer, start)
    depth = 0
  while (if forward: w.inc else: w.dec) != -1:
    if w.pos.column >= w.runes.len:
      continue
    let r = w.runes[w.pos.column]
    if (r != target and r != other) or w.runes.isEscaped(w.pos.column):
      continue
    if r == other:
      depth += 1
    elif depth == 0:
      return some(w.pos)
    else:
      depth -= 1
  none(BufferPosition)

proc currentBlock(
    buffer: TextBuffer,
    cursor: BufferPosition,
    openChar, closeChar: char,
    inner: bool,
    count: int,
): Result[TextObjectRange, string] =
  ## i( a( i{ a{ i[ a[ i< a< as Vim's current_block: the `count`-th block
  ## around the cursor, or the next one after it when it is in none. The inner
  ## block leaves out the indent before a closing bracket that starts its
  ## line, and then stops at that line's start, which an operator takes as
  ## whole lines when the block's first line holds nothing but its opening.
  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")
  let
    open = Rune(openChar)
    close = Rune(closeChar)

  var w = initWordWalker(buffer, cursor)
  if openChar == '{':
    # `{` ignores the indent the cursor is in.
    while w.inIndent:
      if w.inc != 0:
        break
  if w.pos.column < w.runes.len and w.runes[w.pos.column] == open:
    w.pos.column += 1

  var openPos = buffer.findUnmatched(w.pos, open, close, forward = false)
  # In no block, the next one after the cursor.
  let forward = openPos.isNone
  if forward:
    openPos = buffer.findUnmatched(w.pos, open, close, forward = true)
  for _ in 2 .. max(1, count):
    if openPos.isNone:
      break
    openPos = buffer.findUnmatched(openPos.get, open, close, forward)
  if openPos.isNone:
    return err("No opening delimiter found")
  let closePos = buffer.findUnmatched(openPos.get, close, open, forward = true)
  if closePos.isNone:
    return err("No closing delimiter found")

  if not inner:
    return ok(TextObjectRange(start: openPos.get, endPos: closePos.get))

  var first = initWordWalker(buffer, openPos.get)
  discard first.incl
  var last = initWordWalker(buffer, closePos.get)
  var startsLine = last.pos.column == 0
  discard last.decl
  while last.inIndent:
    startsLine = true
    if last.decl != 0:
      break
  if startsLine:
    discard last.incl
    return ok(
      TextObjectRange(
        start: first.pos,
        endPos: last.pos,
        exclusive: true,
        isEmpty: first.pos == last.pos,
      )
    )
  if first.pos <= last.pos:
    return ok(TextObjectRange(start: first.pos, endPos: last.pos))
  # Nothing between the brackets: `ci(` still inserts there.
  ok(TextObjectRange(start: first.pos, endPos: first.pos, isEmpty: true))

proc lastCell*(r: TextObjectRange, buffer: TextBuffer): BufferPosition =
  ## The last place the object covers, as Visual mode selects it: before an
  ## exclusive end, the line break ahead of it when that starts a line.
  if not r.exclusive:
    r.endPos
  elif r.endPos.column > 0:
    BufferPosition(line: r.endPos.line, column: r.endPos.column - 1)
  else:
    BufferPosition(
      line: r.endPos.line - 1, column: buffer.getLine(r.endPos.line - 1).charLen
    )

proc findParagraphBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Paragraph text object (ip/ap). A paragraph is a run of non-blank lines
  ## delimited by blank lines; the object is linewise.
  if buffer.len == 0:
    return err("Empty buffer")
  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let onBlank = isBlankLine(buffer.getLine(cursor.line))

  # Extend over the run of lines of the same kind (blank vs non-blank).
  var startLine = cursor.line
  while startLine > 0 and isBlankLine(buffer.getLine(startLine - 1)) == onBlank:
    startLine.dec
  var endLine = cursor.line
  while endLine < buffer.len - 1 and isBlankLine(buffer.getLine(endLine + 1)) == onBlank:
    endLine.inc

  if not inner:
    # Around: also take the following run of the opposite kind, or the preceding
    # run when there is nothing after (matches vim's ap).
    let prevEnd = endLine
    while endLine < buffer.len - 1 and
        isBlankLine(buffer.getLine(endLine + 1)) != onBlank:
      endLine.inc
    if endLine == prevEnd:
      while startLine > 0 and isBlankLine(buffer.getLine(startLine - 1)) != onBlank:
        startLine.dec

  return ok(
    TextObjectRange(
      start: BufferPosition(line: startLine, column: 0),
      endPos: BufferPosition(
        line: endLine, column: max(0, lineRunesNoNl(buffer, endLine).len - 1)
      ),
      isLinewise: true,
    )
  )

proc findSentenceBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Sentence text object (is/as). A sentence ends at . ! ? (optionally followed
  ## by closing quotes/brackets) then whitespace or end of line, and never
  ## crosses a blank line. Charwise. Whitespace ownership follows vim: `is` on a
  ## space is the whitespace run; `as` keeps trailing whitespace or, for the last
  ## sentence, the leading whitespace. Trailing whitespace across a line break
  ## (the newline itself) is not pulled in.
  if buffer.len == 0 or cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")
  if isBlankLine(buffer.getLine(cursor.line)):
    return err("No sentence on a blank line")

  # Paragraph bounds — sentences never cross blank lines.
  var paraStart = cursor.line
  while paraStart > 0 and not isBlankLine(buffer.getLine(paraStart - 1)):
    paraStart.dec
  var paraEnd = cursor.line
  while paraEnd < buffer.len - 1 and not isBlankLine(buffer.getLine(paraEnd + 1)):
    paraEnd.inc

  # Flatten the paragraph into runes; inter-line breaks become a single space
  # separator. Instead of a BufferPosition per rune, keep per-line start offsets
  # (O(lines)) and map flat indices back on demand.
  let numLines = paraEnd - paraStart + 1
  var
    flat: seq[Rune]
    segStart = newSeq[int](numLines)
    lineLens = newSeq[int](numLines)
  for ln in paraStart .. paraEnd:
    let k = ln - paraStart
    segStart[k] = flat.len
    let lr = lineRunesNoNl(buffer, ln)
    lineLens[k] = lr.len
    for c in 0 ..< lr.len:
      flat.add lr[c]
    if ln < paraEnd:
      flat.add Rune(' ') # synthetic line-break separator

  if flat.len == 0:
    return err("Empty sentence")

  proc segmentOf(idx: int): int =
    ## Paragraph line (0-based) whose flat segment contains idx.
    var lo = 0
    var hi = numLines - 1
    while lo < hi:
      let mid = (lo + hi + 1) div 2
      if segStart[mid] <= idx:
        lo = mid
      else:
        hi = mid - 1
    lo

  proc flatToPos(idx: int): BufferPosition =
    let k = segmentOf(idx)
    BufferPosition(line: paraStart + k, column: idx - segStart[k])

  proc isSynthetic(idx: int): bool =
    ## True for a synthetic line-break separator (the cell right after a
    ## non-last line's content).
    let k = segmentOf(idx)
    k < numLines - 1 and idx - segStart[k] == lineLens[k]

  # Cursor index within the flattened paragraph, clamping a column past
  # end-of-line to the line's last index rather than snapping onto the next.
  var cursorIdx =
    if cursor.line < paraStart:
      0
    elif cursor.line > paraEnd:
      flat.len - 1
    else:
      let k = cursor.line - paraStart
      let maxCol =
        if k < numLines - 1:
          lineLens[k] # may land on the synthetic separator
        else:
          max(0, lineLens[k] - 1)
      segStart[k] + min(max(0, cursor.column), maxCol)

  proc isEnd(r: Rune): bool =
    let c = r.int32
    c == '.'.int32 or c == '!'.int32 or c == '?'.int32

  proc isCloser(r: Rune): bool =
    let c = r.int32
    c == ')'.int32 or c == ']'.int32 or c == '"'.int32 or c == '\''.int32

  # Sentence start indices within the paragraph.
  var starts = @[0]
  var i = 0
  while i < flat.len:
    if isEnd(flat[i]):
      var k = i + 1
      while k < flat.len and isCloser(flat[k]):
        k.inc
      if k < flat.len and isSpaceOrBreak(flat[k]):
        while k < flat.len and isSpaceOrBreak(flat[k]):
          k.inc
        if k < flat.len:
          starts.add k
        i = k
        continue
    i.inc

  # The sentence containing the cursor spans [s, nextStart - 1]. `starts` is
  # increasing, so a single pass finds both the last start <= cursor and the
  # first start past it.
  var s = 0
  var nextStart = flat.len
  for st in starts:
    if st <= cursorIdx:
      s = st
    else:
      nextStart = st
      break

  # Last non-whitespace char of this sentence (its terminator).
  var textEnd = nextStart - 1
  while textEnd > s and isSpaceOrBreak(flat[textEnd]):
    textEnd.dec

  # A cursor sitting on the whitespace run *between* two sentences is its own
  # object in vim: `is` is the whitespace, `as` is the whitespace plus the
  # following sentence. (Leading whitespace of the first sentence is part of its
  # text -- s is 0 there -- so this only fires between sentences. A synthetic
  # line break is excluded so a cursor clamped past end-of-line still selects
  # the sentence on its own line.)
  if cursorIdx > textEnd and nextStart < flat.len and not isSynthetic(cursorIdx):
    let wsStart = textEnd + 1
    if inner:
      var wsEnd = nextStart - 1
      while wsEnd > wsStart and isSynthetic(wsEnd):
        wsEnd.dec
      return ok(
        TextObjectRange(
          start: flatToPos(wsStart), endPos: flatToPos(wsEnd), isLinewise: false
        )
      )
    else:
      # Around: whitespace + the next sentence's text (without its own trailing).
      var nextEnd = flat.len - 1
      for st in starts:
        if st > nextStart:
          nextEnd = st - 1
          break
      while nextEnd > nextStart and isSpaceOrBreak(flat[nextEnd]):
        nextEnd.dec
      return ok(
        TextObjectRange(
          start: flatToPos(wsStart), endPos: flatToPos(nextEnd), isLinewise: false
        )
      )

  var endIdx = nextStart - 1
  if inner:
    # Inner drops trailing whitespace (and the synthetic line separators).
    while endIdx > s and isSpaceOrBreak(flat[endIdx]):
      endIdx.dec
  else:
    # Around keeps trailing whitespace but not a synthetic line-break edge.
    while endIdx > s and isSynthetic(endIdx):
      endIdx.dec
    # vim's `as`: when the last sentence has no trailing whitespace, include the
    # *leading* whitespace instead. Stay on the same line (skip synthetics).
    if endIdx == textEnd and nextStart == flat.len:
      while s > 0 and not isSynthetic(s - 1) and isSpaceOrBreak(flat[s - 1]):
        s.dec
  if endIdx < s:
    endIdx = s

  return ok(
    TextObjectRange(start: flatToPos(s), endPos: flatToPos(endIdx), isLinewise: false)
  )

proc findTagBoundariesInRange(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool, loLine, hiLine: int
): Result[TextObjectRange, string] =
  ## Windowed core of the tag text object: runs the same scan as
  ## findTagBoundaries but only over lines [loLine, hiLine]. A pair straddling
  ## the window edge is treated as unterminated here and picked up once the
  ## window grows to enclose it, so the result matches a full-buffer scan.

  # Flatten the window into runes (newlines kept so tags may span lines). `flat`
  # is O(window runes); the position map is only per-line start offsets
  # (window-local) with flat indices mapped back to absolute positions on demand
  # -- avoiding a BufferPosition per rune.
  let winLen = hiLine - loLine + 1
  var
    flat: seq[Rune]
    lineStart = newSeq[int](winLen + 1)
  for k in 0 ..< winLen:
    lineStart[k] = flat.len
    let lr = lineRunesNoNl(buffer, loLine + k)
    for c in 0 ..< lr.len:
      flat.add lr[c]
    flat.add Rune('\n')
  lineStart[winLen] = flat.len

  proc flatToPos(idx: int): BufferPosition =
    # Largest window line whose start offset is <= idx; column is the remainder.
    # The trailing newline of a line maps to column == line length (as before).
    var lo = 0
    var hi = winLen - 1
    while lo < hi:
      let mid = (lo + hi + 1) div 2
      if lineStart[mid] <= idx:
        lo = mid
      else:
        hi = mid - 1
    BufferPosition(line: loLine + lo, column: idx - lineStart[lo])

  proc isNameChar(r: Rune): bool =
    let c = r.int32
    isWordChar(r) or c == '-'.ord or c == ':'.ord or c == '.'.ord

  type
    TagKind = enum
      tkOpen
      tkClose

    Tag = object
      kind: TagKind
      name: string
      ltIdx: int # index of '<'
      gtIdx: int # index of '>'

  # Collect tag tokens.
  var tags: seq[Tag]
  let n = flat.len
  var i = 0
  while i < n:
    if flat[i].int32 == '<'.ord and i + 1 < n:
      let ltIdx = i
      var j = i + 1
      var kind = tkOpen
      if flat[j].int32 == '/'.ord:
        kind = tkClose
        j.inc
      elif flat[j].int32 == '!'.ord or flat[j].int32 == '?'.ord:
        # <!-- comment -->, <!doctype …>, <? … ?>: skip to '>' and ignore.
        while j < n and flat[j].int32 != '>'.ord:
          j.inc
        i = j + 1
        continue
      # Read the tag name. A '<' not followed by a tag name (a '<' used as a
      # less-than operator, or a lone '</') is not a tag -- treat it as a
      # literal char so it never swallows the real markup that follows.
      var name = ""
      while j < n and isNameChar(flat[j]):
        name.add $flat[j]
        j.inc
      if name.len == 0:
        i = ltIdx + 1
        continue
      # Scan to '>' honouring quotes; track self-closing.
      var selfClose = false
      while j < n and flat[j].int32 != '>'.ord:
        let c = flat[j].int32
        if c == '"'.ord or c == '\''.ord:
          j.inc
          while j < n and flat[j].int32 != c:
            j.inc
          if j < n:
            j.inc
        elif c == '/'.ord:
          selfClose = true
          j.inc
        else:
          if c != ' '.ord and c != '\t'.ord and c != '\n'.ord:
            selfClose = false
          j.inc
      if j >= n:
        # Unterminated tag (e.g. an unclosed quote ran to end of buffer):
        # recover by treating the '<' as a literal instead of dropping every
        # tag collected after it.
        i = ltIdx + 1
        continue
      let gtIdx = j
      if name.len > 0 and not selfClose:
        tags.add Tag(kind: kind, name: name, ltIdx: ltIdx, gtIdx: gtIdx)
      i = gtIdx + 1
    else:
      i.inc

  # Cursor index within the flattened window. Column is clamped to the line's
  # last *content* index (not its newline) so a position at/past end-of-line
  # never snaps onto the next line yet still falls inside a tag that ends the
  # line -- e.g. it/at with the cursor on the closing '>'.
  var cursorIdx =
    if cursor.line < 0:
      0
    elif cursor.line >= buffer.len:
      n - 1
    else:
      let k = clamp(cursor.line - loLine, 0, winLen - 1)
      let contentLen = lineStart[k + 1] - lineStart[k] - 1
      lineStart[k] + min(max(0, cursor.column), max(0, contentLen - 1))

  # Match open/close pairs with a stack; the first popped pair that encloses the
  # cursor is the innermost (closers pop inner pairs before outer ones).
  var stack: seq[Tag]
  var bestOpen, bestClose: Tag
  var found = false
  block matchTags:
    for t in tags:
      if t.kind == tkOpen:
        stack.add t
      else:
        # Find the nearest matching open. A stray closer (no matching open, e.g.
        # an orphan </br>) is ignored rather than discarding the still-open
        # enclosing tags; only the inner unmatched opens above a real match are
        # dropped (improperly nested markup).
        var matchIdx = -1
        for k in countdown(stack.high, 0):
          if stack[k].name == t.name:
            matchIdx = k
            break
        if matchIdx < 0:
          continue
        let mOpen = stack[matchIdx]
        stack.setLen(matchIdx)
        if mOpen.ltIdx <= cursorIdx and cursorIdx <= t.gtIdx:
          bestOpen = mOpen
          bestClose = t
          found = true
          break matchTags
  if not found:
    return err("Cursor is not inside a tag")

  if not inner:
    return ok(
      TextObjectRange(
        start: flatToPos(bestOpen.ltIdx),
        endPos: flatToPos(bestClose.gtIdx),
        isLinewise: false,
      )
    )
  else:
    # Inner: between the open tag's '>' and the close tag's '<'.
    let rawS = bestOpen.gtIdx + 1
    let rawE = bestClose.ltIdx - 1
    if rawS > rawE:
      # Empty tag like <a></a>: no inner content. vim's `cit` still works --
      # it drops the cursor between the tags and enters Insert mode -- so return
      # an empty (no-op) range at that position rather than failing the object.
      let pos = flatToPos(bestClose.ltIdx)
      return
        ok(TextObjectRange(start: pos, endPos: pos, isLinewise: false, isEmpty: true))
    # When the content occupies whole lines -- the open '>' is immediately
    # followed by a newline and the close '</' immediately preceded by one --
    # vim's `it` is linewise and `dit` removes the content lines rather than
    # leaving them blank.
    let wholeLines = flat[rawS].int32 == '\n'.ord and flat[rawE].int32 == '\n'.ord
    # Trim the boundary newlines so single-line content maps exactly.
    var s = rawS
    var e = rawE
    while s <= e and flat[s].int32 == '\n'.ord:
      s.inc
    while e >= s and flat[e].int32 == '\n'.ord:
      e.dec
    if s > e:
      # Multi-line empty tag like <a>\n</a>: the inner content is only
      # newlines. Treat it the same as <a></a> so `cit`/`dit`/`yit` work.
      let pos = flatToPos(bestClose.ltIdx)
      return
        ok(TextObjectRange(start: pos, endPos: pos, isLinewise: false, isEmpty: true))
    if wholeLines:
      return ok(
        TextObjectRange(
          start: BufferPosition(line: flatToPos(s).line, column: 0),
          endPos: flatToPos(e),
          isLinewise: true,
        )
      )
    return
      ok(TextObjectRange(start: flatToPos(s), endPos: flatToPos(e), isLinewise: false))

proc findTagBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Tag text object (it/at). Matches the innermost <tag>…</tag> pair enclosing
  ## the cursor, honouring nesting, multi-line tags and quotes within a tag.
  ## Self-closing tags do not enclose. Note: inner content trims boundary
  ## newlines, so `dit` on multi-line tags removes the inner text but keeps the
  ## surrounding line breaks.
  ##
  ## Scans a window of lines centred on the cursor, quadrupling it until the
  ## enclosing pair is found or the whole buffer has been covered. A window can
  ## only miss tags, never invent a closer pair, so growing it reproduces the
  ## full-buffer result while keeping the common case proportional to the
  ## enclosing tag's size rather than the file's.
  if buffer.len == 0:
    return err("Empty buffer")

  let center = clamp(cursor.line, 0, buffer.len - 1)
  var radius = tagScanInitialRadius
  while true:
    let
      loLine = max(0, center - radius)
      hiLine = min(buffer.len - 1, center + radius)
    let res = findTagBoundariesInRange(buffer, cursor, inner, loLine, hiLine)
    if res.isOk or (loLine == 0 and hiLine == buffer.len - 1):
      return res
    # Quadruple rather than double: when the enclosing pair is far (or absent in
    # a huge buffer) this reaches the full buffer in fewer re-scans, bounding the
    # wasted re-tokenisation to ~1/3 of the final window instead of ~1x.
    radius *= 4

proc calculateBaseTextObjectRange(
    buffer: TextBuffer,
    cursor: BufferPosition,
    kind: TextObjectKind,
    modifier: TextObjectModifier,
): Result[TextObjectRange, string] =
  ## Range of a single text object (no count extension). See
  ## calculateTextObjectRange for the counted entry point.

  let inner = (modifier == tomInner)

  case kind
  of toWord, toWideWord:
    return err("Words are found by currentWord")
  of toQuotedDouble:
    return findQuotedBoundaries(buffer, cursor, '"', inner)
  of toQuotedSingle:
    return findQuotedBoundaries(buffer, cursor, '\'', inner)
  of toQuotedBacktick:
    return findQuotedBoundaries(buffer, cursor, '`', inner)
  of toParenthesis:
    return currentBlock(buffer, cursor, '(', ')', inner, 1)
  of toBracket:
    return currentBlock(buffer, cursor, '[', ']', inner, 1)
  of toBrace:
    return currentBlock(buffer, cursor, '{', '}', inner, 1)
  of toAngleBracket:
    return currentBlock(buffer, cursor, '<', '>', inner, 1)
  of toSentence:
    return findSentenceBoundaries(buffer, cursor, inner)
  of toParagraph:
    return findParagraphBoundaries(buffer, cursor, inner)
  of toTag:
    return findTagBoundaries(buffer, cursor, inner)

proc nextObjectProbe(
    buffer: TextBuffer, fromLine, fromCol: int
): Option[BufferPosition] =
  ## Cursor position one cell past (fromLine, fromCol), wrapping to the next
  ## line's start at end of line. none() when that runs past the buffer.
  var line = fromLine
  var col = fromCol + 1
  if col >= buffer.getLine(line).charLen:
    line.inc
    col = 0
  if line >= buffer.len:
    return none(BufferPosition)
  some(BufferPosition(line: line, column: col))

proc posBeforeTagOpen(buffer: TextBuffer, pos: BufferPosition): Option[BufferPosition] =
  ## Position one cell before pos, wrapping to the previous line's last column.
  ## none() at the very start of the buffer. Steps just outside the current tag
  ## so the enclosing tag is matched for the counted it/at object.
  if pos.column > 0:
    return some(BufferPosition(line: pos.line, column: pos.column - 1))
  if pos.line > 0:
    let prevLen = buffer.getLine(pos.line - 1).charLen
    return some(BufferPosition(line: pos.line - 1, column: max(0, prevLen - 1)))
  none(BufferPosition)

proc calculateTextObjectRange*(
    buffer: TextBuffer,
    cursor: BufferPosition,
    kind: TextObjectKind,
    modifier: TextObjectModifier,
    count: int = 1,
): Result[TextObjectRange, string] =
  ## Range of a text object, extended over `count` objects (2dap, d3is, 2dat,
  ## d2i(). `count <= 1` is a single object. The quote kinds ignore it. Words
  ## are found by currentWord, which also tells where a failed search went.
  let base = calculateBaseTextObjectRange(buffer, cursor, kind, modifier)
  if base.isErr or count <= 1:
    return base
  var toRange = base.value

  case kind
  of toWord, toWideWord:
    discard # refused by calculateBaseTextObjectRange
  of toParagraph:
    # Each count selects one more whole paragraph of the SAME modifier (Nap = N
    # paragraphs incl. their trailing blank runs; Nip = N alternating runs).
    for i in 1 ..< count:
      let probe = nextObjectProbe(buffer, toRange.endPos.line, toRange.endPos.column)
      if probe.isNone:
        break
      let nextResult = calculateBaseTextObjectRange(buffer, probe.get, kind, modifier)
      if nextResult.isErr:
        break
      toRange.endPos = nextResult.value.endPos
  of toTag:
    # Tags nest, so each count selects the tag one level out (2at = the tag and
    # its parent). Re-probe from just before the current tag's '<'.
    for i in 1 ..< count:
      let around = calculateBaseTextObjectRange(buffer, toRange.start, kind, tomAround)
      if around.isErr:
        break
      let outer = posBeforeTagOpen(buffer, around.value.start)
      if outer.isNone:
        break
      let m = if i == count - 1: modifier else: tomAround
      let nextResult = calculateBaseTextObjectRange(buffer, outer.get, kind, m)
      if nextResult.isErr:
        break
      toRange = nextResult.value
  of toSentence:
    # A sentence owns its trailing whitespace, so walk forward by each segment's
    # *around* extent (one finder call per step); for an inner request, recompute
    # only the final segment as inner.
    var endAround = toRange.endPos
    var lastStart = toRange.start
    block sentenceCount:
      let firstAround =
        calculateBaseTextObjectRange(buffer, toRange.start, kind, tomAround)
      if firstAround.isErr:
        break sentenceCount
      endAround = firstAround.value.endPos
      var reached = 1
      while reached < count:
        let probe = nextObjectProbe(buffer, endAround.line, endAround.column)
        if probe.isNone:
          break
        let nextA = calculateBaseTextObjectRange(buffer, probe.get, kind, tomAround)
        if nextA.isErr:
          break
        endAround = nextA.value.endPos
        lastStart = nextA.value.start
        reached.inc
      if modifier == tomInner:
        let lastInner = calculateBaseTextObjectRange(buffer, lastStart, kind, tomInner)
        toRange.endPos = if lastInner.isOk: lastInner.value.endPos else: endAround
      else:
        toRange.endPos = endAround
  of toParenthesis:
    return currentBlock(buffer, cursor, '(', ')', modifier == tomInner, count)
  of toBracket:
    return currentBlock(buffer, cursor, '[', ']', modifier == tomInner, count)
  of toBrace:
    return currentBlock(buffer, cursor, '{', '}', modifier == tomInner, count)
  of toAngleBracket:
    return currentBlock(buffer, cursor, '<', '>', modifier == tomInner, count)
  of toQuotedDouble, toQuotedSingle, toQuotedBacktick:
    discard # count is not supported

  return ok(toRange)
