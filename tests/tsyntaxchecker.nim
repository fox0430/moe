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
import moepkg/independentutils

import moepkg/syntaxchecker {.all.}

suite "syntaxchecker: toSyntaxCheckMessageType: Nim":
  test "Return SyntaxCheckMessageType.error":
    check toSyntaxCheckMessageType("Error").get == SyntaxCheckMessageType.error

  test "Return SyntaxCheckMessageType.warning":
    check toSyntaxCheckMessageType("Warning").get == SyntaxCheckMessageType.warning

  test "Return SyntaxCheckMessageType.info":
    check toSyntaxCheckMessageType("Info").get == SyntaxCheckMessageType.info

  test "Return SyntaxCheckMessageType.hint":
    check toSyntaxCheckMessageType("Hint").get == SyntaxCheckMessageType.hint

  test "Invalid text":
    check toSyntaxCheckMessageType("Ok").isErr


suite "syntaxchecker: parseNimCheckResult":
  test "No error":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
Hint:
107093 lines; 0.466s; 147.027MiB peakmem; proj: /home/user/moe/tests/tsyntaxchecker.nim; out: unknownOutput [SuccessX]
"""

    check path.parseNimCheckResult(cmdOutput).get.isEmpty

  test "Including hint":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
/home/user/moe/tests/tsyntaxchecker.nim(61, 9) Hint: 'a' is declared but not used [XDeclaredButNotUsed]
Hint:
107093 lines; 0.466s; 147.027MiB peakmem; proj: /home/user/moe/tests/tsyntaxchecker.nim; out: unknownOutput [SuccessX]
"""

    let r = path.parseNimCheckResult(cmdOutput).get
    check r.len == 1
    check r[0].position == BufferPosition(line: 60, column: 8)
    check r[0].messageType == SyntaxCheckMessageType.hint
    check not r[0].message.isEmpty

  test "Including warning":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
/home/user/moe/tests/tsyntaxchecker.nim(23, 14) Warning: imported and not used: 'unicodeext' [UnusedImport]
Hint:
107093 lines; 0.466s; 147.027MiB peakmem; proj: /home/user/moe/tests/tsyntaxchecker.nim; out: unknownOutput [SuccessX]
"""

    let r = path.parseNimCheckResult(cmdOutput).get
    check r.len == 1
    check r[0].position == BufferPosition(line: 22, column: 13)
    check r[0].messageType == SyntaxCheckMessageType.warning
    check not r[0].message.isEmpty

  test "Including error":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
/home/user/moe/src/moepkg/unicodeext.nim(454, 5) Hint: 'b2Mask' is declared but not used [XDeclaredButNotUsed]
/home/user/moe/src/moepkg/unicodeext.nim(458, 5) Hint: 'b3Mask' is declared but not used [XDeclaredButNotUsed]
/home/user/moe/src/moepkg/unicodeext.nim(462, 5) Hint: 'b4Mask' is declared but not used [XDeclaredButNotUsed]
.......................
/home/user/moe/tests/tsyntaxchecker.nim(47, 1) Error: invalid indentation
"""

    let r = path.parseNimCheckResult(cmdOutput).get
    check r.len == 1
    check r[0].position == BufferPosition(line: 46, column: 0)
    check r[0].messageType == SyntaxCheckMessageType.error
    check not r[0].message.isEmpty

  test "Including some hints":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
