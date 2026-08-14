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

## Tests for highlight_config.nim

import std/unittest

import ../src/moepkg/[config, highlight_config]
import ../src/moepkg/buffer

suite "highlight_config":
  test "applyHighlightCap seeds maxHighlightLineLength":
    let buffer = newTextBuffer("test")
    var config = newEditorConfig()
    config.highlight.maxHighlightLineLength = 123
    buffer.applyHighlightCap(config)
    check buffer.maxHighlightLineLength == 123

  test "applyHighlightConfig applies reserved words and cap":
    let buffer = newTextBuffer("test")
    var config = newEditorConfig()
    config.highlight.reservedWord = @["TODO", "WIP"]
    config.highlight.maxHighlightLineLength = 77
    buffer.applyHighlightConfig(config)
    check buffer.reservedWords.len == 2
    check buffer.reservedWords[0].word == "TODO"
    check buffer.reservedWords[1].word == "WIP"
    check buffer.maxHighlightLineLength == 77
    check buffer.highlightNeedsUpdate

  test "applyHighlightCap is a no-op when the cap is unchanged":
    let buffer = newTextBuffer("test")
    var config = newEditorConfig()
    config.highlight.maxHighlightLineLength = 100
    buffer.setMaxHighlightLineLength(100)
    buffer.highlightNeedsUpdate = false
    buffer.applyHighlightCap(config)
    check buffer.highlightNeedsUpdate == false
