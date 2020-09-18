import macros, strformat
import undoredostack
export undoredostack

type GapBuffer*[T] = object
  buffer: seq[T]
  size: int # 意味のあるデータが実際に格納されているサイズ
  capacity: int # Amount of secured memory
  gapBegin, gapEnd: int # 半開区間[gapBegin,gapEnd)を隙間とする
  undoRedoStack: UndoRedoStack[T]

proc gapLen(gapBuffer: GapBuffer): int {.inline.} = gapBuffer.gapEnd - gapBuffer.gapBegin

proc makeGap(gapBuffer: var GapBuffer, gapBegin: int) =
  ## Create a gap starting with gapBegin
  doAssert(0 <= gapBegin and gapBuffer.capacity - gapBegin >= gapBuffer.gapLen,
           "Gapbuffer: Invalid position.")

  if gapBegin < gapBuffer.gapBegin:
    let
      len = gapBuffer.gapBegin-gapBegin
      index = gapBegin + gapBuffer.gapLen .. gapBegin+gapBuffer.gapLen+len - 1
    gapBuffer.buffer[index] = gapBuffer.buffer[gapBegin .. gapBegin + len - 1]
  else:
    let
      gapEnd = gapBegin + (gapBuffer.gapEnd-gapBuffer.gapBegin)
      len = gapEnd - gapBuffer.gapEnd
    gapBuffer.buffer[gapBuffer.gapBegin .. gapBuffer.gapBegin + len - 1] =
      gapBuffer.buffer[gapBuffer.gapEnd .. gapBuffer.gapEnd + len - 1]

  gapBuffer.gapEnd = gapBegin+gapBuffer.gapLen
  gapBuffer.gapBegin = gapBegin

proc reserve(gapBuffer: var GapBuffer, capacity: int) =
  doAssert(1 <= capacity and gapBuffer.size <= capacity,
           "Gapbuffer: New buffer capacity is too small.")

  gapBuffer.makeGap(gapBuffer.capacity-gapBuffer.gapLen)
  gapBuffer.buffer.setLen(capacity)
  gapBuffer.gapBegin = gapBuffer.size
  gapBuffer.gapEnd = capacity
  gapBuffer.capacity = capacity

proc insert*[T](gapBuffer: var GapBuffer,
                element: T,
                position: int,
                pushToStack: bool = true) =
  ## positionの直前に要素を挿入する.末尾に追加したい場合はpositionにバッファの要素数を渡す.
  ## ex.空のバッファに要素を追加する場合はpositionに0を渡す.
  doAssert(0 <= position and position <= gapBuffer.size,
           "Gapbuffer: Invalid position.")

  if pushToStack:
    gapBuffer.undoRedoStack.push(newInsertCommand[T](element, position))

  if gapBuffer.size == gapBuffer.capacity:
    gapBuffer.reserve(gapBuffer.capacity*2)
  if gapBuffer.gapBegin != position: gapBuffer.makeGap(position)
  gapBuffer.buffer[gapBuffer.gapBegin] = element
  inc(gapBuffer.gapBegin)
  inc(gapBuffer.size)

proc add*[T](gapBuffer: var GapBuffer[T], val: T, pushToStack: bool = true) {.inline.} =
  gapBuffer.insert(val, gapBuffer.len, pushToStack)

proc initGapBuffer*[T](): GapBuffer[T] =
  result.buffer = newSeq[T](1)
  result.capacity = 1
  result.gapEnd = 1
  result.undoRedoStack = initUndoRedoStack[T]()

proc initGapBuffer*[T](elements: seq[T]): GapBuffer[T] =
  result = initGapBuffer[T]()
  for e in elements: result.add(e, false)

proc deleteInterval(gapBuffer: var GapBuffer, first, last: int) =
  ## Delete [first, last] elements
  let
    delBegin = first
    delEnd = last+1
  doAssert(0 <= delBegin and delBegin <= delEnd and delEnd <= gapBuffer.size,
           "Gapbuffer: Invalid interval.")

  let
    trueBegin = if gapBuffer.gapBegin > delBegin: delBegin
                else: gapBuffer.gapEnd + (delBegin - gapBuffer.gapBegin)
    trueEnd = if gapBuffer.gapBegin > delEnd: delEnd
              else: gapBuffer.gapEnd + (delEnd - gapBuffer.gapBegin)

  if trueBegin <= gapBuffer.gapBegin and gapBuffer.gapEnd <= trueEnd:
    gapBuffer.gapBegin = trueBegin
    gapBuffer.gapEnd = trueEnd
  elif trueEnd <= gapBuffer.gapBegin:
    gapBuffer.makeGap(trueEnd)
    gapBuffer.gapBegin = trueBegin
  else:
    let len = trueBegin - gapBuffer.gapEnd
    gapBuffer.buffer[gapBuffer.gapBegin .. gapBuffer.gapBegin + len - 1] =
      gapBuffer.buffer[gapBuffer.gapEnd .. gapBuffer.gapEnd+len - 1]
    gapBuffer.gapBegin = gapBuffer.gapBegin + trueBegin - gapBuffer.gapEnd
    gapBuffer.gapEnd = trueEnd

  gapBuffer.size -= delEnd - delBegin
  while gapBuffer.size > 0 and gapBuffer.size * 4 <= gapBuffer.capacity:
    gapBuffer.reserve(gapBuffer.capacity div 2)

