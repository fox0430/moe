## Write a log file for debug moe.

import std/[os, times]
import unicodeext

var
  enableLogger = false
  logPath = ""

proc defaultDir(): string {.inline.} = getCacheDir() / "moe/logs"

# Return a log file path.
proc defaultFilePath(): string =
  let dir = defaultDir()
  createDir(dir)

  return dir / $getTime() & ".log"

proc getLogPath(): string =
  result = getEnv("MOE_LOG_FILENAME")
  if result.len > 0:
    return defaultDir() / result

  result = getEnv("MOE_LOG_PATH")
  if result.len == 0:
    result = defaultFilePath()

# TODO: Add date format.
proc initLogger*() =
  enableLogger = true
  logPath = getLogPath()

proc debug*(str: string) =
  if enableLogger:
    let f = open(logPath, FileMode.fmAppend)
    f.write(str & "\n")
    f.close

proc debug*(runes: Rune) =
  if enableLogger:
    let f = open(logPath, FileMode.fmAppend)
    f.write(runes & ru"\n")
    f.close
