import std/[unittest, unicode]
import ../src/moepkg/[unicode_utils, render_utils, buffer]

suite "Multibyte Character - Display Width":
  test "ASCII characters have width 1":
    check runeWidth("a".runeAt(0)) == 1
    check runeWidth("A".runeAt(0)) == 1
    check runeWidth("1".runeAt(0)) == 1
    check runeWidth(" ".runeAt(0)) == 1

  test "CJK characters have width 2":
    check runeWidth("漢".runeAt(0)) == 2
    check runeWidth("字".runeAt(0)) == 2
    check runeWidth("日".runeAt(0)) == 2
    check runeWidth("本".runeAt(0)) == 2
    check runeWidth("한".runeAt(0)) == 2
    check runeWidth("글".runeAt(0)) == 2
    check runeWidth("中".runeAt(0)) == 2
    check runeWidth("文".runeAt(0)) == 2

  test "Emoji have width 2":
    check runeWidth("👋".runeAt(0)) == 2
    check runeWidth("🌍".runeAt(0)) == 2
    check runeWidth("😀".runeAt(0)) == 2

  test "displayWidthUpToWithTabs calculates correct width for ASCII":
    let text = "hello"
    check displayWidthUpToWithTabs(text, 0, 4) == 0
    check displayWidthUpToWithTabs(text, 1, 4) == 1
    check displayWidthUpToWithTabs(text, 5, 4) == 5

  test "displayWidthUpToWithTabs calculates correct width for CJK":
    let text = "漢字"
    check displayWidthUpToWithTabs(text, 0, 4) == 0
    check displayWidthUpToWithTabs(text, 1, 4) == 2 # '漢' has width 2
    check displayWidthUpToWithTabs(text, 2, 4) == 4 # '漢字' has width 4

  test "displayWidthUpToWithTabs calculates correct width for mixed text":
    let text = "ab漢cd"
    check displayWidthUpToWithTabs(text, 0, 4) == 0 # Before 'a'
    check displayWidthUpToWithTabs(text, 1, 4) == 1 # After 'a'
    check displayWidthUpToWithTabs(text, 2, 4) == 2 # After 'ab'
    check displayWidthUpToWithTabs(text, 3, 4) == 4 # After 'ab漢' (a=1, b=1, 漢=2)
    check displayWidthUpToWithTabs(text, 4, 4) == 5 # After 'ab漢c'
    check displayWidthUpToWithTabs(text, 5, 4) == 6 # After 'ab漢cd'

  test "displayWidthUpToWithTabs handles tab character":
    let text = "ab\tcd"
    # 'a'=1, 'b'=1, tab expands to next tab stop
    # At position 2, displayWidth=2, next tabStop is 4, so tab adds 2
    check displayWidthUpToWithTabs(text, 2, 4) == 2 # Before tab
    check displayWidthUpToWithTabs(text, 3, 4) == 4
      # After tab (2 + 2 spaces to reach tabStop 4)

  test "displayWidthUpToWithTabs with negative charPos returns 0":
    let text = "hello"
    check displayWidthUpToWithTabs(text, -1, 4) == 0
    check displayWidthUpToWithTabs(text, -10, 4) == 0

  test "displayWidthUpToWithTabs with invalid tabStop uses default":
    let text = "hello"
    check displayWidthUpToWithTabs(text, 3, 0) == 3 # Uses tabStop=1
    check displayWidthUpToWithTabs(text, 3, -5) == 3 # Uses tabStop=1

