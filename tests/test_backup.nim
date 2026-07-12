import std/[unittest, os, options, json, strutils]
import pkg/results
import ../src/moepkg/[backup, buffer, config]

let TestBackupDir = getTempDir() / "moe_test_backup"

proc cleanupTestDir() =
  if dirExists(TestBackupDir):
    removeDir(TestBackupDir)

proc createTestConfig(
    backupDir: Option[string] = some(TestBackupDir), dirToExclude: seq[string] = @[]
): AutoBackupConfig =
  AutoBackupConfig(
    enable: true,
    backupDir: backupDir,
    idleTime: 1,
    interval: 1,
    dirToExclude: dirToExclude,
  )

suite "backup - expandBackupDir":
  test "Expand ~ to home directory":
    let result = expandBackupDir("~")
    check result == getHomeDir()

  test "Expand ~/path to home directory + path":
    let result = expandBackupDir("~/test/path")
    check result == getHomeDir() / "test/path"

  test "Return path unchanged if no ~":
    let result = expandBackupDir("/absolute/path")
    check result == "/absolute/path"

  test "Do not expand ~user (only ~ and ~/)":
    let result = expandBackupDir("~username/path")
    check result == "~username/path"

suite "backup - getBaseBackupDir":
  test "Return default backup dir when config has no backupDir":
    let config = AutoBackupConfig(
      enable: true, backupDir: none(string), idleTime: 1, interval: 1, dirToExclude: @[]
    )
    let result = getBaseBackupDir(config)
    check result == expandBackupDir(DefaultBackupDir)

  test "Return configured backupDir when set":
    let config = createTestConfig(some("/custom/backup/dir"))
    let result = getBaseBackupDir(config)
    check result == "/custom/backup/dir"

  test "Expand ~ in configured backupDir":
    let config = createTestConfig(some("~/my/backups"))
    let result = getBaseBackupDir(config)
    check result == getHomeDir() / "my/backups"

suite "backup - validateBackupFileName":
  test "Valid datetime filename":
    check validateBackupFileName("2025-01-15T10:30:45+09:00") == true

  test "Valid datetime filename with negative timezone":
    check validateBackupFileName("2025-01-15T10:30:45-05:00") == true

  test "Valid datetime filename with UTC":
    check validateBackupFileName("2025-01-15T10:30:45+00:00") == true

  test "Invalid filename - random string":
    check validateBackupFileName("not-a-date") == false

  test "Invalid filename - missing timezone":
    check validateBackupFileName("2025-01-15T10:30:45") == false

  test "Invalid filename - empty string":
    check validateBackupFileName("") == false

  test "Invalid filename - backup.json":
    check validateBackupFileName("backup.json") == false

suite "backup - getBackupFilesInDir":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Return empty seq for non-existent directory":
    let result = getBackupFilesInDir("/nonexistent/dir")
    check result.len == 0

  test "Return empty seq for empty directory":
    let result = getBackupFilesInDir(TestBackupDir)
    check result.len == 0

  test "Return backup files with valid datetime names":
    # Create valid backup files
    writeFile(TestBackupDir / "2025-01-15T10:30:45+09:00", "content1")
    writeFile(TestBackupDir / "2025-01-16T11:00:00+09:00", "content2")
    # Create invalid file (should be ignored)
    writeFile(TestBackupDir / "backup.json", "{}")
    writeFile(TestBackupDir / "invalid.txt", "invalid")

    let result = getBackupFilesInDir(TestBackupDir)
    check result.len == 2
    check "2025-01-15T10:30:45+09:00" in result
    check "2025-01-16T11:00:00+09:00" in result

  test "Return empty seq for empty path":
    let result = getBackupFilesInDir("")
    check result.len == 0

suite "backup - getBackupDirForSource and getBackupFiles":
  setup:
    cleanupTestDir()
    createDir(TestBackupDir)

  teardown:
    cleanupTestDir()

  test "Return empty string when base backup dir doesn't exist":
    cleanupTestDir()
    let result = getBackupDirForSource("/nonexistent", "/some/file.txt")
    check result == ""

  test "Return empty string when no matching backup exists":
    let result = getBackupDirForSource(TestBackupDir, "/some/file.txt")
    check result == ""

  test "Find existing backup directory for source file":
    # Create a backup directory with backup.json
    let backupSubDir = TestBackupDir / "abc123"
    createDir(backupSubDir)
    let jsonContent = %*{"path": "/home/user/test.txt"}
    writeFile(backupSubDir / "backup.json", $jsonContent)

    let result = getBackupDirForSource(TestBackupDir, "/home/user/test.txt")
    check result == backupSubDir

  test "Return empty string for different source file":
    let backupSubDir = TestBackupDir / "abc123"
    createDir(backupSubDir)
    let jsonContent = %*{"path": "/home/user/test.txt"}
    writeFile(backupSubDir / "backup.json", $jsonContent)

    let result = getBackupDirForSource(TestBackupDir, "/home/user/other.txt")
    check result == ""

  test "getBackupFiles returns files for existing source":
    let backupSubDir = TestBackupDir / "def456"
    createDir(backupSubDir)
    let jsonContent = %*{"path": "/home/user/myfile.txt"}
    writeFile(backupSubDir / "backup.json", $jsonContent)
    writeFile(backupSubDir / "2025-01-15T10:30:45+09:00", "backup content")

    let files = getBackupFiles(TestBackupDir, "/home/user/myfile.txt")
    check files.len == 1
    check "2025-01-15T10:30:45+09:00" in files

  test "getBackupFiles returns empty seq for non-existent source":
    let files = getBackupFiles(TestBackupDir, "/nonexistent/file.txt")
    check files.len == 0

  test "Find existing backup directory when baseBackupDir contains glob metachars":
    # baseBackupDir with `[`, `*`, `?` must be treated as a literal path,
    # not as a glob pattern. Previously walkPattern would fail to match
    # and callers would create a fresh Oid dir on every launch,
    # splitting the backup history.
    let bracketDir = getTempDir() / "moe_test_backup[bracket]*?"
    if dirExists(bracketDir):
      removeDir(bracketDir)
    createDir(bracketDir)
    defer:
      removeDir(bracketDir)

    let backupSubDir = bracketDir / "abc123"
    createDir(backupSubDir)
    let jsonContent = %*{"path": "/home/user/glob.txt"}
    writeFile(backupSubDir / "backup.json", $jsonContent)

    let result = getBackupDirForSource(bracketDir, "/home/user/glob.txt")
    check result == backupSubDir

