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

import moepkg/path_key

suite "path_key - pathKey":
  test "An empty path has no key":
    check pathKey("") == ""

  test "A relative path resolves against the current directory":
    check pathKey("a.txt") == getCurrentDir() / "a.txt"

  test "Redundant components are collapsed":
    # Built by hand rather than with `/`, which collapses them as it joins.
    let want = getTempDir() / "a.txt"
    check pathKey(getTempDir() & "." & $DirSep & "a.txt") == want
    check pathKey(getTempDir() & "sub" & $DirSep & ".." & $DirSep & "a.txt") == want

  test "A leading tilde is expanded":
    check pathKey("~" & $DirSep & "a.txt") == getHomeDir() / "a.txt"
    check pathKey("~") == normalizedPath(getHomeDir())

  test "A tilde inside a path is a plain directory name":
    check pathKey(getTempDir() / "~" / "a.txt") == getTempDir() / "~" / "a.txt"

  test "An absolute path is already its own key":
    let key = pathKey(getTempDir() / "a.txt")
    check pathKey(key) == key

suite "path_key - samePath":
  test "Two spellings of one file match":
    check samePath(getTempDir() / "a.txt", getTempDir() & "." & $DirSep & "a.txt")

  test "A tilde path and its expansion name one file":
    check samePath("~" & $DirSep & "a.txt", getHomeDir() / "a.txt")

  test "Different files do not match":
    check not samePath(getTempDir() / "a.txt", getTempDir() / "b.txt")

  test "An empty path matches nothing, including another empty one":
    check not samePath("", getTempDir() / "a.txt")
    check not samePath(getTempDir() / "a.txt", "")
    check not samePath("", "")

suite "path_key - sameFileEntity":
  test "An alias and its target are one entity":
    when defined(posix):
      let dir = getTempDir() / "moe_test_entity"
      createDir(dir)
      let real = dir / "real.txt"
      let link = dir / "link.txt"
      writeFile(real, "hello")
      createSymlink(real, link)
      defer:
        removeFile(link)
        removeFile(real)
        removeDir(dir)

      check sameFileEntity(real, link)
      check sameFileEntity(link, real)
    else:
      skip()

  test "Different files are not one entity":
    let dir = getTempDir() / "moe_test_entity_two"
    createDir(dir)
    let a = dir / "a.txt"
    let b = dir / "b.txt"
    writeFile(a, "hello")
    writeFile(b, "hello")
    defer:
      removeFile(a)
      removeFile(b)
      removeDir(dir)

    check not sameFileEntity(a, b)

  test "Unresolvable paths never match, even each other":
    let missing = getTempDir() / "moe_test_entity_missing.txt"
    removeFile(missing)
    let dir = getTempDir() / "moe_test_entity_dir"
    createDir(dir)
    defer:
      removeDir(dir)

    check not sameFileEntity(missing, missing)
    check not sameFileEntity(missing, dir)
    check not sameFileEntity(dir, missing)
