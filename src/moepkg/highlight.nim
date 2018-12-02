import packages/docutils/highlite
import strutils, unicode, sequtils
import ui

proc getHighlightColor*(buffer, language: string): seq[seq[ColorPair]] =
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
    of gtStringLit:
      color = concat(color, magentaDefault.repeat(str.len))
    of gtDecNumber:
      color = concat(color, lightBlueDefault.repeat(str.len))
    of gtWhitespace:
      var numOfSpace = 0
      for i in 0 ..< str.len:
        if str[i] != '\n':
          numOfSpace.inc
      color = concat(color, defaultColor.repeat(numOfSpace))
    of gtEof:
      break
    else:
      color = concat(color, defaultColor.repeat(str.len))

  var splitBuffer: seq[string] = @[]
  for buffer in buffer.splitLines:
    splitBuffer.add(buffer)

  result = @[]
  var all = 0
  for i in 0 ..< splitBuffer.len:
    var line: seq[Colorpair] = @[]
    for j in 0 ..< splitBuffer[i].len:
      if splitBuffer[i].len != 0:
        line.add(color[all])
        all.inc
    result.add(line)
