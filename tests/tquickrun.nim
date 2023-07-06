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
import moepkg/[unicodeext, settings, bufferstatus, commandline, gapbuffer]

import moepkg/quickrun {.all.}

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

suite "QuickRun: generateCommand":
  test "Nim":
    const
      Path = "test.nim"
      Buffer = @[ru"echo 1"]
    let
      settings = QuickRunSettings(nimAdvancedCommand: "c", timeout: 1)

    check "timeout 1 nim c -r  test.nim" ==
      generateCommand(Path, SourceLanguage.langNim, Buffer, settings).get

  test "C":
    const
      Path = "test.c"
      Buffer = @[ru"""#include <stdio.h> main() { printf("Hello World\n"); }"""]
    let
      settings = QuickRunSettings(timeout: 1)

    check "timeout 1 gcc  test.c && ./a.out" ==
      generateCommand(Path, SourceLanguage.langC, Buffer, settings).get

  test "C++":
    const
      Path = "test.cpp"
      Buffer = @[ru"""#include <stdio.h> main() { printf("Hello World\n"); }"""]
    let
      settings = QuickRunSettings(timeout: 1)

    check "timeout 1 g++  test.cpp && ./a.out" ==
      generateCommand(Path, SourceLanguage.langCpp, Buffer, settings).get

  test "Shell (Sh)":
    const
      Path = "test.sh"
      Buffer = @[ru"#!/bin/sh", ru "echo 1"]
    let
      settings = QuickRunSettings(timeout: 1)

    check "timeout 1 sh  test.sh" ==
      generateCommand(Path, SourceLanguage.langShell, Buffer, settings).get

  test "Shell (Bash)":
    const
      Path = "test.sh"
      Buffer = @[ru"#!/bin/bash", ru "echo 1"]
    let
      settings = QuickRunSettings(timeout: 1)

    check "timeout 1 bash  test.sh" ==
      generateCommand(Path, SourceLanguage.langShell, Buffer, settings).get

suite "QuickRun: runQuickRun":
  test "Run Nim code without file":
    const
      Path = "test.nim"
    let
      settings = initEditorSettings()
    var
      bufStatus = initBufferStatus(Path)
      commandLine = initCommandLine()

    bufStatus.buffer = @[ru"echo 123"].toGapBuffer

    let r = runQuickRun(bufStatus, commandLine, settings).get

    check ru"123" == r[r.high - 1]

  test "Run Nim code with file":
    const
      Dir = "./quickrun_test"
      Path = Dir / "quickruntest.nim"
      Buffer = "echo 123"

    # Create dir and file for the test.
    createDir(Dir)
    writeFile(Path, Buffer)

    let
      settings = initEditorSettings()
    var
      bufStatus = initBufferStatus(Path)
      commandLine = initCommandLine()

    let r = runQuickRun(bufStatus, commandLine, settings).get

    # Cleanup test file and dir.
    removeDir(Dir)

    check ru"123" == r[r.high - 1]

  test "Run Nim code with file and before save":
    const
      Dir = "./quickrun_test"
      Path = Dir / "quickruntest.nim"
      Buffer = "echo 123"

    # Create dir and file for the test.
    createDir(Dir)
    writeFile(Path, Buffer)

    var
      settings = initEditorSettings()
      bufStatus = initBufferStatus(Path)
      commandLine = initCommandLine()

    settings.quickrun.saveBufferWhenQuickRun = true
    bufStatus.buffer[0] = ru"echo 1234"

    let
      r = runQuickRun(bufStatus, commandLine, settings).get
      fileBuffer = readFile(Path)

    # Cleanup test file and dir.
    removeDir(Dir)

    check "echo 1234" == fileBuffer
    check ru"1234" == r[r.high - 1]
