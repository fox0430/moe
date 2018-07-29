import strutils
import moepkg/unicodeext

doAssert("abc".toRunes.width == 3)
doAssert("あいう".toRunes.width == 6)
doAssert("abcあいう編集表示".toRunes.width == 17)

doAssert(48.toRune == '0'.toRune)
doAssert(65.toRune == 'A'.toRune)
doAssert(97.toRune == 'a'.toRune)

doAssert(($(ru'a'))[0] == 'a')

doAssert($(ru"abcde") == "abcde")
doAssert($(ru"あいうえお") == "あいうえお")
doAssert($(ru"編集表示") == "編集表示")

for x in 0 .. 127:
  let c = char(x)
  doAssert(c.toRune.canConvertToChar)
  doAssert(c.toRune.toChar == c)

for x in 0 .. 127:
  let c = char(x)
  doAssert(numberOfBytes(c) == 1)

doAssert(numberOfBytes("Ā"[0]) == 2)
doAssert(numberOfBytes("あ"[0]) == 3)
doAssert(numberOfBytes("。"[0]) == 3)
doAssert(numberOfBytes("１"[0]) == 3)
doAssert(numberOfBytes("🀀"[0]) == 4)

doAssert(ru"あいうえお   あいう".countRepeat(Whitespace, 5) == 3)
doAssert(ru"    ".countRepeat(Whitespace, 1) == 3)
