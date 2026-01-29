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

import ../src/moepkg/keybindconfig {.all.}
import ../src/moepkg/keybindings
import ../src/moepkg/modes

suite "KeybindConfig - parseMode":
  test "parse normal mode":
    check parseMode("normal").isSome
    check parseMode("normal").get == EditorMode.Normal

  test "parse insert mode":
    check parseMode("insert").isSome
    check parseMode("insert").get == EditorMode.Insert

  test "parse visual mode":
    check parseMode("visual").isSome
    check parseMode("visual").get == EditorMode.Visual

  test "parse replace mode":
    check parseMode("replace").isSome
    check parseMode("replace").get == EditorMode.Replace

  test "parse mode is case insensitive":
    check parseMode("NORMAL").isSome
    check parseMode("NORMAL").get == EditorMode.Normal
    check parseMode("Normal").isSome
    check parseMode("Normal").get == EditorMode.Normal
    check parseMode("INSERT").isSome
    check parseMode("INSERT").get == EditorMode.Insert

  test "parse unknown mode returns none":
    check parseMode("unknown").isNone
    check parseMode("command").isNone
    check parseMode("search").isNone
    check parseMode("").isNone

suite "KeybindConfig - parseOverlay":
  test "parse command overlay":
    check parseOverlay("command").isSome
    check parseOverlay("command").get == okCommand

  test "parse search overlay":
    check parseOverlay("search").isSome
    check parseOverlay("search").get == okSearch

  test "parse rename overlay":
    check parseOverlay("rename").isSome
    check parseOverlay("rename").get == okRename

  test "parse overlay is case insensitive":
    check parseOverlay("COMMAND").isSome
    check parseOverlay("COMMAND").get == okCommand
    check parseOverlay("Command").isSome
    check parseOverlay("Command").get == okCommand
    check parseOverlay("SEARCH").isSome
    check parseOverlay("SEARCH").get == okSearch
    check parseOverlay("RENAME").isSome
    check parseOverlay("RENAME").get == okRename

  test "parse unknown overlay returns none":
    check parseOverlay("unknown").isNone
    check parseOverlay("normal").isNone
    check parseOverlay("insert").isNone
    check parseOverlay("").isNone

suite "KeybindConfig - parseCommandType":
  test "parse motion":
    check parseCommandType("motion") == ctMotion

  test "parse action":
    check parseCommandType("action") == ctAction

  test "parse mode_switch":
    check parseCommandType("mode_switch") == ctModeSwitch
    check parseCommandType("modeswitch") == ctModeSwitch

  test "parse overlay_switch":
    check parseCommandType("overlay_switch") == ctOverlaySwitch
    check parseCommandType("overlayswitch") == ctOverlaySwitch

  test "parse text_object":
    check parseCommandType("text_object") == ctTextObject
    check parseCommandType("textobject") == ctTextObject

  test "parse operator":
    check parseCommandType("operator") == ctOperator

  test "parse operator_pending":
    check parseCommandType("operator_pending") == ctOperatorPending
    check parseCommandType("operatorpending") == ctOperatorPending

  test "parse custom":
    check parseCommandType("custom") == ctCustom

  test "parse command type is case insensitive":
    check parseCommandType("MOTION") == ctMotion
    check parseCommandType("Motion") == ctMotion
    check parseCommandType("ACTION") == ctAction
    check parseCommandType("MODE_SWITCH") == ctModeSwitch
    check parseCommandType("OVERLAY_SWITCH") == ctOverlaySwitch

  test "unknown command type defaults to action":
    check parseCommandType("unknown") == ctAction
    check parseCommandType("") == ctAction
    check parseCommandType("invalid") == ctAction