suite "Multibyte Character - Display Width Substring":
  test "displayWidthSubstr for ASCII text":
    let text = "hello world"
    # Within maxWidth=5, we can fit "hello" (5 chars, 5 width)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 5)
    check charCount == 5
    check actualWidth == 5

  test "displayWidthSubstr for CJK text":
    let text = "漢字日本"
    # maxWidth=5 can fit "漢字" (2 chars, 4 width) but not "漢字日" (3 chars, 6 width)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 5)
    check charCount == 2
    check actualWidth == 4

  test "displayWidthSubstr for mixed text":
    let text = "ab漢cd"
    # maxWidth=4 can fit "ab漢" (3 chars: a=1, b=1, 漢=2)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 4)
    check charCount == 3
    check actualWidth == 4

  test "displayWidthSubstr with offset":
    let text = "hello漢字world"
    # Starting from char 5 (at '漢'), maxWidth=10
    # "漢字world" = 2+2+5 = 9 width, 7 chars
    let (charCount, actualWidth) = displayWidthSubstr(text, 5, 10)
    check charCount == 7
    check actualWidth == 9

  test "displayWidthSubstr stops before exceeding maxWidth":
    let text = "a漢b"
    # maxWidth=2 can only fit 'a' (1 width), cannot fit '漢' (would be 3 total)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 2)
    check charCount == 1
    check actualWidth == 1

  test "displayWidthSubstr with exact fit":
    let text = "漢字"
    # maxWidth=4 exactly fits both characters
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 4)
    check charCount == 2
    check actualWidth == 4

suite "Multibyte Character - Character Length":
  test "charLen returns character count for ASCII":
    check "hello".charLen == 5
    check "".charLen == 0

  test "charLen returns character count for CJK":
    check "漢字".charLen == 2
    check "日本語".charLen == 3

  test "charLen returns character count for mixed text":
    check "ab漢cd".charLen == 5
    check "CJK characters: 漢字 日本語 中文 한글".charLen == 28

  test "charLen vs len (byte length)":
    let text = "漢字"
    check text.charLen == 2 # 2 characters
    check text.len == 6 # 6 bytes (each CJK char is 3 bytes in UTF-8)

suite "Multibyte Character - Character Position Conversion":
  test "charToBytePos for ASCII text":
    let text = "hello"
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 1) == 1
    check charToBytePos(text, 5) == 5

  test "charToBytePos for CJK text":
    let text = "漢字" # Each char is 3 bytes
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 1) == 3
    check charToBytePos(text, 2) == 6

  test "charToBytePos for mixed text":
    let text = "ab漢cd"
    # 'a'=1 byte, 'b'=1 byte, '漢'=3 bytes, 'c'=1 byte, 'd'=1 byte
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 2) == 2 # Before '漢'
    check charToBytePos(text, 3) == 5 # After '漢'
    check charToBytePos(text, 5) == 7 # End

  test "Extract substring using character positions":
    let text = "ab漢cd"
    # Extract using charToBytePos
    let start0 = charToBytePos(text, 0)
    let end2 = charToBytePos(text, 2)
    check text[start0 ..< end2] == "ab"

    let start2 = charToBytePos(text, 2)
    let end3 = charToBytePos(text, 3)
    check text[start2 ..< end3] == "漢"

    let start3 = charToBytePos(text, 3)
    let end5 = charToBytePos(text, 5)
    check text[start3 ..< end5] == "cd"

suite "Multibyte Character - Rendering Simulation":
  test "Rendering advance for ASCII":
    var displayX = 0
    let text = "hello"
    for rune in text.runes:
      displayX += runeWidth(rune)
    check displayX == 5

  test "Rendering advance for CJK":
    var displayX = 0
    let text = "漢字日本"
    for rune in text.runes:
      displayX += runeWidth(rune)
    check displayX == 8 # Each CJK char has width 2

  test "Rendering advance for mixed text":
    var displayX = 0
    let text = "ab漢cd"
    for rune in text.runes:
      displayX += runeWidth(rune)
    check displayX == 6 # a(1) + b(1) + 漢(2) + c(1) + d(1)

  test "Rendering advance for complex text":
    var displayX = 0
    let text = "CJK characters: 漢字 日本語 中文 한글"
    for rune in text.runes:
      displayX += runeWidth(rune)
    # 16 ASCII chars + 9 CJK chars (width 2 each) = 16 + 18 = 34... wait
    # Let me count: "CJK characters: " = 16 chars (width 16)
    # "漢字 日本語 中文 한글" = 漢(2) + 字(2) + space(1) + 日(2) + 本(2) + 語(2) + space(1) + 中(2) + 文(2) + space(1) + 한(2) + 글(2) = 21
    # Total: 16 + 21 = 37
    check displayX == 37
