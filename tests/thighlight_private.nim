import unittest, sequtils

include moepkg/highlight

suite "parseReservedWord":
  test "no reserved word":
    check toSeq(parseReservedWord("abcdefh", EditorColorPair.defaultChar)) == @[
      ("abcdefh", EditorColorPair.defaultChar),
    ]
  test "1 TODO":
    check toSeq(parseReservedWord("# hello TODO world", EditorColorPair.defaultChar)) == @[
      ("# hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      (" world", EditorColorPair.defaultChar),
    ]
  test "2 TODO":
    check toSeq(parseReservedWord("# hello TODO world TODO", EditorColorPair.defaultChar)) == @[
      ("# hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      (" world ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      ("", EditorColorPair.defaultChar),
    ]
  test "edge TODO":
    check toSeq(parseReservedWord("TODO hello TODO", EditorColorPair.defaultChar)) == @[
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      (" hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      ("", EditorColorPair.defaultChar),
    ]
  test "TODO and WIP":
    check toSeq(parseReservedWord("hello TODO WIP world", EditorColorPair.defaultChar)) == @[
      ("hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      (" ", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.todo),
      (" world", EditorColorPair.defaultChar),
    ]
  test "no whitespace":
    check toSeq(parseReservedWord("TODOWIPTODOWIP", EditorColorPair.defaultChar)) == @[
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      ("", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.todo),
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.todo),
      ("", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.todo),
      ("", EditorColorPair.defaultChar),
    ]
