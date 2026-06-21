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

import ../src/moepkg/[list_viewer, key_bindings, buffer]

proc newView(count: int): ListViewer[string] =
  var items: seq[string]
  for i in 0 ..< count:
    items.add("item" & $i)
  ListViewer[string](items: items, selectedIndex: 0, title: "Test")

proc charKey(ch: string): KeyCombo =
  KeyCombo(isSpecial: false, char: ch, modifiers: {})

proc ctrlKey(ch: string): KeyCombo =
  KeyCombo(isSpecial: false, char: ch, modifiers: {kmCtrl})

proc specialKey(key: SpecialKey): KeyCombo =
  KeyCombo(isSpecial: true, special: key, modifiers: {})

suite "ListViewer navigation":
  test "itemCount / getItem / getSelectedItem":
    let v = newView(3)
    check v.itemCount == 3
    check v.getItem(1) == some("item1")
    check v.getItem(-1).isNone
    check v.getItem(3).isNone
    check v.getSelectedItem == some("item0")

  test "moveDown stops at the last item":
    let v = newView(3)
    v.moveDown()
    check v.selectedIndex == 1
    v.moveDown()
    v.moveDown() # already at the end
    check v.selectedIndex == 2

  test "moveUp stops at the first item":
    let v = newView(3)
    v.selectedIndex = 2
    v.moveUp()
    check v.selectedIndex == 1
    v.moveUp()
    v.moveUp() # already at the start
    check v.selectedIndex == 0

  test "moveToFirst / moveToLast":
    let v = newView(5)
    v.moveToLast()
    check v.selectedIndex == 4
    v.moveToFirst()
    check v.selectedIndex == 0

  test "moveToLast on empty list clamps to 0":
    let v = newView(0)
    v.moveToLast()
    check v.selectedIndex == 0

  test "halfPageDown / halfPageUp clamp to bounds":
    let v = newView(20)
    v.halfPageDown(10) # 0 -> 5
    check v.selectedIndex == 5
    v.halfPageDown(10) # 5 -> 10
    v.halfPageDown(10) # 10 -> 15
    v.halfPageDown(10) # 15 -> 19 (clamped, would be 20)
    check v.selectedIndex == 19
    v.halfPageUp(10) # 19 -> 14
    check v.selectedIndex == 14

suite "ListViewer shared key handling":
  test "j / k move and keep selection visible":
    let v = newView(5)
    check v.handleListNavKey(10, charKey("j")) == lvaConsumed
    check v.selectedIndex == 1
    check v.handleListNavKey(10, charKey("k")) == lvaConsumed
    check v.selectedIndex == 0

  test "arrow keys move":
    let v = newView(5)
    check v.handleListNavKey(10, specialKey(skDown)) == lvaConsumed
    check v.selectedIndex == 1
    check v.handleListNavKey(10, specialKey(skUp)) == lvaConsumed
    check v.selectedIndex == 0

  test "G jumps to last, gg jumps to first":
    let v = newView(5)
    check v.handleListNavKey(10, charKey("G")) == lvaConsumed
    check v.selectedIndex == 4
    # first 'g' arms, second 'g' jumps
    check v.handleListNavKey(10, charKey("g")) == lvaConsumed
    check v.waitingForG
    check v.handleListNavKey(10, charKey("g")) == lvaConsumed
    check v.selectedIndex == 0
    check not v.waitingForG

  test "g followed by a non-g cancels and re-dispatches":
    let v = newView(5)
    discard v.handleListNavKey(10, charKey("g"))
    check v.waitingForG
    # 'j' clears waitingForG and still moves down
    check v.handleListNavKey(10, charKey("j")) == lvaConsumed
    check not v.waitingForG
    check v.selectedIndex == 1

  test "Ctrl-d / Ctrl-u half page":
    let v = newView(40)
    check v.handleListNavKey(10, ctrlKey("d")) == lvaConsumed
    check v.selectedIndex == 5
    check v.handleListNavKey(10, ctrlKey("u")) == lvaConsumed
    check v.selectedIndex == 0

  test "q and Escape are distinct, : enters command":
    let v = newView(5)
    check v.handleListNavKey(10, charKey("q")) == lvaQuitKey
    check v.handleListNavKey(10, specialKey(skEscape)) == lvaEscape
    check v.handleListNavKey(10, charKey(":")) == lvaEnterCommand

  test "Enter selects":
    let v = newView(5)
    check v.handleListNavKey(10, specialKey(skEnter)) == lvaSelect

  test "unknown keys are unhandled":
    let v = newView(5)
    check v.handleListNavKey(10, charKey("z")) == lvaUnhandled
    check v.handleListNavKey(10, specialKey(skTab)) == lvaUnhandled

suite "ListViewer rendering":
  test "toListTextBuffer renders header + formatted items, read-only":
    let v = newView(2)
    let buf = v.toListTextBuffer(
      "-- HEAD --",
      proc(s: string): string =
        ">" & s,
    )
    check buf.readOnly
    check buf.len == 3 # header + 2 items
    check buf[0] == "-- HEAD --"
    check buf[1] == ">item0"
    check buf[2] == ">item1"

  test "toListTextBuffer on empty list renders header only":
    let v = newView(0)
    let buf = v.toListTextBuffer(
      "-- EMPTY --",
      proc(s: string): string =
        s,
    )
    check buf.len == 1
    check buf[0] == "-- EMPTY --"
