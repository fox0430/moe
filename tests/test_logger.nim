#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, os, strutils, importutils]

import ../src/moepkg/logger {.all.}

privateAccess(Logger)

suite "logger - LogLevel":
  test "logLevelToStr Debug":
    check logLevelToStr(LogLevel.Debug) == "DEBUG"

  test "logLevelToStr Info":
    check logLevelToStr(LogLevel.Info) == "INFO"

  test "logLevelToStr Warn":
    check logLevelToStr(LogLevel.Warn) == "WARN"

  test "logLevelToStr Error":
    check logLevelToStr(LogLevel.Error) == "ERROR"

suite "logger - Initialization":
  test "initLogger default creates disabled logger":
    let logger = initLogger()
    check not logger.enabled

  test "initLogger with enabled=true":
    let logger = initLogger(enabled = true)
    if logger.enabled:
      logger.close()

  test "initLogger with custom log level":
    let logger = initLogger(minLevel = LogLevel.Warn)
    check logger.minLevel == LogLevel.Warn

suite "logger - Log level filtering":
  test "log does nothing when logger is disabled":
    let logger = initLogger(enabled = false)
    logger.log(LogLevel.Debug, "test", "message")
    logger.log(LogLevel.Error, "test", "message")

  test "log does nothing with nil logger":
    var logger: Logger = nil
    logger.log(LogLevel.Debug, "test", "message")

suite "logger - File writing":
  test "logger writes to file":
    let logger = initLogger(enabled = true)
    if logger.enabled:
      logger.log(LogLevel.Info, "test_module", "test message")
      logger.close()

      let logPath = logger.filePath
      if fileExists(logPath):
        let content = readFile(logPath)
        check "INFO" in content
        check "test_module" in content
        check "test message" in content

suite "logger - Global logger":
  test "getGlobalLogger returns non-nil":
    let logger = getGlobalLogger()
    check not logger.isNil

  test "setGlobalLogger and getGlobalLogger round trip":
    let original = getGlobalLogger()
    let newLogger = initLogger(minLevel = LogLevel.Error)
    setGlobalLogger(newLogger)
    check getGlobalLogger() == newLogger
    setGlobalLogger(original)

suite "logger - Convenience procs":
  test "logDebug does not crash":
    logDebug("test", "debug message")

  test "logInfo does not crash":
    logInfo("test", "info message")

  test "logWarn does not crash":
    logWarn("test", "warn message")

  test "logError does not crash":
    logError("test", "error message")
