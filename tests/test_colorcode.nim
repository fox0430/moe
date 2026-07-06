#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import std/[unittest, options]

import pkg/celina

import ../src/moepkg/[colorcode, color]

suite "colorcode: scanLineForColorCodes":
  test "#FF0000 - red, contrast foreground is white":
    let matches = scanLineForColorCodes("color: #FF0000;")
    check matches.len == 1
    check matches[0].startCol == 7
    check matches[0].endCol == 13
    # Background should be red, foreground white
    let expectedBg = Rgb(red: 255, green: 0, blue: 0)
    let expectedFg = contrastForeground(expectedBg)
    check expectedFg == Rgb(red: 255, green: 255, blue: 255)

  test "#000 - black (3-digit shorthand)":
    let matches = scanLineForColorCodes("#000")
    check matches.len == 1
    check matches[0].startCol == 0
    check matches[0].endCol == 3

  test "#FFF - white, contrast foreground is black":
    let matches = scanLineForColorCodes("#FFF")
    check matches.len == 1
    let expectedFg = contrastForeground(Rgb(red: 255, green: 255, blue: 255))
    check expectedFg == Rgb(red: 0, green: 0, blue: 0)

  test "#ZZZZZZ - no match":
    let matches = scanLineForColorCodes("#ZZZZZZ")
    check matches.len == 0

  test "#FF0000FF - only #FF0000 matches (word boundary)":
    let matches = scanLineForColorCodes("#FF0000FF")
    # The 'FF' after #FF0000 is a hex char, so word boundary check fails
    check matches.len == 0

  test "Multiple color codes in one line":
    let matches = scanLineForColorCodes("bg: #FF0000; fg: #00FF00;")
    check matches.len == 2
    check matches[0].startCol == 4
    check matches[0].endCol == 10
    check matches[1].startCol == 17
    check matches[1].endCol == 23

  test "3-digit color code #F00":
    let matches = scanLineForColorCodes("#F00")
    check matches.len == 1
    check matches[0].startCol == 0
    check matches[0].endCol == 3

  test "Mixed 3 and 6 digit codes":
    let matches = scanLineForColorCodes("#F00 #00FF00")
    check matches.len == 2
    check matches[0].endCol == 3
    check matches[1].endCol == 11

  test "No color codes in plain text":
    let matches = scanLineForColorCodes("hello world")
    check matches.len == 0

  test "Hash without valid hex":
    let matches = scanLineForColorCodes("# comment")
    check matches.len == 0

  test "Color code at end of line":
    let matches = scanLineForColorCodes("color: #ABCDEF")
    check matches.len == 1
    check matches[0].startCol == 7
    check matches[0].endCol == 13

  test "Empty string":
    let matches = scanLineForColorCodes("")
    check matches.len == 0

  test "Only a hash character":
    let matches = scanLineForColorCodes("#")
    check matches.len == 0

  test "2-digit hex after hash - no match":
    let matches = scanLineForColorCodes("#AB")
    check matches.len == 0

  test "4-digit hex after hash - no match":
    let matches = scanLineForColorCodes("#ABCD")
    check matches.len == 0

  test "5-digit hex after hash - no match":
    let matches = scanLineForColorCodes("#ABCDE")
    check matches.len == 0

  test "Lowercase hex digits":
    let matches = scanLineForColorCodes("#ff00aa")
    check matches.len == 1
    check matches[0].startCol == 0
    check matches[0].endCol == 6

  test "Mixed case hex digits":
    let matches = scanLineForColorCodes("#fF00Aa")
    check matches.len == 1
    check matches[0].startCol == 0
    check matches[0].endCol == 6

  test "3-digit lowercase":
    let matches = scanLineForColorCodes("#abc")
    check matches.len == 1
    check matches[0].startCol == 0
    check matches[0].endCol == 3

  test "Hex char before hash blocks match (word boundary)":
    # 'A' is a hex char immediately before '#'
    let matches = scanLineForColorCodes("A#FF0000")
    check matches.len == 0

  test "Non-hex char before hash allows match":
    # 'G' is not a hex char
    let matches = scanLineForColorCodes("G#FF0000")
    check matches.len == 1
    check matches[0].startCol == 1
    check matches[0].endCol == 7

  test "3-digit with hex char after - no match (word boundary)":
    let matches = scanLineForColorCodes("#ABCF")
    # 'F' after #ABC is a hex char, so word boundary fails for 3-digit
    # And #ABCF is only 4 digits, not 6, so no 6-digit match either
    check matches.len == 0

  test "3-digit with non-hex char after - match":
    let matches = scanLineForColorCodes("#ABC;")
    check matches.len == 1
    check matches[0].startCol == 0
    check matches[0].endCol == 3

  test "Multiple hashes without valid codes":
    let matches = scanLineForColorCodes("## heading # comment")
    check matches.len == 0

  test "Color code surrounded by whitespace":
    let matches = scanLineForColorCodes("  #AABBCC  ")
    check matches.len == 1
    check matches[0].startCol == 2
    check matches[0].endCol == 8

  test "Consecutive color codes separated by space":
    let matches = scanLineForColorCodes("#FF0000 #00FF00 #0000FF")
    check matches.len == 3
    check matches[0].startCol == 0
    check matches[1].startCol == 8
    check matches[2].startCol == 16

  test "Color code in CSS-like context":
    let matches = scanLineForColorCodes("background-color: #1a2b3c; color: #fff;")
    check matches.len == 2
    check matches[0].startCol == 18
    check matches[0].endCol == 24
    check matches[1].startCol == 34
    check matches[1].endCol == 37

  test "Color code in TOML-like context":
    let matches = scanLineForColorCodes("""foreground = "#FF8800"""")
    check matches.len == 1
    check matches[0].startCol == 14
    check matches[0].endCol == 20

suite "colorcode: scanLineForColorCodes - style verification":
  test "#FF0000 style has red background and white foreground":
    let matches = scanLineForColorCodes("#FF0000")
    check matches.len == 1
    let s = matches[0].style
    check s.bg == Rgb(red: 255, green: 0, blue: 0).toColorValue
    check s.fg == Rgb(red: 255, green: 255, blue: 255).toColorValue

  test "#FFFFFF style has white background and black foreground":
    let matches = scanLineForColorCodes("#FFFFFF")
    check matches.len == 1
    let s = matches[0].style
    check s.bg == Rgb(red: 255, green: 255, blue: 255).toColorValue
    check s.fg == Rgb(red: 0, green: 0, blue: 0).toColorValue

  test "#000000 style has black background and white foreground":
    let matches = scanLineForColorCodes("#000000")
    check matches.len == 1
    let s = matches[0].style
    check s.bg == Rgb(red: 0, green: 0, blue: 0).toColorValue
    check s.fg == Rgb(red: 255, green: 255, blue: 255).toColorValue

  test "#F00 3-digit expands correctly (same as #FF0000)":
    let matches3 = scanLineForColorCodes("#F00")
    let matches6 = scanLineForColorCodes("#FF0000")
    check matches3.len == 1
    check matches6.len == 1
    check matches3[0].style.bg == matches6[0].style.bg
    check matches3[0].style.fg == matches6[0].style.fg

  test "#ABC 3-digit expands to #AABBCC":
    let matches3 = scanLineForColorCodes("#ABC")
    let matches6 = scanLineForColorCodes("#AABBCC")
    check matches3.len == 1
    check matches6.len == 1
    check matches3[0].style.bg == matches6[0].style.bg

  test "Style has no modifiers":
    let matches = scanLineForColorCodes("#FF0000")
    check matches[0].style.modifiers == {}

suite "colorcode: scanLineForColorCodes - multibyte":
  test "Color code after multibyte characters":
    let matches = scanLineForColorCodes("色: #FF0000")
    check matches.len == 1
    # '色' is rune 0, ':' is rune 1, ' ' is rune 2, '#' is rune 3
    check matches[0].startCol == 3
    check matches[0].endCol == 9

  test "3-digit color code after multibyte characters":
    let matches = scanLineForColorCodes("背景色=#F00")
    check matches.len == 1
    # '背'=0, '景'=1, '色'=2, '='=3, '#'=4
    check matches[0].startCol == 4
    check matches[0].endCol == 7

  test "Multiple color codes with multibyte separators":
    let matches = scanLineForColorCodes("#FF0000　#00FF00")
    # '　' is fullwidth space (1 rune, 3 bytes)
    check matches.len == 2
    check matches[0].startCol == 0
    check matches[0].endCol == 6
    check matches[1].startCol == 8
    check matches[1].endCol == 14

  test "Color code between emoji":
    let matches = scanLineForColorCodes("🎨#FF0000🖌")
    check matches.len == 1
    check matches[0].startCol == 1
    check matches[0].endCol == 7

  test "Only multibyte characters, no color codes":
    let matches = scanLineForColorCodes("こんにちは世界")
    check matches.len == 0

suite "colorcode: getColorCodeStyle":
  test "Position inside a color code returns style":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "color: #FF0000;")
    check cache.getColorCodeStyle(0, 7).isSome # '#'
    check cache.getColorCodeStyle(0, 10).isSome # middle
    check cache.getColorCodeStyle(0, 13).isSome # last hex digit

  test "Position outside color code returns none":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "color: #FF0000;")
    check cache.getColorCodeStyle(0, 0).isNone
    check cache.getColorCodeStyle(0, 6).isNone
    check cache.getColorCodeStyle(0, 14).isNone

  test "Out of bounds line returns none":
    var cache = initColorCodeCache(1)
    check cache.getColorCodeStyle(5, 0).isNone
    check cache.getColorCodeStyle(-1, 0).isNone

  test "Multiple matches - each returns correct style":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "#FF0000 #0000FF")
    # First match (red)
    let style1 = cache.getColorCodeStyle(0, 0)
    check style1.isSome
    check style1.get.bg == Rgb(red: 255, green: 0, blue: 0).toColorValue
    # Gap between matches
    check cache.getColorCodeStyle(0, 7).isNone
    # Second match (blue)
    let style2 = cache.getColorCodeStyle(0, 8)
    check style2.isSome
    check style2.get.bg == Rgb(red: 0, green: 0, blue: 255).toColorValue

  test "3-digit code in cache returns correct style":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "#F00")
    let style = cache.getColorCodeStyle(0, 0)
    check style.isSome
    check style.get.bg == Rgb(red: 255, green: 0, blue: 0).toColorValue

  test "Empty line in cache":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "no colors here")
    check cache.getColorCodeStyle(0, 0).isNone
    check cache.getColorCodeStyle(0, 5).isNone

  test "Multi-line cache - different lines":
    var cache = initColorCodeCache(3)
    cache.updateLine(0, "#FF0000")
    cache.updateLine(1, "plain text")
    cache.updateLine(2, "#00FF00")
    check cache.getColorCodeStyle(0, 0).isSome
    check cache.getColorCodeStyle(1, 0).isNone
    check cache.getColorCodeStyle(2, 0).isSome

