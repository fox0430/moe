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

## Tests for buffer_manager.nim

import std/[unittest, options, strutils]
import ../src/moepkg/buffer/core
import ../src/moepkg/buffer_manager

suite "BufferManagerState - Constructor":
  test "newBufferManagerState creates empty state":
    let state = newBufferManagerState()

    check state.items.len == 0
    check state.selectedIndex == 0

suite "BufferEntry - initBufferManagerEntries":
  test "Create entries from empty buffer list":
    let entries = initBufferManagerEntries(@[])

    # Should add placeholder entry when empty
    check entries.len == 1
    check entries[0].number == 0
    check entries[0].name == "No Name"
    check entries[0].modified == false
    check entries[0].active == true

  test "Create entries from single buffer":
    let bufferInfos = @[
      BufferInfo(filePath: some("/path/to/file.nim"), isModified: false, isActive: true)
    ]
    let entries = initBufferManagerEntries(bufferInfos)

    check entries.len == 1
    check entries[0].number == 0
    check entries[0].name == "/path/to/file.nim"
    check entries[0].modified == false
    check entries[0].active == true

  test "Create entries from multiple buffers":
    # The numbers are not consecutive on purpose: they are buffer ids, so a
    # deleted buffer leaves a gap instead of renumbering the rest.
    let bufferInfos = @[
      BufferInfo(
        number: 1, filePath: some("/path/file1.nim"), isModified: false, isActive: false
      ),
      BufferInfo(
        number: 4, filePath: some("/path/file2.nim"), isModified: true, isActive: true
      ),
      BufferInfo(number: 7, filePath: none(string), isModified: false, isActive: false),
    ]
    let entries = initBufferManagerEntries(bufferInfos)

    check entries.len == 3

    check entries[0].number == 1
    check entries[0].name == "/path/file1.nim"
    check entries[0].modified == false
    check entries[0].active == false

    check entries[1].number == 4
    check entries[1].name == "/path/file2.nim"
    check entries[1].modified == true
    check entries[1].active == true

    check entries[2].number == 7
    check entries[2].name == "No Name"
    check entries[2].modified == false
    check entries[2].active == false

  test "Buffer without filePath shows 'No Name'":
    let bufferInfos =
      @[BufferInfo(filePath: none(string), isModified: true, isActive: true)]
    let entries = initBufferManagerEntries(bufferInfos)

    check entries.len == 1
    check entries[0].name == "No Name"
    check entries[0].modified == true

  test "displayName overrides filePath":
    let bufferInfos = @[
      BufferInfo(
        filePath: some("/path/to/file.nim"),
        displayName: some("[Terminal: bash]"),
        isModified: false,
        isActive: true,
      )
    ]
    let entries = initBufferManagerEntries(bufferInfos)

    check entries.len == 1
    check entries[0].name == "[Terminal: bash]"

  test "filePath is used when displayName is none":
    let bufferInfos = @[
      BufferInfo(
        filePath: some("/path/to/file.nim"),
        displayName: none(string),
        isModified: false,
        isActive: false,
      )
    ]
    let entries = initBufferManagerEntries(bufferInfos)

    check entries.len == 1
    check entries[0].name == "/path/to/file.nim"

  test "a raw newline in displayName cannot forge a listing line":
    let bufferInfos = @[
      BufferInfo(
        filePath: none(string),
        displayName: some("[Terminal: bad\nname]"),
        isModified: false,
        isActive: false,
      )
    ]
    let entries = initBufferManagerEntries(bufferInfos)

    check entries.len == 1
    # The model keeps the label raw; only the display line is sanitized.
    check entries[0].name == "[Terminal: bad\nname]"
    check '\n' notin formatLine(entries[0])
    check "[Terminal: bad name]" in formatLine(entries[0])

  test "an escape sequence in displayName is neutralized on display":
    let bufferInfos = @[
      BufferInfo(
        filePath: none(string),
        displayName: some("\x1b[2J"),
        isModified: false,
        isActive: false,
      )
    ]
    let entries = initBufferManagerEntries(bufferInfos)

    check entries.len == 1
    check entries[0].name == "\x1b[2J"
    check '\x1b' notin formatLine(entries[0])

