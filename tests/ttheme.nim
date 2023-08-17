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

import std/unittest
import pkg/results
import moepkg/[ui, rgb, color]

import moepkg/theme {.all.}

const DarkTheme = ColorTheme.dark

template darkDefaultFg: var Color =
  ColorThemeTable[DarkTheme][EditorColorPairIndex.default].foreground

template darkDefaultBg: var Color =
  ColorThemeTable[DarkTheme][EditorColorPairIndex.default].background

suite "color: Get Color from ColorThemeTable":
  test "foregroundRgb":
    darkDefaultFg.rgb = "#111111".hexToRgb.get

    assert darkDefaultFg == Color(
      index: EditorColorIndex.foreground,
      rgb: "#111111".hexToRgb.get)

  test "backgroundRgb":
    darkDefaultBg.rgb = "#111111".hexToRgb.get

    assert darkDefaultBg == Color(
      index: EditorColorIndex.background,
      rgb: "#111111".hexToRgb.get)

  test "rgbPairFromEditorColorPair":
    darkDefaultFg.rgb = "#222222".hexToRgb.get
    darkDefaultBg.rgb = "#222222".hexToRgb.get

    assert DarkTheme.rgbPairFromEditorColorPair(EditorColorPairIndex.default) ==
      RgbPair(
        foreground: Rgb(red: 34, green: 34, blue: 34),
        background: Rgb(red: 34, green: 34, blue: 34))

suite "color: Set index to ColorThemeTable":
  test "setForegroundIndex 1":
    for i in EditorColorIndex:
      DarkTheme.setForegroundIndex(EditorColorPairIndex.default, i)

    for i in EditorColorIndex:
      DarkTheme.setForegroundIndex(EditorColorPairIndex.default, i.int)

  test "setForegroundIndex 2":
    let invalidValue = EditorColorIndex.high.int + 1
    var isErr = false

    try:
      DarkTheme.setForegroundIndex(EditorColorPairIndex.default, invalidValue)
    except RangeDefect:
      isErr = true

    assert isErr

  test "setBackgroundIndex 1":
    for i in EditorColorIndex:
      DarkTheme.setBackgroundIndex(EditorColorPairIndex.default, i)

    for i in EditorColorIndex:
      DarkTheme.setBackgroundIndex(EditorColorPairIndex.default, i.int)

  test "setBackgroundIndex 2":
    let invalidValue = EditorColorIndex.high.int + 1
    var isErr = false

    try:
      DarkTheme.setBackgroundIndex(EditorColorPairIndex.default, invalidValue)
    except RangeDefect:
      isErr = true

    assert isErr

suite "color: Set Rgb to ColorThemeTable":
  test "setForegroundRgb":
    DarkTheme.setForegroundRgb(
      EditorColorPairIndex.default,
      "#333333".hexToRgb.get)

    assert darkDefaultFg.rgb == "#333333".hexToRgb.get

  test "setBackgroundRgb":
    DarkTheme.setBackgroundRgb(
      EditorColorPairIndex.default,
      "#333333".hexToRgb.get)

    assert darkDefaultBg.rgb == "#333333".hexToRgb.get

suite "color: Downgrade":
  test "rgbToColor8":
    assert Color8.maroon == "#800001".hexToRgb.get.rgbToColor8

  test "rgbToColor16":
    assert Color16.maroon == "#800001".hexToRgb.get.rgbToColor16

  test "rgbToColor256":
    assert Color256.maroon == "#800001".hexToRgb.get.rgbToColor256

  test "downgrade rgb to c8 rgb":
    assert Rgb(red: 128, green: 0, blue: 0) ==
      "#800001".hexToRgb.get.downgrade(ColorMode.c8)

  test "downgrade rgb to c16 rgb":
    assert Rgb(red: 128, green: 0, blue: 0) ==
      "#800001".hexToRgb.get.downgrade(ColorMode.c16)

  test "downgrade rgb to c256 rgb":
    assert Rgb(red: 128, green: 0, blue: 0) ==
      "#800001".hexToRgb.get.downgrade(ColorMode.c256)

  test "Do nothing if c24bit":
    assert "#800001".hexToRgb.get ==
      "#800001".hexToRgb.get.downgrade(ColorMode.c24bit)
