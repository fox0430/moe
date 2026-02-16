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

import std/unittest

import pkg/results

import ../src/moepkg/app_info

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
