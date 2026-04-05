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

import ../src/moepkg/highlight
import ../src/moepkg/syntax/[tokenizer, syntaxhyprland]

suite "syntaxhyprland - comments":
  test "hash comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.hyprlandNextToken()
    check g.kind == gtComment

suite "syntaxhyprland - keywords":
  test "bind keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("bind")
    g.hyprlandNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "exec-once keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("exec-once")
    g.hyprlandNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "monitor keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("monitor")
    g.hyprlandNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "source keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("source")
    g.hyprlandNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "windowrulev2 keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("windowrulev2")
    g.hyprlandNextToken()
    check g.kind == gtKeyword
    check g.length == 12

suite "syntaxhyprland - booleans":
  test "true":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.hyprlandNextToken()
    check g.kind == gtBoolean

  test "false":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.hyprlandNextToken()
    check g.kind == gtBoolean

  test "yes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("yes")
    g.hyprlandNextToken()
    check g.kind == gtBoolean

  test "no":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("no")
    g.hyprlandNextToken()
    check g.kind == gtBoolean

  test "on":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("on")
    g.hyprlandNextToken()
    check g.kind == gtBoolean

  test "off":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("off")
    g.hyprlandNextToken()
    check g.kind == gtBoolean

suite "syntaxhyprland - variables":
  test "variable reference":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$terminal")
    g.hyprlandNextToken()
    check g.kind == gtSpecialVar
    check g.length == 9

  test "dollar sign alone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$ ")
    g.hyprlandNextToken()
    check g.kind == gtSpecialVar
    check g.length == 1

suite "syntaxhyprland - numbers":
  test "decimal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42")
    g.hyprlandNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

  test "float number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1.5")
    g.hyprlandNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "zero-prefixed decimal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("042")
    g.hyprlandNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "hex number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xDEADBEEF")
    g.hyprlandNextToken()
    check g.kind == gtHexNumber
    check g.length == 10

suite "syntaxhyprland - strings":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.hyprlandNextToken()
    check g.kind == gtStringLit
    check g.length == 13

suite "syntaxhyprland - strings with escape sequences":
  test "string with escape sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    # First token: "hello
    g.hyprlandNextToken()
    check g.kind == gtStringLit
    check g.length == 6
    # Second token: \n (escape sequence)
    g.hyprlandNextToken()
    check g.kind == gtEscapeSequence
    check g.length == 2
    # Third token: world"
    g.hyprlandNextToken()
    check g.kind == gtStringLit
    check g.length == 6

suite "syntaxhyprland - section names":
  test "section followed by brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("general {")
    g.hyprlandNextToken()
    check g.kind == gtTable
    check g.length == 7

  test "identifier not followed by brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("gaps_in")
    g.hyprlandNextToken()
    check g.kind == gtIdentifier
    check g.length == 7

suite "syntaxhyprland - punctuation and operators":
  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.hyprlandNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.hyprlandNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.hyprlandNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.hyprlandNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxhyprland - whitespace":
  test "spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   ")
    g.hyprlandNextToken()
    check g.kind == gtWhitespace
    check g.length == 3

suite "syntaxhyprland - detectLanguage":
  test "hyprland.conf":
    check detectLanguage("hyprland.conf") == langHyprland

  test ".hl extension":
    check detectLanguage("colors.hl") == langHyprland

  test "path with hyprland.conf":
    check detectLanguage("/home/user/.config/hypr/hyprland.conf") == langHyprland
