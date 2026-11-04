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

import std/[os, unittest]

import pkg/results

import ../src/moepkg/app_info

suite "app_info - parseNimbleVersion":
  test "the version line":
    check parseNimbleVersion("author = \"x\"\nversion = \"1.2.3\"\n") == "1.2.3"

  test "spacing around the equals sign":
    check parseNimbleVersion("version  =  \"1.2.3\"") == "1.2.3"

  test "a comment after the value":
    check parseNimbleVersion("version = \"1.2.3\" # release") == "1.2.3"

  test "an unquoted value":
    check parseNimbleVersion("version = 1.2.3") == ""

  test "other lines do not count":
    check parseNimbleVersion("# version = \"0.0.1\"\nversion = \"1.2.3\"") == "1.2.3"
    check parseNimbleVersion("nim_version = \"0.0.1\"\nversion = \"1.2.3\"") == "1.2.3"
    check parseNimbleVersion("  version = \"0.0.1\"\nversion = \"1.2.3\"") == "1.2.3"

  test "no version line":
    check parseNimbleVersion("author = \"x\"") == ""

suite "app_info - toSemVerString":
  test "format version as semver string":
    let v = VersionInfo(major: 1, minor: 2, patch: 3)
    check v.toSemVerString == "1.2.3"

  test "format zero version":
    let v = VersionInfo(major: 0, minor: 0, patch: 0)
    check v.toSemVerString == "0.0.0"

  test "format large version numbers":
    let v = VersionInfo(major: 100, minor: 200, patch: 300)
    check v.toSemVerString == "100.200.300"

suite "app_info - formatVersionInfo":
  test "known hash":
    check formatVersionInfo("1.2.3", "abc", "Release") ==
      "moe v1.2.3\n\nGit hash: abc\nBuild type: Release"

  test "unknown hash":
    check formatVersionInfo("1.2.3", "", "Debug") ==
      "moe v1.2.3\n\nGit hash: unknown\nBuild type: Debug"

suite "app_info - parseGitHash":
  const
    Hash = "0123456789abcdef0123456789abcdef01234567"
    Sha256Hash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  test "a SHA-1 repository":
    check parseGitHash(Hash & "\n", 0) == Hash

  test "a SHA-256 repository":
    check parseGitHash(Sha256Hash & "\n", 0) == Sha256Hash

  test "a git warning precedes the output":
    check parseGitHash("warning: x\n" & Hash, 0) == Hash

  test "no hash in the output":
    check parseGitHash("", 0) == ""
    check parseGitHash("HEAD", 0) == ""

  test "git failed":
    check parseGitHash("fatal: not a git repository", 128) == ""
    check parseGitHash(Hash, 128) == ""

  test "a checkout reports its commit":
    const
      Git = "git -C " & quoteShell(currentSourcePath.parentDir.parentDir)
      CdUp = gorgeEx(Git & " rev-parse --show-cdup")
      Head = gorgeEx(Git & " rev-parse HEAD")
      GitHash = gitHash()
    if CdUp.exitCode == 0 and CdUp.output.len == 0 and Head.exitCode == 0:
      check GitHash == parseGitHash(Head.output, Head.exitCode)

suite "app_info - parseVersionInfo":
  test "parse valid version string":
    let result = parseVersionInfo("1.2.3")
    check result.isOk
    let v = result.get
    check v.major == 1
    check v.minor == 2
    check v.patch == 3

  test "parse zero version":
    let result = parseVersionInfo("0.0.0")
    check result.isOk
    let v = result.get
    check v.major == 0
    check v.minor == 0
    check v.patch == 0

  test "parse version with large numbers":
    let result = parseVersionInfo("10.20.30")
    check result.isOk
    let v = result.get
    check v.major == 10
    check v.minor == 20
    check v.patch == 30

  test "parse non-numeric version":
    let result = parseVersionInfo("a.b.c")
    check result.isErr

suite "app_info - Round trip":
  test "parse then format returns original string":
    let original = "1.2.3"
    let parsed = parseVersionInfo(original)
    check parsed.isOk
    check parsed.get.toSemVerString == original

  test "parse then format for zero version":
    let original = "0.0.0"
    let parsed = parseVersionInfo(original)
    check parsed.isOk
    check parsed.get.toSemVerString == original