/home/user/moe/tests/tsyntaxchecker.nim(61, 9) Hint: 'a' is declared but not used [XDeclaredButNotUsed]
/home/user/moe/tests/tsyntaxchecker.nim(73, 9) Hint: 'r' is declared but not used [XDeclaredButNotUsed]
Hint:
107093 lines; 0.466s; 147.027MiB peakmem; proj: /home/user/moe/tests/tsyntaxchecker.nim; out: unknownOutput [SuccessX]
"""

    let r = path.parseNimCheckResult(cmdOutput).get

    check r.len == 2

    check r[0].position == BufferPosition(line: 60, column: 8)
    check r[0].messageType == SyntaxCheckMessageType.hint
    check not r[0].message.isEmpty

    check r[1].position == BufferPosition(line: 72, column: 8)
    check r[1].messageType == SyntaxCheckMessageType.hint
    check not r[1].message.isEmpty

  test "Including some warnings":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
/home/user/moe/tests/tsyntaxchecker.nim(23, 14) Warning: imported and not used: 'unicodeext' [UnusedImport]
/home/user/moe/tests/tsyntaxchecker.nim(20, 11) Warning: imported and not used: 'os' [UnusedImport]
/home/user/moe/tests/tsyntaxchecker.nim(22, 21) Warning: imported and not used: 'highlite' [UnusedImport]
Hint:
107093 lines; 0.466s; 147.027MiB peakmem; proj: /home/user/moe/tests/tsyntaxchecker.nim; out: unknownOutput [SuccessX]
"""

    let r = path.parseNimCheckResult(cmdOutput).get

    check r.len == 3

    check r[0].position == BufferPosition(line: 22, column: 13)
    check r[0].messageType == SyntaxCheckMessageType.warning
    check not r[0].message.isEmpty

    check r[1].position == BufferPosition(line: 19, column: 10)
    check r[1].messageType == SyntaxCheckMessageType.warning
    check not r[1].message.isEmpty

    check r[2].position == BufferPosition(line: 21, column: 20)
    check r[2].messageType == SyntaxCheckMessageType.warning
    check not r[2].message.isEmpty

  test "Including some errors":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
/home/user/moe/src/moepkg/unicodeext.nim(454, 5) Hint: 'b2Mask' is declared but not used [XDeclaredButNotUsed]
/home/user/moe/src/moepkg/unicodeext.nim(458, 5) Hint: 'b3Mask' is declared but not used [XDeclaredButNotUsed]
/home/user/moe/src/moepkg/unicodeext.nim(462, 5) Hint: 'b4Mask' is declared but not used [XDeclaredButNotUsed]
.......................
/home/user/moe/tests/tsyntaxchecker.nim(47, 1) Error: invalid indentation
/home/user/moe/tests/tsyntaxchecker.nim(50, 1) Error: invalid indentation
/home/user/moe/tests/tsyntaxchecker.nim(55, 1) Error: invalid indentation
"""

    let r = path.parseNimCheckResult(cmdOutput).get

    check r.len == 3

    check r[0].position == BufferPosition(line: 46, column: 0)
    check r[0].messageType == SyntaxCheckMessageType.error
    check not r[0].message.isEmpty

    check r[1].position == BufferPosition(line: 49, column: 0)
    check r[1].messageType == SyntaxCheckMessageType.error
    check not r[1].message.isEmpty

    check r[2].position == BufferPosition(line: 54, column: 0)
    check r[2].messageType == SyntaxCheckMessageType.error
    check not r[2].message.isEmpty

  test "Including hint and warning":
    const
      path = "/home/user/moe/tests/tsyntaxchecker.nim"
      cmdOutput = """
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/nim.cfg' [Conf]
Hint: used config file '/home/user/.choosenim/toolchains/nim-1.6.12/config/config.nims' [Conf]
Hint: used config file '/home/user/moe/tests/nim.cfg' [Conf]
Hint: used config file '/home/user/moe/tests/config.nims' [Conf]
..........................................................................................................................................
/home/user/moe/tests/tsyntaxchecker.nim(61, 9) Hint: 'a' is declared but not used [XDeclaredButNotUsed]
/home/user/moe/tests/tsyntaxchecker.nim(23, 14) Warning: imported and not used: 'unicodeext' [UnusedImport]
Hint:
107093 lines; 0.466s; 147.027MiB peakmem; proj: /home/user/moe/tests/tsyntaxchecker.nim; out: unknownOutput [SuccessX]
"""

    let r = path.parseNimCheckResult(cmdOutput).get
    check r.len == 2

    check r[0].position == BufferPosition(line: 60, column: 8)
    check r[0].messageType == SyntaxCheckMessageType.hint
    check not r[0].message.isEmpty

    check r[1].position == BufferPosition(line: 22, column: 13)
    check r[1].messageType == SyntaxCheckMessageType.warning
    check not r[1].message.isEmpty

suite "syntaxchecker: execSyntaxCheck: Nim":
  let testFileDir = getCurrentDir() / "syntaxchecker_test"

  setup:
    createDir(testFileDir)

  teardown:
    removeDir(testFileDir)

  test "No error":
    let testFilePath = testFileDir / "syntaxchecker_nim.nim"
    const code ="""echo "Hello world""""
    writeFile(testFilePath, code)

    check testFilePath.execSyntaxCheck(SourceLanguage.langNim).get.len == 0

    removeFile(testFilePath)

  test "hint":
    let testFilePath = testFileDir / "syntaxchecker_nim.nim"
    const code ="""
