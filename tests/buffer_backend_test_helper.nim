## Shared helpers reproducing the removed linear byte-index buffer API on top
## of the surviving line/column API. The backend tests (`test_gap_buffer`,
## `test_piece_table`) use these to keep byte-offset-shaped assertions without
## each duplicating the flat-offset <-> (line, col) walk. The insert/delete
## wrappers stay per-backend (they route through each backend's own edit path),
## but the offset arithmetic below is identical and lives here once.

proc flatByteLen*[T](buf: T): int =
  ## Total flat byte length of `buf`: the sum of every line's content plus the
  ## single newline separating each line from the next (no trailing newline).
  ## Equals the byte length the removed linear-index API addressed into.
  mixin len, getLine
  for i in 0 ..< buf.len:
    result += buf.getLine(i).len
  if buf.len > 1:
    result += buf.len - 1

proc offsetToLineCol*[T](buf: T, idx: int): tuple[line, col: int] =
  ## Map a flat byte offset to a (line, col) position. Each non-last line spans
  ## `lineLen` bytes plus one separator newline; the last line has no trailing
  ## newline. Offsets <= 0 map to (0, 0) and offsets past the end clamp to the
  ## last line's end, matching the removed linear-index API's clamping.
  mixin len, getLine
  if idx <= 0:
    return (0, 0)
  var
    remaining = idx
    line = 0
  let lastLine = buf.len - 1
  while line < lastLine:
    let lineLen = buf.getLine(line).len
    if remaining <= lineLen:
      return (line, remaining)
    # Consume this line's bytes plus its separator newline.
    remaining -= lineLen + 1
    inc line
  # On (or past) the final line: clamp col to the line length.
  (lastLine, min(remaining, buf.getLine(lastLine).len))
