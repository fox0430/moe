#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[strutils, unittest, encodings, sequtils, sugar]
from std/os import `/`
import moepkg/gapbuffer
import moepkg/unicodeext

suite "unicodeext: width":
  test "width 1":
    check("abc".toRunes.width == 3)
    check("あいう".toRunes.width == 6)
    check("abcあいう編集表示".toRunes.width == 17)

  test "width 2":
    check(Rune(0x10FFFF).width == 1)
    check(Rune(0x110000).width == 1)

suite "unicodeext: iterator split":
  test "Basic":
    const
      ExpectedResult = @["abc", "", "def"].toSeqRunes

      ActualResult = collect(newSeq):
        for x in unicodeext.split(ru"abc;def", r => r == ru ';'):
          x

    check ActualResult == ExpectedResult

  test "Basic 2":
    const
      ExpectedResult =
        @["", "", "this", "", "is", "", "an", "", "", "example", "", "", ""].toSeqRunes

      Buffer = ru";;this;is;an;;example;;;"
      ActualResult = collect(newSeq):
        for x in unicodeext.split(Buffer, r => r == ru ';'):
          x

    check ActualResult == ExpectedResult

  test "Remove empty rntries":
    const
      ExpectedResult = @["", "", "this", "is", "an", "", "example", "", "", ""].toSeqRunes.filter(
        runes => runes.len > 0
      )

      Buffer = ru";;this;is;an;;example;;;"
      ActualResult = collect(newSeq):
        for x in unicodeext.split(Buffer, r => r == ru ';', true):
          x

    check ActualResult == ExpectedResult

suite "unicodeext: split":
  test "Basic":
    check split(ru"abc;def", ru ';') == @["abc", "", "def"].toSeqRunes

  test "Basic 2":
    check split(ru";;this;is;an;;example;;;", ru ';') ==
      @["", "", "this", "", "is", "", "an", "", "", "example", "", "", ""].toSeqRunes

  test "Remove empty entries":
    check split(ru";;this;is;an;;example;;;", ru ';', true) ==
      @["this", "is", "an", "example"].toSeqRunes

  test "Empty":
    check split(ru"", ru ';') == @[""].toSeqRunes

  test "Empty with remove empty entries":
    check split(ru"", ru ';', true).len == 0

suite "unicodeext: splitWhitespace":
  test "Basic":
    check splitWhitespace(ru"abc def") == @["abc", "", "def"].toSeqRunes

  test "Basic 2":
    check splitWhitespace(ru"  abc def  efg  ") ==
      @["", "", "abc", "", "def", "", "", "efg", "", ""].toSeqRunes

  test "Remove empty entries":
    check splitWhitespace(ru"  abc def  efg  ", true) ==
      @["abc", "def", "efg"].toSeqRunes

  test "Empty":
    check splitWhitespace(ru"") == @[""].toSeqRunes

  test "Empty with remove empty entries":
    check splitWhitespace(ru"", true).len == 0

  test "Without whitespaces":
    check splitWhitespace(ru"abc") == @["abc"].toSeqRunes

suite "unicodeext: iterator splitLines":
  test "Basic":
    let r = collect:
      for x in splitLines(toRunes("ABC\nDEF\n")):
        x

    check r == @["ABC", "DEF", ""].toSeqRunes

  test "Basic 2":
    let r = collect:
      for x in splitLines(toRunes("\n\nA\nBC\n\n")):
        x

    check r == @["", "", "A", "BC", "", ""].toSeqRunes

  test "Empty":
    let r = collect:
      for x in splitLines(toRunes("")):
        x

    check r == @[""].toSeqRunes

  test "Only lines":
    let r = collect:
      for x in splitLines(toRunes("\n\n\n")):
        x

    check r == @["", "", "", ""].toSeqRunes

  test "Without lines":
    let r = collect:
      for x in splitLines(toRunes("abc")):
        x

    check r == @["abc"].toSeqRunes

suite "unicodeext: splitLines":
  test "Basic":
    check splitLines(toRunes("ABC\nDEF\n")) == @["ABC", "DEF", ""].toSeqRunes

  test "Basic 2":
    check splitLines(toRunes("\n\nA\nBC\n\n")) == @["", "", "A", "BC", "", ""].toSeqRunes

  test "Empty":
    check splitLines(ru"") == @[""].toSeqRunes

  test "Only lines":
    check splitLines(toRunes("\n\n\n")) == @["", "", "", ""].toSeqRunes

  test "Without lines":
    check splitLines(ru"abc") == @["abc"].toSeqRunes

suite "unicodeext: toRune, ru":
  test "toRune":
    check(48.toRune == '0'.toRune)
    check(65.toRune == 'A'.toRune)
    check(97.toRune == 'a'.toRune)

  test "ru":
    check(($(ru 'a'))[0] == 'a')

    check($(ru"abcde") == "abcde")
    check($(ru"あいうえお") == "あいうえお")
    check($(ru"編集表示") == "編集表示")

suite "unicodeext: canConvertToChar, toChar":
  test "canConvertToChar, toChar":
    for x in 0 .. 127:
      let c = char(x)
      doAssert(c.toRune.canConvertToChar)
      doAssert(c.toRune.toChar == c)

