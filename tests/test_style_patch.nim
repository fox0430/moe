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

import ../src/moepkg/style_patch {.all.}

func rgb(r, g, b: int): ColorValue =
  ColorValue(kind: Rgb, rgb: RgbColor(r: r.uint8, g: g.uint8, b: b.uint8))

func baseStyle(): Style =
  Style(fg: rgb(10, 20, 30), bg: rgb(40, 50, 60), modifiers: {StyleModifier.Bold})

suite "StylePatch.merge":
  test "empty patch returns base unchanged":
    let base = baseStyle()
    let result = base.merge(noPatch)
    check result.fg == base.fg
    check result.bg == base.bg
    check result.modifiers == base.modifiers

  test "bgOnly replaces only bg":
    let base = baseStyle()
    let newBg = rgb(99, 99, 99)
    let result = base.merge(bgOnly(newBg))
    check result.fg == base.fg
    check result.bg == newBg
    check result.modifiers == base.modifiers

  test "fgOnly replaces only fg":
    let base = baseStyle()
    let newFg = rgb(99, 99, 99)
    let result = base.merge(fgOnly(newFg))
    check result.fg == newFg
    check result.bg == base.bg
    check result.modifiers == base.modifiers

  test "withModifiers unions modifier sets":
    let base = baseStyle() # has {Bold}
    let result = base.merge(withModifiers({StyleModifier.Italic}))
    check result.fg == base.fg
    check result.bg == base.bg
    check result.modifiers == {StyleModifier.Bold, StyleModifier.Italic}

  test "withModifiers empty set is a no-op for modifiers":
    let base = baseStyle()
    let result = base.merge(withModifiers({}))
    check result.modifiers == base.modifiers

  test "withModifiers preserves base modifier when same modifier added":
    let base = baseStyle() # {Bold}
    let result = base.merge(withModifiers({StyleModifier.Bold}))
    check result.modifiers == {StyleModifier.Bold}

  test "full replaces fg, bg and unions modifiers":
    let base = baseStyle() # fg(10,20,30) bg(40,50,60) {Bold}
    let src =
      Style(fg: rgb(1, 2, 3), bg: rgb(4, 5, 6), modifiers: {StyleModifier.Italic})
    let result = base.merge(full(src))
    check result.fg == src.fg
    check result.bg == src.bg
    check result.modifiers == {StyleModifier.Bold, StyleModifier.Italic}

  test "merge is sequentially applicable":
    let base = baseStyle()
    let p1 = bgOnly(rgb(99, 99, 99))
    let p2 = fgOnly(rgb(11, 22, 33))
    let result = base.merge(p1).merge(p2)
    check result.fg == rgb(11, 22, 33)
    check result.bg == rgb(99, 99, 99)
    check result.modifiers == base.modifiers

  test "later patch overrides earlier patch for same field":
    let base = baseStyle()
    let p1 = bgOnly(rgb(1, 1, 1))
    let p2 = bgOnly(rgb(2, 2, 2))
    let result = base.merge(p1).merge(p2)
    check result.bg == rgb(2, 2, 2)

suite "StylePatch helpers":
  test "noPatch has no fields set":
    check noPatch.fg.isNone
    check noPatch.bg.isNone
    check noPatch.modifiers == {}

  test "bgOnly leaves fg and modifiers unset":
    let p = bgOnly(rgb(1, 2, 3))
    check p.fg.isNone
    check p.bg == some(rgb(1, 2, 3))
    check p.modifiers == {}

  test "fgOnly leaves bg and modifiers unset":
    let p = fgOnly(rgb(1, 2, 3))
    check p.fg == some(rgb(1, 2, 3))
    check p.bg.isNone
    check p.modifiers == {}

  test "withModifiers leaves fg and bg unset":
    let p = withModifiers({StyleModifier.Italic, StyleModifier.Underline})
    check p.fg.isNone
    check p.bg.isNone
    check p.modifiers == {StyleModifier.Italic, StyleModifier.Underline}

  test "full carries all fields":
    let src =
      Style(fg: rgb(1, 2, 3), bg: rgb(4, 5, 6), modifiers: {StyleModifier.Italic})
    let p = full(src)
    check p.fg == some(src.fg)
    check p.bg == some(src.bg)
    check p.modifiers == src.modifiers
