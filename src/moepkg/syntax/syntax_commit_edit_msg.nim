import tokenizer

const
  # Canonical Conventional Commits type words (sorted for binarySearch).
  conventionalTypes = [
    "build", "chore", "ci", "docs", "feat", "fix", "perf", "refactor", "revert",
    "style", "test",
  ]

  # Common trailer keys per git-interpret-trailers (sorted for binarySearch).
  trailerTokens = [
    "Acked-by", "BREAKING-CHANGE", "Cc", "Change-Id", "Closes", "Co-authored-by",
    "Co-developed-by", "Fixes", "Helped-by", "Link", "References", "Refs",
    "Reported-by", "Reviewed-by", "Reviewed-on", "Signed-off-by", "Suggested-by",
    "Tested-by",
  ]

  # If a `#` comment line's content (after the `#` and leading whitespace)
  # starts with any of these markers, the line is emitted as gtPreprocessor
  # rather than gtComment so the structural git-status block stands out from
  # free-form comments.
  statusMarkers = [
    "Changes not staged for commit:", "Changes to be committed:", "On branch ",
    "Unmerged paths:", "Untracked files:", "Your branch", "copied:", "deleted:",
    "modified:", "new file:", "renamed:", "typechange:", "unmerged:",
  ]

  lowerAlpha = {'a' .. 'z'}
  trailerNameChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-'}

  # Sentinel `g.state` values that encode the mid-line phase for the
  # Conventional Commits / trailer state machines. Kept as TokenClass values
  # so no extra field is needed on GeneralTokenizer.
  ccPostType = gtKeyword # after "feat"
  ccPostParen = gtTagStart # after "(" — scope name expected next
  ccPostScope = gtTagEnd # after scope — ")" expected next
  ccPostBang = gtOperator # after "!" — ":" expected next
  ccPostColon = gtStringLit # after ":" — optional ws + rest of line
  ccRestOfLine = gtLongComment # after ":" and any ws — rest of line as body
  trPostKey = gtLabel # after trailer key — ":" expected next

proc scanToEol(buf: cstring, pos: var int) =
  while buf[pos] notin {'\0', '\n'}:
    inc pos
  if buf[pos] == '\n':
    inc pos

proc bufStartsWith(buf: cstring, pos: int, s: string): bool =
  for i in 0 ..< s.len:
    if buf[pos + i] != s[i]:
      return false
  true

proc matchStatusMarker(buf: cstring, pos: int): bool =
  for s in statusMarkers:
    if bufStartsWith(buf, pos, s):
      return true
  false

proc matchConventionalType(buf: cstring, pos: int): int =
  ## If a Conventional Commits type word followed by `(`, `!`, or `:` starts
  ## at `pos`, return the type word length; else 0.
  var p = pos
  while buf[p] in lowerAlpha:
    inc p
  let wordLen = p - pos
  if wordLen == 0 or buf[p] notin {'(', '!', ':'}:
    return 0
  var word = newString(wordLen)
  for i in 0 ..< wordLen:
    word[i] = buf[pos + i]
  if isKeyword(conventionalTypes, word) < 0:
    return 0
  wordLen

proc matchTrailerKey(buf: cstring, pos: int): int =
  ## If a known trailer key followed by `:` and whitespace / EOL starts at
  ## `pos`, return its length; else 0.
  var p = pos
  while buf[p] in trailerNameChars:
    inc p
  let nameLen = p - pos
  if nameLen == 0 or buf[p] != ':':
    return 0
  # A trailer's `:` must be followed by whitespace or EOL, otherwise this is
  # body prose that happens to contain a colon.
  if buf[p + 1] notin {' ', '\t', '\n', '\0'}:
    return 0
  var name = newString(nameLen)
  for i in 0 ..< nameLen:
    name[i] = buf[pos + i]
  if isKeyword(trailerTokens, name) < 0:
    return 0
  nameLen

