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

## File-based logging system for debugging
## This module provides a thread-safe logging mechanism that writes to a file
## to avoid interfering with the TUI display.

import std/[times, os, strformat, locks, syncio]

type
  LogLevel* {.pure.} = enum
    ## Log severity levels
    Debug ## Detailed debugging information
    Info ## General informational messages
    Warn ## Warning messages for potentially harmful situations
    Error ## Error messages for failures

  Logger* = ref object ## File-based logger for debugging
    filePath: string
    minLevel: LogLevel
    lock: Lock
    enabled: bool
    file: File

proc getLogFilePath(): string =
  ## Determine the log file path
  ## Priority: ./moe-debug.log (current directory), fallback to /tmp/moe-debug.log
  ## Note: This does not create the file, just determines the path
  result = getCurrentDir() / "moe-debug.log"

proc initLogger*(minLevel: LogLevel = LogLevel.Debug, enabled: bool = false): Logger =
  ## Initialize a new logger instance
  ##
  ## Args:
  ##   minLevel: Minimum log level to record (default: Debug)
  ##   enabled: Whether logging is enabled (default: false)
  ##
  ## Returns:
  ##   A new Logger instance
  result = Logger(filePath: getLogFilePath(), minLevel: minLevel, enabled: enabled)
  initLock(result.lock)

  if enabled:
    try:
      result.file = open(result.filePath, fmAppend)
    except CatchableError as e:
      # Try fallback location
      try:
        result.filePath = getTempDir() / "moe-debug.log"
        result.file = open(result.filePath, fmAppend)
      except CatchableError:
        # If we can't open the log file, disable logging
        result.enabled = false
        stderr.writeLine(&"Warning: Failed to open log file: {e.msg}")

# Global logger instance - initialized at module load time for thread safety
var globalLogger: Logger

try:
  globalLogger = initLogger()
except CatchableError:
  # Fallback to disabled logger if initialization fails (e.g., getCurrentDir() fails)
  globalLogger = Logger(enabled: false)

proc close*(logger: Logger) =
  ## Close the logger and release resources
  if not logger.isNil and logger.enabled:
    withLock(logger.lock):
      if logger.file != nil:
        logger.file.close()

proc setGlobalLogger*(logger: Logger) =
  ## Set the global logger instance
  globalLogger = logger

proc getGlobalLogger*(): Logger {.gcsafe, raises: [].} =
  ## Get the global logger instance (initialized at module load time)
  {.cast(gcsafe).}:
    result = globalLogger

proc logLevelToStr(level: LogLevel): string =
  ## Convert log level to string representation
  case level
  of LogLevel.Debug: "DEBUG"
  of LogLevel.Info: "INFO"
  of LogLevel.Warn: "WARN"
  of LogLevel.Error: "ERROR"

proc log*(
    logger: Logger, level: LogLevel, module: string, message: string
) {.gcsafe, raises: [].} =
  ## Write a log message to the log file
  ##
  ## Args:
  ##   logger: Logger instance to use
  ##   level: Severity level of the message
  ##   module: Source module name
  ##   message: Log message content
  if logger.isNil or not logger.enabled or level < logger.minLevel:
    return

  try:
    let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
    let levelStr = logLevelToStr(level)
    let logLine = &"[{timestamp}] [{levelStr}] [{module}] {message}\n"

    withLock(logger.lock):
      logger.file.write(logLine)
      logger.file.flushFile()
  except CatchableError:
    # Silently fail if we can't write to the log file
    discard

proc log*(level: LogLevel, module: string, message: string) {.gcsafe, raises: [].} =
  ## Write a log message using the global logger
  ##
  ## Args:
  ##   level: Severity level of the message
  ##   module: Source module name
  ##   message: Log message content
  getGlobalLogger().log(level, module, message)

# Convenience procs for different log levels
proc logDebug*(module: string, message: string) {.gcsafe, raises: [].} =
  ## Log a debug message using the global logger
  log(LogLevel.Debug, module, message)

proc logInfo*(module: string, message: string) {.gcsafe, raises: [].} =
  ## Log an info message using the global logger
  log(LogLevel.Info, module, message)

proc logWarn*(module: string, message: string) {.gcsafe, raises: [].} =
  ## Log a warning message using the global logger
  log(LogLevel.Warn, module, message)

proc logError*(module: string, message: string) {.gcsafe, raises: [].} =
  ## Log an error message using the global logger
  log(LogLevel.Error, module, message)

# Initialize global logger on module import
when isMainModule:
  # Test the logger
  let logger = initLogger()
  setGlobalLogger(logger)

  logDebug("test", "This is a debug message")
  logInfo("test", "This is an info message")
  logWarn("test", "This is a warning message")
  logError("test", "This is an error message")

  logger.close()
  echo "Log file created at: ", logger.filePath
