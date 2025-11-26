import unittest
import ../src/moepkg/gapbuffer

suite "String conversion and iterators":
  test "String conversion: empty buffer":
    let gb = newGapBuffer()
    check $gb == ""

  test "String conversion: single line":
    let gb = newGapBuffer("Hello")
    check $gb == "Hello"

  test "String conversion: multiple lines":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    check $gb == "Line1\nLine2\nLine3"

  test "String conversion: empty lines":
    let gb = newGapBuffer("\n\n")
    check $gb == "\n\n"

  test "Substring: basic extraction":
    let gb = newGapBuffer("ABCDEFGH")
    check gb.substring(0, 3) == "ABC"
    check gb.substring(3, 3) == "DEF"
    check gb.substring(5, 3) == "FGH"

  test "Substring: cross-line extraction":
    let gb = newGapBuffer("AB\nCD\nEF")
    # Positions: A(0) B(1) \n(2) C(3) D(4) \n(5) E(6) F(7)
    check gb.substring(1, 4) == "B\nCD"
    check gb.substring(0, 8) == "AB\nCD\nEF"

  test "Substring: boundary cases":
    let gb = newGapBuffer("Test")
    check gb.substring(0, 0) == ""
    check gb.substring(0, 100) == "Test"
    check gb.substring(100, 5) == ""
    check gb.substring(2, -5) == ""

  test "Chars iterator: empty buffer":
    let gb = newGapBuffer()
    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars.len == 0

  test "Chars iterator: single line":
    let gb = newGapBuffer("ABC")
    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars == @['A', 'B', 'C']

  test "Chars iterator: multiple lines":
    let gb = newGapBuffer("AB\nCD")
    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars == @['A', 'B', '\n', 'C', 'D']

  test "Chars iterator: reconstruction":
    let text = "Hello\nWorld\n!"
    let gb = newGapBuffer(text)
    var reconstructed = ""
    for ch in gb.chars():
      reconstructed.add(ch)
    check reconstructed == text

  test "Lines iterator: empty buffer":
    let gb = newGapBuffer()
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @[""]

  test "Lines iterator: single line":
    let gb = newGapBuffer("Test")
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["Test"]

  test "Lines iterator: multiple lines":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["Line1", "Line2", "Line3"]

  test "Lines iterator: empty lines":
    # POSIX semantics: "\n\n" = 2 empty lines (each \n terminates a line)
    let gb = newGapBuffer("\n\n")
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["", ""]

  test "charAt: character access":
    let gb = newGapBuffer("ABCDE")
    check gb.charAt(0) == 'A'
    check gb.charAt(2) == 'C'
    check gb.charAt(4) == 'E'

  test "Bracket operator: slice access":
    let gb = newGapBuffer("ABCDEFGH")
    check gb[0 .. 2] == "ABC"
    check gb[3 .. 5] == "DEF"
    check gb[6 .. 7] == "GH"

  test "Bracket operator: slice with newlines":
    let gb = newGapBuffer("AB\nCD")
    # Positions: A(0) B(1) \n(2) C(3) D(4)
    check gb[0 .. 1] == "AB"
    check gb[1 .. 3] == "B\nC"
    check gb[2 .. 4] == "\nCD"

  test "Bracket operator: edge cases":
    let gb = newGapBuffer("Test")
    check gb[0 .. 0] == "T"
    check gb[3 .. 3] == "t"
    check gb[5 .. 10] == "" # Start beyond end

  test "String conversion after modifications":
    let gb = newGapBuffer("Initial")
    gb.insert(0, "Pre")
    check $gb == "PreInitial"

    gb.insert(gb.charLen, "Post")
    check $gb == "PreInitialPost"

    gb.delete(3, 7)
    check $gb == "PrePost"

  test "Iterator consistency after modifications":
    let gb = newGapBuffer("AB\nCD")
    gb.insert(2, "X") # "ABX\nCD"

    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars == @['A', 'B', 'X', '\n', 'C', 'D']

    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["ABX", "CD"]

  test "Substring consistency with charAt":
    let gb = newGapBuffer("ABCDEFGH")

    for start in 0 .. 7:
      for length in 1 .. 3:
        let sub = gb.substring(start, length)
        for i in 0 ..< sub.len:
          if start + i < gb.charLen:
            check sub[i] == gb.charAt(start + i)

  test "String conversion with Unicode":
    let gb = newGapBuffer("Hello 世界 🌍")
    let result = $gb
    check result == "Hello 世界 🌍"

  test "Chars iterator with Unicode":
    let gb = newGapBuffer("日本")
    var result = ""
    for ch in gb.chars():
      result.add(ch)
    check result == "日本"
