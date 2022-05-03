import std/[logging, os, times]

proc defaultFilePath(): string =
  let cacheDir = getCacheDir() / "moe/logs"
  createDir(cacheDir)

  return cacheDir / $getTime() & ".log"

proc initLogger*() =
  let path = defaultFilePath()

  var fileLog = newFileLogger(path, levelThreshold=lvlDebug)
  addHandler(fileLog)
