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

import std/[unittest, os, tempfiles, sequtils]

import ../src/moepkg/dir_scan
import ../src/moepkg/types/filer_types

proc createTestDir(): string =
  let tmpDir = createTempDir("moe_test_", "_dirscan")
  createDir(tmpDir / "beta")
  createDir(tmpDir / "alpha")
  writeFile(tmpDir / "zebra.txt", "z")
  writeFile(tmpDir / "apple.txt", "a")
  writeFile(tmpDir / ".hidden", "h")
  return tmpDir

suite "dir_scan.isHiddenName":
  test "returns true for dotfile":
    check isHiddenName(".foo")
    check isHiddenName(".")

  test "returns false for regular names":
    check not isHiddenName("foo")
    check not isHiddenName("")

suite "dir_scan.isDirectoryLike":
  test "plain directory":
    check isDirectoryLike(fekDirectory, fekDirectory)

  test "symlink to directory":
    check isDirectoryLike(fekSymlink, fekDirectory)

  test "regular file":
    check not isDirectoryLike(fekFile, fekFile)

  test "symlink to file":
    check not isDirectoryLike(fekSymlink, fekFile)

suite "dir_scan.scanDirectory":
  test "sorts directories first, then alphabetical":
    let tmp = createTestDir()
    defer:
      removeDir(tmp)
    let entries = scanDirectory(tmp, showHidden = false)
    let names = entries.mapIt(it.name)
    check names == @["alpha", "beta", "apple.txt", "zebra.txt"]

  test "filters hidden entries when showHidden=false":
    let tmp = createTestDir()
    defer:
      removeDir(tmp)
    let entries = scanDirectory(tmp, showHidden = false)
    check not entries.anyIt(it.name == ".hidden")

  test "includes hidden entries when showHidden=true":
    let tmp = createTestDir()
    defer:
      removeDir(tmp)
    let entries = scanDirectory(tmp, showHidden = true)
    check entries.anyIt(it.name == ".hidden")

  test "sets isHidden flag on dotfiles":
    let tmp = createTestDir()
    defer:
      removeDir(tmp)
    let entries = scanDirectory(tmp, showHidden = true)
    let hidden = entries.filterIt(it.name == ".hidden")
    check hidden.len == 1
    check hidden[0].isHidden

  test "classifies entries by kind":
    let tmp = createTestDir()
    defer:
      removeDir(tmp)
    let entries = scanDirectory(tmp, showHidden = false)
    for e in entries:
      case e.name
      of "alpha", "beta":
        check e.kind == fekDirectory
        check e.targetKind == fekDirectory
      of "apple.txt", "zebra.txt":
        check e.kind == fekFile
        check e.targetKind == fekFile
      else:
        discard

  test "records executable flag for regular files":
    let tmp = createTempDir("moe_test_", "_dirscan_exec")
    defer:
      removeDir(tmp)
    writeFile(tmp / "script.sh", "#!/bin/sh\n")
    writeFile(tmp / "plain.txt", "x")
    setFilePermissions(
      tmp / "script.sh",
      {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpOthersRead},
    )
    let entries = scanDirectory(tmp, showHidden = false)
    let script = entries.filterIt(it.name == "script.sh")
    let plain = entries.filterIt(it.name == "plain.txt")
    check script.len == 1 and script[0].isExecutable
    check plain.len == 1 and not plain[0].isExecutable

  test "classifies symlink target kinds":
    let tmp = createTempDir("moe_test_", "_dirscan_link")
    defer:
      removeDir(tmp)
    createDir(tmp / "realdir")
    writeFile(tmp / "realfile.txt", "x")
    createSymlink(tmp / "realdir", tmp / "link_to_dir")
    createSymlink(tmp / "realfile.txt", tmp / "link_to_file")
    let entries = scanDirectory(tmp, showHidden = false)
    let byName = entries.filterIt(it.kind == fekSymlink)
    check byName.len == 2
    for e in byName:
      case e.name
      of "link_to_dir":
        check e.targetKind == fekDirectory
      of "link_to_file":
        check e.targetKind == fekFile
      else:
        discard

  test "returns empty seq on missing path":
    var err = ""
    let entries = scanDirectory(
      "/definitely-does-not-exist-moe-test", showHidden = true, error = err
    )
    check entries.len == 0

  test "short overload also returns empty on missing path":
    let entries =
      scanDirectory("/definitely-does-not-exist-moe-test-2", showHidden = true)
    check entries.len == 0

  test "skipOnStatError=true still returns readable entries":
    let tmp = createTestDir()
    defer:
      removeDir(tmp)
    let entries = scanDirectory(tmp, showHidden = true, skipOnStatError = true)
    check entries.len == 5 # 2 dirs + 2 files + .hidden
