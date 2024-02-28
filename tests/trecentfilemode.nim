#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[unittest, oids, os]

import pkg/results

import moepkg/unicodeext

import moepkg/recentfilemode {.all.}

const RecentlyUsedXbelBuffer = """
<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0"
      xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"
      xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info"
>
  <bookmark href="file:///home/user/picture.jpg" added="2023-04-08T22:24:37.028348Z" modified="2023-04-08T22:26:43.281755Z" visited="2023-04-08T22:24:37.028349Z">
    <info>
      <metadata owner="http://freedesktop.org">
        <mime:mime-type type="image/jpeg"/>
        <bookmark:applications>
          <bookmark:application name="app" exec="&apos;app %u&apos;" modified="2023-04-08T22:26:43.281753Z" count="2"/>
        </bookmark:applications>
      </metadata>
    </info>
  </bookmark>
</xbel>
"""

suite "getRecentUsedFiles":
  const RecentlyUsedXbelTestDir = "./recentlyUsedXbelTest"

  teardown:
    if dirExists(RecentlyUsedXbelTestDir):
      removeDir(RecentlyUsedXbelTestDir)

  test "Not found":
    check getRecentUsedFiles(RecentlyUsedXbelTestDir / $genOid()).isErr

  test "Basic":
    let recentlyUsedXbelPath = RecentlyUsedXbelTestDir / $genOid()
    createDir(RecentlyUsedXbelTestDir)
    writeFile(recentlyUsedXbelPath, RecentlyUsedXbelBuffer)

    check @[ru"/home/user/picture.jpg"] == getRecentUsedFiles(
      recentlyUsedXbelPath).get
