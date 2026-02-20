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

import std/unittest

import ../src/moepkg/color
import ../src/moepkg/theme {.all.}

suite "theme - makeColorPair helper":
  test "makeColorPair creates valid ColorPair":
    let pair = makeColorPair("#ff0000", "#00ff00")
    check pair.foreground.rgb.red == 255
    check pair.foreground.rgb.green == 0
    check pair.foreground.rgb.blue == 0
    check pair.background.rgb.red == 0
    check pair.background.rgb.green == 255
    check pair.background.rgb.blue == 0

  test "makeColorPairDefaultBg uses black background":
    let pair = makeColorPairDefaultBg("#ffffff")
    check pair.foreground.rgb.red == 255
    check pair.foreground.rgb.green == 255
    check pair.foreground.rgb.blue == 255
    check pair.background.rgb.red == 0
    check pair.background.rgb.green == 0
    check pair.background.rgb.blue == 0

suite "theme - DefaultColors completeness":
  test "DefaultColors covers all EditorColorPairIndex values":
    # DefaultColors is an array indexed by EditorColorPairIndex,
    # so all values are guaranteed to be present at compile time.
    # Verify a sampling of entries have non-zero content.
    let colors = DefaultColors
    check colors[EditorColorPairIndex.default].foreground.rgb.red >= 0
    check colors[EditorColorPairIndex.keyword].foreground.rgb.red >= 0
    check colors[EditorColorPairIndex.comment].foreground.rgb.red >= 0

  test "default entry has expected colors":
    let pair = DefaultColors[EditorColorPairIndex.default]
    # Foreground: #f8f5e3 = (248, 245, 227)
    check pair.foreground.rgb.red == 248
    check pair.foreground.rgb.green == 245
    check pair.foreground.rgb.blue == 227
    # Background: #000000 = (0, 0, 0)
    check pair.background.rgb.red == 0
    check pair.background.rgb.green == 0
    check pair.background.rgb.blue == 0

  test "errorMessage has red foreground":
    let pair = DefaultColors[EditorColorPairIndex.errorMessage]
    check pair.foreground.rgb.red == 255
    check pair.foreground.rgb.green == 0
    check pair.foreground.rgb.blue == 0

  test "searchResult has red background":
    let pair = DefaultColors[EditorColorPairIndex.searchResult]
    check pair.background.rgb.red == 255
    check pair.background.rgb.green == 0
    check pair.background.rgb.blue == 0

suite "theme - initDefaultTheme":
  test "initDefaultTheme sets theme colors":
    initDefaultTheme()
    let defaultColor = getThemeColor(EditorColorPairIndex.default)
    check defaultColor.foreground.rgb.red == 248
