import std/[os, encodings]
import gapbuffer, unicodeext

proc normalizePath*(path: seq[Rune]): seq[Rune] =
  if path[0] == ru'~':
    if path == ru"~" or path == ru"~/":
      result = getHomeDir().toRunes
    else:
      result = getHomeDir().toRunes & path[2..path.high]
  elif path == ru"./":
    return path
  elif path.len > 1 and path[0 .. 1] == ru"./":
    return path[2 .. path.high]
  else:
    return path

proc openFile*(filename: seq[Rune]): tuple[text: seq[Rune],
                                           encoding: CharacterEncoding] =

  let
    raw = readFile($filename)
    encoding = detectCharacterEncoding(raw)
    text =  if encoding == CharacterEncoding.unknown or
               encoding == CharacterEncoding.utf8:
      # 符号化形式が不明な場合は諦めてUTF-8としてUTF-32に変換する
      raw.toRunes
    else:
      convert(raw, "UTF-8", $encoding).toRunes
  return (text, encoding)

proc newFile*(): GapBuffer[seq[Rune]] {.inline.} =
  result = initGapBuffer[seq[Rune]]()
  result.add(ru"", false)

proc saveFile*(filename: seq[Rune],
               runes: seq[Rune],
               encoding: CharacterEncoding) =

  let
    encode = if encoding == CharacterEncoding.unknown: CharacterEncoding.utf8
             else: encoding
    buffer = convert($runes, $(encode),"UTF-8")
  writeFile($filename, buffer)
