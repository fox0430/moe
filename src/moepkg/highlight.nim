import packages/docutils/highlite
import strutils, unicode, sequtils, ospaths
import ui, gapbuffer

proc getAllDefaultColor(buffer: string): seq[seq[Colorpair]] =
  var color: seq[ColorPair] = @[]
  let splitBuffer = buffer.splitLines

  var first = 0
  for i in 0 ..< splitBuffer.len:
    let index = first + splitBuffer[i].high
    result.add(brightWhiteDefault.repeat(splitBuffer[i].len))
    first = first + splitBuffer[i].len

proc getHighlightColor(buffer, language: string): seq[seq[ColorPair]] =
  let lang = getSourceLanguage(if language == "Plain": "None" else: language)
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
    of gtComment, gtLongComment:
      color = concat(color, whiteDefault.repeat(str.len))
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

proc initHighlightInfo*(buffer: GapBuffer[seq[Rune]], language: string, setting: bool): seq[seq[Colorpair]] =
  if setting and language != "Plain":
    return getHighlightColor($buffer, language)
  else:
    return getAllDefaultColor($buffer)

proc initLanguage*(filename: string): string =
  
  let extention = filename.splitFile.ext
  case extention:
  of ".nim", ".nimble":
    result = "Nim"
  of ".c", ".h":
    result = "C"
  of ".cpp":
    result = "C++"
  of ".cs":
    result = "C#"
  of ".java":
    result = "Java"
  of ".yaml":
    result = "Yaml"
  else:
    result = "Plain"
