import std/[unittest, deques]
import moepkg/[editorview, gapbuffer, unicodeext]

test "initEditorView 1":
  let
    lines = @[ru"abc", ru"def"]
    buffer = initGapBuffer[seq[Rune]](lines)
    view = initEditorView(buffer, 2, 3)
  check(view.lines[0] == ru"abc")
  check(view.lines[1] == ru"def")

test "initEditorView 2":
  let
    lines = @[ru"abcあd", ru"いうefgh", ru"ij"]
    buffer = initGapBuffer[seq[Rune]](lines)
    view = initEditorView(buffer, 8, 4)
  check(view.lines[0] == ru"abc")
  check(view.lines[1] == ru"あd")
  check(view.lines[2] == ru"いう")
  check(view.lines[3] == ru"efgh")
  check(view.lines[4] == ru"ij")
  check(view.originalLine[5] == -1)
  check(view.originalLine[6] == -1)
  check(view.originalLine[7] == -1)

test "seekCursor 1":
  let
    lines = @[ru"aaa", ru"bbbb", ru"ccccc", ru"ddd"]
    buffer = initGapBuffer[seq[RUne]](lines)
  var view = initEditorView(buffer, 2, 3)

  check(view.lines[0] == ru"aaa")
  check(view.lines[1] == ru"bbb")

  view.seekCursor(buffer, 2, 3)
  check(view.lines[0] == ru"ccc")
  check(view.lines[1] == ru"cc")

  view.seekCursor(buffer, 3, 1)
  check(view.lines[0] == ru"cc")
  check(view.lines[1] == ru"ddd")

test "seekCursor 2":
  let
    lines = @[ru"aaaaaaa", ru"bbbb", ru"ccc", ru"d"]
    buffer = initGapBuffer(lines)
  var view = initEditorView(buffer, 2, 3)

  check(view.lines[0] == ru"aaa")
  check(view.lines[1] == ru"aaa")

  view.seekCursor(buffer, 3, 0)

  check(view.lines[0] == ru"ccc")
  check(view.lines[1] == ru"d")

  view.seekCursor(buffer, 1, 3)

  check(view.lines[0] == ru"b")
  check(view.lines[1] == ru"ccc")

  view.seekCursor(buffer, 0, 6)

  check(view.lines[0] == ru"a")
  check(view.lines[1] == ru"bbb")
