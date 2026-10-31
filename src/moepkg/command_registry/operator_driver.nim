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

## The one place a waiting operator acts, as Vim's do_pending_operator: a
## motion, a text object or a search only finds where the operator goes.

import std/[options, tables, unicode]

import pkg/results

import ../[types, motion, key_bindings, unicode_utils, modes]
import ../buffer/[core, fold]

import core, operator_engine, insert_entry

const MotionOperandTypes = ["find", "till", "mark-line", "mark-exact"]
  ## Operand-taking commands an operator acts over (`dfx`, `d'a`)

proc inIndent(buffer: TextBuffer, pos: BufferPosition): bool =
  ## Only blanks before `pos` on its line (Vim's inindent).
  let runes = buffer.lineRunesNoNl(pos.line)
  for i in 0 ..< min(pos.column, runes.len):
    if runes[i] != Rune(' ') and runes[i] != Rune('\t'):
      return false
  true

proc blanksFrom(buffer: TextBuffer, line, column: int): bool =
  ## Only blanks from `column` to the end of `line`.
  let runes = buffer.lineRunesNoNl(line)
  for i in max(0, column) ..< runes.len:
    if runes[i] != Rune(' ') and runes[i] != Rune('\t'):
      return false
  true

proc lineBreakAfter(buffer: TextBuffer, line: int): BufferPosition =
  ## The place of `line`'s line break, which an inclusive range ending there
  ## takes.
  BufferPosition(line: line, column: buffer.getLine(line).charLen)

proc rangeUpTo(
    buffer: TextBuffer, target: MotionTarget, operator: OperatorType
): OperatorRange =
  ## The text `operator` takes up to `target`, by Vim's rules: a closed fold
  ## at an end is taken whole, keeping the motion's kind; an exclusive span
  ## that ends at a line start stops at the end of the line before, and takes
  ## whole lines when it starts in the indent (`:h exclusive`); a delete over
  ## lines that leaves only blanks around takes them whole (`:h d`); and a
  ## motion's end on an empty line stands on no character there.
  var (first, last) =
    if target.finish < target.start:
      (target.finish, target.start)
    else:
      (target.start, target.finish)
  if target.empty:
    return OperatorRange(start: first, endPos: last, isEmpty: true)

  var
    kind = target.motionType
    area = target.area
  # As Vim's do_pending_operator: only a forward or linewise span takes in a
  # fold, from its first line's start and, unless an exclusive end is at a
  # line start, to its last line's end (without the line break).
  if target.start < target.finish or kind == mtLinewise:
    if buffer.foldState.getCollapsedFoldAt(first.line).isSome:
      first = BufferPosition(line: buffer.foldStart(first.line), column: 0)
    if (last.column > 0 or kind != mtExclusive) and
        buffer.foldState.getCollapsedFoldAt(last.line).isSome:
      last = buffer.lineBreakAfter(min(buffer.foldEnd(last.line), buffer.len - 1))
      area = false

  if kind == mtExclusive:
    if first == last:
      return OperatorRange(start: first, endPos: first, isEmpty: true)
    if last.column == 0:
      let before = last.line - 1
      if buffer.inIndent(first):
        kind = mtLinewise
        last = BufferPosition(line: before, column: 0)
      else:
        let beforeLen = buffer.getLine(before).charLen
        # An empty line before keeps the end exclusive at its start.
        last = BufferPosition(line: before, column: max(0, beforeLen - 1))
        if beforeLen > 0:
          kind = mtInclusive

  if operator == OpDelete and kind != mtLinewise and last.line > first.line and
      buffer.inIndent(first) and
      buffer.blanksFrom(last.line, last.column + ord(kind == mtInclusive)):
    kind = mtLinewise

  case kind
  of mtLinewise:
    OperatorRange(
      start: BufferPosition(line: first.line, column: 0),
      endPos: buffer.lineBreakAfter(last.line),
      isLinewise: true,
    )
  of mtInclusive:
    let lastLen = buffer.getLine(last.line).charLen
    if last.column < lastLen or (area and last.line < buffer.len - 1):
      OperatorRange(start: first, endPos: last)
    else:
      # Nothing to take at the end: no character on an empty line, and no
      # line break after the last line.
      let before =
        if lastLen > 0:
          BufferPosition(line: last.line, column: lastLen - 1)
        elif last.line > first.line:
          buffer.lineBreakAfter(last.line - 1)
        else:
          first
      if before < first or (lastLen == 0 and last.line == first.line):
        OperatorRange(start: first, endPos: first, isEmpty: true)
      else:
        OperatorRange(start: first, endPos: before)
  of mtExclusive:
    if last.column == 0:
      OperatorRange(start: first, endPos: buffer.lineBreakAfter(last.line - 1))
    else:
      OperatorRange(
        start: first, endPos: BufferPosition(line: last.line, column: last.column - 1)
      )

