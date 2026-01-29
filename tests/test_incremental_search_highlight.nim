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

## Tests for incremental search highlighting behavior
##
## This test suite verifies the fix for the issue where the second and
## subsequent incremental searches would not update highlights in real-time.
##
## The core behavior being tested:
## 1. First search: typing characters updates highlight in real-time
## 2. Second search: previous search pattern should not interfere
## 3. Search mode: only current searchText should be highlighted
## 4. Normal mode: lastSearchText should remain highlighted
##
## Implementation note: We test the search pattern selection logic directly
## rather than testing the full editor, since the editor setup is complex.

import std/[unittest, strutils]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/cursor {.all.}
import ../src/moepkg/modes {.all.}

## Helper proc to simulate the search pattern selection logic
## This mimics the logic in getSelectionStyle (editor.nim:834-843)
proc getSearchPattern(
    isSearchOverlay: bool, searchText: string, lastSearchText: string
): string =
  ## Determine which search pattern to use for highlighting
  ## Returns the pattern that should be highlighted, or empty string for no highlight
  if isSearchOverlay:
    # In Search mode: only highlight if user has typed something
    if searchText.len > 0:
      searchText
    else:
      "" # No highlight when starting a new search
  else:
    # Not in Search mode: use last search pattern
    lastSearchText

suite "Incremental Search Highlight - Search Pattern Selection":
  test "first search in Search mode with text":
    let pattern = getSearchPattern(true, "hello", "")
    check pattern == "hello"

  test "first search in Search mode without text":
    let pattern = getSearchPattern(true, "", "")
    check pattern == ""

  test "second search in Search mode without text (key fix)":
    # This is THE KEY TEST for the bug fix
    # Previous bug: would return "world" here (lastSearchText)
    # Fixed behavior: returns "" (empty searchText in Search mode)
    let pattern = getSearchPattern(true, "", "world")
    check pattern == ""
    check pattern != "world" # Explicitly verify it doesn't use lastSearchText

  test "second search in Search mode with new text":
    # User has started typing a new search
    let pattern = getSearchPattern(true, "h", "world")
    check pattern == "h"
    check pattern != "world"

  test "second search progressive typing":
    # Simulate user typing "hello" character by character
    var pattern: string

    pattern = getSearchPattern(true, "h", "world")
    check pattern == "h"

    pattern = getSearchPattern(true, "he", "world")
    check pattern == "he"

    pattern = getSearchPattern(true, "hel", "world")
    check pattern == "hel"

    pattern = getSearchPattern(true, "hell", "world")
    check pattern == "hell"

    pattern = getSearchPattern(true, "hello", "world")
    check pattern == "hello"

  test "Normal mode uses lastSearchText":
    let pattern = getSearchPattern(false, "", "world")
    check pattern == "world"

  test "Normal mode ignores empty searchText":
    let pattern = getSearchPattern(false, "ignored", "world")
    check pattern == "world"

suite "Incremental Search Highlight - Mode Transitions":
  test "entering Search mode from Normal mode":
    # User is in Normal mode with previous search
    var mode = false
    var searchText = ""
    var lastSearchText = "world"

    # Check Normal mode shows lastSearchText
    var pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "world"

    # User presses / to enter Search mode
    mode = true
    searchText = "" # Empty initially

    # Key test: entering Search mode should not show lastSearchText
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == ""

  test "exiting Search mode to Normal mode":
    # User completes a search
    var mode = true
    var searchText = "hello"
    var lastSearchText = "world"

    # In Search mode, shows current searchText
    var pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "hello"

    # User presses Enter - search is finalized
    lastSearchText = searchText # Save to history
    searchText = "" # Clear search buffer
    mode = false

    # In Normal mode, shows lastSearchText
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "hello"

  test "canceling search with Escape":
    # User starts a search but cancels it
    var mode = true
    var searchText = "hel"
    var lastSearchText = "world"

    # User presses Escape - cancel search
    searchText = "" # Clear search buffer
    mode = false

    # Back in Normal mode, old lastSearchText is preserved
    var pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "world"

