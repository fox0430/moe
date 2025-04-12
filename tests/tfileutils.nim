#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[unittest, oids, os, encodings]

import pkg/results

import moepkg/unicodeext

import moepkg/fileutils {.all.}

const Text =
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

suite "fileutils: readFile":
  var filename = ""

  teardown:
    removeFile(filename)
    filename = ""

  test "Basic":
    const Buf = "abc"
    filename = $genOid()
    writeFile(filename, Buf & '\n')

    check readFile(filename.toRunes) == @["abc"].toSeqRunes

  test "Basic 2":
    const Buf = "abc\nあいうdef"
    filename = $genOid()
    writeFile(filename, Buf & '\n')

    check readFile(filename.toRunes) == @["abc", "あいうdef"].toSeqRunes

  test "Basic 3":
    filename = $genOid()
    writeFile(filename, Text & '\n')

    check readFile(filename.toRunes) == Text.toSeqRunes

  test "Large file mode":
    const Buf = "abc\nあいうdef"
    filename = $genOid()
    writeFile(filename, Buf & '\n')

    check readFile(filename.toRunes, 1) == @["abc", "あいうdef"].toSeqRunes

suite "fileutils: detectFileEncoding":
  var filename = ""

  teardown:
    removeFile(filename)
    filename = ""

  template writeTestFile(e: CharacterEncoding) =
    let
      ec = open($e, "UTF-8")
      converted = convert(ec, Text & '\n')
    assert converted.detectCharacterEncoding == e

    filename = $genOid()
    writeFile(filename, converted)

  test "UTF-8":
    writeTestFile(CharacterEncoding.utf8)

    check detectFileEncoding(filename).get == CharacterEncoding.utf8

  test "UTF-16BE":
    writeTestFile(CharacterEncoding.utf16Be)

    check detectFileEncoding(filename).get == CharacterEncoding.utf16Be

  test "UTF-16LE":
    writeTestFile(CharacterEncoding.utf16Le)

    check detectFileEncoding(filename).get == CharacterEncoding.utf16Le

  test "UTF-32BE":
    writeTestFile(CharacterEncoding.utf32Be)

    check detectFileEncoding(filename).get == CharacterEncoding.utf32Be

  test "UTF-32LE":
    writeTestFile(CharacterEncoding.utf32Le)

    check detectFileEncoding(filename).get == CharacterEncoding.utf32Le

suite "fileutils: openFile":
  var filename = ""

  teardown:
    removeFile(filename)
    filename = ""

  template writeTestFile(e: CharacterEncoding, text: string) =
    let
      ec = open($e, "UTF-8")
      converted = convert(ec, text & '\n')
    assert converted.detectCharacterEncoding == e

    filename = $genOid()
    writeFile(filename, converted)

  test "UTF-8":
    writeTestFile(CharacterEncoding.utf8, Text)

    check openFile(filename).get ==
      TextAndEncoding(text: Text.toSeqRunes, encoding: CharacterEncoding.utf8)

  test "UTF-16BE":
    writeTestFile(CharacterEncoding.utf16Be, Text)

    check openFile(filename).get ==
      TextAndEncoding(text: Text.toSeqRunes, encoding: CharacterEncoding.utf16Be)

  test "UTF-16LE":
    writeTestFile(CharacterEncoding.utf16Le, Text)

    check openFile(filename).get ==
      TextAndEncoding(text: Text.toSeqRunes, encoding: CharacterEncoding.utf16Le)

  test "UTF-32BE":
    writeTestFile(CharacterEncoding.utf32Be, Text)

    check openFile(filename).get ==
      TextAndEncoding(text: Text.toSeqRunes, encoding: CharacterEncoding.utf32Be)

  test "UTF-32LE":
    writeTestFile(CharacterEncoding.utf32Le, Text)

    check openFile(filename).get ==
      TextAndEncoding(text: Text.toSeqRunes, encoding: CharacterEncoding.utf32Le)