suite "TextBuffer.matchRank - :b precedence":
  test "an authored alias outranks the path":
    let buf = newTextBuffer()
    buf.filePath = some("/tmp/bash")
    buf.matchAliases = @["bash"]
    check buf.matchRank("bash") == bmrAliasExact

  test "a whole path and its filename rank as the same exact match":
    let buf = newTextBuffer()
    buf.filePath = some("/tmp/dir/file.nim")
    check buf.matchRank("/tmp/dir/file.nim") == bmrPathExact
    check buf.matchRank("file.nim") == bmrPathExact

  test "a path partial never outranks an alias exact":
    let aliasExact = newTextBuffer()
    aliasExact.filePath = some("/tmp/bash_backup")
    aliasExact.matchAliases = @["bash"]
    let pathPartial = newTextBuffer()
    pathPartial.filePath = some("/tmp/bash")
    check aliasExact.matchRank("bash") > pathPartial.matchRank("bash")

  test "an alias partial outranks a path partial":
    let buf = newTextBuffer()
    buf.filePath = some("/tmp/bash_backup.log")
    buf.matchAliases = @["bash_backup"]
    check buf.matchRank("bash") == bmrAliasPartial

  test "the display label is never a match key":
    let buf = newTextBuffer()
    buf.displayName = some("[Terminal: bash]")
    buf.matchAliases = @["bash"]
    # The label's own text and any substring of it are not identity.
    check buf.matchRank("[Terminal: bash]") == bmrNone
    check buf.matchRank("Terminal") == bmrNone
    check buf.matchRank("bash") == bmrAliasExact

  test "rewriting the label leaves the rank unchanged":
    let buf = newTextBuffer()
    buf.displayName = some("[Terminal: bash]")
    buf.matchAliases = @["bash"]
    let before = buf.matchRank("bash")
    buf.displayName = some("session-1")
    check buf.matchRank("bash") == before

  test "an empty argument matches nothing":
    let buf = newTextBuffer()
    buf.filePath = some("/tmp/file.nim")
    buf.matchAliases = @["bash"]
    check buf.matchRank("") == bmrNone

suite "BufferEntry - number":
  test "each row carries the number of the buffer it describes":
    let first = newTextBuffer("/a", some("/tmp/a.nim"))
    let second = newTextBuffer("/b", some("/tmp/b.nim"))
    let entries =
      initBufferManagerEntries(@[first.toBufferInfo(true), second.toBufferInfo(false)])

    check entries.len == 2
    check entries[0].number == first.id.int
    check entries[1].number == second.id.int

suite "BufferManagerState - updateEntries":
  test "Update entries from buffer info":
    let state = newBufferManagerState()
    let bufferInfos = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true),
      BufferInfo(filePath: some("/file2.nim"), isModified: true, isActive: false),
    ]

    state.updateEntries(bufferInfos)

    check state.items.len == 2
    check state.items[0].name == "/file1.nim"
    check state.items[1].name == "/file2.nim"

  test "Update clamps selectedIndex when entries shrink":
    let state = newBufferManagerState()
    state.selectedIndex = 5

    let bufferInfos =
      @[BufferInfo(filePath: some("/file.nim"), isModified: false, isActive: true)]

    state.updateEntries(bufferInfos)

    check state.items.len == 1
    check state.selectedIndex == 0

  test "Update preserves valid selectedIndex":
    let state = newBufferManagerState()
    state.selectedIndex = 1

    let bufferInfos = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: false),
      BufferInfo(filePath: some("/file2.nim"), isModified: false, isActive: true),
      BufferInfo(filePath: some("/file3.nim"), isModified: false, isActive: false),
    ]

    state.updateEntries(bufferInfos)

    check state.items.len == 3
    check state.selectedIndex == 1

suite "BufferManagerState - Navigation":
  test "moveUp decreases selectedIndex":
    let state = newBufferManagerState()
    let bufferInfos = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: false),
      BufferInfo(filePath: some("/file2.nim"), isModified: false, isActive: true),
    ]
    state.updateEntries(bufferInfos)
    state.selectedIndex = 1

    state.moveUp()

    check state.selectedIndex == 0

  test "moveUp at top stays at top":
    let state = newBufferManagerState()
    let bufferInfos =
      @[BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true)]
    state.updateEntries(bufferInfos)
    state.selectedIndex = 0

    state.moveUp()

    check state.selectedIndex == 0

  test "moveDown increases selectedIndex":
    let state = newBufferManagerState()
    let bufferInfos = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true),
      BufferInfo(filePath: some("/file2.nim"), isModified: false, isActive: false),
    ]
    state.updateEntries(bufferInfos)
    state.selectedIndex = 0

    state.moveDown()

    check state.selectedIndex == 1

  test "moveDown at bottom stays at bottom":
    let state = newBufferManagerState()
    let bufferInfos =
      @[BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true)]
    state.updateEntries(bufferInfos)
    state.selectedIndex = 0

    state.moveDown()

    check state.selectedIndex == 0

  test "moveDown multiple times":
    let state = newBufferManagerState()
    let bufferInfos = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true),
      BufferInfo(filePath: some("/file2.nim"), isModified: false, isActive: false),
      BufferInfo(filePath: some("/file3.nim"), isModified: false, isActive: false),
    ]
    state.updateEntries(bufferInfos)
    state.selectedIndex = 0

    state.moveDown()
    state.moveDown()

    check state.selectedIndex == 2

    # Should not go beyond last entry
    state.moveDown()
    check state.selectedIndex == 2

