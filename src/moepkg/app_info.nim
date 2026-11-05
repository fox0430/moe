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

import std/[strformat, strutils, os]

import pkg/results

const
  MoeVersion = "0.5.0"
    ## Keep in sync with moe.nimble, which cannot import this as `nimble install`
    ## drops src/ from the path.
  RepoRoot = currentSourcePath.parentDir.parentDir.parentDir
  HasNimble = fileExists(RepoRoot / "moe.nimble")

proc parseNimbleVersion*(nimbleSpec: string): string =
  ## The value of the top-level `version` line, or empty without one.

  for line in nimbleSpec.splitLines:
    let parts = line.split('=', maxsplit = 1)
    if parts.len == 2 and parts[0].strip(leading = false) == "version":
      let quoted = parts[1].split('"')
      return
        if quoted.len >= 3:
          quoted[1]
        else:
          ""

when HasNimble:
  static:
    doAssert parseNimbleVersion(staticRead(RepoRoot / "moe.nimble")) == MoeVersion,
      "MoeVersion differs from moe.nimble"

type VersionInfo* = object
  major*, minor*, patch*: int

proc toSemVerString*(v: VersionInfo): string {.inline.} =
  fmt"{v.major}.{v.minor}.{v.patch}"

proc parseVersionInfo*(s: string): Result[VersionInfo, string] =
  let strSplit = s.split('.')
  try:
    return Result[VersionInfo, string].ok VersionInfo(
      major: strSplit[0].parseInt,
      minor: strSplit[1].parseInt,
      patch: strSplit[2].parseInt,
    )
  except:
    return
      Result[VersionInfo, string].err fmt"Invalid value: {getCurrentExceptionMsg()}"

proc moeVersion*(): VersionInfo {.compileTime.} =
  MoeVersion.parseVersionInfo.get

proc moeSemVersionStr*(): string {.compileTime.} =
  moeVersion().toSemVerString

proc parseGitHash*(output: string, exitCode: int): string =
  ## Parse `git rev-parse HEAD`. Git warnings can precede the hash, as gorgeEx
  ## merges stderr.

  let lastLine = output.strip(leading = false).splitLines[^1]
  if exitCode == 0 and lastLine.len in [40, 64] and lastLine.allCharsInSet(HexDigits):
    return lastLine

proc staticGetGitHash(): string {.compileTime.} =
  ## Get the current git hash. Empty unless moe.nimble and .git are both at
  ## the root, so a vendored copy does not report its embedder's commit.
  ## --git-dir also keeps an inherited GIT_DIR from selecting the embedder's.

  if HasNimble:
    let cmdResult =
      gorgeEx("git " & quoteShell("--git-dir=" & RepoRoot / ".git") & " rev-parse HEAD")
    return parseGitHash(cmdResult.output, cmdResult.exitCode)

proc gitHash*(): string {.compileTime.} =
  staticGetGitHash()

proc buildType*(): string {.compileTime.} =
  ## Return the build type. "Release" or "Debug".

  if defined(release):
    return "Release"
  else:
    return "Debug"

proc formatVersionInfo*(version, hash, buildType: string): string =
  ## An empty `hash` is shown as unknown.

  let hashValue = if hash.len > 0: hash else: "unknown"
  result =
    "moe v" & version & "\n\nGit hash: " & hashValue & "\nBuild type: " & buildType

proc generateVersionInfoMessage*(): string =
  const Message = formatVersionInfo(moeSemVersionStr(), gitHash(), buildType())
  result = Message
