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

import ../src/moepkg/color {.all.}

suite "color - Rgb type":
  test "isTermDefaultColor with terminal default":
    check TerminalDefaultRgb.isTermDefaultColor

  test "isTermDefaultColor with regular color":
    let color = Rgb(red: 255, green: 128, blue: 0)
    check not color.isTermDefaultColor

suite "color - hexToRgb":
  test "parse with # prefix":
    let result = hexToRgb("#ff0000")
    check result.isOk
    check result.get.red == 255
    check result.get.green == 0
    check result.get.blue == 0

  test "parse without # prefix":
    let result = hexToRgb("00ff00")
    check result.isOk
    check result.get.red == 0
    check result.get.green == 255
    check result.get.blue == 0

  test "parse blue":
    let result = hexToRgb("#0000ff")
    check result.isOk
    check result.get.red == 0
    check result.get.green == 0
    check result.get.blue == 255

  test "parse mixed color":
    let result = hexToRgb("#1a2b3c")
    check result.isOk
    check result.get.red == 0x1a
    check result.get.green == 0x2b
    check result.get.blue == 0x3c

  test "parse white":
    let result = hexToRgb("#ffffff")
    check result.isOk
    check result.get.red == 255
    check result.get.green == 255
    check result.get.blue == 255

  test "parse black":
    let result = hexToRgb("#000000")
    check result.isOk
    check result.get.red == 0
    check result.get.green == 0
    check result.get.blue == 0

  test "invalid length":
    let result = hexToRgb("#fff")
    check result.isErr

  test "invalid characters":
    let result = hexToRgb("#gggggg")
    check result.isErr

  test "empty string":
    let result = hexToRgb("")
    check result.isErr

  test "6-char string with # prefix is rejected without crashing":
    # "#" + 5 hex chars is 6 long; the prefixed branch must not slice past the end
    check hexToRgb("#abcde").isErr

  test "leading double # is rejected without crashing":
    check hexToRgb("##abcd").isErr

suite "color - parseThemeColor":
  test "parse termDefault":
    let result = parseThemeColor("termDefault")
    check result.isOk
    check result.get == TerminalDefaultRgb

  test "parse hex color with prefix":
    let result = parseThemeColor("#ff5500")
    check result.isOk
    check result.get.red == 255
    check result.get.green == 0x55
    check result.get.blue == 0

  test "parse hex color without prefix":
    let result = parseThemeColor("aabbcc")
    check result.isOk
    check result.get.red == 0xaa
    check result.get.green == 0xbb
    check result.get.blue == 0xcc

suite "color - toHex":
  test "convert red to hex":
    let color = Rgb(red: 255, green: 0, blue: 0)
    let result = color.toHex()
    check result.isSome
    check result.get == "#ff0000"

  test "convert green to hex":
    let color = Rgb(red: 0, green: 255, blue: 0)
    let result = color.toHex()
    check result.isSome
    check result.get == "#00ff00"

  test "convert blue to hex":
    let color = Rgb(red: 0, green: 0, blue: 255)
    let result = color.toHex()
    check result.isSome
    check result.get == "#0000ff"

  test "convert without prefix":
    let color = Rgb(red: 171, green: 205, blue: 239)
    let result = color.toHex(withPrefix = false)
    check result.isSome
    check result.get == "abcdef"

  test "terminal default returns none":
    let result = TerminalDefaultRgb.toHex()
    check result.isNone

suite "color - isHexColor":
  test "valid with prefix":
    check isHexColor("#ff0000")
    check isHexColor("#000000")
    check isHexColor("#ffffff")
    check isHexColor("#1a2b3c")

  test "valid without prefix":
    check isHexColor("ff0000", withPrefix = false)
    check isHexColor("abcdef", withPrefix = false)

  test "invalid format":
    check not isHexColor("#fff")
    check not isHexColor("fff")
    check not isHexColor("#gggggg")
    check not isHexColor("")
    check not isHexColor("ff0000", withPrefix = true)

suite "color - rgb helper":
  test "create from hex string":
    let c = color.rgb("#ff8800")
    check c.red == 255
    check c.green == 0x88
    check c.blue == 0

suite "color - inverseColor":
  test "inverse of black is white":
    let black = Rgb(red: 0, green: 0, blue: 0)
    let inv = inverseColor(black)
    check inv.red == 255
    check inv.green == 255
    check inv.blue == 255

  test "inverse of white is black":
    let white = Rgb(red: 255, green: 255, blue: 255)
    let inv = inverseColor(white)
    check inv.red == 0
    check inv.green == 0
    check inv.blue == 0

  test "inverse of red is cyan":
    let red = Rgb(red: 255, green: 0, blue: 0)
    let inv = inverseColor(red)
    check inv.red == 0
    check inv.green == 255
    check inv.blue == 255

  test "inverse of terminal default is terminal default":
    let inv = inverseColor(TerminalDefaultRgb)
    check inv == TerminalDefaultRgb

suite "color - rgbTo8Color":
  test "black":
    check rgbTo8Color(0, 0, 0) == 0'u8

  test "red":
    check rgbTo8Color(255, 0, 0) == 1'u8

  test "green":
    check rgbTo8Color(0, 255, 0) == 2'u8

  test "yellow":
    check rgbTo8Color(255, 255, 0) == 3'u8

  test "blue":
    check rgbTo8Color(0, 0, 255) == 4'u8

  test "magenta":
    check rgbTo8Color(255, 0, 255) == 5'u8

  test "cyan":
    check rgbTo8Color(0, 255, 255) == 6'u8

  test "white":
    check rgbTo8Color(255, 255, 255) == 7'u8

  test "threshold boundary - below":
    # Below threshold (128), should be black
    check rgbTo8Color(127, 127, 127) == 0'u8

  test "threshold boundary - at threshold":
    # At threshold (128), should be white
    check rgbTo8Color(128, 128, 128) == 7'u8

