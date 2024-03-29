#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[unittest, os, options]
import pkg/results

import moepkg/backgroundprocess {.all.}

suite "BackgroundTask: isFinish":
  test "Return true":
    let command = BackgroundProcessCommand(
      cmd: "/bin/sh",
      args:  @["-c", "sleep 0"])
    var bp = command.startBackgroundProcess.get

    # Wait just in case
    sleep 100

    let isFinish = bp.isFinish

    bp.close

    check isFinish

  test "Return false":
    let command = BackgroundProcessCommand(
      cmd: "/bin/sh",
      args:  @["-c", "sleep 0.5"])
    var bp = command.startBackgroundProcess.get

    let isFinish = bp.isFinish

    bp.close

    # Wait just in case
    sleep 100

    check not isFinish

suite "BackgroundTask: cancel":
  test"Cancel background process":
    let command = BackgroundProcessCommand(
      cmd: "/bin/sh",
      args:  @["-c", "sleep 0.5"])
    var bp = command.startBackgroundProcess.get

    bp.cancel

    # Wait just in case
    sleep 100

    check not bp.isRunning

suite "BackgroundTask: kill":
  test"Kill background process":
    let command = BackgroundProcessCommand(
      cmd: "/bin/sh",
      args:  @["-c", "sleep 0.5"])
    var bp = command.startBackgroundProcess.get

    bp.kill

    # Wait just in case
    sleep 100

    check not bp.isRunning

suite "BackgroundTask: Run background process":
  test "Exec '/bin/sh -c echo 1'":
    var
      bp: Option[BackgroundProcess]
      output: seq[string]

    for _ in 0 .. 50:
      if bp.isNone:
        let command = BackgroundProcessCommand(
          cmd: "/bin/sh",
          args:  @["-c", "echo 1"])
        bp = command.startBackgroundProcess.get.some
      elif bp.get.isFinish:
        output = bp.get.result.get
        break
      else:
        sleep 100

    check @["1"] == output

  test "Exec '/bin/sh -c echo 1; echo 2'":
    var
      bp: Option[BackgroundProcess]
      output: seq[string]

    for _ in 0 .. 50:
      if bp.isNone:
        let command = BackgroundProcessCommand(
          cmd: "/bin/sh",
          args:  @["-c", "echo 1; echo 2"])
        bp = command.startBackgroundProcess.get.some
      elif bp.get.isFinish:
        output = bp.get.result.get
        break
      else:
        sleep 100

    check @["1", "2"] == output

  test "Exec '/bin/sh -c sleep 1; echo 1' and waitFor":
    let command = BackgroundProcessCommand(
      cmd: "/bin/sh",
      args:  @["-c", "sleep 0.5; echo 1"])
    var bp = command.startBackgroundProcess.get

    check @["1"] == bp.waitFor
    check not bp.isRunning