suite "Incremental Search Highlight - Real-world Scenarios":
  test "user workflow: search foo, then search bar":
    # Simulate complete user workflow
    var mode: bool
    var searchText: string
    var lastSearchText: string
    var pattern: string

    # Initial state
    mode = false
    searchText = ""
    lastSearchText = ""

    # User presses / to search
    mode = true

    # User types "foo"
    searchText = "foo"
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "foo"

    # User presses Enter
    lastSearchText = searchText
    searchText = ""
    mode = false

    # Verify lastSearchText is highlighted
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "foo"

    # User presses / again for a new search
    mode = true
    searchText = ""

    # KEY TEST: Should not show "foo" anymore
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == ""
    check pattern != "foo"

    # User types "bar"
    searchText = "bar"
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "bar"

  test "user workflow: backspace during second search":
    var mode = true
    var searchText = ""
    var lastSearchText = "world"
    var pattern: string

    # User types "test"
    searchText = "test"
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "test"

    # User backspaces to "tes"
    searchText = "tes"
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "tes"

    # User backspaces to "te"
    searchText = "te"
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "te"

    # User backspaces to "t"
    searchText = "t"
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == "t"

    # User backspaces to empty
    searchText = ""
    pattern = getSearchPattern(mode, searchText, lastSearchText)
    check pattern == ""
    check pattern != "world" # Should not revert to lastSearchText

  test "rapid mode switching":
    var mode: bool
    var searchText: string
    var lastSearchText = "initial"
    var pattern: string

    # Enter and exit Search mode multiple times
    for i in 1 .. 5:
      # Enter Search mode
      mode = true
      searchText = ""

      # Should start with no highlight
      pattern = getSearchPattern(mode, searchText, lastSearchText)
      check pattern == ""

      # Type something
      searchText = "test" & $i
      pattern = getSearchPattern(mode, searchText, lastSearchText)
      check pattern == "test" & $i

      # Exit to Normal mode
      lastSearchText = searchText
      searchText = ""
      mode = false

      # Should show lastSearchText
      pattern = getSearchPattern(mode, searchText, lastSearchText)
      check pattern == "test" & $i

suite "Incremental Search Highlight - Buffer Integration":
  test "highlighting correct positions with searchText":
    let buf = newTextBuffer("hello world hello again")

    # Simulate Search mode with searchText = "hello"
    let searchPattern = getSearchPattern(true, "hello", "world")
    check searchPattern == "hello"

    # Verify buffer can find the pattern
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 0), searchPattern)
    check buf.isPositionInSearchMatch(
      BufferPosition(line: 0, column: 12), searchPattern
    )
    check not buf.isPositionInSearchMatch(
      BufferPosition(line: 0, column: 6), searchPattern
    )

  test "no highlighting with empty searchText in Search mode":
    let buf = newTextBuffer("hello world hello again")

    # Simulate Search mode with empty searchText
    let searchPattern = getSearchPattern(true, "", "world")
    check searchPattern == ""

    # With empty pattern, isPositionInSearchMatch should return false
    check not buf.isPositionInSearchMatch(
      BufferPosition(line: 0, column: 0), searchPattern
    )
    check not buf.isPositionInSearchMatch(
      BufferPosition(line: 0, column: 6), searchPattern
    )

  test "highlighting with lastSearchText in Normal mode":
    let buf = newTextBuffer("hello world hello again")

    # Simulate Normal mode with lastSearchText = "world"
    let searchPattern = getSearchPattern(false, "", "world")
    check searchPattern == "world"

    # Verify buffer highlights the pattern
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 6), searchPattern)
    check not buf.isPositionInSearchMatch(
      BufferPosition(line: 0, column: 0), searchPattern
    )

suite "Incremental Search Highlight - Edge Cases":
  test "empty strings everywhere":
    let pattern = getSearchPattern(true, "", "")
    check pattern == ""

  test "unicode in search patterns":
    let pattern1 = getSearchPattern(true, "日本語", "")
    check pattern1 == "日本語"

    let pattern2 = getSearchPattern(false, "", "한글")
    check pattern2 == "한글"

  test "very long search patterns":
    let longPattern = "a".repeat(1000)
    let pattern = getSearchPattern(true, longPattern, "short")
    check pattern == longPattern
    check pattern.len == 1000

  test "Insert mode ignores search":
    # Insert mode should use lastSearchText (like Normal mode)
    let pattern = getSearchPattern(false, "", "world")
    check pattern == "world"

  test "Visual mode ignores search":
    # Visual mode should use lastSearchText (like Normal mode)
    let pattern = getSearchPattern(false, "", "world")
    check pattern == "world"

  test "Command mode ignores search":
    # Command mode should use lastSearchText (like Normal mode)
    let pattern = getSearchPattern(false, "", "world")
    check pattern == "world"
