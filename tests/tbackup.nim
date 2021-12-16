import std/[unittest, times, os]
import moepkg/unicodeext
include moepkg/backup

suite "Backup: Generate filename":
  test "The same path that opened the editor":
    let
      time = now()
      filename = ru"test.nim"
      backupFilename = generateFilename(filename, time)

    check backupFilename == ru"test_" & ($time).toRunes & ru".nim"

  test "The path that opened the editor and a different path":
    let
      time = now()
      filename = ru"/tmp/hoge/test.nim"
      backupFilename = generateFilename(filename, time)

    check backupFilename == ru"test_" & ($time).toRunes & ru".nim"

  test "The path contains non-US-ASCII characters (issue #936)":
    let
      time = now()
      filename = ru"/tmp/ディレクトリ/test.nim"
      backupFilename = generateFilename(filename, time)

    check backupFilename == ru"test_" & ($time).toRunes & ru".nim"

suite "Backup: Generate backup dir":
  test "The same path that opened the editor":
    let
      time = now()
      filename = ru"test.nim"
      dir = checkAndCreateBackupDir(filename, ru"")

    check dir == ru".history"

  test "The path that opened the editor and a different path":
    let
      time = now()
      path = ru"/tmp/hoge/test.nim"
      dir = checkAndCreateBackupDir(path, ru"")

    check dir == ru"/tmp/hoge/.history"
