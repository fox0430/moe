import std/[os, times, re]
import settings, unicodeext, fileutils, bufferstatus, gapbuffer, messages,
       commandline

type AutoBackupStatus* = object
  lastBackupTime*: DateTime

proc initAutoBackupStatus*(): AutoBackupStatus {.inline.} =
  result.lastBackupTime = now()

proc generateFilename(filename: seq[Rune], time: DateTime): seq[Rune] =
  let slashPosition = filename.rfind(ru"/")
  if  slashPosition > 0:
    result = filename[slashPosition + 1 .. ^1]
  else:
    result = filename

  let
    dotPosi = result.rfind(ru".")
    timeRunes = ($time).toRunes
  if dotPosi > 0:
    result = result[0 ..< dotPosi] & ru"_" & timeRunes & result[dotPosi .. ^1]
  else:
    result &= ru"_" & timeRunes

proc checkAndCreateBackupDir(path: seq[Rune],
                             backupDirSetting: seq[Rune]): seq[Rune] =

  if backupDirSetting.len > 0: result = backupDirSetting
  else:
    let slashPosition = path.rfind(ru"/")
    if  slashPosition > 0:
      result = path[0 ..< slashPosition] / ru".history"
    else:
      result = ru".history"

  if not dirExists($result):
    try: createDir($result)
    except OSError: result = @[]

proc diffWithBackup(path: seq[Rune], buffer: string): bool =
  let
    # filename including timestamp
    patern = re".*_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}.*"
    splitPath = splitPath($path)
  var
    filePath = ""
    timeStamp: DateTime

  # Get most recently backup file
  for kind, path in walkDir($splitPath.head):
    if kind == PathComponent.pcFile:
      let splitPath = path.splitPath
      if splitPath.tail.match(patern):
        let
          # Timestamp
          patern = re"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}"
          timeStamps = splitPath.tail.findAll(patern)
          mostRecent = parse(timeStamps[^1], "yyyy-MM-dd\'T\'HH:mm:sszzz")

        if filePath.len == 0 or (mostRecent > timeStamp):
          timeStamp = mostRecent
          filePath = path

  if filePath.len > 0:
    let mostRecentBackupBuffer = openFile(filePath.toRunes)
    result = $mostRecentBackupBuffer.text == buffer[0 ..< ^1]

proc backupBuffer*(bufStatus: BufferStatus,
                   encoding: CharacterEncoding,
                   autoBackupSettings: AutoBackupSettings,
                   notificationSettings: NotificationSettings,
                   commandLine: var CommandLine,
                   messageLog: var seq[seq[Rune]]) =

  if bufStatus.path.len == 0: return

  let
    sourceFilePath = absolutePath($bufStatus.path)
    sourceFileDir = (sourceFilePath.splitPath).head
    dirToExclude = autoBackupSettings.dirToExclude
  if dirToExclude.contains(ru sourceFileDir): return

  let
    backupFilename = bufStatus.path.generateFilename(now())
    dir = bufStatus.path.checkAndCreateBackupDir(autoBackupSettings.backupDir)
  if dir.len == 0:
    commandLine.writeAutoBackupFailedMessage(
      backupFilename,
      notificationSettings,
      messageLog)
    return

  let
    path = dir / backupFilename
    isSame = diffWithBackup(path, $bufStatus.buffer)
  if not isSame:
    commandLine.writeStartAutoBackupMessage(notificationSettings, messageLog)

    saveFile(path, bufStatus.buffer.toRunes, encoding)

    let message = "Automatic backup successful: " & $path
    commandLine.writeAutoBackupSuccessMessage(
      message,
      notificationSettings,
      messageLog)
