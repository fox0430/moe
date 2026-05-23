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

import std/[strutils, unittest]

import ../tools/migrate_theme_toml

suite "migrate_theme_toml":
  test "regular fg/bg pair becomes inline table":
    let src = """
[Colors]
foreground = "#dadada"
background = "#000000"

lineNum = "#636d83"
lineNumBg = "#000000"
"""
    let actual = migrateThemeToml(src)
    check "foreground = \"#dadada\"" in actual
    check "background = \"#000000\"" in actual
    check "lineNum = { fg = \"#636d83\", bg = \"#000000\" }" in actual

  test "fg-only entry omits bg in inline table":
    let src = """
[Colors]
foreground = "#dadada"
background = "#000000"

keyword = "#5fd7ff"
"""
    let actual = migrateThemeToml(src)
    check "keyword = { fg = \"#5fd7ff\" }" in actual
    check "keywordBg" notin actual

  test "currentLineBg renames to currentLine (bg-only)":
    let src = """
[Colors]
foreground = "#dadada"
background = "#000000"

currentLineBg = "#3e4452"
currentColumnBg = "#3e4452"
"""
    let actual = migrateThemeToml(src)
    check "currentLine = { bg = \"#3e4452\" }" in actual
    check "currentColumn = { bg = \"#3e4452\" }" in actual
    # legacy names must not leak through
    check "currentLineBg" notin actual
    check "currentColumnBg" notin actual

  test "configModePopupBg pair collapses to configModePopup":
    let src = """
[Colors]
foreground = "#dadada"
background = "#000000"

configModePopupBg = "#ffffff"
configModePopupBgBg = "#323232"
"""
    let actual = migrateThemeToml(src)
    check "configModePopup = { fg = \"#ffffff\", bg = \"#323232\" }" in actual
    # The standalone legacy keys must not appear.
    check "configModePopupBg " notin actual
    check "configModePopupBgBg" notin actual

  test "orphan keyBg (no matching key) emits bg-only entry":
    # Defensive: if a user has only the Bg side, preserve their data.
    let src = """
[Colors]
foreground = "#dadada"
background = "#000000"

selectAreaBg = "#5c3d6e"
"""
    let actual = migrateThemeToml(src)
    check "selectArea = { bg = \"#5c3d6e\" }" in actual

  test "termDefault color values are preserved":
    let src = """
[Colors]
foreground = "termDefault"
background = "termDefault"

lineNum = "termDefault"
lineNumBg = "termDefault"
"""
    let actual = migrateThemeToml(src)
    check "foreground = \"termDefault\"" in actual
    check "background = \"termDefault\"" in actual
    check "lineNum = { fg = \"termDefault\", bg = \"termDefault\" }" in actual

  test "already-migrated file is returned unchanged (idempotent)":
    let src = """
[Colors]

foreground = "#dadada"
background = "#000000"

lineNum = { fg = "#636d83", bg = "#000000" }
keyword = { fg = "#5fd7ff" }
currentLine = { bg = "#3e4452" }
"""
    let actual = migrateThemeToml(src)
    check actual == src

  test "missing [Colors] section raises MigrationError":
    expect MigrationError:
      discard migrateThemeToml("foreground = \"#dadada\"\n")

  test "key order from the input is preserved in the output":
    let src = """
[Colors]
foreground = "#000000"
background = "#ffffff"

zebra = "#111111"
alpha = "#222222"
"""
    let actual = migrateThemeToml(src)
    let zebraIdx = actual.find("zebra =")
    let alphaIdx = actual.find("alpha =")
    check zebraIdx >= 0
    check alphaIdx >= 0
    check zebraIdx < alphaIdx