let a = 0
echo "Hello world"
"""
    writeFile(testFilePath, code)

    let r = testFilePath.execSyntaxCheck(SourceLanguage.langNim)
    check r.get.len == 1
    check r.get[0].position == BufferPosition(line: 0, column: 4)
    check r.get[0].messageType == SyntaxCheckMessageType.hint
    check r.get[0].message.len > 0

    removeFile(testFilePath)

  test "warning":
    let testFilePath = testFileDir / "syntaxchecker_nim.nim"
    const code ="""
import std/os
echo "Hello world"
"""
    writeFile(testFilePath, code)

    let r = testFilePath.execSyntaxCheck(SourceLanguage.langNim)
    check r.get.len == 1
    check r.get[0].position == BufferPosition(line: 0, column: 10)
    check r.get[0].messageType == SyntaxCheckMessageType.warning
    check r.get[0].message.len > 0

    removeFile(testFilePath)

  test "error":
    let testFilePath = testFileDir / "syntaxchecker_nim.nim"
    const code ="""
import std/nonExistModule
"""
    writeFile(testFilePath, code)

    let r = testFilePath.execSyntaxCheck(SourceLanguage.langNim)
    check r.get.len == 1
    check r.get[0].position == BufferPosition(line: 0, column: 10)
    check r.get[0].messageType == SyntaxCheckMessageType.error
    check r.get[0].message.len > 0

    removeFile(testFilePath)

  test "some warnings":
    let testFilePath = testFileDir / "syntaxchecker_nim.nim"
    const code ="""
import std/os
import std/osproc

echo "Hello world"
"""
    writeFile(testFilePath, code)

    let r = testFilePath.execSyntaxCheck(SourceLanguage.langNim)

    check r.get.len == 2

    check r.get[0].position == BufferPosition(line: 0, column: 10)
    check r.get[0].messageType == SyntaxCheckMessageType.warning
    check r.get[0].message.len > 0

    check r.get[1].position == BufferPosition(line: 1, column: 10)
    check r.get[1].messageType == SyntaxCheckMessageType.warning
    check r.get[1].message.len > 0

    removeFile(testFilePath)

  test "some errors":
    let testFilePath = testFileDir / "syntaxchecker_nim.nim"
    const code ="""
import std/nonExistModule
import std/nonExistModule2
"""
    writeFile(testFilePath, code)

    let r = testFilePath.execSyntaxCheck(SourceLanguage.langNim)

    check r.get.len == 2

    check r.get[0].position == BufferPosition(line: 0, column: 10)
    check r.get[0].messageType == SyntaxCheckMessageType.error
    check r.get[0].message.len > 0

    check r.get[1].position == BufferPosition(line: 1, column: 10)
    check r.get[1].messageType == SyntaxCheckMessageType.error
    check r.get[1].message.len > 0

    removeFile(testFilePath)

  test "hint and warning":
    let testFilePath = testFileDir / "syntaxchecker_nim.nim"
    const code ="""
import std/os
let a = 1
echo "Hello world"
"""
    writeFile(testFilePath, code)

    let r = testFilePath.execSyntaxCheck(SourceLanguage.langNim)

    check r.get.len == 2

    check r.get[0].position == BufferPosition(line: 1, column: 4)
    check r.get[0].messageType == SyntaxCheckMessageType.hint
    check r.get[0].message.len > 0

    check r.get[1].position == BufferPosition(line: 0, column: 10)
    check r.get[1].messageType == SyntaxCheckMessageType.warning
    check r.get[1].message.len > 0

    removeFile(testFilePath)
