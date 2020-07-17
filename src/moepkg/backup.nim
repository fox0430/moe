import os, times, strutils, re
import settings, unicodeext, fileutils, bufferstatus, ui, gapbuffer, messages

type AutoBackupStatus* = object
  lastBackupTime*: DateTime

proc initAutoBackupStatus*(): AutoBackupStatus =
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

  if not existsDir($result):
    try: createDir($result)
    except OSError: result = @[]

proc diffWithBackup(path: seq[Rune], buffer: string): bool =
  var
    filename = ru""
    dir = ru""
  let slashPosition = path.rfind(ru"/")
  if  slashPosition > 0:
    filename = path[slashPosition + 1 .. ^1]
    dir = path[0 .. slashPosition]
  else:
    filename = filename

  let dotPosi = filename.rfind(ru".")
  if dotPosi > 0:
    filename = filename[0 ..< dotPosi] & ru"_*"  & filename[dotPosi .. ^1]
  else:
    filename &= ru"_*"

  # filename including timestamp
  let patern = re".*_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}.*"
  var
    filePath = ""
    timeStamp: DateTime

  # Get most recently backup file
  for kind, path in walkDir($dir):
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
                   settings: AutoBackupSettings,
                   cmdWin: var Window,
                   messageLog: var seq[seq[Rune]]) =

  if bufStatus.filename.len == 0: return

  let
    backupFilename = bufStatus.filename.generateFilename(now())
    dir = bufStatus.filename.checkAndCreateBackupDir(settings.backupDir)

  if dir.len > 0:
    let
      path = dir / backupFilename
      isSame = diffWithBackup(path, $bufStatus.buffer)
    if not isSame:
      cmdWin.writeStartAutoBackupMessage(messageLog)
      saveFile(path, bufStatus.buffer.toRunes, encoding)
      cmdWin.writeAutoBackupSuccessMessage(messageLog)
