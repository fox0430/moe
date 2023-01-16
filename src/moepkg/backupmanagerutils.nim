import unicodeext, backup

proc initBackupManagerBuffer*(
  baseBackupDir, sourceFilePath: seq[Rune]): seq[Runes] =
    let filename = getBackupFiles(baseBackupDir, sourceFilePath)
    # Add backup file names.
    if filename.len > 0:
      for name in getBackupFiles(baseBackupDir, sourceFilePath):
        result.add name
    else:
      return @[ru""]