proc toOperatorRange*(
    buffer: TextBuffer, target: MotionTarget, operator: OperatorType
): OperatorRange =
  ## The text `operator` takes up to `target` (`rangeUpTo`), and which
  ## registers a delete of it fills.
  result = buffer.rangeUpTo(target, operator)
  result.useRegOne = target.useRegOne

proc settle(ctx: CommandContext, pos: BufferPosition): BufferPosition =
  ## `pos` as a Normal mode cursor: on a character of its line, and at the
  ## start of a closed fold it lies in.
  let p = ctx.motionController.cursorManager.clampPosition(
    CursorPosition(x: pos.column, y: pos.line), ctx.buffer, some(EditorMode.Normal)
  )
  BufferPosition(line: p.y, column: p.x)

proc reverseFindMotion*(m: Motion): Motion =
  ## The opposite-direction find/till motion, used by `,`.
  case m
  of Motion.FindChar: Motion.FindCharBackward
  of Motion.FindCharBackward: Motion.FindChar
  of Motion.TillChar: Motion.TillCharBackward
  of Motion.TillCharBackward: Motion.TillChar
  else: m

proc motionTarget(
    ctx: CommandContext, op: PendingOperator, operand: Operand
): Result[Option[MotionTarget], string] =
  ## Where the motion lands for the operator; the motion decides how the
  ## operator takes the text and whether it fails.
  var cmd = MotionCommand(
    motion: operand.motion, count: operand.count, targetChar: operand.targetChar
  )
  case operand.motion
  of Motion.RepeatFind, Motion.RepeatFindReverse:
    if ctx.state.editState.lastFindChar.isNone:
      return ok(none(MotionTarget))
    let last = ctx.state.editState.lastFindChar.get
    cmd.motion =
      if operand.motion == Motion.RepeatFindReverse:
        reverseFindMotion(last.motion)
      else:
        last.motion
    cmd.targetChar = last.targetChar
    cmd.repeat = true
  of Motion.FindChar, Motion.FindCharBackward, Motion.TillChar, Motion.TillCharBackward:
    ctx.state.editState.lastFindChar =
      some(LastFindChar(motion: operand.motion, targetChar: operand.targetChar))
  of Motion.LastLine:
    # A bare G goes to the last line; a count before the operator or the
    # motion makes it a line number (`3dG`).
    if not operand.countGiven:
      cmd.count = 0
  else:
    discard
  let landing = ctx.motionController.landMotion(cmd, op.startPos, some(op.operatorType))
  if landing.failed:
    # The operator does nothing, and the cursor stays as far as the motion went.
    ctx.cursor = ctx.settle(landing.pos)
    ctx.motionController.keepScreenAim(ctx.state, landing)
    return ok(none(MotionTarget))
  ok(
    some(
      MotionTarget(
        start: op.startPos,
        finish: landing.pos,
        motionType: landing.motionType,
        useRegOne: landing.useRegOne,
      )
    )
  )

