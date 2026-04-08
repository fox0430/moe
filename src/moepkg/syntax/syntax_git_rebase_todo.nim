import tokenizer

const
  gitRebaseCommands = [
    "b", "break", "d", "drop", "e", "edit", "exec", "f", "fixup", "l", "label", "m",
    "merge", "p", "pick", "r", "reset", "reword", "s", "squash", "t", "u", "update-ref",
    "x",
  ]

  hexChars = {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}

proc gitRebaseTodoNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = pos

  if g.buf[pos] == '\0':
    g.kind = gtEof
    g.length = 0
    return

  # At line start (initial state or after consuming a full line)
  if g.state in {gtEof, gtNone}:
    # Comment line
    if g.buf[pos] == '#':
      g.kind = gtComment
      while g.buf[pos] notin {'\0', '\n'}:
        inc pos
      if g.buf[pos] == '\n':
        inc pos
      g.length = pos - g.pos
      g.state = gtNone
      g.pos = pos
      return

    # Try to read a keyword
    var word = ""
    while g.buf[pos] notin {'\0', '\n', ' ', '\t'}:
      word.add g.buf[pos]
      inc pos
    if isKeyword(gitRebaseCommands, word) >= 0:
      g.kind = gtKeyword
      g.length = pos - g.start
      g.state = gtKeyword
      g.pos = pos
      return
    else:
      # Not a keyword, consume rest of line as gtNone
      while g.buf[pos] notin {'\0', '\n'}:
        inc pos
      if g.buf[pos] == '\n':
        inc pos
      g.kind = gtNone
      g.length = pos - g.start
      g.state = gtNone
      g.pos = pos
      return

  # After keyword: whitespace
  if g.state == gtKeyword and g.buf[pos] in {' ', '\t'}:
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t'}:
      inc pos
    g.length = pos - g.start
    g.state = gtWhitespace
    g.pos = pos
    return

  # After whitespace following keyword: try commit hash (hex string)
  if g.state == gtWhitespace and g.buf[pos] in hexChars:
    let hashStart = pos
    while g.buf[pos] in hexChars:
      inc pos
    # Only treat as hash if followed by space, newline, or EOF
    if g.buf[pos] in {' ', '\t', '\n', '\0'}:
      g.kind = gtDecNumber
      g.length = pos - g.start
      g.state = gtDecNumber
      g.pos = pos
      return
    else:
      # Not a hash, consume rest of line as gtNone
      pos = hashStart
      while g.buf[pos] notin {'\0', '\n'}:
        inc pos
      if g.buf[pos] == '\n':
        inc pos
      g.kind = gtNone
      g.length = pos - g.start
      g.state = gtNone
      g.pos = pos
      return

  # After hash: whitespace before commit message
  if g.state == gtDecNumber and g.buf[pos] in {' ', '\t'}:
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t'}:
      inc pos
    g.length = pos - g.start
    g.state = gtStringLit # Commit message follows (not line start)
    g.pos = pos
    return

  # Consume rest of line as gtNone (commit message or other text)
  while g.buf[pos] notin {'\0', '\n'}:
    inc pos
  if g.buf[pos] == '\n':
    inc pos
  g.kind = gtNone
  g.length = pos - g.start
  g.state = gtNone
  g.pos = pos