suite "unicodeext: numberOfBytes":
  test "numberOfBytes":
    for x in 0 .. 127:
      let c = char(x)
      check(numberOfBytes(c) == 1)

    check(numberOfBytes("Ā"[0]) == 2)
    check(numberOfBytes("あ"[0]) == 3)
    check(numberOfBytes("。"[0]) == 3)
    check(numberOfBytes("１"[0]) == 3)
    check(numberOfBytes("🀀"[0]) == 4)

suite "unicodeext: countRepeat":
  test "countRepeat":
    check(ru"あいうえお   あいう".countRepeat(Whitespace, 5) == 3)
    check(ru"    ".countRepeat(Whitespace, 1) == 3)

suite "unicodeext: toRunes":
  test "toRunes":
    let runes: Runes = @[]
    check(runes.toGapBuffer.toRunes == runes)

let s =
  """Sentences that contain all letters commonly used in a language
--------------------------------------------------------------

Markus Kuhn <http://www.cl.cam.ac.uk/~mgk25/> -- 2012-04-11

This is an example of a plain-text file encoded in UTF-8.


Danish (da)
---------

  Quizdeltagerne spiste jordbær med fløde, mens cirkusklovnen
  Wolther spillede på xylofon.
  (= Quiz contestants were eating strawberry with cream while Wolther
  the circus clown played on xylophone.)

German (de)
-----------

  Falsches Üben von Xylophonmusik quält jeden größeren Zwerg
  (= Wrongful practicing of xylophone music tortures every larger dwarf)

  Zwölf Boxkämpfer jagten Eva quer über den Sylter Deich
  (= Twelve boxing fighters hunted Eva across the dike of Sylt)

  Heizölrückstoßabdämpfung
  (= fuel oil recoil absorber)
  (jqvwxy missing, but all non-ASCII letters in one word)

Greek (el)
----------

  Γαζέες καὶ μυρτιὲς δὲν θὰ βρῶ πιὰ στὸ χρυσαφὶ ξέφωτο
  (= No more shall I see acacias or myrtles in the golden clearing)

  Ξεσκεπάζω τὴν ψυχοφθόρα βδελυγμία
  (= I uncover the soul-destroying abhorrence)

English (en)
------------

  The quick brown fox jumps over the lazy dog

Spanish (es)
------------

  El pingüino Wenceslao hizo kilómetros bajo exhaustiva lluvia y 
  frío, añoraba a su querido cachorro.
  (Contains every letter and every accent, but not every combination
  of vowel + acute.)

French (fr)
-----------

  Portez ce vieux whisky au judge blond qui fume sure son île intérieure, à
  côté de l'alcôve ovoïde, où les bûches se consument dans l'âtre, ce
  qui lui permet de penser à la cænogenèse de l'être dont il est question
  dans la cause ambiguë entendue à Moÿ, dans un capharnaüm qui,
  pense-t-il, diminue çà et là la qualité de son œuvre. 

  l'île exiguë
  Où l'obèse jury mûr
  Fête l'haï volapük,
  Âne ex aéquo au whist,
  Ôtez ce vœu déçu.

  Le cœur déçu mais l'âme plutôt naïve, Louÿs rêva de crapaüter en
  canoë au delà des îles, près du mälström où brûlent les novæ.

Irish Gaelic (ga)
-----------------

  D'fhuascail Íosa, Úrmhac na hÓighe Beannaithe, pór Éava agus Ádhaimh

Hungarian (hu)
--------------

  Árvíztűrő tükörfúrógép
  (= flood-proof mirror-drilling machine, only all non-ASCII letters)

Icelandic (is)
--------------

  Kæmi ný öxi hér ykist þjófum nú bæði víl og ádrepa

  Sævör grét áðan því úlpan var ónýt
  (some ASCII letters missing)

Japanese (jp)
-------------

  Hiragana: (Iroha)

  いろはにほへとちりぬるを
  わかよたれそつねならむ
  うゐのおくやまけふこえて
  あさきゆめみしゑひもせす

  Katakana:

  イロハニホヘト チリヌルヲ ワカヨタレソ ツネナラム
  ウヰノオクヤマ ケフコエテ アサキユメミシ ヱヒモセスン

Hebrew (iw)
-----------

  ? דג סקרן שט בים מאוכזב ולפתע מצא לו חברה איך הקליטה

Polish (pl)
-----------

  Pchnąć w tę łódź jeża lub ośm skrzyń fig
  (= To push a hedgehog or eight bins of figs in this boat)

Russian (ru)
------------

  В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!
  (= Would a citrus live in the bushes of south? Yes, but only a fake one!)

  Съешь же ещё этих мягких французских булок да выпей чаю
  (= Eat some more of these fresh French loafs and have some tea) 

Thai (th)
---------

  [--------------------------|------------------------]
  ๏ เป็นมนุษย์สุดประเสริฐเลิศคุณค่า  กว่าบรรดาฝูงสัตว์เดรัจฉาน
  จงฝ่าฟันพัฒนาวิชาการ           อย่าล้างผลาญฤๅเข่นฆ่าบีฑาใคร
  ไม่ถือโทษโกรธแช่งซัดฮึดฮัดด่า     หัดอภัยเหมือนกีฬาอัชฌาสัย
  ปฏิบัติประพฤติกฎกำหนดใจ        พูดจาให้จ๊ะๆ จ๋าๆ น่าฟังเอย ฯ

  [The copyright for the Thai example is owned by The Computer
  Association of Thailand under the Royal Patronage of His Majesty the
  King.]

Turkish (tr)
------------

  Pijamalı hasta, yağız şoföre çabucak güvendi.
  (=Patient with pajamas, trusted swarthy driver quickly)


Special thanks to the people from all over the world who contributed
these sentences since 1999.

A much larger collection of such pangrams is now available at

  http://en.wikipedia.org/wiki/List_of_pangrams"""

