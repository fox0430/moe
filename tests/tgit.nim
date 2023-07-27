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

import std/[unittest, strutils]

import moepkg/git {.all.}

suite "git: gitDiff":
  test "Changed 1":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index f328eafe..4f540b87 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -6,7 +6,7 @@
 #  it under the terms of the GNU General Public License as published by        #
 #  the Free Software Foundation, either version 3 of the License, or           #
 #  (at your option) any later version.                                         #
-#                                                                              #
+                                                                              #
 #  This program is distributed in the hope that it will be useful,             #
 #  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
 #  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
@@ -19,7 +19,7 @@
 
 import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
             encodings]
-import syntax/highlite
+mport syntax/highlite
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
        windownode, color, settings, statusline, bufferstatus, cursor, tabline,
        backup, messages, commandline, register, platform, movement,
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.changed, firstLine: 8, lastLine: 8),
      Diff(operation: OperationType.changed, firstLine: 21, lastLine: 21),
    ]

  test "Deleted 1":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index f328eafe..a8229205 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -17,7 +17,6 @@
 #                                                                              #
 #[############################################################################]#
 
-import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
             encodings]
 import syntax/highlite
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.deleted, firstLine: 18, lastLine: 18),
    ]

  test "Deleted 2":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index f328eafe..03715814 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -17,8 +17,6 @@
 #                                                                              #
 #[############################################################################]#
 
-import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
-            encodings]
 import syntax/highlite
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
        windownode, color, settings, statusline, bufferstatus, cursor, tabline,
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.deleted, firstLine: 18, lastLine: 19),
    ]

  test "Deleted 3":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index f328eafe..8fa55819 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -6,7 +6,6 @@
 #  it under the terms of the GNU General Public License as published by        #
 #  the Free Software Foundation, either version 3 of the License, or           #
 #  (at your option) any later version.                                         #
-#                                                                              #
 #  This program is distributed in the hope that it will be useful,             #
 #  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
 #  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
@@ -17,7 +16,6 @@
 #                                                                              #
 #[############################################################################]#
 
-import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
             encodings]
 import syntax/highlite
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,

"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.deleted, firstLine: 7, lastLine: 7),
      Diff(operation: OperationType.deleted, firstLine: 17, lastLine: 17),
    ]

  test "Added 1":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index f328eafe..6deb6128 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -20,6 +20,7 @@
 import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
             encodings]
 import syntax/highlite
+a
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
        windownode, color, settings, statusline, bufferstatus, cursor, tabline,
        backup, messages, commandline, register, platform, movement,
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.added, firstLine: 22, lastLine: 22)
    ]

  test "Added 2":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index f328eafe..e43d4504 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -20,6 +20,8 @@
 import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
             encodings]
 import syntax/highlite
+a
+b
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
        windownode, color, settings, statusline, bufferstatus, cursor, tabline,
        backup, messages, commandline, register, platform, movement,
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.added, firstLine: 22, lastLine: 23)
    ]

  test "Added 3":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index f328eafe..57a9ea4d 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -20,13 +20,14 @@
 import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
             encodings]
 import syntax/highlite
+a
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
        windownode, color, settings, statusline, bufferstatus, cursor, tabline,
        backup, messages, commandline, register, platform, movement,
        autocomplete, suggestionwindow, filermodeutils, debugmodeutils,
        independentutils, viewhighlight, helputils, backupmanagerutils,
        diffviewerutils, messagelog, sidebar
+b
 # Save cursor position when a buffer for a window(file) gets closed.
 type LastCursorPosition* = object
   path: Runes
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.added, firstLine: 22, lastLine: 22),
      Diff(operation: OperationType.added, firstLine: 29, lastLine: 29)
    ]

  test "Changed and added 1":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index 6b23176b..d3d54244 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -18,7 +18,8 @@
 #[############################################################################]#

 import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
-            encodings] modified
+            encodings]
+
 import syntax/highlite
 import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
        windownode, color, settings, statusline, bufferstatus, cursor, tabline,
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.changed, firstLine: 20, lastLine: 20),
      Diff(operation: OperationType.added, firstLine: 21, lastLine: 21)
    ]

  test "Changed and deleted 1":
    const diffResult = """
diff --git a/src/moepkg/editorstatus.nim b/src/moepkg/editorstatus.nim
index 6b23176b..bd0a8fd3 100644
--- a/src/moepkg/editorstatus.nim
+++ b/src/moepkg/editorstatus.nim
@@ -19,8 +19,7 @@

 import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
             encodings]
-import syntax/highlite
-import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
+import syntax/highlite modified
        windownode, color, settings, statusline, bufferstatus, cursor, tabline,
        backup, messages, commandline, register, platform, movement,
        autocomplete, suggestionwindow, filermodeutils, debugmodeutils,
"""

    check diffResult.splitLines.parseGitDiffOutput == @[
      Diff(operation: OperationType.changedAndDeleted, firstLine: 21, lastLine: 21)
    ]
