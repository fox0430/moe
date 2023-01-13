import std/[unittest, times, os, json, oids]
import moepkg/unicodeext

import moepkg/backup {.all.}

suite "Backup: createDir":
  test "createDir":
    let dirName = $now()

    check createDir(dirName.toRunes)
    check dirExists(dirName)

    # Clean up
    removeDir(dirName)

  test "createDir 2":
    let dirName = $now()

    os.createDir(dirName)

    let r = createDir(dirName.toRunes)

    # Clean up
    removeDir(dirName)

    check r

suite "Backup: validateBackupJson":
  test "validateBackupJson":
    let jsonNode = %* { "path" : "path" }
    check validateBackupInfoJson(jsonNode)

  test "validateBackupJson 2":
    # Invalid json
    let jsonNode = %* { "a" : "path" }
    check not validateBackupInfoJson(jsonNode)

  test "validateBackupJson 3":
    # Invalid json
    let jsonNode = %* { "path" : 0 }
    check not validateBackupInfoJson(jsonNode)

suite "Backup: validateBackupFileName":
  test "validateBackupFileName":
    let filename = "2022-10-26T08:28:50+09:00"
    check validateBackupFileName(filename)

  test "validateBackupFileName 2":
    # Invalid filename
    let filename = "2022-10-26T08:28:50"
    check not validateBackupFileName(filename)

suite "Backup: backupDir":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()
    sourceFilePath = getCurrentDir() / "source.txt"
    backupInfoJsonNode = %* { "path": sourceFilePath }

  setup:
    os.createDir(baseBackupDir)

    os.createDir(backupDir)

    let backupInfoJsonPath = backupDir / "backup.json"
    writeFile(backupInfoJsonPath, $backupInfoJsonNode)

    for _ in 0 .. 4:
      # Dummy files
      let backupDir = baseBackupDir / $genOid()
      os.createDir(backupDir)

      let
        backupJsonInfoPath = backupDir / "backup.json"
        sourceFilePath = getCurrentDir() / "source-1.txt"
        backupInfoJsonNode = %* { "path": sourceFilePath }
      writeFile(backupJsonInfoPath, $backupInfoJsonNode)

  teardown:
    removeDir(baseBackupDir)

  test "backupDir":
    check backupDir(baseBackupDir, sourceFilePath) == backupDir

suite "Backup: getBackupFiles":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()
    sourceFilePath = getCurrentDir() / "source.txt"
    backupInfoJsonNode = %* { "path": sourceFilePath }

  setup:
    os.createDir(baseBackupDir)

    os.createDir(backupDir)

    let backupInfoJsonPath = backupDir / "backup.json"
    writeFile(backupInfoJsonPath, $backupInfoJsonNode)

    var backupFilenames: seq[seq[Rune]]
    for _ in 0 .. 2:
      backupFilenames.add now().toRunes
      writeFile(backupDir / $backupFilenames[^1], "\n")

    for _ in 0 .. 4:
      # Dummy files
      let backupDir = baseBackupDir / $genOid()
      os.createDir(backupDir)

      let
        backupJsonInfoPath = backupDir / "backup.json"
        sourceFilePath = getCurrentDir() / "source-1.txt"
        backupInfoJsonNode = %* { "path": sourceFilePath }
      writeFile(backupJsonInfoPath, $backupInfoJsonNode)

  teardown:
    removeDir(baseBackupDir)

  test "getBackupFiles":
    let r = getBackupFiles(baseBackupDir.toRunes, sourceFilePath.toRunes)
    for f in backupFilenames:
      check r.in f

suite "Backup: initBackupDir":
  let baseBackupDir = getCurrentDir() / "baseBackupDirForTest"

  teardown:
    removeDir(baseBackupDir)

  test "initBackupDir":
    let
      sourceFilePath = getCurrentDir() / "source.txt"
      backupDir = initBackupDir(baseBackupDir.toRunes, sourceFilePath.toRunes)

    check dirExists($backupDir)

suite "Backup: writeBackupFile":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()

  setup:
    os.createDir(baseBackupDir)
    os.createDir(backupDir)

  teardown:
    removeDir(baseBackupDir)

  test "writeBackupFile":
    const
      BUFFER = ru"abc"
      ENCODING = CharacterEncoding.utf8
    let
      backupFilename = now().toRunes
      backupFilePath = backupDir.toRunes / backupFilename

    check writeBackupFile(backupFilePath, BUFFER, ENCODING)
    check fileExists(backupDir / $backupFilename)

suite "Backup: writeBackupInfoJson":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()

  setup:
    os.createDir(baseBackupDir)
    os.createDir(backupDir)

  teardown:
    removeDir(baseBackupDir)

  test "writeBackupInfoJson":
    const SOURCE_FILE_PATH = "/source/file/path".toRunes
    check writeBackupInfoJson(backupDir.toRunes, SOURCE_FILE_PATH)

    let backupInfoJsonPath = $backupInfoJsonPath(backupDir.toRunes)
    check fileExists(backupInfoJsonPath)
    check json.parseFile(backupInfoJsonPath) == %* { "path": $SOURCE_FILE_PATH}
