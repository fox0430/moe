import packages/docutils/highlite
import strutils, unicode, sequtils, gapbuffer
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
      let countSpace = str.len - str.count('\n')
      color = concat(color, defaultColor.repeat(countSpace))
    of gtEof:
      break
    else:
      color = concat(color, defaultColor.repeat(str.len))
  
  let splitBuffer = buffer.splitLines

  var first = 0
  for i in 0 ..< splitBuffer.len:
    let index = first + splitBuffer[i].high
    result.add(color[first .. index])
    first = first + splitBuffer[i].len

proc setHighlightInfo*(buffer: GapBuffer[seq[Rune]]): seq[seq[Colorpair]] =
  return getHighlightColor($buffer, "Nim")

