import std/[unittest, sequtils]

include moepkg/highlight

const reservedWords = @[
  ReservedWord(word: "TODO", color: EditorColorPair.reservedWord),
  ReservedWord(word: "WIP", color: EditorColorPair.reservedWord),
  ReservedWord(word: "NOTE", color: EditorColorPair.reservedWord)
]

suite "parseReservedWord":
  test "no reserved word":
    check toSeq(parseReservedWord("abcdefh", reservedWords, EditorColorPair.defaultChar)) == @[
      ("abcdefh", EditorColorPair.defaultChar),
    ]
  test "1 TODO":
    check toSeq(parseReservedWord("# hello TODO world", reservedWords, EditorColorPair.defaultChar)) == @[
      ("# hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" world", EditorColorPair.defaultChar),
    ]
  test "2 TODO":
    check toSeq(parseReservedWord("# hello TODO world TODO", reservedWords, EditorColorPair.defaultChar)) == @[
      ("# hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" world ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
    ]
  test "edge TODO":
    check toSeq(parseReservedWord("TODO hello TODO", reservedWords, EditorColorPair.defaultChar)) == @[
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
    ]
  test "TODO and WIP and NOTE":
    check toSeq(parseReservedWord("hello TODO WIP NOTE world", reservedWords, EditorColorPair.defaultChar)) == @[
      ("hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" ", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.reservedWord),
      (" ", EditorColorPair.defaultChar),
      ("NOTE", EditorColorPair.reservedWord),
      (" world", EditorColorPair.defaultChar),
    ]
  test "no whitespace":
    check toSeq(parseReservedWord("TODOWIPNOTETODOWIPNOTE", reservedWords, EditorColorPair.defaultChar)) == @[
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("NOTE", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("NOTE", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
    ]