suite "colorcode: cache update":
  test "updateLine re-scans when content changes":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "#FF0000")
    check cache.lines[0].matches.len == 1

    cache.updateLine(0, "#00FF00")
    check cache.lines[0].matches.len == 1

  test "updateLine changes style when color changes":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "#FF0000")
    let style1 = cache.lines[0].matches[0].style
    cache.updateLine(0, "#0000FF")
    let style2 = cache.lines[0].matches[0].style
    check style1.bg != style2.bg

  test "Cache unchanged when same content":
    var cache = initColorCodeCache(1)
    let line = "#FF0000"
    cache.updateLine(0, line)
    let hash1 = cache.lines[0].lineHash
    cache.updateLine(0, line)
    let hash2 = cache.lines[0].lineHash
    check hash1 == hash2

  test "resize adjusts line count":
    var cache = initColorCodeCache(3)
    check cache.lines.len == 3
    cache.resize(5)
    check cache.lines.len == 5
    cache.resize(2)
    check cache.lines.len == 2

  test "updateLine with out-of-bounds index does not crash":
    var cache = initColorCodeCache(2)
    cache.updateLine(-1, "#FF0000")
    cache.updateLine(5, "#FF0000")
    check cache.lines.len == 2

  test "updateLine from no-color to color line":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "plain text")
    check cache.lines[0].matches.len == 0
    cache.updateLine(0, "color: #FF0000;")
    check cache.lines[0].matches.len == 1

  test "updateLine from color to no-color line":
    var cache = initColorCodeCache(1)
    cache.updateLine(0, "#FF0000")
    check cache.lines[0].matches.len == 1
    cache.updateLine(0, "plain text")
    check cache.lines[0].matches.len == 0

  test "initColorCodeCache with zero lines":
    var cache = initColorCodeCache(0)
    check cache.lines.len == 0

  test "updateAll rebuilds entire cache":
    var cache = initColorCodeCache(0)
    let lines = @["#FF0000", "plain", "#00FF00"]
    cache.updateAll(
      proc(i: int): string =
        lines[i],
      lines.len,
    )
    check cache.lines.len == 3
    check cache.lines[0].matches.len == 1
    check cache.lines[1].matches.len == 0
    check cache.lines[2].matches.len == 1

  test "updateAll with zero lines":
    var cache = initColorCodeCache(3)
    cache.updateAll(
      proc(i: int): string =
        "",
      0,
    )
    check cache.lines.len == 0

  test "resize preserves existing cached data":
    var cache = initColorCodeCache(2)
    cache.updateLine(0, "#FF0000")
    cache.updateLine(1, "#00FF00")
    cache.resize(3)
    check cache.lines[0].matches.len == 1
    check cache.lines[1].matches.len == 1
    check cache.lines[2].matches.len == 0

