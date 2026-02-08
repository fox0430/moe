import tokenizer

proc diffNextToken*(g: var GeneralTokenizer) =
  ## Tokenize unified diff output.
  ## Each line is classified by its first character:
  ##   '+' → gtStringLit  (added)
  ##   '-' → gtComment    (deleted)
  ##   '@' → gtPreprocessor (hunk header)
  ##   'd','i','n' etc. starting meta → gtKeyword (meta)
  ##   otherwise → gtNone  (context)
  var pos = g.pos
  g.start = pos

  if g.buf[pos] == '\0':
    g.kind = gtEof
    g.length = 0
    return

  # Determine token class from line-start character
  let lineStart = g.buf[pos]

  # Classify the whole line as a single token
  case lineStart
  of '+':
    g.kind = gtStringLit
  of '-':
    g.kind = gtComment
  of '@':
    g.kind = gtPreprocessor
  of 'd', 'i', 'n', 'o', 'r', 's':
    # "diff ", "index ", "new file", "old mode", "rename", "similarity"
    g.kind = gtKeyword
  else:
    g.kind = gtNone

  # Consume the entire line
  while g.buf[pos] notin {'\0', '\n'}:
    inc pos
  # Consume the newline if present
  if g.buf[pos] == '\n':
    inc pos

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "diffNextToken: produced an empty token"
  g.pos = pos