suite "unicodeext: detectCharacterEncoding":
  test "UTF-8 with BOM":
    check(("\xEF\xBB\xBF" & s).detectCharacterEncoding == CharacterEncoding.utf8)

  test "UTF-16 with BE BOM":
    check(("\xFE\xFF" & s).detectCharacterEncoding == CharacterEncoding.utf16)

  test "UTF-16 with LE BOM":
    check(("\xFF\xFE" & s).detectCharacterEncoding == CharacterEncoding.utf16)

  test "UTF-32 with BE BOM":
    check(("\x00\x00\xFE\xFF" & s).detectCharacterEncoding == CharacterEncoding.utf32)

  test "UTF-32 with LE BOM":
    check(("\xFF\xFE\x00\x00" & s).detectCharacterEncoding == CharacterEncoding.utf32)

  test "UTF-8":
    check(s.detectCharacterEncoding == CharacterEncoding.utf8)

  test "UTF-16BE":
    let
      ec = open("UTF-16BE", "UTF-8")
      converted = convert(ec, s)
    check(converted.detectCharacterEncoding == CharacterEncoding.utf16Be)
    ec.close

  test "UTF-16LE":
    let
      ec = open("UTF-16LE", "UTF-8")
      converted = convert(ec, s)
    check(converted.detectCharacterEncoding == CharacterEncoding.utf16Le)
    ec.close

  test "UTF-32BE":
    let
      ec = open("UTF-32BE", "UTF-8")
      converted = convert(ec, s)
    check(converted.detectCharacterEncoding == CharacterEncoding.utf32Be)
    ec.close

  test "UTF-32LE":
    let
      ec = open("UTF-32LE", "UTF-8")
      converted = convert(ec, s)
    check(converted.detectCharacterEncoding == CharacterEncoding.utf32Le)
    ec.close

suite "unicodeext: findRune":
  test "findRune":
    check find(ru"あaa", ru 'a') == 1
    check find(ru"あaa", ru 'b') == -1

  test "findRunes":
    check find(runes = ru"あいういう", sub = ru"いう") == 1
    check find(runes = ru"あいういういう", sub = ru"いう", start = 2, last = 4) ==
      3
    check find(runes = ru"あいういう", sub = ru"いうう") == -1

suite "unicodeext: rfindRune":
  test "rfindRune":
    check rfind(ru"あaa", ru 'a') == 2
    check rfind(ru"あaa", ru 'b') == -1

  test "rfindRunes":
    check rfind(ru"あいういう", ru"いう") == 3
    check rfind(ru"あいういう", ru"いう", start = 1, last = 3) == 1

suite "unicodeext: substrWithLast":
  test "substrWithLast":
    check substr(ru"あいうえお", first = 1, last = 3) == ru"いうえ"

suite "unicodeext: substr":
  test "substr":
    check substr(ru"あいう", first = 1) == ru"いう"

suite "unicodeext: join":
  test "join 1":
    check @[ru"a", ru"b", ru"c"].join == ru"abc"

  test "join 2":
    check @[ru"a", ru"b", ru"c"].join(ru" ") == ru"a b c"

suite "unicodeext: '/' (Join paths)":
  test "'/'":
    proc checkJoinPath(head, tail: string) =
      check head.ru / tail.ru == (head / tail).ru

    checkJoinPath("usr", "")
    checkJoinPath("", "lib")
    checkJoinPath("", "/lib")
    checkJoinPath("usr", "/lib")
    checkJoinPath("usr/", "/lib/")
    check ru"usr" / ru"lib" / ru"../bin" == ru"usr/bin"

suite "unicodeext: replaceToNewLines":
  test "Basic":
    check replaceToNewLines("\\nabc\\n".toRunes) == "\nabc\n".toRunes

  test "Escape":
    check replaceToNewLines("\\\\nabc\\\\n".toRunes) == "\\nabc\\n".toRunes

  test "Without Newline":
    check replaceToNewLines(ru"abc") == ru"abc"

  test "Empty":
    check replaceToNewLines(ru"") == ru""

suite "unicodeext: toString":
  test "Basics":
    check @[""].toSeqRunes.toString == "\n"
    check @["abc"].toSeqRunes.toString == "abc\n"
    check @["abc", "def"].toSeqRunes.toString == "abc\ndef\n"
