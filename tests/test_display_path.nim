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

import std/[options, os, unittest]

import moepkg/display_path {.all.}

template withHomeEnv(value: string, body: untyped) =
  ## Runs `body` with `$HOME` set to `value` and the prefixes not yet read.
  let hadHome = existsEnv("HOME")
  let savedHome = getEnv("HOME")
  let savedDirs = homeDirs
  putEnv("HOME", value)
  homeDirs = none(seq[string])
  try:
    body
  finally:
    homeDirs = savedDirs
    if hadHome:
      putEnv("HOME", savedHome)
    else:
      delEnv("HOME")

suite "display_path - homeReplace":
  let home = getTempDir() / "moe_display_path_home"
  setup:
    removeDir(home)
    createDir(home)
  teardown:
    removeDir(home)

  test "The home itself":
    check homeReplace("/home/u", ["/home/u"]) == "~"

  test "A path under the home":
    check homeReplace("/home/u/.config/moe", ["/home/u"]) == "~/.config/moe"

  test "Another user's path that shares the prefix":
    check homeReplace("/home/u2/file.nim", ["/home/u"]) == "/home/u2/file.nim"

  test "Relative paths and other absolute paths stay":
    check homeReplace("src/file.nim", ["/home/u"]) == "src/file.nim"
    check homeReplace("/etc/hosts", ["/home/u"]) == "/etc/hosts"

  test "Either the home as written or its real path":
    let homes = ["/home/u", "/var/home/u"]
    check homeReplace("/home/u/a.nim", homes) == "~/a.nim"
    check homeReplace("/var/home/u/a.nim", homes) == "~/a.nim"

  test "The prefixes are $HOME and the path its link resolves to":
    let real = home / "real"
    let link = home / "link"
    createDir(real)
    createSymlink(real, link)
    withHomeEnv(link):
      check homePrefixes() == @[link, expandFilename(real)]

  test "A plain $HOME is one prefix without its trailing separator":
    let plain = expandFilename(home)
    withHomeEnv(plain & DirSep):
      check homePrefixes() == @[plain]

  test "A $HOME that does not exist is kept as written":
    let missing = home / "missing"
    withHomeEnv(missing):
      check homePrefixes() == @[missing]

  test "A root home replaces the root alone":
    withHomeEnv("/"):
      check homePrefixes() == @["/"]
      check homeReplace("/") == "~"
      check homeReplace("/etc/hosts") == "/etc/hosts"

  test "An empty $HOME gives no prefix":
    withHomeEnv(""):
      check homePrefixes().len == 0
      check homeReplace("/") == "/"