suite "backup - backupBuffer":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Return error when buffer has no file path":
    let
      buf = newTextBuffer()
      config = createTestConfig()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "test content")

    let result = backupBuffer(buf.filePath, buf.getTextString(), config)
    check result.isErr
    check result.error == "No file path"

  test "Successfully backup buffer with file path":
    let testSourceFile = getTempDir() / "moe_test_source.txt"
    writeFile(testSourceFile, "original content")

    let buf = newTextBuffer()
    discard buf.loadFile(testSourceFile)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "new ")

    let config = createTestConfig()
    let result = backupBuffer(buf.filePath, buf.getTextString(), config)

    check result.isOk
    check result.get().startsWith(TestBackupDir)
    check fileExists(result.get())

    # Verify backup content
    let backupContent = readFile(result.get())
    check "new " in backupContent

    removeFile(testSourceFile)

  test "Return error when directory is excluded":
    let testSourceFile = getTempDir() / "excluded/test.txt"
    createDir(getTempDir() / "excluded")
    writeFile(testSourceFile, "content")

    let buf = newTextBuffer()
    discard buf.loadFile(testSourceFile)

    let config = createTestConfig(dirToExclude = @[getTempDir() / "excluded"])
    let result = backupBuffer(buf.filePath, buf.getTextString(), config)

    check result.isErr
    check result.error == "Directory excluded from backup"

    removeFile(testSourceFile)
    removeDir(getTempDir() / "excluded")

  test "Return error when subdirectory is excluded":
    let testSourceFile = getTempDir() / "excluded/subdir/test.txt"
    createDir(getTempDir() / "excluded/subdir")
    writeFile(testSourceFile, "content")

    let buf = newTextBuffer()
    discard buf.loadFile(testSourceFile)

    let config = createTestConfig(dirToExclude = @[getTempDir() / "excluded"])
    let result = backupBuffer(buf.filePath, buf.getTextString(), config)

    check result.isErr
    check result.error == "Directory excluded from backup"

    removeFile(testSourceFile)
    removeDir(getTempDir() / "excluded/subdir")
    removeDir(getTempDir() / "excluded")

  test "Do not backup when content unchanged":
    let testSourceFile = getTempDir() / "moe_test_unchanged.txt"
    writeFile(testSourceFile, "same content")

    let buf = newTextBuffer()
    discard buf.loadFile(testSourceFile)

    let config = createTestConfig()

    # First backup should succeed
    let result1 = backupBuffer(buf.filePath, buf.getTextString(), config)
    check result1.isOk

    # Second backup without changes should fail
    let result2 = backupBuffer(buf.filePath, buf.getTextString(), config)
    check result2.isErr
    check result2.error == "No changes since last backup"

    removeFile(testSourceFile)

  test "Create new backup when content changed":
    let testSourceFile = getTempDir() / "moe_test_changed.txt"
    writeFile(testSourceFile, "initial")

    let buf = newTextBuffer()
    discard buf.loadFile(testSourceFile)

    let config = createTestConfig()

    # First backup
    let result1 = backupBuffer(buf.filePath, buf.getTextString(), config)
    check result1.isOk

    # Modify buffer
    discard buf.insertText(BufferPosition(line: 0, column: 0), "modified ")

    # Sleep to ensure different timestamp
    sleep(1100)

    # Second backup should succeed
    let result2 = backupBuffer(buf.filePath, buf.getTextString(), config)
    check result2.isOk
    check result1.get() != result2.get()

    removeFile(testSourceFile)

  test "Reuse existing backup directory for same source file":
    let testSourceFile = getTempDir() / "moe_test_reuse.txt"
    writeFile(testSourceFile, "content v1")

    let buf = newTextBuffer()
    discard buf.loadFile(testSourceFile)

    let config = createTestConfig()

    # First backup
    let result1 = backupBuffer(buf.filePath, buf.getTextString(), config)
    check result1.isOk
    let backupDir1 = result1.get().parentDir

    # Modify and backup again
    discard buf.insertText(BufferPosition(line: 0, column: 0), "v2 ")
    sleep(1100)

    let result2 = backupBuffer(buf.filePath, buf.getTextString(), config)
    check result2.isOk
    let backupDir2 = result2.get().parentDir

    # Should use the same backup directory
    check backupDir1 == backupDir2

    removeFile(testSourceFile)

  test "Exclude pattern should not match partial directory names":
    # Excluding /etc should not exclude /etcfoo
    let testSourceFile = getTempDir() / "etcfoo/test.txt"
    createDir(getTempDir() / "etcfoo")
    writeFile(testSourceFile, "content")

    let buf = newTextBuffer()
    discard buf.loadFile(testSourceFile)

    let config = createTestConfig(dirToExclude = @[getTempDir() / "etc"])
    let result = backupBuffer(buf.filePath, buf.getTextString(), config)

    # Should succeed because /tmp/etcfoo is not /tmp/etc
    check result.isOk

    removeFile(testSourceFile)
    removeDir(getTempDir() / "etcfoo")
