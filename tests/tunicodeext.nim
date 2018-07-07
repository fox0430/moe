import moepkg/unicodeext

doAssert("abc".toRunes.width == 3)
doAssert("あいう".toRunes.width == 6)
doAssert("abcあいう編集表示".toRunes.width == 17)

doAssert(48.toRune == '0'.toRune)
doAssert(65.toRune == 'A'.toRune)
doAssert(97.toRune == 'a'.toRune)

doAssert(($(u8'a'))[0] == 'a')

doAssert($(u8"abcde") == "abcde")
doAssert($(u8"あいうえお") == "あいうえお")
doAssert($(u8"編集表示") == "編集表示")


