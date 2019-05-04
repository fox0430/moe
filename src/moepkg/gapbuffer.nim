type GapBuffer*[T] = object
  buffer: seq[T]
  size: int # 意味のあるデータが実際に格納されているサイズ
  capacity: int # Amount of secured memory
  gapBegin, gapEnd: int # 半開区間[gapBegin,gapEnd)を隙間とする

proc gapLen(gapBuffer: GapBuffer): int = gapBuffer.gapEnd - gapBuffer.gapBegin

proc makeGap(gapBuffer: var GapBuffer, gapBegin: int) =
  ## Create a gap starting with gapBegin
  doAssert(0 <= gapBegin and gapBuffer.capacity - gapBegin >= gapBuffer.gapLen, "Gapbuffer: Invalid position.")

  if gapBegin < gapBuffer.gapBegin:
    let len = gapBuffer.gapBegin-gapBegin
    gapBuffer.buffer[gapBegin+gapBuffer.gapLen..gapBegin+gapBuffer.gapLen+len-1] = gapBuffer.buffer[gapBegin..gapBegin+len-1]
  else:
    let
      gapEnd = gapBegin + (gapBuffer.gapEnd-gapBuffer.gapBegin)
      len = gapEnd - gapBuffer.gapEnd
    gapBuffer.buffer[gapBuffer.gapBegin..gapBuffer.gapBegin+len-1] = gapBuffer.buffer[gapBuffer.gapEnd..gapBuffer.gapEnd+len-1]

  gapBuffer.gapEnd = gapBegin+gapBuffer.gapLen
  gapBuffer.gapBegin = gapBegin

proc reserve(gapBuffer: var GapBuffer, capacity: int) =
  doAssert(1<=capacity and gapBuffer.size <= capacity, "Gapbuffer: New buffer capacity is too small.")

  gapBuffer.makeGap(gapBuffer.capacity-gapBuffer.gapLen)
  gapBuffer.buffer.setLen(capacity)
  gapBuffer.gapBegin = gapBuffer.size
  gapBuffer.gapEnd = capacity
  gapBuffer.capacity = capacity

proc insert*[T](gapBuffer: var GapBuffer, element: T, position: int) =
  ## positionの直前に要素を挿入する.末尾に追加したい場合はpositionにバッファの要素数を渡す.
  ## ex.空のバッファに要素を追加する場合はpositionに0を渡す.
  doAssert(0<=position and position <= gapBuffer.size, "Gapbuffer: Invalid position.")

  if gapBuffer.size == gapBuffer.capacity: gapBuffer.reserve(gapBuffer.capacity*2)
  if gapBuffer.gapBegin != position: gapBuffer.makeGap(position)
  gapBuffer.buffer[gapBuffer.gapBegin] = element
  inc(gapBuffer.gapBegin)
  inc(gapBuffer.size)

proc add*[T](gapBuffer: var GapBuffer[T], val: T) =
  gapBuffer.insert(val, gapBuffer.len)

proc initGapBuffer*[T](): GapBuffer[T] =
  result.buffer = newSeq[T](1)
  result.capacity = 1
  result.gapEnd = 1

proc initGapBuffer*[T](elements: seq[T]): GapBuffer[T] =
  result = initGapBuffer[T]()
  for e in elements: result.add(e)

proc delete*(gapBuffer: var GapBuffer, delBegin, delEnd: int) =
  ## Delete [delBegin, delEnd) elements
  doAssert(0<=delBegin and delBegin <= delEnd and delEnd <= gapBuffer.size, "Gapbuffer: Invalid interval.")

  let
    trueBegin = if gapBuffer.gapBegin > delBegin: delBegin else: gapBuffer.gapEnd + (delBegin - gapBuffer.gapBegin)
    trueEnd = if gapBuffer.gapBegin > delEnd: delEnd else: gapBuffer.gapEnd + (delEnd - gapBuffer.gapBegin)

  if trueBegin <= gapBuffer.gapBegin and gapBuffer.gapEnd <= trueEnd:
    gapBuffer.gapBegin = trueBegin
    gapBuffer.gapEnd = trueEnd
  elif trueEnd <= gapBuffer.gapBegin:
    gapBuffer.makeGap(trueEnd)
    gapBuffer.gapBegin = trueBegin
  else:
    let len = trueBegin - gapBuffer.gapEnd
    gapBuffer.buffer[gapBuffer.gapBegin..gapBuffer.gapBegin+len-1] = gapBuffer.buffer[gapBuffer.gapEnd..gapBuffer.gapEnd+len-1]
    gapBuffer.gapBegin = gapBuffer.gapBegin + trueBegin - gapBuffer.gapEnd
    gapBuffer.gapEnd = trueEnd

  gapBuffer.size -= delEnd - delBegin
  while gapBuffer.size > 0 and gapBuffer.size*4 <= gapBuffer.capacity: gapBuffer.reserve(gapBuffer.capacity div 2)

proc `[]`*[T](gapBuffer: GapBuffer[T], index: int): T =
  doAssert(0<=index and index<gapBuffer.size, "Gapbuffer: Invalid index. index = "&($index)&", gapBuffer.size = "&($gapBuffer.size))

  if index < gapBuffer.gapBegin: return gapBuffer.buffer[index]
  return gapBuffer.buffer[gapBuffer.gapEnd+(index-gapBuffer.gapBegin)]

proc `[]`*[T](gapBuffer: var GapBuffer[T], index: int): var T =
  doAssert(0<=index and index<gapBuffer.size, "Gapbuffer: Invalid index.")

  if index < gapBuffer.gapBegin: return gapBuffer.buffer[index]
  return gapBuffer.buffer[gapBuffer.gapEnd+(index-gapBuffer.gapBegin)]

proc `[]=`*[T](gapBuffer: var GapBuffer, index: int, val: T) =
  doAssert(0<=index and index<gapBuffer.size, "Gapbuffer: Invalid index.")

  if index < gapBuffer.gapBegin: gapBuffer.buffer[index] = val
  else: gapBuffer.buffer[gapBuffer.gapEnd+(index-gapBuffer.gapBegin)] = val

proc len*(gapBuffer: GapBuffer): int = gapBuffer.size

proc high*(gapBuffer: GapBuffer): int = gapBuffer.len-1

proc empty*(gapBuffer: GapBuffer): bool = return gapBuffer.len == 0

proc `$`*(gapBuffer: GapBuffer): string =
  result = ""
  for i in 0 ..< gapBuffer.len: result &= $gapBuffer[i] & "\n"

proc next*(gapBuffer: GapBuffer, line, column: int): (int, int) =
  result = (line, column)
  if line == gapBuffer.size-1 and column >= gapBuffer[gapBuffer.len-1].len-1: return result

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

proc isFirst*(gapBuffer: GapBuffer, line, column: int): bool = line == 0 and column == 0

proc isLast*(gapBuffer: GapBuffer, line, column: int): bool = line == gapBuffer.len-1 and column >= gapBuffer[gapBuffer.len-1].len-1

