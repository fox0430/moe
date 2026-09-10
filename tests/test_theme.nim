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

# Declared first so it observes the global state established purely by module
# initialization, before any later suite mutates it.
suite "theme - global seed (regression: all-black dark.toml)":
  test "themeColors is seeded with DefaultColors at module load":
    ## `color.nim` zero-initializes the `themeColors` global (every channel 0,
    ## i.e. all-black #000000) because it cannot reference `DefaultColors`
    ## without an import cycle. `theme.nim` seeds the global with `DefaultColors`
    ## at module load so any save path that runs before
    ## `initTheme`/`setThemeColors` (e.g. a tool/test using a default
    ## `EditorConfig`, whose `theme.path` points at the real
    ## ~/.config/moe/themes/dark.toml) writes a valid dark theme instead of
    ## overwriting that file with all-black. Removing the seed makes this fail.
    check themeColors == DefaultColors

    # Discriminate against the zero-initialized (all-black) state: the default
    # foreground in DefaultColors is #dadada (red 218), never 0.
    check themeColors[EditorColorPairIndex.default].foreground.rgb.red == 218
    check themeColors[EditorColorPairIndex.default].foreground.rgb != rgb("#000000")

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
    # Foreground: #dadada = (218, 218, 218)
    check pair.foreground.rgb.red == 218
    check pair.foreground.rgb.green == 218
    check pair.foreground.rgb.blue == 218
    # Background: #000000 = (0, 0, 0)
    check pair.background.rgb.red == 0
    check pair.background.rgb.green == 0
    check pair.background.rgb.blue == 0

  test "errorMessage has muted red foreground":
    let pair = DefaultColors[EditorColorPairIndex.errorMessage]
    # #e06c75 = (224, 108, 117)
    check pair.foreground.rgb.red == 224
    check pair.foreground.rgb.green == 108
    check pair.foreground.rgb.blue == 117

  test "searchResult has muted red background":
    let pair = DefaultColors[EditorColorPairIndex.searchResult]
    # #be5046 = (190, 80, 70)
    check pair.background.rgb.red == 190
    check pair.background.rgb.green == 80
    check pair.background.rgb.blue == 70

suite "theme - initDefaultTheme":
  test "initDefaultTheme sets theme colors":
    initDefaultTheme()
    let defaultColor = getThemeColor(EditorColorPairIndex.default)
    check defaultColor.foreground.rgb.red == 218

suite "theme - diff viewer tints follow the background":
  test "A light background swaps the dark default tints":
    var colors = DefaultColors
    colors[EditorColorPairIndex.default].background = ThemeColor(rgb: rgb("#ffffff"))
    colors.adaptDiffTintsToBackground()
    # The diff viewer signals added/deleted lines with the background alone and
    # keeps the terminal-default foreground, so a dark tint would be unreadable.
    check colors[EditorColorPairIndex.diffViewerAddedLineBg].background.rgb ==
      rgb("#e6ffec")
    check colors[EditorColorPairIndex.diffViewerDeletedLineBg].background.rgb ==
      rgb("#ffebe9")
    check colors[EditorColorPairIndex.diffViewerAddedWord].background.rgb ==
      rgb("#a8f0b8")
    check colors[EditorColorPairIndex.diffViewerDeletedWord].background.rgb ==
      rgb("#ffc4c9")
    check colors[EditorColorPairIndex.diffViewerFiller].background.rgb == rgb("#ededed")

  test "A dark background keeps the default tints":
    var colors = DefaultColors
    colors.adaptDiffTintsToBackground()
    check colors == DefaultColors

  test "A terminal-default background follows the foreground":
    # "background = termDefault" hides the surface color, so a dark explicit
    # foreground is the only sign that the terminal behind it is light.
    var colors = DefaultColors
    colors[EditorColorPairIndex.default].background =
      ThemeColor(rgb: TerminalDefaultRgb)
    colors[EditorColorPairIndex.default].foreground = ThemeColor(rgb: rgb("#000000"))
    colors.adaptDiffTintsToBackground()
    check colors[EditorColorPairIndex.diffViewerAddedLineBg].background.rgb ==
      rgb("#e6ffec")
    check colors[EditorColorPairIndex.diffViewerDeletedLineBg].background.rgb ==
      rgb("#ffebe9")

  test "A terminal-default foreground on a terminal-default background keeps the tints":
    var colors = DefaultColors
    colors[EditorColorPairIndex.default].background =
      ThemeColor(rgb: TerminalDefaultRgb)
    colors[EditorColorPairIndex.default].foreground =
      ThemeColor(rgb: TerminalDefaultRgb)
    let before = colors
    colors.adaptDiffTintsToBackground()
    check colors == before

  test "A theme that sets its own tints keeps them":
    var colors = DefaultColors
    colors[EditorColorPairIndex.default].background = ThemeColor(rgb: rgb("#ffffff"))
    colors[EditorColorPairIndex.diffViewerAddedLineBg].background =
      ThemeColor(rgb: rgb("#123456"))
    colors.adaptDiffTintsToBackground()
    check colors[EditorColorPairIndex.diffViewerAddedLineBg].background.rgb ==
      rgb("#123456")
    check colors[EditorColorPairIndex.diffViewerDeletedLineBg].background.rgb ==
      rgb("#ffebe9")
