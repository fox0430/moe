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

## The cells a Visual block covers and what each of its lines gives an
## operator, as Vim's get_op_vcol and block_prep. Cells count the screen from
## the line start, so a tab or a wide character does not move the block's
## edges the way character indexes would.

import std/[strutils, unicode]

import pkg/results

import types, modes, render_utils, wanted_column, unicode_utils
import buffer/[core, edit]

type
  BlockUse* = enum
    ## What an operator does with a line, which decides how a character the
    ## block's edge cuts through counts.
    buTake ## Takes whole characters only: a yank, a case change
    buDelete ## Takes a cut character whole and leaves blanks for its outside
    buInsert ## `I`
    buAppend ## `A`
    buReplace ## `r`

  BlockLine* = object ## What one line of a block gives an operator, as Vim's block_def.
    textCol*: int ## The first character taken
    textLen*: int ## How many characters are taken
    startSpaces*, endSpaces*: int
      ## Blanks for a character cut at either edge: its cells inside the block
      ## for `buTake`, outside it for `buDelete`
    isShort*: bool ## The line ends before the block does
    endCell*: int ## The cell after the characters the walk reached (end_vcol)
    startCharCells*, endCharCells*: int ## Widths of the characters at the edges

  BlockShown* = object
    ## What a block selection shows over on one line; nothing by default.
    first*, count*: int
      ## The characters any of whose cells it covers. A combining mark has no
      ## cell of its own and draws with the character it follows.
    leadCells*, trailCells*: int
      ## Cells of a tab at either end that lie outside the block, which show
      ## unselected as Vim draws by cell. A wide character shows whole.
    firstWidth*, lastWidth*: int
      ## The cells the characters at either end take on the line, which a
      ## tab drawn after a wrap or a horizontal scroll may not
    lineEnd*: bool ## The cell after the line's end shows selected

func columns*(shown: BlockShown): Slice[int] =
  shown.first ..< shown.first + shown.count

proc widestCell(buffer: TextBuffer, first, last, tabStop: int): int =
  ## The cell after the end of the widest of lines `first`..`last`, where a
  ## block after `<C-v>$` ends (Vim's MAXCOL).
  for line in first .. last:
    result = max(result, buffer.getLine(line).displayWidthWithTabs(tabStop))

proc blockArea*(
    buffer: TextBuffer, sel: VisualSelection, tabStop: int, measureWidest = true
): BlockArea =
  ## The cells `sel` covers, from the anchor's and the cursor's, as Vim's
  ## get_op_vcol. After `<C-v>$` the block ends where the widest of its lines
  ## does; `measureWidest = false` skips that scan for a caller that reads only
  ## `startCell` then.
  result.firstLine = min(sel.start.line, sel.current.line)
  result.lastLine = max(sel.start.line, sel.current.line)
  let
    anchor = buffer.getLine(sel.start.line).cellSpan(sel.start.column, tabStop)
    cursor = buffer.getLine(sel.current.line).cellSpan(sel.current.column, tabStop)
  result.startCell = min(anchor.first, cursor.first)
  result.endCell = max(anchor.last, cursor.last)
  if sel.extendsToLineEnd:
    result.toLineEnd = true
    if measureWidest:
      result.endCell = buffer.widestCell(result.firstLine, result.lastLine, tabStop)
  let top = buffer.getLine(result.firstLine)
  result.topLeft = BufferPosition(
    line: result.firstLine,
    column: top.columnAtCell(result.startCell, tabStop, EditorMode.VisualBlock),
  )

proc blockLine*(area: BlockArea, text: string, tabStop: int, use: BlockUse): BlockLine =
  ## What line `text` gives `use` of `area`, as Vim's block_prep. Its two walks,
  ## up to the block and across it, are one pass here.
  let isDel = use != buTake
  var
    leftEnd = 0 ## The cell after the characters left of the block (start_vcol)
    rightEnd = -1 ## The cell after the characters the block reaches (end_vcol)
    leftWidth = 0
    width = 0 ## Cells of the last character walked (incr)
    start = 0 ## The first character not left of the block (pstart)
    beforeStart = 0 ## The last character left of it (prev_pstart)
    stop = -1 ## Just past the characters the block reaches (pend)
    beforeStop = -1 ## The last of them (prev_pend)
  for g in text.glyphsOf(tabStop):
    if g.cell < area.startCell:
      leftEnd = g.cell + g.width
      leftWidth = g.width
      start = g.next
      beforeStart = g.column
    elif g.cell <= area.endCell:
      rightEnd = g.cell + g.width
      stop = g.next
      beforeStop = g.column
    else:
      break
    width = g.width
  if stop < 0:
    rightEnd = leftEnd
    stop = start
    beforeStop = start

  result.startCharCells = leftWidth
  if leftEnd < area.startCell:
    result.endCell = leftEnd
    result.isShort = true
    if not isDel or use == buAppend:
      result.endSpaces = area.endCell - area.startCell + 1
  else:
    result.startSpaces = leftEnd - area.startCell
    if isDel and result.startSpaces > 0:
      result.startSpaces = leftWidth - result.startSpaces
    result.endCell = rightEnd
    if leftEnd > area.endCell:
      case use
      of buInsert:
        result.endSpaces = leftWidth - result.startSpaces
      of buAppend:
        result.startSpaces += area.endCell - area.startCell + 1
        result.endSpaces = leftWidth - result.startSpaces
      of buTake:
        result.startSpaces = area.endCell - area.startCell + 1
      of buDelete, buReplace:
        # The character is split in two around the block.
        result.startSpaces = leftWidth - (leftEnd - area.startCell)
        result.endSpaces = leftEnd - area.endCell - 1
    elif rightEnd <= area.endCell and (not isDel or use in {buAppend, buReplace}):
      result.isShort = true
      if use == buAppend:
        result.endSpaces = area.endCell - rightEnd + 1
    elif rightEnd > area.endCell:
      result.endSpaces = rightEnd - area.endCell - 1
      if not isDel and result.endSpaces > 0:
        result.endSpaces = width - result.endSpaces
        if stop != start:
          stop = beforeStop
    result.endCharCells = width
    if isDel and result.startSpaces > 0:
      start = beforeStart
    result.textLen = stop - start
  result.textCol = start