proc emitRestOfLine(g: var GeneralTokenizer, pos: var int) =
  scanToEol(g.buf, pos)
  g.kind = gtNone
  g.length = pos - g.start
  g.state = gtNone
  g.pos = pos

proc commitEditMsgNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = pos

  if g.buf[pos] == '\0':
    g.kind = gtEof
    g.length = 0
    return

  # Mid-line phases of the Conventional Commits / trailer state machines.
  # Each branch either emits a specific sub-token or drops back to
  # rest-of-line body text on an unexpected char.
  case g.state
  of ccPostType:
    case g.buf[pos]
    of '(':
      g.kind = gtPunctuation
      inc pos
      g.length = pos - g.start
      g.state = ccPostParen
      g.pos = pos
    of '!':
      g.kind = gtOperator
      inc pos
      g.length = pos - g.start
      g.state = ccPostBang
      g.pos = pos
    of ':':
      g.kind = gtPunctuation
      inc pos
      g.length = pos - g.start
      g.state = ccPostColon
      g.pos = pos
    else:
      emitRestOfLine(g, pos)
    return
  of ccPostParen:
    while g.buf[pos] notin {'\0', '\n', ')'}:
      inc pos
    if pos > g.start:
      g.kind = gtIdentifier
      g.length = pos - g.start
      g.state = ccPostScope
      g.pos = pos
      return
    if g.buf[pos] == ')':
      g.kind = gtPunctuation
      inc pos
      g.length = pos - g.start
      g.state = ccPostType
      g.pos = pos
      return
    emitRestOfLine(g, pos)
    return
  of ccPostScope:
    if g.buf[pos] == ')':
      g.kind = gtPunctuation
      inc pos
      g.length = pos - g.start
      g.state = ccPostType
      g.pos = pos
      return
    emitRestOfLine(g, pos)
    return
  of ccPostBang:
    if g.buf[pos] == ':':
      g.kind = gtPunctuation
      inc pos
      g.length = pos - g.start
      g.state = ccPostColon
      g.pos = pos
      return
    emitRestOfLine(g, pos)
    return
  of ccPostColon:
    if g.buf[pos] in {' ', '\t'}:
      while g.buf[pos] in {' ', '\t'}:
        inc pos
      g.kind = gtWhitespace
      g.length = pos - g.start
      g.state = ccRestOfLine
      g.pos = pos
      return
    emitRestOfLine(g, pos)
    return
  of ccRestOfLine:
    emitRestOfLine(g, pos)
    return
  of trPostKey:
    if g.buf[pos] == ':':
      g.kind = gtPunctuation
      inc pos
      g.length = pos - g.start
      g.state = ccPostColon
      g.pos = pos
      return
    emitRestOfLine(g, pos)
    return
  else:
    discard

  # Line-start dispatch.
  if g.buf[pos] == '#':
    var probe = pos + 1
    while g.buf[probe] in {' ', '\t'}:
      inc probe
    let isSpecial = matchStatusMarker(g.buf, probe)
    scanToEol(g.buf, pos)
    g.kind = if isSpecial: gtPreprocessor else: gtComment
    g.length = pos - g.start
    g.state = gtNone
    g.pos = pos
    return

  if g.buf[pos] == '\n':
    inc pos
    g.kind = gtNone
    g.length = pos - g.start
    g.state = gtNone
    g.pos = pos
    return

  # Non-empty, non-comment content line.
  if not g.lang.commit.subjectSeen:
    g.lang.commit.subjectSeen = true
    let ccLen = matchConventionalType(g.buf, pos)
    if ccLen > 0:
      g.kind = gtKeyword
      inc pos, ccLen
      g.length = pos - g.start
      g.state = ccPostType
      g.pos = pos
      return
    emitRestOfLine(g, pos)
    return

  # Body line — try trailer.
  let trLen = matchTrailerKey(g.buf, pos)
  if trLen > 0:
    g.kind = gtKey
    inc pos, trLen
    g.length = pos - g.start
    g.state = trPostKey
    g.pos = pos
    return

  emitRestOfLine(g, pos)
