import packages/docutils/highlite
import strutils, unicode, sequtils
import ui

proc getHighlightColor(buffer, language: string): seq[seq[ColorPair]] =
  let lang = getSourceLanguage(language)
  var token = GeneralTokenizer()
  token.initGeneralTokenizer(buffer)
  var color: seq[ColorPair] = @[]
  let defaultColor = brightWhiteDefault
  
  while true:
    token.getNextToken(lang)
    let str = buffer[token.start ..< token.start + token.length]

    case token.kind:
    of gtKeyword:
      color = concat(color, brightGreenDefault.repeat(str.len))
    of gtEof:
      break
    of gtWhitespace:
      color = concat(color, defaultColor.repeat(if str.len == str.countLines: str.len: else: str.len - 1))
    else:
      color = concat(color, defaultColor.repeat(str.len))

  var splitBuffer: seq[string] = @[]
  for buffer in buffer.splitLines:
    splitBuffer.add(buffer)

#[
  var all = 0
  for i in 0 ..< splitBuffer.len:
    for j in 0 ..< splitBuffer[i].len:
      stdout.write if color[all] == brightGreenDefault: "1" else: "0"
      all.inc
    if splitBuffer[i].len == 0:
      stdout.write "0"
      all.inc
    echo ""
    echo splitBuffer[i]
  quit()
]#

  result = @[]
  var
    first = 0
    last = 0
  for i in 0 ..< splitBuffer.len:
    if splitBuffer[i].len == 0:
      last.inc
      result.add(@[defaultColor])
    else:
      last = last + splitBuffer[i].high + 1
      result.add(color[first .. last])
    first = last

proc setHighlightColor*(buffer, lang: string): seq[seq[Colorpair]] =
  return getHighlightColor(buffer, lang)
