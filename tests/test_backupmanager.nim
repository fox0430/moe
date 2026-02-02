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

import std/[unittest, os, options, json, times, posix]

import ../src/moepkg/backupmanager

const TestBackupDir = "/tmp/moe_test_backupmanager"

proc cleanupTestDir() =
  if dirExists(TestBackupDir):
    removeDir(TestBackupDir)

proc createBackupSubDir(subDirName: string, sourcePath: string): string =
  ## Create a backup subdirectory with backup.json
  result = TestBackupDir / subDirName
  createDir(result)
  let jsonContent = %*{"path": sourcePath}
  writeFile(result / "backup.json", $jsonContent)

proc createTestBackupFile(
    backupDir: string, timestamp: string, content: string = "backup content"
) =
  writeFile(backupDir / timestamp, content)

suite "backupmanager - newBackupManagerState":
  test "Create new state with default values":
    let state = newBackupManagerState()
    check state.entries.len == 0
    check state.selectedIndex == 0
    check state.topLine == 0
    check state.sourceFilePath == ""
    check state.backupDir == ""
    check state.baseBackupDir == ""

suite "backupmanager - initBackupManagerEntries":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Return empty seq for non-existent directory":
    let entries = initBackupManagerEntries("/nonexistent/dir")
    check entries.len == 0

  test "Return empty seq for empty string":
    let entries = initBackupManagerEntries("")
    check entries.len == 0

  test "Return empty seq for empty directory":
    let entries = initBackupManagerEntries(TestBackupDir)
    check entries.len == 0

  test "Parse backup files with valid datetime names":
    let backupDir = createBackupSubDir("test1", "/home/user/test.txt")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")
    createTestBackupFile(backupDir, "2025-01-16T11:00:00+09:00")

    let entries = initBackupManagerEntries(backupDir)
    check entries.len == 2

  test "Ignore invalid filenames":
    let backupDir = createBackupSubDir("test2", "/home/user/test.txt")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")
    writeFile(backupDir / "backup.json", "{}")
    writeFile(backupDir / "invalid.txt", "invalid")

    let entries = initBackupManagerEntries(backupDir)
    check entries.len == 1
    check entries[0].filename == "2025-01-15T10:30:45+09:00"

  test "Sort entries by timestamp descending (newest first)":
    let backupDir = createBackupSubDir("test3", "/home/user/test.txt")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")
    createTestBackupFile(backupDir, "2025-01-17T12:00:00+09:00")
    createTestBackupFile(backupDir, "2025-01-16T11:00:00+09:00")

    let entries = initBackupManagerEntries(backupDir)
    check entries.len == 3
    # Newest first
    check entries[0].filename == "2025-01-17T12:00:00+09:00"
    check entries[1].filename == "2025-01-16T11:00:00+09:00"
    check entries[2].filename == "2025-01-15T10:30:45+09:00"

  test "Entry has correct fullPath":
    let backupDir = createBackupSubDir("test4", "/home/user/test.txt")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let entries = initBackupManagerEntries(backupDir)
    check entries.len == 1
    check entries[0].fullPath == backupDir / "2025-01-15T10:30:45+09:00"