proc takenText*(line: BlockLine, text: string): string =
  ## What a yank takes from `text`, blanks for cut characters included, as
  ## Vim's yank_copy_line.
  ' '.repeat(line.startSpaces) & text.charSubStr(line.textCol, line.textLen) &
    ' '.repeat(line.endSpaces)

proc swapTaken*(line: BlockLine, text, middle: string): string =
  ## `text` with the characters `line` takes swapped for `middle`.
  text.charSubStr(0, line.textCol) & middle &
    text.charSubStr(line.textCol + line.textLen)

proc blockRows(buffer: TextBuffer, area: BlockArea, tabStop: int): seq[string] =
  ## What a yank of `area` takes from each of its lines.
  result = newSeqOfCap[string](area.lastLine - area.firstLine + 1)
  for line in area.firstLine .. area.lastLine:
    let text = buffer.getLine(line)
    result.add area.blockLine(text, tabStop, buTake).takenText(text)

proc blockText*(buffer: TextBuffer, area: BlockArea, tabStop: int): string =
  ## What a yank of `area` takes, a line of the block to a line of text.
  buffer.blockRows(area, tabStop).join("\n")

func blockWidth(area: BlockArea): int =
  ## The cells a put of what `area` took pads its rows to, as Vim's y_width
  ## + 1: up to the widest line's end after `<C-v>$`.
  if area.toLineEnd:
    max(1, area.endCell - area.startCell)
  else:
    area.endCell - area.startCell + 1

proc takenBlock*(buffer: TextBuffer, area: BlockArea, tabStop: int): Register =
  ## What a yank of `area` keeps, as a block (Vim's MBLOCK).
  blockRegister(buffer.blockRows(area, tabStop), area.blockWidth)

proc shownOn*(area: BlockArea, line: int, text: string, tabStop: int): BlockShown =
  ## What a block of `area` shows over on line `line`, whose text is `text`.
  ## Its first and last lines hold the anchor and the cursor, and when the
  ## block starts at such a line's end, as on an empty one or with the cursor
  ## past a shorter line's end, the cell after the end shows selected, as Vim
  ## draws it.
  var lineEnd = 0
  for g in text.glyphsOf(tabStop):
    if g.cell > area.endCell and not area.toLineEnd:
      return
    lineEnd = g.cell + g.width
    let last = g.cell + max(g.width, 1) - 1
    if last >= area.startCell:
      if result.count == 0:
        result.first = g.column
        result.firstWidth = g.width
        if g.rune == TAB_CHAR:
          result.leadCells = max(0, area.startCell - g.cell)
      result.count = g.column - result.first + 1
      result.lastWidth = g.width
      result.trailCells =
        if g.rune == TAB_CHAR and not area.toLineEnd:
          max(0, last - area.endCell)
        else:
          0
  result.lineEnd = lineEnd == area.startCell and line in [area.firstLine, area.lastLine]

proc replacedWith*(area: BlockArea, line: BlockLine, text, ch: string): string =
  ## `text` with the cells `line` gives `buReplace` filled with `ch`, as Vim's
  ## op_replace: a cut character's cells outside the block become blanks, and
  ## a wide `ch` goes in half as many times.
  if line.textLen == 0:
    return text
  var
    count = area.endCell - area.startCell + 1
    endSpaces = line.endSpaces
  if line.isShort:
    count -= area.endCell - line.endCell + 1
  if ch.toCharRunes[0].charWidth > 1:
    if count mod 2 == 1 and not line.isShort:
      endSpaces.inc
    count = count div 2
  var middle = ' '.repeat(line.startSpaces) & ch.repeat(count)
  if not line.isShort:
    middle.add ' '.repeat(endSpaces)
  line.swapTaken(text, middle)

