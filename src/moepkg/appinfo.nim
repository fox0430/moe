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

import std/[strformat, strutils, os, pegs]
import pkg/results

type
  VersionInfo* = object
    major*, minor*, patch*: int

proc toSemVerString*(v: VersionInfo): string {.inline.} =
  fmt"{v.major}.{v.minor}.{v.patch}"

proc parseVersionInfo*(s: string): Result[VersionInfo, string] =
  let strSplit = s.split('.')
  try:
    return Result[VersionInfo, string].ok VersionInfo(
      major: strSplit[0].parseInt,
      minor: strSplit[1].parseInt,
      patch: strSplit[2].parseInt)
  except:
    return Result[VersionInfo, string].err fmt"Invalid value: {getCurrentExceptionMsg()}"

proc staticReadVersionFromNimble: string {.compileTime.} =
  ## Get the moe version from moe.nimble.

  let
    peg = """@ "version" \s* "=" \s* \" {[0-9.]+} \" @ $""".peg

    nimblePath = currentSourcePath.parentDir() / "../../moe.nimble"
    nimbleSpec = staticRead(nimblePath)

  var captures: seq[string] = @[""]
  assert nimbleSpec.match(peg, captures)
  assert captures.len == 1
  return captures[0]

proc moeVersion*(): VersionInfo {.compileTime.} =
  staticReadVersionFromNimble().parseVersionInfo.get

proc moeSemVersionStr*(): string {.compileTime.} =
  moeVersion().toSemVerString

proc staticGetGitHash: string {.compileTime.} =
  ## Get the current git hash.

  const CmdResult = gorgeEx("git rev-parse HEAD")
  if CmdResult.exitCode == 0 and CmdResult.output.len == 40:
    return CmdResult.output
  else:
    return ""

proc gitHash*(): string {.compileTime.} =
  staticGetGitHash()

proc buildType*: string {.compileTime.} =
  ## Return the build type. "Release" or "Debug".

  if defined(release): return "Release"
  else: return "Debug"
