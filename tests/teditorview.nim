import unittest, deques
import moepkg/editorview, moepkg/gapbuffer, moepkg/unicodeext

test "initEditorView: 1":
  let
    line0 = ru"abc"
    line1 = ru"def"
  var buffer = initGapBuffer[seq[Rune]](@[line0, line1])
  let view = initEditorView(buffer, 2, 3)
  check(view.lines[0] == line0)
  check(view.lines[1] == line1)

test "seekCursor: 1":
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

test "seekCursor: 2":
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
