import std/[unittest, os]
import moepkg/[unicodeext, settings]
include moepkg/[historymanager]

suite "History Manager: Gnerate file name patern":
  test "Generate filename patern":
    let patern = generateFilenamePatern(ru"test.nim")
    check patern == ru"test_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}.nim"

suite "History Manager: Get backup directory":
  test "Get backup directory in current dir":
    const path = ru"test.nim"
    let
      settings = initEditorSettings()
      dir = getBackupDir(path, settings.autoBackupSettings)
    check dir == getCurrentDir().ru / ru".history"

  test "Get backup directory in other dir":
    const path = ru"/tmp/test.nim"
    let
      settings = initEditorSettings()
      dir = getBackupDir(path, settings.autoBackupSettings)
    check dir == ru"/tmp/.history"

suite "History Manager: Generate backup file path":
  test "From other directory":
    const
      originalFilePath = ru"src/moepkg/editorstatus.nim"
      backupFileName =  ru"editorstatus_2020-12-01T17:34:22+09:00.nim"
    let
      settings = initEditorSettings()
      p = generateBackUpFilePath(originalFilePath,
                                 backupFileName,
                                 settings.autoBackupSettings)

    check p == ru"src/moepkg/.history/editorstatus_2020-12-01T17:34:22+09:00.nim"
