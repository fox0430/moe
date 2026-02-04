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

## Tests for editor_render_modes.nim

import std/[unittest, options, times]
import pkg/celina
import
  ../src/moepkg/[
    editor, config, config_loader, filer, buffer_manager, diff_viewer, recent_file_mode,
    backup_manager, debug_viewer, help_viewer, config_mode, references_viewer,
    documentsymbol_viewer, callhierarchy_viewer,
  ]
import ../src/moepkg/editor_render_modes

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestBuffer(): Buffer =
  ## Create a minimal Celina Buffer for testing
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

suite "renderFiler - Basic behavior":
  test "Render with no filer state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # FilerState is None by default
    check e.windowManager.windows[e.windowManager.activeWindowIndex].filerState.isNone

    # Should not crash
    e.renderFiler(buffer, e.activeWindow, true, 0)

  test "Render with empty filer state":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Set up a filer state with no entries
    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/tmp",
        entries: @[],
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    # Should not crash
    e.renderFiler(buffer, e.activeWindow, true, 0)

  test "Render filer with entries":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Create test entries
    let entries =
      @[
        FileEntry(
          name: "test_dir",
          kind: fekDirectory,
          size: 4096,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekDirectory,
        ),
        FileEntry(
          name: "test_file.txt",
          kind: fekFile,
          size: 1024,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
      ]

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/tmp/test",
        entries: entries,
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    # Should not crash and should update screen cursor
    e.renderFiler(buffer, e.activeWindow, true, 0)

    # Verify screen cursor was set
    check e.state.screenCursor.y >= 0

  test "Render filer with hidden files":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let entries =
      @[
        FileEntry(
          name: ".hidden_file",
          kind: fekFile,
          size: 100,
          modified: getTime(),
          isHidden: true,
          isExecutable: false,
          targetKind: fekFile,
        )
      ]

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/home",
        entries: entries,
        selectedIndex: 0,
        showHidden: true,
        topLine: 0,
        previousPath: none(string),
      )
    )

    e.renderFiler(buffer, e.activeWindow, true, 0)

  test "Render filer with symlink":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let entries =
      @[
        FileEntry(
          name: "link_to_dir",
          kind: fekSymlink,
          size: 0,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekDirectory,
        ),
        FileEntry(
          name: "link_to_file",
          kind: fekSymlink,
          size: 0,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
      ]

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/home",
        entries: entries,
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    e.renderFiler(buffer, e.activeWindow, true, 0)

  test "Render filer with executable file":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let entries =
      @[
        FileEntry(
          name: "run.sh",
          kind: fekFile,
          size: 512,
          modified: getTime(),
          isHidden: false,
          isExecutable: true,
          targetKind: fekFile,
        )
      ]

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/usr/bin",
        entries: entries,
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    e.renderFiler(buffer, e.activeWindow, true, 0)

  test "Render filer with long path truncation":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Create a very long path that exceeds buffer width
    let longPath =
      "/home/user/very/long/path/that/should/be/truncated/somewhere/in/the/middle/of/the/path/display/area"

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: longPath,
        entries: @[],
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    e.renderFiler(buffer, e.activeWindow, true, 0)

suite "renderBufferManager - Basic behavior":
  test "Render with no buffer manager state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    check e.windowManager.windows[e.windowManager.activeWindowIndex].bufferManagerState.isNone
    e.renderBufferManager(buffer)

  test "Render with empty buffer manager state":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let bmState = newBufferManagerState()
    e.windowManager.windows[e.windowManager.activeWindowIndex].bufferManagerState =
      some(bmState)

    e.renderBufferManager(buffer)

  test "Render buffer manager with entries":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let bmState = newBufferManagerState()
    bmState.entries =
      @[
        BufferEntry(index: 0, name: "file1.txt", modified: false, active: true),
        BufferEntry(index: 1, name: "file2.nim", modified: true, active: false),
        BufferEntry(index: 2, name: "No Name", modified: false, active: false),
      ]
    bmState.selectedIndex = 1

    e.windowManager.windows[e.windowManager.activeWindowIndex].bufferManagerState =
      some(bmState)

    e.renderBufferManager(buffer)
    check e.state.screenCursor.y >= 0

  test "Render buffer manager with scroll position":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let bmState = newBufferManagerState()
    # Create many entries to trigger scrolling
    for i in 0 ..< 50:
      bmState.entries.add(
        BufferEntry(
          index: i,
          name: "buffer_" & $i & ".txt",
          modified: i mod 3 == 0,
          active: i == 0,
        )
      )
    bmState.selectedIndex = 45
    bmState.topLine = 40

    e.windowManager.windows[e.windowManager.activeWindowIndex].bufferManagerState =
      some(bmState)

    e.renderBufferManager(buffer)

suite "renderBackupManager - Basic behavior":
  test "Render with no backup manager state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    check e.windowManager.windows[e.windowManager.activeWindowIndex].backupManagerState.isNone
    e.renderBackupManager(buffer)

  test "Render backup manager with empty entries":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let bkState = newBackupManagerState()
    bkState.sourceFilePath = "/tmp/test.txt"
    e.windowManager.windows[e.windowManager.activeWindowIndex].backupManagerState =
      some(bkState)

    e.renderBackupManager(buffer)
    # Should show "No backup files found" message

  test "Render backup manager with entries":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let bkState = newBackupManagerState()
    bkState.sourceFilePath = "/tmp/test.txt"
    bkState.entries =
      @[
        BackupEntry(
          filename: "20260128_120000",
          timestamp: now(),
          fullPath: "/tmp/backup/test.txt.1",
        ),
        BackupEntry(
          filename: "20260128_110000",
          timestamp: now() - initDuration(hours = 1),
          fullPath: "/tmp/backup/test.txt.2",
        ),
      ]
    bkState.selectedIndex = 0

    e.windowManager.windows[e.windowManager.activeWindowIndex].backupManagerState =
      some(bkState)

    e.renderBackupManager(buffer)
    check e.state.screenCursor.y >= 0

suite "renderDiffViewer - Basic behavior":
  test "Render with no diff viewer state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    check e.windowManager.windows[e.windowManager.activeWindowIndex].diffViewerState.isNone
    e.renderDiffViewer(buffer)

  test "Render diff viewer with empty lines":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let dvState = newDiffViewerState()
    dvState.sourceFilePath = "/tmp/current.txt"
    dvState.backupFilePath = "/tmp/backup.txt"
    e.windowManager.windows[e.windowManager.activeWindowIndex].diffViewerState =
      some(dvState)

    e.renderDiffViewer(buffer)
    # Should show "No diff content" message

  test "Render diff viewer with diff lines":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let dvState = newDiffViewerState()
    dvState.sourceFilePath = "/tmp/current.txt"
    dvState.backupFilePath = "/tmp/backup.txt"
    dvState.lines =
      @[
        DiffLine(text: "diff --git a/file.txt b/file.txt", kind: dlkMeta),
        DiffLine(text: "--- a/file.txt", kind: dlkHeader),
        DiffLine(text: "+++ b/file.txt", kind: dlkHeader),
        DiffLine(text: "@@ -1,3 +1,4 @@", kind: dlkHeader),
        DiffLine(text: " unchanged line", kind: dlkNormal),
        DiffLine(text: "-removed line", kind: dlkDeleted),
        DiffLine(text: "+added line", kind: dlkAdded),
      ]
    dvState.selectedLine = 4

    e.windowManager.windows[e.windowManager.activeWindowIndex].diffViewerState =
      some(dvState)

    e.renderDiffViewer(buffer)
    check e.state.screenCursor.y >= 0

suite "renderRecentFileMode - Basic behavior":
  test "Render recent file mode with empty files":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # RecentFileModeState is not Option-wrapped
    e.recentFileModeState.files = @[]
    e.recentFileModeState.selectedIndex = 0
    e.recentFileModeState.topLine = 0

    e.renderRecentFileMode(buffer)

  test "Render recent file mode with files":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.recentFileModeState.files =
      @[
        RecentFileEntry(path: "/home/user/document.txt"),
        RecentFileEntry(path: "/tmp/nonexistent_file.txt"),
        RecentFileEntry(path: "/etc/hosts"),
      ]
    e.recentFileModeState.selectedIndex = 1

    e.renderRecentFileMode(buffer)
    check e.state.screenCursor.y >= 0

suite "renderDebugMode - Basic behavior":
  test "Render with no debug viewer state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let window = e.windowManager.windows[e.windowManager.activeWindowIndex]

    check window.debugViewerState.isNone
    e.renderDebugMode(buffer, window, isBottomWindow = true, tabLineOffset = 0)

  test "Render debug mode with empty lines":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let window = e.windowManager.windows[e.windowManager.activeWindowIndex]

    let debugState = newDebugViewerState()
    window.debugViewerState = some(debugState)

    e.renderDebugMode(buffer, window, isBottomWindow = true, tabLineOffset = 0)

  test "Render debug mode with debug information":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let window = e.windowManager.windows[e.windowManager.activeWindowIndex]

    let debugState = newDebugViewerState()
    debugState.lines =
      @[
        "-- EDITOR STATE --", "Mode: Normal", "Cursor: 0, 0", "-- BUFFER INFO --",
        "Lines: 100", "Modified: false",
      ]
    debugState.selectedLine = 2

    window.debugViewerState = some(debugState)

    e.renderDebugMode(buffer, window, isBottomWindow = true, tabLineOffset = 0)
    check e.state.screenCursor.y >= 0

suite "renderReferencesViewer - Basic behavior":
  test "Render with no references viewer state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    check e.windowManager.windows[e.windowManager.activeWindowIndex].referencesViewerState.isNone
    e.renderReferencesViewer(buffer)

  test "Render references viewer with items":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let items =
      @[
        ReferenceItem(path: "/src/main.nim", line: 10, column: 5, text: "proc foo() ="),
        ReferenceItem(path: "/src/utils.nim", line: 25, column: 8, text: "  foo()"),
      ]
    let refState = newReferencesViewerState(items, "REFERENCES")

    e.windowManager.windows[e.windowManager.activeWindowIndex].referencesViewerState =
      some(refState)

    e.renderReferencesViewer(buffer)
    check e.state.screenCursor.y >= 0

suite "renderDocumentSymbolViewer - Basic behavior":
  test "Render with no document symbol viewer state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    check e.windowManager.windows[e.windowManager.activeWindowIndex].documentSymbolViewerState.isNone
    e.renderDocumentSymbolViewer(buffer)

  test "Render document symbol viewer with empty items":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Create state with empty items directly
    let symState = DocumentSymbolViewerState(
      items: @[], selectedIndex: 0, topLine: 0, filePath: "/test/file.nim"
    )

    e.windowManager.windows[e.windowManager.activeWindowIndex].documentSymbolViewerState =
      some(symState)

    e.renderDocumentSymbolViewer(buffer)

suite "renderCallHierarchyViewer - Basic behavior":
  test "Render with no call hierarchy viewer state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    check e.windowManager.windows[e.windowManager.activeWindowIndex].callHierarchyViewerState.isNone
    e.renderCallHierarchyViewer(buffer)

  test "Render call hierarchy viewer with empty items":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Create state with empty items using the constructor
    let chState = newCallHierarchyViewerState(@[], chvkIncoming)

    e.windowManager.windows[e.windowManager.activeWindowIndex].callHierarchyViewerState =
      some(chState)

    e.renderCallHierarchyViewer(buffer)

suite "renderHelpViewer - Basic behavior":
  test "Render with no help viewer state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    check e.windowManager.windows[e.windowManager.activeWindowIndex].helpViewerState.isNone
    e.renderHelpViewer(buffer, e.activeWindow, true, 0)

  test "Render help viewer with content":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let helpState = newHelpViewerState()
    helpState.lines =
      @[
        "# Moe Editor Help", "", "## Navigation", "h - move left", "j - move down",
        "k - move up", "l - move right", "", "## Editing", "i - insert mode",
        "a - append",
      ]
    helpState.selectedIndex = 3

    e.windowManager.windows[e.windowManager.activeWindowIndex].helpViewerState =
      some(helpState)

    e.renderHelpViewer(buffer, e.activeWindow, true, 0)
    check e.state.screenCursor.y >= 0

  test "Render help viewer with header styling":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let helpState = newHelpViewerState()
    helpState.lines = @["# Main Header", "Regular line", "# Another Header"]
    helpState.selectedIndex = 0

    e.windowManager.windows[e.windowManager.activeWindowIndex].helpViewerState =
      some(helpState)

    e.renderHelpViewer(buffer, e.activeWindow, true, 0)

suite "Filer - Various file types with icons":
  test "Render filer with various file extensions":
    let e = createTestEditor()
    e.config.filer.showIcons = true
    var buffer = createTestBuffer()

    # Create entries with various file extensions
    let entries =
      @[
        FileEntry(
          name: "main.nim",
          kind: fekFile,
          size: 1000,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "script.py",
          kind: fekFile,
          size: 500,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "app.js",
          kind: fekFile,
          size: 2000,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "README.md",
          kind: fekFile,
          size: 300,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "Dockerfile",
          kind: fekFile,
          size: 100,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "config.toml",
          kind: fekFile,
          size: 200,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "archive.zip",
          kind: fekFile,
          size: 50000,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "image.png",
          kind: fekFile,
          size: 10000,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "video.mp4",
          kind: fekFile,
          size: 100000,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "music.mp3",
          kind: fekFile,
          size: 5000,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "unknown",
          kind: fekFile,
          size: 100,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
      ]

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/test",
        entries: entries,
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    e.renderFiler(buffer, e.activeWindow, true, 0)

  test "Render filer without icons":
    let e = createTestEditor()
    e.config.filer.showIcons = false
    var buffer = createTestBuffer()

    let entries =
      @[
        FileEntry(
          name: "dir",
          kind: fekDirectory,
          size: 4096,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekDirectory,
        ),
        FileEntry(
          name: "link",
          kind: fekSymlink,
          size: 0,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "file.txt",
          kind: fekFile,
          size: 100,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
      ]

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/test",
        entries: entries,
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    e.renderFiler(buffer, e.activeWindow, true, 0)

suite "Status line visibility":
  test "Render modes with status line hidden":
    var config = newEditorConfig()
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.display.showStatusLine = false

    var buffer = createTestBuffer()

    # Test filer
    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/tmp",
        entries: @[],
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )
    e.renderFiler(buffer, e.activeWindow, true, 0)

    # Test buffer manager
    let bmState = newBufferManagerState()
    e.windowManager.windows[e.windowManager.activeWindowIndex].bufferManagerState =
      some(bmState)
    e.renderBufferManager(buffer)

  test "Render modes with status line shown":
    var config = newEditorConfig()
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.display.showStatusLine = true

    var buffer = createTestBuffer()

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/tmp",
        entries: @[],
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )
    e.renderFiler(buffer, e.activeWindow, true, 0)

suite "Screen cursor positioning":
  test "Filer cursor position changes with selection":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let entries =
      @[
        FileEntry(
          name: "file1.txt",
          kind: fekFile,
          size: 100,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "file2.txt",
          kind: fekFile,
          size: 200,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
        FileEntry(
          name: "file3.txt",
          kind: fekFile,
          size: 300,
          modified: getTime(),
          isHidden: false,
          isExecutable: false,
          targetKind: fekFile,
        ),
      ]

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState = some(
      FilerState(
        currentPath: "/test",
        entries: entries,
        selectedIndex: 0,
        showHidden: false,
        topLine: 0,
        previousPath: none(string),
      )
    )

    e.renderFiler(buffer, e.activeWindow, true, 0)
    let y0 = e.state.screenCursor.y

    e.windowManager.windows[e.windowManager.activeWindowIndex].filerState.get.selectedIndex =
      2
    e.renderFiler(buffer, e.activeWindow, true, 0)
    let y2 = e.state.screenCursor.y

    check y2 > y0

  test "Buffer manager cursor position changes with selection":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let bmState = newBufferManagerState()
    bmState.entries =
      @[
        BufferEntry(index: 0, name: "file1.txt", modified: false, active: true),
        BufferEntry(index: 1, name: "file2.txt", modified: false, active: false),
        BufferEntry(index: 2, name: "file3.txt", modified: false, active: false),
      ]
    bmState.selectedIndex = 0

    e.windowManager.windows[e.windowManager.activeWindowIndex].bufferManagerState =
      some(bmState)

    e.renderBufferManager(buffer)
    let y0 = e.state.screenCursor.y

    bmState.selectedIndex = 2
    e.renderBufferManager(buffer)
    let y2 = e.state.screenCursor.y

    check y2 > y0

suite "renderConfig - Basic behavior":
  test "Render with no config state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # ConfigModeState is None by default
    check e.windowManager.windows[e.windowManager.activeWindowIndex].configModeState.isNone

    # Should not crash
    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render with config state":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Set up config mode state
    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].configModeState =
      some(configState)

    # Should not crash
    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render config with selection":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let configState = newConfigModeState(e.config)
    configState.selectedIndex = 1
    e.windowManager.windows[e.windowManager.activeWindowIndex].configModeState =
      some(configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render config with status line hidden":
    var config = newEditorConfig()
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.display.showStatusLine = false
    var buffer = createTestBuffer()

    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].configModeState =
      some(configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render config with status line shown":
    var config = newEditorConfig()
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.display.showStatusLine = true
    var buffer = createTestBuffer()

    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].configModeState =
      some(configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)
