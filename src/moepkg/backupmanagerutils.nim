import unicodeext, backup

proc initBackupManagerBuffer*(
  baseBackupDir, sourceFilePath: seq[Rune]): seq[Runes] =
    let filenames = getBackupFiles(baseBackupDir, sourceFilePath)
    if filenames.len > 0:
      for name in filenames: result.add name
    else:
      result = @[ru""]