proc markTarget(
    ctx: CommandContext, op: PendingOperator, operand: Operand
): Result[Option[MotionTarget], string] =
  let dest = ?ctx.namedMarkPosition(operand.markName)
  ok(
    some(
      MotionTarget(
        start: op.startPos,
        finish: dest,
        motionType: if operand.markLinewise: mtLinewise else: mtExclusive,
        useRegOne: not operand.markLinewise,
      )
    )
  )

proc textObjectTarget(
    ctx: CommandContext, operand: Operand
): Result[Option[MotionTarget], string] =
  let r = ?calculateTextObjectRange(
    ctx.buffer, ctx.cursor, operand.textObjectKind, operand.textObjectModifier,
    operand.count,
  )
  ok(
    some(
      MotionTarget(
        start: r.start,
        finish: r.endPos,
        motionType:
          if r.isLinewise:
            mtLinewise
          elif r.exclusive:
            mtExclusive
          else:
            mtInclusive,
        empty: r.isEmpty,
        area: true,
      )
    )
  )

proc linesTarget(
    ctx: CommandContext, op: PendingOperator, operand: Operand
): Option[MotionTarget] =
  ## The operator's line and the `count - 1` lines below it, a closed fold
  ## counting as one, as Vim's nv_lineop. None when there are lines to go down
  ## over and none below (`2dd` on the last line).
  let
    start = op.startPos
    below = max(1, operand.count) - 1
  # A stale cursor names no line, and the lines below it are not its own.
  if start.line notin 0 ..< ctx.buffer.len:
    return none(MotionTarget)
  if below > 0 and ctx.buffer.foldEnd(start.line) >= ctx.buffer.len - 1:
    return none(MotionTarget)
  some(
    MotionTarget(
      start: start,
      finish: BufferPosition(
        line: ctx.buffer.linesDown(start.line, below), column: start.column
      ),
      motionType: mtLinewise,
    )
  )

proc isMotion*(registry: CommandRegistry, cmd: Command): bool =
  ## A waiting operator acts over `cmd` (`dw`, `dfx`, `dn`).
  case cmd.kind
  of ctMotion:
    true
  of ctOperatorPending:
    cmd.operatorType in MotionOperandTypes
  of ctAction, ctCustom, ctTextObject, ctOperator:
    cmd.commandId in registry.targets
  of ctModeSwitch, ctOverlaySwitch:
    false

proc endsOperator*(registry: CommandRegistry, cmd: Command): bool =
  ## `cmd` completes a waiting operator: a motion it acts over, an operator
  ## (its own kind goes on to lines, `dd`; another cancels it, `dy`) or a text
  ## object. Any other command cancels the operator and does not run, as
  ## Vim's checkclearop.
  cmd.kind in {ctOperator, ctTextObject} or registry.isMotion(cmd)

proc operandCount*(op: PendingOperator, count: int): int =
  ## The operator's and the motion's counts multiplied as Vim's normal_cmd
  ## does (`2d3w` deletes six words), capped as a typed count is.
  min(op.operatorCount * max(1, count), MaxNumericPrefix)

proc operandFor*(op: PendingOperator, cmd: Command): Operand =
  ## The operand a motion command gives the waiting operator `op`. `cmd` must
  ## be a motion (`isMotion`).
  let
    count = op.operandCount(cmd.count)
    countGiven = op.countGiven or cmd.hasCount
  case cmd.kind
  of ctMotion:
    Operand(count: count, countGiven: countGiven, kind: odMotion, motion: cmd.motion)
  of ctOperatorPending:
    case cmd.operatorType
    of "find", "till":
      let motion =
        if cmd.operatorType == "find":
          (if cmd.reverse: Motion.FindCharBackward else: Motion.FindChar)
        else:
          (if cmd.reverse: Motion.TillCharBackward else: Motion.TillChar)
      Operand(
        count: count,
        countGiven: countGiven,
        kind: odMotion,
        motion: motion,
        targetChar: cmd.targetChar,
      )
    else:
      Operand(
        count: count,
        countGiven: countGiven,
        kind: odMark,
        markName:
          if cmd.targetChar.len == 1:
            cmd.targetChar[0]
          else:
            '\0',
        markLinewise: cmd.operatorType == "mark-line",
      )
  else:
    Operand(
      count: count, countGiven: countGiven, kind: odCommand, commandId: cmd.commandId
    )

