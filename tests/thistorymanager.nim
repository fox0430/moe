import unittest, os
import moepkg/[unicodetext, settings]
include moepkg/historymanager

suite "History Manager: Gnerate file name patern":
  test "Generate filename patern":
    let patern = generateFilenamePatern(ru"test.nim")
    check patern == ru"test_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}.nim"

suite "History Manager: Get backup directory":
  test "Get backup directory in current dir":
    let
      settings = initEditorSettings()
      dir = getBackupDir(ru"test.nim", settings.autoBackupSettings)
    check dir == getCurrentDir().ru / ru".history"

  test "Get backup directory in other dir":
    let
      settings = initEditorSettings()
      dir = getBackupDir(ru"/tmp/test.nim", settings.autoBackupSettings)
    check dir == ru"/tmp/.history"
