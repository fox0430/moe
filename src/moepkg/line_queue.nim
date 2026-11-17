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

## The lines a running command writes, handed from the read in the event loop
## to the editor, which takes them as it has time.
##
## No chronos here, so the editor state can hold a queue: the read waits for
## room through a plain closure (`onRoom`) instead of a Future.

import std/[deques, options]

import encoding

proc memchr(
  s: pointer, c: cint, n: csize_t
): pointer {.importc: "memchr", header: "<string.h>".}

proc addChars*(s: var string, part: openArray[char]) =
  ## Append `part` without copying it into a string of its own first.
  if part.len > 0:
    let at = s.len
    s.setLen(at + part.len)
    copyMem(addr s[at], unsafeAddr part[0], part.len)

const DefaultQueueCapacity* = 1024 * 1024
  ## Bytes queued before the read waits for the taker.

type
  RoomAction* = proc() {.closure, gcsafe, raises: [].}

  LineQueue* = ref object
    lines: Deque[string]
    bytes: int ## Queued, a line counting its separator too.
    capacity: int
    waiter: RoomAction ## The read waiting for room, woken by `take`.
    # Written by the run, final once `ended` is set.
    ended*: bool ## The run has returned: no more lines come.
    limitReached*: bool ## Output went on past the line limit, and was not queued.
    stopped*: bool ## Stopped from outside before its output was read to the end.
    exitCode*: Option[int]
      ## How it ended on its own; none if a kill of the run's reached it running.
    failure*: string ## Why it could not be started or read; empty if neither.
    diagnostics*: seq[string] ## The first lines of its standard error.
    diagnosticsTruncated*: bool

proc newLineQueue*(capacity = DefaultQueueCapacity): LineQueue =
  LineQueue(capacity: max(1, capacity))

proc len*(q: LineQueue): int =
  q.lines.len

proc full*(q: LineQueue): bool =
  q.bytes >= q.capacity

proc downToHalf(q: LineQueue): bool =
  ## Where a read waiting for room is woken: woken at the first byte of room,
  ## it would read a line's worth per take.
  q.bytes <= q.capacity div 2

proc add*(q: LineQueue, line: sink string) =
  q.bytes += line.len + 1
  q.lines.addLast(line)

proc onRoom*(q: LineQueue, action: RoomAction) =
  ## Run `action` once takes bring the queue down to half its capacity, or now
  ## if it is not full. Replaces any previous action; nil drops it.
  if not action.isNil and not q.full:
    q.waiter = nil
    action()
  else:
    q.waiter = action

proc take*(q: LineQueue, count: int): seq[string] =
  ## Take up to `count` of the oldest lines, waking a read waiting for room
  ## once the queue is down to half its capacity.
  while result.len < count and q.lines.len > 0:
    let line = q.lines.popFirst()
    q.bytes -= line.len + 1
    result.add line
  if not q.waiter.isNil and q.downToHalf:
    let action = q.waiter
    q.waiter = nil
    action()

proc drained*(q: LineQueue): bool =
  ## The run has returned and every line it read has been taken.
  q.ended and q.lines.len == 0

const DefaultMaxLineBytes* = 16 * 1024
  ## Bytes of a line kept; the rest of a longer one is dropped.

type LineSplitter* = object
  ## Cuts a stream into lines for a queue, bounded in length and in number.
  separator: char
  maxLines: int ## Non-positive means no bound.
  maxLineBytes: int ## Non-positive means no bound.
  count: int
  line: string
  cut: bool ## `line` lost its end to `maxLineBytes`.
  over: bool ## A byte past `maxLines` lines came.

proc initLineSplitter*(
    separator: char, maxLines = 0, maxLineBytes = DefaultMaxLineBytes
): LineSplitter =
  LineSplitter(separator: separator, maxLines: maxLines, maxLineBytes: maxLineBytes)

proc overLimit*(s: LineSplitter): bool =
  ## Output went on past `maxLines` lines: what follows is a line too many.
  s.over

proc append(s: var LineSplitter, part: openArray[char]) =
  var n = part.len
  if s.maxLineBytes > 0 and s.line.len + n > s.maxLineBytes:
    n = s.maxLineBytes - s.line.len
    s.cut = true
  s.line.addChars(part.toOpenArray(0, n - 1))

proc push(s: var LineSplitter, q: LineQueue) =
  if s.cut:
    # Drop a character the cut left incomplete.
    let tail = s.line.utf8TruncatedTailStart
    if tail >= 0:
      s.line.setLen(tail)
  q.add move(s.line)
  s.line = ""
  s.cut = false
  inc s.count

proc find(data: openArray[char], c: char, start: int): int =
  ## Where the first `c` at or after `start` is, or `data.len` if none is.
  if start >= data.len:
    return data.len
  let found = memchr(unsafeAddr data[start], cint(c), csize_t(data.len - start))
  if found.isNil:
    data.len
  else:
    start + (cast[int](found) - cast[int](unsafeAddr data[start]))

iterator pieces(
    data: openArray[char], separator: char
): tuple[first, last: int, ended: bool] =
  ## `data[first ..< last]` up to each separator (`ended`), then the text after
  ## the last one if there is any.
  var start = 0
  while start < data.len:
    let at = data.find(separator, start)
    yield (start, at, at < data.len)
    start = at + 1

proc feed*(s: var LineSplitter, q: LineQueue, data: openArray[char]): int =
  ## Queue the lines `data` ends, keeping the text after the last separator
  ## for the next feed, and return the bytes taken. Fewer than `data.len` are
  ## taken once a line fills `q`, the rest to be fed when it has room, or once
  ## a byte past `maxLines` lines comes, which sets `overLimit`: whatever
  ## follows, that byte begins a line past the limit.
  for (first, last, ended) in data.pieces(s.separator):
    if s.maxLines > 0 and s.count >= s.maxLines:
      s.over = true
      return first
    s.append(data.toOpenArray(first, last - 1))
    if ended:
      s.push(q)
      if q.full:
        return last + 1
  data.len

proc finish*(s: var LineSplitter, q: LineQueue) =
  ## Queue the text after the last separator, which is a line if there is
  ## any.
  if s.line.len > 0:
    s.push(q)

proc cutLines*(text: openArray[char], separator: char): seq[string] =
  ## `text` cut into lines as a stream of it would be: empty lines kept, the
  ## text after the last separator a line if there is any.
  for (first, last, _) in text.pieces(separator):
    var line = newStringOfCap(last - first)
    line.addChars(text.toOpenArray(first, last - 1))
    result.add line
