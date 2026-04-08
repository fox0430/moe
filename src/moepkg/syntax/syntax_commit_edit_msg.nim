import tokenizer

proc commitEditMsgNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = pos

  if g.buf[pos] == '\0':
    g.kind = gtEof
    g.length = 0
    return

  # Comment line (# at line start)
  if g.state in {gtEof, gtNone} and g.buf[pos] == '#':
    g.kind = gtComment
    while g.buf[pos] notin {'\0', '\n'}:
      inc pos
    if g.buf[pos] == '\n':
      inc pos
    g.length = pos - g.start
    g.state = gtNone
    g.pos = pos
    return

  # Consume rest of line as gtNone (commit message text)
  while g.buf[pos] notin {'\0', '\n'}:
    inc pos
  if g.buf[pos] == '\n':
    inc pos
  g.kind = gtNone
  g.length = pos - g.start
  g.state = gtNone
  g.pos = pos
