#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[unittest, strutils]
import pkg/[chronos, results]
import moepkg/lsp/client

suite "LSP timeout":
  test "No timeout (timeoutMs = 0)":
    proc quickTask(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(10))
      return 42

    let result = waitFor withLspTimeout(quickTask(), 0)
    check result.isOk
    check result.get == 42

  test "Successful completion within timeout":
    proc quickTask(): Future[string] {.async.} =
      await sleepAsync(chronos.milliseconds(50))
      return "success"

    let result = waitFor withLspTimeout(quickTask(), 200)
    check result.isOk
    check result.get == "success"

  test "Timeout occurs":
    proc slowTask(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(200))
      return 99

    let result = waitFor withLspTimeout(slowTask(), 50)
    check result.isErr
    check "timed out" in result.error

  test "Task fails with error":
    proc failingTask(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(10))
      raise newException(IOError, "test error")

    let result = waitFor withLspTimeout(failingTask(), 100)
    check result.isErr
    check "test error" in result.error

  test "Immediate success":
    proc instantTask(): Future[string] {.async.} =
      return "instant"

    let result = waitFor withLspTimeout(instantTask(), 100)
    check result.isOk
    check result.get == "instant"

  test "Timeout message format":
    proc slowTask(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(100))
      return 1

    let result = waitFor withLspTimeout(slowTask(), 50)
    check result.isErr
    check result.error == "Request timed out after 50ms"

  test "Multiple concurrent timeouts":
    proc task1(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(30))
      return 1

    proc task2(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(60))
      return 2

    proc task3(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(90))
      return 3

    # All should succeed
    let result1 = waitFor withLspTimeout(task1(), 100)
    let result2 = waitFor withLspTimeout(task2(), 100)
    let result3 = waitFor withLspTimeout(task3(), 100)

    check result1.isOk and result1.get == 1
    check result2.isOk and result2.get == 2
    check result3.isOk and result3.get == 3

    # Some should timeout
    let result4 = waitFor withLspTimeout(task1(), 20)
    let result5 = waitFor withLspTimeout(task2(), 40)
    let result6 = waitFor withLspTimeout(task3(), 70)

    check result4.isErr # 30ms task with 20ms timeout
    check result5.isErr # 60ms task with 40ms timeout
    check result6.isErr # 90ms task with 70ms timeout

  test "Zero timeout means no timeout":
    proc longTask(): Future[string] {.async.} =
      await sleepAsync(chronos.milliseconds(100))
      return "completed"

    let result = waitFor withLspTimeout(longTask(), 0)
    check result.isOk
    check result.get == "completed"

  test "Negative timeout treated as no timeout":
    proc task(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(50))
      return 123

    let result = waitFor withLspTimeout(task(), -1)
    check result.isOk
    check result.get == 123

  test "Very short timeout":
    proc task(): Future[bool] {.async.} =
      await sleepAsync(chronos.milliseconds(10))
      return true

    # 1ms timeout should almost always fail
    let result = waitFor withLspTimeout(task(), 1)
    check result.isErr

  test "Very long timeout":
    proc task(): Future[int] {.async.} =
      await sleepAsync(chronos.milliseconds(100))
      return 999

    # 10 second timeout should never trigger
    let result = waitFor withLspTimeout(task(), 10000)
    check result.isOk
    check result.get == 999

  test "Exception in no-timeout path":
    proc errorTask(): Future[int] {.async.} =
      raise newException(ValueError, "no timeout error")

    let result = waitFor withLspTimeout(errorTask(), 0)
    check result.isErr
    check "no timeout error" in result.error