proc finishOperator*(
    registry: CommandRegistry, ctx: CommandContext, operand: Operand
): Result[(), string] =
  ## Apply the waiting operator over what `operand` finds, end it and remember
  ## it for `.`. The operator ends whether or not anything is found.
  let op = ctx.state.pendingInput.pendingOperator.get
  ctx.state.pendingInput.pendingOperator = none(PendingOperator)
  ctx.state.pendingInput.pendingTextObject = none(PendingTextObject)
  ctx.register = op.register

  let target =
    case operand.kind
    of odMotion:
      ?ctx.motionTarget(op, operand)
    of odMark:
      ?ctx.markTarget(op, operand)
    of odTextObject:
      ?ctx.textObjectTarget(operand)
    of odCommand:
      if operand.commandId notin registry.targets:
        return err("Not a motion: " & operand.commandId)
      ?registry.targets[operand.commandId](ctx, op, operand.count, operand.countGiven)
    of odLines:
      ctx.linesTarget(op, operand)
  if target.isNone:
    # Nothing to act over (`dj` on the last line): Vim's clearopbeep.
    ctx.state.beep()
    return ok(())

  let range = ctx.buffer.toOperatorRange(target.get, op.operatorType)
  # As Vim's do_pending_operator, the cursor goes where the operated text
  # starts, before any widening to lines, and the operator moves it on from
  # there: a yank leaves it (`yb`, `yj`), and so does a refusal (`gUb`).
  ctx.cursor = ctx.settle(min(target.get.start, target.get.finish))
  if (target.get.start < target.get.finish or target.get.motionType == mtLinewise) and
      ctx.buffer.foldState.getCollapsedFoldAt(ctx.cursor.line).isSome:
    ctx.cursor = BufferPosition(line: ctx.cursor.line, column: 0)
  let opResult = executeOperatorOnRange(
    ctx, op.operatorType, range, op.operatorCount, some(op.topLine)
  )
  if opResult.isErr:
    return opResult
  case op.operatorType
  of OpYank:
    discard
  of OpChange:
    # What is typed next belongs to the change, so Insert records it.
    ctx.enterInsert(InsertEntry(kind: ieChange, operand: operand), 1)
  else:
    ctx.recordChange(
      LastEditCommand(
        kind: lecOperatorMotion, operator: op.operatorType, operand: operand
      )
    )
  ok(())

proc operatorKey*(
    registry: CommandRegistry,
    ctx: CommandContext,
    operatorType: OperatorType,
    count: int,
    countGiven: bool,
    statusMsg: string,
): Result[(), string] =
  ## An operator's key: over lines when the same operator waits (`dd`, `2d3d`
  ## for six lines), else wait for what it acts over, cancelling an operator of
  ## another kind (`dy`).
  let op = ctx.state.pendingInput.pendingOperator
  if op.isSome and op.get.operatorType == operatorType:
    return registry.finishOperator(
      ctx,
      Operand(
        kind: odLines,
        count: op.get.operandCount(count),
        countGiven: op.get.countGiven or countGiven,
      ),
    )
  ctx.setPendingOperator(operatorType, count, countGiven, statusMsg)
  ok(())

proc operateOnLines*(
    registry: CommandRegistry,
    ctx: CommandContext,
    operatorType: OperatorType,
    count: int,
): Result[(), string] =
  ## Apply `operatorType` over the count's lines from the cursor, as its
  ## doubled key does (`S` is `cc`).
  ctx.startOperator(operatorType)
  registry.finishOperator(ctx, Operand(kind: odLines, count: max(1, count)))
