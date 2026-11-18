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

import std/[options, times, unittest]

import ../src/moepkg/types
import ../src/moepkg/picker/session

proc item(key: string): PickerItem =
  PickerItem(key: key, display: key, target: PickerTarget(kind: ptkFile, path: key))

proc sessionOf(keys: varargs[string]): PickerSession =
  result = PickerSession()
  for key in keys:
    result.items.add item(key)

proc rows(s: PickerSession): seq[string] =
  for row in 0 ..< s.rowCount:
    result.add s.items[s.rowItem(row)].key

proc vimOrder(keys: seq[string], query: string): seq[string] =
  ## What matchfuzzy() gives, as the matcher's own tests check.
  for rank in fuzzyFilter(initFuzzyPattern(query), keys):
    result.add keys[rank.index]

proc selectedKey(s: PickerSession): string =
  let item = s.selectedItem
  if item.isSome: item.get.key else: ""

suite "picker: the list":
  test "An empty query lists every item in the source's order":
    let s = sessionOf("b", "a", "c")
    s.advancePicker("")
    check s.rows == @["b", "a", "c"]

  test "A blank query is an empty one":
    let s = sessionOf("b", "a")
    s.advancePicker("  ")
    check s.rows == @["b", "a"]

  test "The items the query matches, best first, as matchfuzzy() ranks them":
    let s = sessionOf("xfxoxo", "foo", "bar", "fo_o")
    s.advancePicker("foo")
    check s.rows == vimOrder(@["xfxoxo", "foo", "bar", "fo_o"], "foo")
    check s.rows[0] == "foo"
    check "bar" notin s.rows

  test "A query that adds to the last one matches as one from the start does":
    let keys = @["src/main.nim", "src/moe.nim", "tests/test_main.nim", "README.md"]
    let s = sessionOf(keys)
    s.advancePicker("m")
    s.advancePicker("ma")
    s.advancePicker("ma n")
    let fresh = sessionOf(keys)
    fresh.advancePicker("ma n")
    check s.rows == fresh.rows

  test "Erasing goes back to every item the shorter query matches":
    let s = sessionOf("abc", "abd", "xyz")
    s.advancePicker("abc")
    check s.rows == @["abc"]
    s.advancePicker("ab")
    check s.rows.len == 2

  test "A budget matches a slice per call, to the same list":
    var keys: seq[string]
    for i in 0 ..< 5000:
      keys.add "file" & $i & ".nim"
    let s = sessionOf(keys)
    var calls = 0
    while true:
      s.advancePicker("f9", some(initDuration(nanoseconds = 1)))
      inc calls
      if s.matchedAll:
        break
    check calls > 1
    let whole = sessionOf(keys)
    whole.advancePicker("f9")
    check s.rows == whole.rows

  test "Items added later are matched too":
    let s = sessionOf("foo")
    s.advancePicker("fo")
    s.items.add item("afo")
    check not s.matchedAll
    s.advancePicker("fo")
    check s.rows.len == 2

suite "picker: the selection":
  test "Unmoved, it follows the best":
    let s = sessionOf("bfoo", "foo")
    s.advancePicker("foo")
    check s.selectedKey == "foo"
    check s.selectedRow == 0

  test "Moved, it stays on its item as the ranks change":
    let s = sessionOf("foo", "xfoo")
    s.advancePicker("foo")
    s.moveSelection(1)
    check s.selectedKey == "xfoo"
    s.items.add item("fooo")
    s.advancePicker("foo")
    check s.selectedKey == "xfoo"

  test "Unmoved, a better item added takes it":
    let s = sessionOf("xfoo")
    s.advancePicker("foo")
    s.items.add item("foo")
    s.advancePicker("foo")
    check s.selectedKey == "foo"

  test "A new query puts it back on the best":
    let s = sessionOf("ab", "abc")
    s.advancePicker("ab")
    s.moveSelection(1)
    check s.selectedKey == "abc"
    s.advancePicker("a")
    check s.selected.isNone
    check s.selectedRow == 0

  test "It stops at either end of the list":
    let s = sessionOf("a", "b", "c")
    s.advancePicker("")
    s.moveSelection(-1)
    check s.selectedKey == "a"
    s.moveSelection(10)
    check s.selectedKey == "c"

  test "No rows, nothing selected":
    let s = sessionOf("a")
    s.advancePicker("zz")
    check s.selectedRow == -1
    check s.selectedItem.isNone
    s.moveSelection(1)
    check s.selected.isNone

  test "The list scrolls to keep the selection shown":
    let s = sessionOf("a", "b", "c", "d", "e")
    s.advancePicker("")
    s.moveSelection(4)
    s.keepSelectionVisible(2)
    check s.topIndex == 3
    s.moveSelection(-4)
    s.keepSelectionVisible(2)
    check s.topIndex == 0

  test "A taller list shows the rows above the selection it now has room for":
    let s = sessionOf("a", "b", "c", "d", "e")
    s.advancePicker("")
    s.moveSelection(4)
    s.keepSelectionVisible(2)
    check s.topIndex == 3
    s.keepSelectionVisible(4)
    check s.topIndex == 1
    s.keepSelectionVisible(10)
    check s.topIndex == 0