func copyUse*(kind: VisualBlockInsertKind): BlockUse =
  ## What a line below the first gives the copy of what an insert typed.
  case kind
  of vbiInsert: buInsert
  of vbiAppend: buAppend
  of vbiChange: buDelete

proc typedInto*(
    area: BlockArea, cut: BlockLine, text, typed: string, kind: VisualBlockInsertKind
): string =
  ## `text`, a line of `area` below the first, with what was `typed` on the
  ## first put in as Vim's block_insert (`I`, `A`) and op_change (`c`) do,
  ## from what the line gives `kind.copyUse` (`cut`): a tab the block's edge
  ## cuts through turns into blanks on either side, `A` pads a short line out
  ## to the block, and `I` and `c` leave a line that ends before the block
  ## alone.
  if kind == vbiChange:
    if cut.isShort:
      return text
    return text.charSubStr(0, cut.textCol) & typed & text.charSubStr(cut.textCol)

  let append = kind == vbiAppend
  if cut.isShort and not append:
    return text
  var
    split = 0 ## The width of the character the edge cuts through
    spaces = 0
    at = 0
  if not append:
    split = cut.startCharCells
    spaces = cut.startSpaces
    at = cut.textCol
  elif not cut.isShort:
    split = cut.endCharCells
    if cut.endSpaces > 0:
      spaces = split - cut.endSpaces
    at = cut.textCol + cut.textLen - ord(spaces != 0)
  else:
    if not area.toLineEnd:
      spaces = area.endCell - cut.endCell + 1
    at = cut.textCol + cut.textLen
  spaces = max(spaces, 0)

  result = text.charSubStr(0, at) & ' '.repeat(spaces) & typed
  var rest = at
  if spaces > 0 and not cut.isShort and text.charSubStr(at, 1) == "\t":
    result.add ' '.repeat(split - spaces)
    rest.inc
  result.add text.charSubStr(rest)

proc rewriteBlock*(
    buffer: TextBuffer,
    area: BlockArea,
    tabStop: int,
    use: BlockUse,
    rewrite:
      proc(area: BlockArea, text: string, cut: BlockLine): string {.closure, gcsafe.},
): Result[(), string] =
  ## Give each line of `area` what `rewrite` makes of it from what `use` takes
  ## there, as one change. It starts at the block's top left, or at the start
  ## of the first line when that is below the top left's (the copy of what an
  ## insert typed), as Vim's block_insert reports it.
  var
    lines = newSeqOfCap[string](area.lastLine - area.firstLine + 1)
    changed = false
  for line in area.firstLine .. area.lastLine:
    let
      text = buffer.getLine(line)
      rewritten = rewrite(area, text, area.blockLine(text, tabStop, use))
    changed = changed or rewritten != text
    lines.add rewritten
  if not changed:
    return ok(())
  let column = if area.topLeft.line == area.firstLine: area.topLeft.column else: 0
  buffer.replaceLines(area.firstLine, lines.len, lines, column = column)

proc rewriteTaken*(
    buffer: TextBuffer,
    area: BlockArea,
    tabStop: int,
    use: BlockUse,
    swap: proc(cut: BlockLine, taken: string): string {.closure, gcsafe.},
): Result[(), string] =
  ## Swap what `use` takes on each line of `area` for what `swap` makes of it,
  ## leaving a line it takes nothing from as it is.
  buffer.rewriteBlock(
    area,
    tabStop,
    use,
    proc(area: BlockArea, text: string, cut: BlockLine): string =
      if cut.textLen == 0:
        text
      else:
        cut.swapTaken(text, swap(cut, text.charSubStr(cut.textCol, cut.textLen))),
  )

proc replaceBlock*(
    buffer: TextBuffer, area: BlockArea, tabStop: int, ch: string
): Result[(), string] =
  ## Fill the cells of `area` with `ch`, as Vim's op_replace.
  buffer.rewriteBlock(
    area,
    tabStop,
    buReplace,
    proc(area: BlockArea, text: string, cut: BlockLine): string =
      area.replacedWith(cut, text, ch),
  )

proc repeatedBlock*(
    buffer: TextBuffer,
    at: BufferPosition,
    lines, cells: int,
    toLineEnd: bool,
    tabStop: int,
): BlockArea =
  ## The block a `.` puts a block of `lines` by `cells` at `at`, as Vim's
  ## redo_VIsual: from where `at`'s character starts, or to each line's end
  ## when the block went to its lines' ends (`toLineEnd`).
  result.firstLine = at.line
  result.lastLine = min(at.line + max(1, lines) - 1, buffer.len - 1)
  result.startCell = buffer.getLine(at.line).cellSpan(at.column, tabStop).first
  result.topLeft = at
  if toLineEnd:
    result.toLineEnd = true
    result.endCell = buffer.widestCell(result.firstLine, result.lastLine, tabStop)
  else:
    result.endCell = result.startCell + max(1, cells) - 1