suite "colorcode: contrastForeground":
  test "Dark background gets white foreground":
    check contrastForeground(Rgb(red: 0, green: 0, blue: 0)) ==
      Rgb(red: 255, green: 255, blue: 255)

  test "Light background gets black foreground":
    check contrastForeground(Rgb(red: 255, green: 255, blue: 255)) ==
      Rgb(red: 0, green: 0, blue: 0)

  test "Mid-tone color":
    # #808080 luminance = (128*299 + 128*587 + 128*114)/1000 = 128
    # 128 <= 128, so white foreground
    check contrastForeground(Rgb(red: 128, green: 128, blue: 128)) ==
      Rgb(red: 255, green: 255, blue: 255)

  test "Pure red - dark enough for white foreground":
    # luminance = (255*299 + 0 + 0)/1000 = 76
    check contrastForeground(Rgb(red: 255, green: 0, blue: 0)) ==
      Rgb(red: 255, green: 255, blue: 255)

  test "Pure green - bright enough for black foreground":
    # luminance = (0 + 255*587 + 0)/1000 = 149
    check contrastForeground(Rgb(red: 0, green: 255, blue: 0)) ==
      Rgb(red: 0, green: 0, blue: 0)

  test "Pure blue - dark, gets white foreground":
    # luminance = (0 + 0 + 255*114)/1000 = 29
    check contrastForeground(Rgb(red: 0, green: 0, blue: 255)) ==
      Rgb(red: 255, green: 255, blue: 255)

  test "Yellow (#FFFF00) - bright, gets black foreground":
    # luminance = (255*299 + 255*587 + 0)/1000 = 225
    check contrastForeground(Rgb(red: 255, green: 255, blue: 0)) ==
      Rgb(red: 0, green: 0, blue: 0)
