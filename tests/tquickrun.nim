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

import std/[unittest, os]
import pkg/results
import moepkg/syntax/highlite
import moepkg/[unicodeext, bufferstatus, gapbuffer, backgroundprocess]

import moepkg/settings {.all.}
import moepkg/quickrunutils {.all.}

suite "QuickRun: languageExtension":
  test "Nim":
    check "nim" == languageExtension(SourceLanguage.langNim).get

  test "C":
    check "c" == languageExtension(SourceLanguage.langC).get

  test "C++":
    check "cpp" == languageExtension(SourceLanguage.langCpp).get

  test "Shell (Bash)":
    check "bash" == languageExtension(SourceLanguage.langShell).get

  test "Unknown":
    check languageExtension(SourceLanguage.langNone).isErr

suite "QuickRun: nimQuickRunCommand":
  test "Default settings":
    const Path = "test.nim"
    let settings = initQuickRunSettings()

    check nimQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "nim",
        args: @["c", "-r", "test.nim"],
        workingDir: "")

  test "User settings":
    const Path = "test.nim"
    let settings = QuickRunSettings(
      nimAdvancedCommand: "js",
      nimOptions: "--d:release")

    check nimQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "nim",
        args: @["js", "-r", "--d:release", "test.nim"],
        workingDir: "")

suite "QuickRun: clangQuickRunCommand":
  test "Default settings":
    const Path = "test.c"
    let settings = initQuickRunSettings()

    check clangQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["-c", "'gcc  test.c && ./.out'"],
        workingDir: "")

  test "User settings":
    const Path = "test.c"
    let settings = QuickRunSettings(
      clangOptions: "--wall")

    check clangQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["-c", "'gcc --wall test.c && ./.out'"],
        workingDir: "")

suite "QuickRun: cppQuickRunCommand":
  test "Default settings":
    const Path = "test.cpp"
    let settings = initQuickRunSettings()

    check cppQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["-c", "'g++  test.cpp && ./.out'"],
        workingDir: "")

  test "User settings":
    const Path = "test.cpp"
    let settings = QuickRunSettings(
      cppOptions: "--wall")

    check cppQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["-c", "'g++ --wall test.cpp && ./.out'"],
        workingDir: "")

suite "QuickRun: shQuickRunCommand":
  test "Default settings":
    const Path = "test.sh"
    let settings = initQuickRunSettings()

    check shQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/sh",
        args: @["test.sh"],
        workingDir: "")

  test "User settings":
    const Path = "test.sh"
    let settings = QuickRunSettings(shOptions: "-c")

    check shQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/sh",
        args: @["-c", "test.sh"],
        workingDir: "")

suite "QuickRun: bashQuickRunCommand":
  test "Default settings":
    const Path = "test.sh"
    let settings = initQuickRunSettings()

    check bashQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["test.sh"],
        workingDir: "")

  test "User settings":
    const Path = "test.sh"
    let settings = QuickRunSettings(bashOptions: "-c")

    check bashQuickRunCommand(Path, settings) ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["-c", "test.sh"],
        workingDir: "")

suite "QuickRun: quickRunCommand":
  test "Nim":
    const
      Path = "test.nim"
      Buffer = @[ru"echo 1"]
    let settings = initQuickRunSettings()

    check quickRunCommand(Path, SourceLanguage.langNim, Buffer, settings).get ==
      BackgroundProcessCommand(
        cmd: "nim",
        args: @["c", "-r", "test.nim"],
        workingDir: "")

  test "C":
    const
      Path = "test.c"
      Buffer = @[ru"int main() {return 0;}"]
    let settings = initQuickRunSettings()

    check quickRunCommand(Path, SourceLanguage.langC, Buffer, settings).get ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["-c", "'gcc  test.c && ./.out'"],
        workingDir: "")

  test "C++":
    const
      Path = "test.cpp"
      Buffer = @[ru"int main() {return 0;}"]
    let settings = initQuickRunSettings()

    check quickRunCommand(Path, SourceLanguage.langCpp, Buffer, settings).get ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["-c", "'g++  test.cpp && ./.out'"],
        workingDir: "")

  test "Sh":
    const
      Path = "test.sh"
      Buffer = @[ru"#!/bin/sh", ru"echo 1"]
    let settings = initQuickRunSettings()

    check quickRunCommand(Path, SourceLanguage.langShell, Buffer, settings).get ==
      BackgroundProcessCommand(
        cmd: "/bin/sh",
        args: @["test.sh"],
        workingDir: "")

  test "Bash":
    const
      Path = "test.sh"
      Buffer = @[ru"#!/bin/bash", ru"echo 1"]
    let settings = initQuickRunSettings()

    check quickRunCommand(Path, SourceLanguage.langShell, Buffer, settings).get ==
      BackgroundProcessCommand(
        cmd: "/bin/bash",
        args: @["test.sh"],
        workingDir: "")

suite "QuickRun: isRunning":
  test "Return true":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.sh")
    bufStatus.buffer = @[ru"sleep 1000"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    # Wait just in case
    sleep 100

    let isRunning = p.isRunning

    p.close

    if fileExists("quickruntemp.bash"):
      removeFile("quickruntemp.bash")

    check isRunning

  test "Return false":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.sh")
    bufStatus.buffer = @[ru"sleep 0"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    # Wait just in case
    sleep 100

    let isRunning = p.isRunning

    p.close

    if fileExists("quickruntemp.bash"):
      removeFile("quickruntemp.bash")

    check not isRunning

suite "QuickRun: isFinish":
  test "Return true":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.sh")
    bufStatus.buffer = @[ru"sleep 0"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    # Wait just in case
    sleep 100

    let isFinish = p.isFinish

    p.close

    check isFinish

  test "Return false":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.sh")
    bufStatus.buffer = @[ru"sleep 500"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    let isFinish = p.isFinish

    p.close

    if fileExists("quickruntemp.bash"):
      removeFile("quickruntemp.bash")

    check not isFinish

suite "QuickRun: cancel":
  test "cancel":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.sh")
    bufStatus.buffer = @[ru"sleep 500"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    p.cancel

    # Wait just in case
    sleep 100

    let isFinish = p.isFinish

    if fileExists("quickruntemp.bash"):
      removeFile("quickruntemp.bash")

    check isFinish

suite "QuickRun: kill":
  test "kill":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.sh")
    bufStatus.buffer = @[ru"sleep 500"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    p.kill

    # Wait just in case
    sleep 100

    let isFinish = p.isFinish

    if fileExists("quickruntemp.bash"):
      removeFile("quickruntemp.bash")

    check isFinish

suite "QuickRun: close":
  test "close":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.sh")
    bufStatus.buffer = @[ru"sleep 500"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    p.close

    if fileExists("quickruntemp.bash"):
      removeFile("quickruntemp.bash")

suite "QuickRun: startBackgroundQuickRun and result":
  test "Without file":
    let settings = initEditorSettings()

    var bufStatus = initBufferStatus("test.nim")
    bufStatus.buffer = @[ru"echo 1"].toGapBuffer

    var p = bufStatus.startBackgroundQuickRun(settings).get

    var timeout = true
    for _ in 0 .. 20:
      sleep 500

      if p.isFinish:
        check p.result.get[^1] == "1"
        timeout = false
        break

    check not timeout