suite "BufferManagerState - getSelectedItem":
  test "Get selected entry returns correct entry":
    let state = newBufferManagerState()
    let bufferInfos = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: false),
      BufferInfo(filePath: some("/file2.nim"), isModified: true, isActive: true),
    ]
    state.updateEntries(bufferInfos)
    state.selectedIndex = 1

    let entry = state.getSelectedItem()

    check entry.isSome
    check entry.get.name == "/file2.nim"
    check entry.get.modified == true
    check entry.get.active == true

  test "Get selected entry from empty state returns none":
    let state = newBufferManagerState()

    let entry = state.getSelectedItem()

    check entry.isNone

  test "Get selected entry with invalid index returns none":
    let state = newBufferManagerState()
    let bufferInfos =
      @[BufferInfo(filePath: some("/file.nim"), isModified: false, isActive: true)]
    state.updateEntries(bufferInfos)
    state.selectedIndex = 10 # Invalid index

    let entry = state.getSelectedItem()

    check entry.isNone

  test "Get selected entry with negative index returns none":
    let state = newBufferManagerState()
    let bufferInfos =
      @[BufferInfo(filePath: some("/file.nim"), isModified: false, isActive: true)]
    state.updateEntries(bufferInfos)
    state.selectedIndex = -1

    let entry = state.getSelectedItem()

    check entry.isNone

suite "BufferEntry - formatLine":
  test "Format active unmodified entry":
    let entry =
      BufferEntry(number: 0, name: "/path/to/file.nim", modified: false, active: true)

    let formatted = formatLine(entry)

    check formatted == "* 0:     /path/to/file.nim"

  test "Format inactive modified entry":
    let entry =
      BufferEntry(number: 1, name: "/path/to/file.nim", modified: true, active: false)

    let formatted = formatLine(entry)

    check formatted == "  1: [+] /path/to/file.nim"

  test "Format active modified entry":
    let entry =
      BufferEntry(number: 2, name: "/path/to/file.nim", modified: true, active: true)

    let formatted = formatLine(entry)

    check formatted == "* 2: [+] /path/to/file.nim"

  test "Format inactive unmodified entry":
    let entry =
      BufferEntry(number: 3, name: "/path/to/file.nim", modified: false, active: false)

    let formatted = formatLine(entry)

    check formatted == "  3:     /path/to/file.nim"

  test "Format entry with No Name":
    let entry = BufferEntry(number: 0, name: "No Name", modified: false, active: true)

    let formatted = formatLine(entry)

    check formatted == "* 0:     No Name"

suite "BufferManagerState - Integration":
  test "Full workflow: create, update, navigate, select":
    let state = newBufferManagerState()

    # Initial state
    check state.items.len == 0

    # Add some buffers
    let bufferInfos = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true),
      BufferInfo(filePath: some("/file2.nim"), isModified: true, isActive: false),
      BufferInfo(filePath: some("/file3.nim"), isModified: false, isActive: false),
    ]
    state.updateEntries(bufferInfos)

    check state.items.len == 3
    check state.selectedIndex == 0

    # Navigate down
    state.moveDown()
    check state.selectedIndex == 1

    # Get selected entry
    let entry = state.getSelectedItem()
    check entry.isSome
    check entry.get.name == "/file2.nim"

    # Navigate to end
    state.moveDown()
    check state.selectedIndex == 2

    # Try to go past end
    state.moveDown()
    check state.selectedIndex == 2

    # Navigate back to top
    state.moveUp()
    state.moveUp()
    check state.selectedIndex == 0

    # Try to go before start
    state.moveUp()
    check state.selectedIndex == 0

  test "Update entries while navigated":
    let state = newBufferManagerState()

    # Initial buffers
    let bufferInfos1 = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true),
      BufferInfo(filePath: some("/file2.nim"), isModified: false, isActive: false),
      BufferInfo(filePath: some("/file3.nim"), isModified: false, isActive: false),
    ]
    state.updateEntries(bufferInfos1)
    state.selectedIndex = 2

    # Remove a buffer (simulate closing)
    let bufferInfos2 = @[
      BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true),
      BufferInfo(filePath: some("/file3.nim"), isModified: false, isActive: false),
    ]
    state.updateEntries(bufferInfos2)

    # selectedIndex should be clamped
    check state.items.len == 2
    check state.selectedIndex == 1
