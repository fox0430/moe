import encodings
import editorstatus, gapbuffer, unicodeext

proc openFile*(filename: seq[Rune]): tuple[text: seq[Rune], encoding: CharacterEncoding] =
  let
    raw = readFile($filename)
    encoding = detectCharacterEncoding(raw)
  
  if encoding == CharacterEncoding.unknown or encoding == CharacterEncoding.utf8:
    # 符号化形式が不明な場合は諦めてUTF-8とする
    return (raw.toRunes, CharacterEncoding.utf8)
  else:
    return (convert(raw, "UTF-8", $encoding).toRunes, encoding)

proc newFile*(): GapBuffer[seq[Rune]] =
  result = initGapBuffer[seq[Rune]]()
  result.add(ru"")

proc saveFile*(filename: seq[Rune], runes: seq[Rune], encoding: CharacterEncoding) =
  writeFile($filename, convert($runes, $encoding, "UTF-8"))