proc delete*[T](gapBuffer: var GapBuffer[T],
                index: int,
                pushToStack: bool = true) =

  ## Delete the i-th element
  if pushToStack:
    gapBuffer.undoRedoStack.push(newDeleteCommand[T](gapBuffer[index], index))
  gapBuffer.deleteInterval(index, index)

proc delete*[T](gapBuffer: var GapBuffer[T],
                first, last: int,
                pushToStack: bool = true) =

  ## Delete [first, last] elements
  for i in countdown(last, first): gapBuffer.delete(i)

proc assign*[T](gapBuffer: var GapBuffer,
                val: T,
                index: int,
                pushToStack: bool = true) =

  doAssert(0<=index and index<gapBuffer.size, "Gapbuffer: Invalid index.")

  if pushToStack:
    gapBuffer.undoRedoStack.push(newAssignCommand[T](gapBuffer[index],
                                                     val,
                                                     index))
  if index < gapBuffer.gapBegin: gapBuffer.buffer[index] = val
  else: gapBuffer.buffer[gapBuffer.gapEnd+(index-gapBuffer.gapBegin)] = val

proc `[]=`*[T](gapBuffer: var GapBuffer, index: int, val: T) =
  gapBuffer.assign(val, index)

proc `[]`*[T](gapBuffer: GapBuffer[T], index: int): T =
  let size = gapBuffer.size
  doAssert(0<=index and index<gapBuffer.size,
           "Gapbuffer: Invalid index. index = "&($index)&", gapBuffer.size = "&($size))

  if index < gapBuffer.gapBegin: return gapBuffer.buffer[index]
  return gapBuffer.buffer[gapBuffer.gapEnd+(index-gapBuffer.gapBegin)]

proc lastSuitId*(gapBuffer: GapBuffer): int {.inline.} = gapBuffer.undoRedoStack.lastSuitId

proc beginNewSuitIfNeeded*(gapBuffer: var GapBuffer) {.inline.} =
  gapBuffer.undoRedoStack.beginNewSuitIfNeeded

proc canUndo*(gapBuffer: GapBuffer): bool {.inline.} = gapBuffer.undoRedoStack.canUndo

proc canRedo*(gapBuffer: GapBuffer): bool {.inline.} = gapBuffer.undoRedoStack.canRedo

proc undo*(gapBuffer: var GapBuffer) {.inline.} = gapBuffer.undoRedoStack.undo(gapBuffer)

proc redo*(gapBuffer: var GapBuffer) {.inline.} = gapBuffer.undoRedoStack.redo(gapBuffer)

proc len*(gapBuffer: GapBuffer): int {.inline.} = gapBuffer.size

proc high*(gapBuffer: GapBuffer): int {.inline.} = gapBuffer.len-1

proc empty*(gapBuffer: GapBuffer): bool {.inline.} = return gapBuffer.len == 0

proc `$`*(gapBuffer: GapBuffer): string =
  result = ""
  for i in 0 ..< gapBuffer.len: result &= $gapBuffer[i] & "\n"

proc next*(gapBuffer: GapBuffer, line, column: int): (int, int) =
  result = (line, column)
  if line == gapBuffer.size-1 and column >= gapBuffer[gapBuffer.len-1].len-1:
    return result

  inc(result[1])
  if result[1] >= gapBuffer[line].len:
    inc(result[0])
    result[1] = 0

proc prev*(gapBuffer: GapBuffer, line, column: int): (int, int) =
  result = (line, column)
  if line == 0 and column == 0: return result

  dec(result[1])
  if result[1] == -1:
    dec(result[0])
    result[1] = max(gapBuffer[result[0]].len-1, 0)

proc isFirst*(gapBuffer: GapBuffer, line, column: int): bool {.inline.} =
  line == 0 and column == 0

proc isLast*(gapBuffer: GapBuffer, line, column: int): bool {.inline.} =
  line == gapBuffer.len-1 and column >= gapBuffer[gapBuffer.len-1].len-1

proc calcIndexInEntireBuffer*[T: array | seq | string](
  gapBuffer: GapBuffer[T],
  line, column: int,
  containNewline: bool): int =

  block:
    let mess = fmt"GapBuffer: The line is less than 0 or exceeds the length of the buffer. line = {line}, gapBuffer.len = {gapBuffer.len}."
    doAssert(0 <= line and line < gapBuffer.len, mess)
  block:
    let mess = fmt"GapBuffer: The column is less than 0 or exceeds the length of the buffer[line]. column = {column}, gapBuffer[line].len = {gapBuffer[line].len}."
    doAssert(0 <= column and column < gapBuffer[line].len, mess)

  for i in 0 ..< line:
    result += gapBuffer[i].len
    if containNewline: inc(result)
  result += column