suite "color - rgbTo16Color":
  test "pure black":
    check rgbTo16Color(0, 0, 0) == 0'u8

  test "bright white":
    check rgbTo16Color(255, 255, 255) == 15'u8

  test "dark gray (grayscale)":
    check rgbTo16Color(100, 100, 100) == 8'u8

  test "light gray (grayscale)":
    check rgbTo16Color(170, 170, 170) == 7'u8

  test "bright red":
    check rgbTo16Color(255, 0, 0) == 9'u8

  test "bright green":
    check rgbTo16Color(0, 255, 0) == 10'u8

  test "bright blue":
    check rgbTo16Color(0, 0, 255) == 12'u8

  test "dark red":
    check rgbTo16Color(150, 0, 0) == 1'u8

  test "dark green":
    check rgbTo16Color(0, 150, 0) == 2'u8

  test "dark blue":
    check rgbTo16Color(0, 0, 150) == 4'u8

suite "color - rgbTo256Color":
  test "pure black":
    check rgbTo256Color(0, 0, 0) == 16'u8

  test "pure white":
    check rgbTo256Color(255, 255, 255) == 231'u8

  test "grayscale mid":
    # Gray values use 232-255 range
    let result = rgbTo256Color(128, 128, 128)
    check result >= 232'u8 and result <= 255'u8

  test "grayscale boundary near white does not overflow":
    # Regression: r=248 previously produced uint8(256) which either raised
    # RangeDefect or wrapped to index 0 (black).
    check rgbTo256Color(248, 248, 248) == 231'u8
    check rgbTo256Color(247, 247, 247) >= 232'u8
    check rgbTo256Color(247, 247, 247) <= 255'u8

  test "pure red":
    # Should map to red in 6x6x6 cube
    # ri = (255 * 6) div 256 = 5
    # 16 + 36*5 + 6*0 + 0 = 196
    check rgbTo256Color(255, 0, 0) == 196'u8

  test "pure green":
    # ri = 0, gi = 5, bi = 0
    # 16 + 36*0 + 6*5 + 0 = 46
    check rgbTo256Color(0, 255, 0) == 46'u8

  test "pure blue":
    # ri = 0, gi = 0, bi = 5
    # 16 + 36*0 + 6*0 + 5 = 21
    check rgbTo256Color(0, 0, 255) == 21'u8

suite "color - toColorValue":
  setup:
    let originalMode = globalColorMode

  teardown:
    globalColorMode = originalMode

  test "terminal default color":
    let cv = TerminalDefaultRgb.toColorValue
    check cv.kind == Default

  test "cmkNone mode returns default":
    globalColorMode = cmkNone
    let color = Rgb(red: 255, green: 0, blue: 0)
    let cv = color.toColorValue
    check cv.kind == Default

  test "cmk8color mode returns indexed":
    globalColorMode = cmk8color
    let color = Rgb(red: 255, green: 0, blue: 0)
    let cv = color.toColorValue
    check cv.kind == Indexed256
    check cv.indexed256 == 1'u8

  test "cmk16color mode returns indexed":
    globalColorMode = cmk16color
    let color = Rgb(red: 255, green: 0, blue: 0)
    let cv = color.toColorValue
    check cv.kind == Indexed256
    check cv.indexed256 == 9'u8

  test "cmk256color mode returns indexed":
    globalColorMode = cmk256color
    let color = Rgb(red: 255, green: 0, blue: 0)
    let cv = color.toColorValue
    check cv.kind == Indexed256
    check cv.indexed256 == 196'u8

  test "cmk24bit mode returns rgb":
    globalColorMode = cmk24bit
    let color = Rgb(red: 100, green: 150, blue: 200)
    let cv = color.toColorValue
    check cv.kind == ColorKind.Rgb
    check cv.rgb.r == 100
    check cv.rgb.g == 150
    check cv.rgb.b == 200

suite "color - toStyle":
  test "basic conversion":
    let colorPair = ColorPair(
      foreground: ThemeColor(rgb: Rgb(red: 255, green: 255, blue: 255)),
      background: ThemeColor(rgb: Rgb(red: 0, green: 0, blue: 0)),
    )
    let style = colorPair.toStyle
    check style.modifiers == {}

  test "conversion with modifiers":
    let colorPair = ColorPair(
      foreground: ThemeColor(rgb: Rgb(red: 255, green: 0, blue: 0)),
      background: ThemeColor(rgb: TerminalDefaultRgb),
    )
    let style = colorPair.toStyle({Bold, Underline})
    check Bold in style.modifiers
    check Underline in style.modifiers

suite "color - theme colors":
  test "setThemeColors and getThemeColor":
    var colors: ThemeColors
    colors[EditorColorPairIndex.default] = ColorPair(
      foreground: ThemeColor(rgb: Rgb(red: 200, green: 200, blue: 200)),
      background: ThemeColor(rgb: Rgb(red: 30, green: 30, blue: 30)),
    )
    setThemeColors(colors)

    let retrieved = getThemeColor(EditorColorPairIndex.default)
    check retrieved.foreground.rgb.red == 200
    check retrieved.background.rgb.red == 30

suite "color - colorModeRank":
  test "ranking order":
    check colorModeRank(cmkNone) == -1
    check colorModeRank(cmk8color) == 0
    check colorModeRank(cmk16color) == 1
    check colorModeRank(cmk256color) == 2
    check colorModeRank(cmk24bit) == 3

suite "color - applyColorModeFallback":
  test "cmkNone always returns cmkNone":
    check applyColorModeFallback(cmkNone) == cmkNone
