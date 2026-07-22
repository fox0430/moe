import tokenizer

const
  gitRebaseCommands = [
    "b", "break", "d", "drop", "e", "edit", "exec", "f", "fixup", "l", "label", "m",
    "merge", "p", "pick", "r", "reset", "reword", "s", "squash", "t", "u", "update-ref",
    "x",
  ]

  # Commands whose argument is a label / ref rather than a commit hash. `t`
  # is the short form of `reset`, `u` of `update-ref`, `l` of `label`, `m` of
  # `merge`. Sorted for binarySearch.
  identifierArgCommands = ["l", "label", "m", "merge", "reset", "t", "u", "update-ref"]

  hexChars = {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}
  # Alphanumeric-like continuation chars that would indicate a hex run is
  # actually part of a longer identifier, not a hash.
  hashContChars = hexChars + {'g' .. 'z', 'G' .. 'Z', '_'}

  # Minimum hex-run length inside a comment before it counts as a hash. Git
  # help text uses 7-char abbreviations, and 7 is short enough that common
  # English words (beef, cafe, abed) don't false-positive.
  minCommentHashLen = 7

  # Sentinel `g.state` values for the mid-line phase machine.
  # Existing states kept as-is for backward compatibility of assertions.
  hashArgKeyword = gtKeyword # after hash-arg keyword
  hashArgWs = gtWhitespace # after ws following hash-arg keyword
  hashArgHash = gtDecNumber # after hash
  hashArgTail = gtStringLit # after ws following hash (commit message)
  idArgKeyword = gtBuiltin # after identifier-arg keyword
  idArgWs = gtLabel # after ws following identifier-arg keyword
  idArgIdent = gtIdentifier # after identifier arg
  inHashComment = gtLongComment # inside a comment line that has a hash

proc lineHasHash(buf: cstring, start: int): bool =
  ## True if the current line contains a hex run of `minCommentHashLen`+ chars
  ## whose trailing boundary is not alphanumeric — i.e., something that
  ## plausibly reads as an abbreviated commit hash.
  var p = start
  while buf[p] notin {'\0', '\n'}:
    if buf[p] in hexChars:
      let s = p
      while buf[p] in hexChars:
        inc p
      if p - s >= minCommentHashLen and buf[p] notin hashContChars:
        return true
    else:
      inc p
  false

proc scanToEol(buf: cstring, pos: var int) =
  while buf[pos] notin {'\0', '\n'}:
    inc pos
  if buf[pos] == '\n':
    inc pos

proc gitRebaseTodoNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = pos

  if g.buf[pos] == '\0':
    g.kind = gtEof
    g.length = 0
    return

  # Inside a comment line that contained a hash: sub-tokenize so hex runs get
  # their own gtDecNumber tokens, but keep prose in as-large chunks as possible.
  if g.state == inHashComment:
    if g.buf[pos] == '\n':
      inc pos
      g.kind = gtComment
      g.length = pos - g.start
      g.state = gtNone
      g.pos = pos
      return

    # If we start on a hash-like hex run, emit it.
    if g.buf[pos] in hexChars:
      var p = pos
      while g.buf[p] in hexChars:
        inc p
      if p - pos >= minCommentHashLen and g.buf[p] notin hashContChars:
        g.kind = gtDecNumber
        g.length = p - g.start
        g.state = inHashComment
        g.pos = p
        return
      # Not a hash — absorb this hex run into the prose chunk below.

    # Consume as one gtComment chunk until the next hash-like hex run or EOL.
    var scan = pos
    while g.buf[scan] notin {'\0', '\n'}:
      if g.buf[scan] in hexChars:
        var p = scan
        while g.buf[p] in hexChars:
          inc p
        if p - scan >= minCommentHashLen and g.buf[p] notin hashContChars:
          break
        scan = p
      else:
        inc scan
    g.kind = gtComment
    g.length = scan - g.start
    g.state = inHashComment
    g.pos = scan
    return

  # Line-start.
  if g.state in {gtEof, gtNone}:
    # Comment line: decide whole-line vs hash-splitting mode with a peek.
    if g.buf[pos] == '#':
      if lineHasHash(g.buf, pos):
        # Emit `#` alone; subsequent calls emit the rest of the line.
        g.kind = gtComment
        inc pos
        g.length = pos - g.start
        g.state = inHashComment
        g.pos = pos
        return
      # No hashes on this line — emit as a single comment token like before.
      scanToEol(g.buf, pos)
      g.kind = gtComment
      g.length = pos - g.start
      g.state = gtNone
      g.pos = pos
      return

    # Read a potential command word.
    var word = ""
    while g.buf[pos] notin {'\0', '\n', ' ', '\t'}:
      word.add g.buf[pos]
      inc pos
    if isKeyword(gitRebaseCommands, word) >= 0:
      g.kind = gtKeyword
      g.length = pos - g.start
      if isKeyword(identifierArgCommands, word) >= 0:
        g.state = idArgKeyword
      else:
        g.state = hashArgKeyword
      g.pos = pos
      return

    # Not a known command — rest of line as gtNone.
    while g.buf[pos] notin {'\0', '\n'}:
      inc pos
    if g.buf[pos] == '\n':
      inc pos
    g.kind = gtNone
    g.length = pos - g.start
    g.state = gtNone
    g.pos = pos
    return

  # After hash-arg keyword: whitespace before the hash.
  if g.state == hashArgKeyword and g.buf[pos] in {' ', '\t'}:
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t'}:
      inc pos
    g.length = pos - g.start
    g.state = hashArgWs
    g.pos = pos
    return

  # After whitespace following hash-arg keyword: try to read a hex hash.
  if g.state == hashArgWs and g.buf[pos] in hexChars:
    let hashStart = pos
    while g.buf[pos] in hexChars:
      inc pos
    if g.buf[pos] in {' ', '\t', '\n', '\0'}:
      g.kind = gtDecNumber
      g.length = pos - g.start
      g.state = hashArgHash
      g.pos = pos
      return
    # Not a clean hash — bail and consume rest of line.
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

  # After hash: whitespace before the commit message.
  if g.state == hashArgHash and g.buf[pos] in {' ', '\t'}:
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t'}:
      inc pos
    g.length = pos - g.start
    g.state = hashArgTail
    g.pos = pos
    return

  # After identifier-arg keyword: whitespace before the label/ref.
  if g.state == idArgKeyword and g.buf[pos] in {' ', '\t'}:
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t'}:
      inc pos
    g.length = pos - g.start
    g.state = idArgWs
    g.pos = pos
    return

  # After whitespace following identifier-arg keyword: emit the label/ref.
  if g.state == idArgWs and g.buf[pos] notin {' ', '\t', '\n', '\0'}:
    while g.buf[pos] notin {' ', '\t', '\n', '\0'}:
      inc pos
    g.kind = gtIdentifier
    g.length = pos - g.start
    g.state = idArgIdent
    g.pos = pos
    return

  # Fallback: consume rest of line as gtNone.
  while g.buf[pos] notin {'\0', '\n'}:
    inc pos
  if g.buf[pos] == '\n':
    inc pos
  g.kind = gtNone
  g.length = pos - g.start
  g.state = gtNone
  g.pos = pos
