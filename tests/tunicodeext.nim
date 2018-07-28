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