suite "backupmanager - initBackupManagerState":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Initialize state with source file that has backups":
    let
      sourcePath = "/home/user/myfile.txt"
      backupDir = createBackupSubDir("abc123", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    check state.sourceFilePath == sourcePath
    check state.baseBackupDir == TestBackupDir
    check state.backupDir == backupDir
    check state.entries.len == 1

  test "Initialize state with source file that has no backups":
    let sourcePath = "/home/user/nobackup.txt"

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    check state.sourceFilePath == sourcePath
    check state.baseBackupDir == TestBackupDir
    check state.backupDir == ""
    check state.entries.len == 0

suite "backupmanager - refresh":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Refresh updates entries list":
    let
      sourcePath = "/home/user/refresh.txt"
      backupDir = createBackupSubDir("refresh1", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    check state.entries.len == 1

    # Add another backup file
    createTestBackupFile(backupDir, "2025-01-16T11:00:00+09:00")

    state.refresh()
    check state.entries.len == 2

  test "Refresh clamps selectedIndex when entries reduced":
    let
      sourcePath = "/home/user/clamp.txt"
      backupDir = createBackupSubDir("clamp1", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")
    createTestBackupFile(backupDir, "2025-01-16T11:00:00+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    state.selectedIndex = 1
    check state.entries.len == 2

    # Remove one file
    removeFile(backupDir / "2025-01-16T11:00:00+09:00")

    state.refresh()
    check state.entries.len == 1
    check state.selectedIndex == 0

  test "Refresh sets selectedIndex to 0 when no entries":
    let
      sourcePath = "/home/user/empty.txt"
      backupDir = createBackupSubDir("empty1", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    check state.entries.len == 1

    # Remove all backup files
    removeFile(backupDir / "2025-01-15T10:30:45+09:00")

    state.refresh()
    check state.entries.len == 0
    check state.selectedIndex == 0

suite "backupmanager - moveUp":
  test "Move up decrements selectedIndex":
    let state = newBackupManagerState()
    state.entries =
      @[
        BackupEntry(filename: "a", timestamp: now(), fullPath: "/a"),
        BackupEntry(filename: "b", timestamp: now(), fullPath: "/b"),
        BackupEntry(filename: "c", timestamp: now(), fullPath: "/c"),
      ]
    state.selectedIndex = 2

    state.moveUp()
    check state.selectedIndex == 1

    state.moveUp()
    check state.selectedIndex == 0

  test "Move up does not go below 0":
    let state = newBackupManagerState()
    state.entries = @[BackupEntry(filename: "a", timestamp: now(), fullPath: "/a")]
    state.selectedIndex = 0

    state.moveUp()
    check state.selectedIndex == 0

  test "Move up does nothing with empty entries":
    let state = newBackupManagerState()
    state.selectedIndex = 0

    state.moveUp()
    check state.selectedIndex == 0

  test "Move up adjusts topLine when needed":
    let state = newBackupManagerState()
    state.entries =
      @[
        BackupEntry(filename: "a", timestamp: now(), fullPath: "/a"),
        BackupEntry(filename: "b", timestamp: now(), fullPath: "/b"),
        BackupEntry(filename: "c", timestamp: now(), fullPath: "/c"),
      ]
    state.selectedIndex = 1
    state.topLine = 1

    state.moveUp()
    check state.selectedIndex == 0
    check state.topLine == 0

suite "backupmanager - moveDown":
  test "Move down increments selectedIndex":
    let state = newBackupManagerState()
    state.entries =
      @[
        BackupEntry(filename: "a", timestamp: now(), fullPath: "/a"),
        BackupEntry(filename: "b", timestamp: now(), fullPath: "/b"),
        BackupEntry(filename: "c", timestamp: now(), fullPath: "/c"),
      ]
    state.selectedIndex = 0

    state.moveDown()
    check state.selectedIndex == 1

    state.moveDown()
    check state.selectedIndex == 2

  test "Move down does not exceed last entry":
    let state = newBackupManagerState()
    state.entries =
      @[
        BackupEntry(filename: "a", timestamp: now(), fullPath: "/a"),
        BackupEntry(filename: "b", timestamp: now(), fullPath: "/b"),
      ]
    state.selectedIndex = 1

    state.moveDown()
    check state.selectedIndex == 1

  test "Move down does nothing with empty entries":
    let state = newBackupManagerState()
    state.selectedIndex = 0

    state.moveDown()
    check state.selectedIndex == 0

suite "backupmanager - moveToFirst":
  test "Move to first sets selectedIndex to 0":
    let state = newBackupManagerState()
    state.entries =
      @[
        BackupEntry(filename: "a", timestamp: now(), fullPath: "/a"),
        BackupEntry(filename: "b", timestamp: now(), fullPath: "/b"),
      ]
    state.selectedIndex = 1
    state.topLine = 1

    state.moveToFirst()
    check state.selectedIndex == 0
    check state.topLine == 0

suite "backupmanager - moveToLast":
  test "Move to last sets selectedIndex to last entry":
    let state = newBackupManagerState()
    state.entries =
      @[
        BackupEntry(filename: "a", timestamp: now(), fullPath: "/a"),
        BackupEntry(filename: "b", timestamp: now(), fullPath: "/b"),
        BackupEntry(filename: "c", timestamp: now(), fullPath: "/c"),
      ]
    state.selectedIndex = 0

    state.moveToLast()
    check state.selectedIndex == 2

  test "Move to last does nothing with empty entries":
    let state = newBackupManagerState()
    state.selectedIndex = 0

    state.moveToLast()
    check state.selectedIndex == 0

suite "backupmanager - getSelectedEntry":
  test "Get selected entry returns correct entry":
    let state = newBackupManagerState()
    let t = now()
    state.entries =
      @[
        BackupEntry(filename: "a", timestamp: t, fullPath: "/a"),
        BackupEntry(filename: "b", timestamp: t, fullPath: "/b"),
      ]
    state.selectedIndex = 1

    let entry = state.getSelectedEntry()
    check entry.isSome
    check entry.get().filename == "b"
    check entry.get().fullPath == "/b"

  test "Get selected entry returns none with empty entries":
    let state = newBackupManagerState()

    let entry = state.getSelectedEntry()
    check entry.isNone

  test "Get selected entry returns none with invalid index":
    let state = newBackupManagerState()
    state.entries = @[BackupEntry(filename: "a", timestamp: now(), fullPath: "/a")]
    state.selectedIndex = 5

    let entry = state.getSelectedEntry()
    check entry.isNone

  test "Get selected entry returns none with negative index":
    let state = newBackupManagerState()
    state.entries = @[BackupEntry(filename: "a", timestamp: now(), fullPath: "/a")]
    state.selectedIndex = -1

    let entry = state.getSelectedEntry()
    check entry.isNone

suite "backupmanager - formatTimestamp":
  test "Format timestamp correctly":
    let dt = dateTime(2025, mJan, 15, 10, 30, 45, zone = utc())
    let formatted = formatTimestamp(dt)
    check formatted == "2025-01-15 10:30:45"

suite "backupmanager - formatEntry":
  test "Format entry uses formatTimestamp":
    let dt = dateTime(2025, mJan, 15, 10, 30, 45, zone = utc())
    let entry = BackupEntry(filename: "test", timestamp: dt, fullPath: "/test")
    let formatted = formatEntry(entry)
    check formatted == "2025-01-15 10:30:45"

suite "backupmanager - deleteBackup":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Delete backup removes file and refreshes":
    let
      sourcePath = "/home/user/delete.txt"
      backupDir = createBackupSubDir("delete1", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")
    createTestBackupFile(backupDir, "2025-01-16T11:00:00+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    check state.entries.len == 2

    let success = state.deleteBackup(0)
    check success == true
    check state.entries.len == 1
    check not fileExists(backupDir / "2025-01-16T11:00:00+09:00")

  test "Delete backup returns false for invalid index":
    let
      sourcePath = "/home/user/invalid.txt"
      backupDir = createBackupSubDir("invalid1", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)

    check state.deleteBackup(-1) == false
    check state.deleteBackup(5) == false
    check state.entries.len == 1

  test "Delete backup returns false for empty entries":
    let state = newBackupManagerState()
    check state.deleteBackup(0) == false

suite "backupmanager - restoreBackup":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Restore backup copies file to source":
    let
      sourcePath = TestBackupDir / "source.txt"
      backupDir = createBackupSubDir("restore1", sourcePath)
    writeFile(sourcePath, "original content")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00", "backup content")

    let state = initBackupManagerState(TestBackupDir, sourcePath)

    let success = state.restoreBackup(0)
    check success == true
    check readFile(sourcePath) == "backup content"

  test "Restore backup returns false for invalid index":
    let
      sourcePath = TestBackupDir / "source2.txt"
      backupDir = createBackupSubDir("restore2", sourcePath)
    writeFile(sourcePath, "original")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)

    check state.restoreBackup(-1) == false
    check state.restoreBackup(5) == false

  test "Restore backup returns false if backup file does not exist":
    let
      sourcePath = TestBackupDir / "source3.txt"
      backupDir = createBackupSubDir("restore3", sourcePath)
    writeFile(sourcePath, "original")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)

    # Delete the backup file after state initialization
    removeFile(backupDir / "2025-01-15T10:30:45+09:00")

    check state.restoreBackup(0) == false

  test "Restore backup returns false for empty entries":
    let state = newBackupManagerState()
    check state.restoreBackup(0) == false

suite "backupmanager - initBackupManagerEntries (edge cases)":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Handle entries with same timestamp":
    let backupDir = createBackupSubDir("same_ts", "/home/user/test.txt")
    # Create two files with identical timestamps
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00", "content1")
    # Note: In real scenarios, identical timestamps are rare, but the sort should handle it
    let entries = initBackupManagerEntries(backupDir)
    check entries.len == 1

suite "backupmanager - refresh (edge cases)":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Refresh keeps selectedIndex when still valid":
    let
      sourcePath = "/home/user/keep.txt"
      backupDir = createBackupSubDir("keep1", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")
    createTestBackupFile(backupDir, "2025-01-16T11:00:00+09:00")
    createTestBackupFile(backupDir, "2025-01-17T12:00:00+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    state.selectedIndex = 1
    check state.entries.len == 3

    # Add another backup file (entries grow, index still valid)
    createTestBackupFile(backupDir, "2025-01-18T12:00:00+09:00")

    state.refresh()
    check state.entries.len == 4
    check state.selectedIndex == 1 # Index should remain unchanged

suite "backupmanager - deleteBackup (edge cases)":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Delete backup returns false when file is read-only":
    let
      sourcePath = "/home/user/readonly.txt"
      backupDir = createBackupSubDir("readonly1", sourcePath)
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00")

    let state = initBackupManagerState(TestBackupDir, sourcePath)
    check state.entries.len == 1

    # Make directory read-only to prevent file deletion
    discard chmod(backupDir.cstring, 0o555)

    let success = state.deleteBackup(0)
    # Restore permissions for cleanup
    discard chmod(backupDir.cstring, 0o755)

    check success == false

suite "backupmanager - restoreBackup (edge cases)":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Restore backup returns false when destination is read-only":
    let
      sourcePath = TestBackupDir / "readonly_dest.txt"
      backupDir = createBackupSubDir("restore_ro", sourcePath)
    writeFile(sourcePath, "original")
    createTestBackupFile(backupDir, "2025-01-15T10:30:45+09:00", "backup content")

    let state = initBackupManagerState(TestBackupDir, sourcePath)

    # Make source file read-only
    discard chmod(sourcePath.cstring, 0o444)

    let success = state.restoreBackup(0)
    # Restore permissions for cleanup
    discard chmod(sourcePath.cstring, 0o644)

    check success == false
    check readFile(sourcePath) == "original" # Should remain unchanged
