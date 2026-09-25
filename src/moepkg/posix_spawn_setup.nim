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

## Starting a child with `posix_spawn`, and what every child moe starts gets.

import std/[dynlib, posix]

var environ* {.importc, header: "<unistd.h>".}: cstringArray

type
  AddActions* =
    proc(actions: var Tposix_spawn_file_actions): cint {.gcsafe, raises: [].}
    ## Add file actions for the child. 0, or the error.
  AddChdir = proc(actions: ptr Tposix_spawn_file_actions, path: cstring): cint {.
    cdecl, gcsafe, raises: []
  .}
  AddClosefrom = proc(actions: ptr Tposix_spawn_file_actions, lowFd: cint): cint {.
    cdecl, gcsafe, raises: []
  .}

{.
  emit: """/*TYPESECTION*/
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>
static int moeCanCloseFrom(void) {
  /* What glibc's closefrom action needs in the child: close_range, or else
     /proc/self/fd to walk. With neither it fails the whole start. */
#if defined(SYS_close_range) && !defined(__ANDROID__)
  /* Closes nothing: no descriptor is that high. */
  if (syscall(SYS_close_range, ~0u, ~0u, 0u) == 0) return 1;
#endif
  int dir = open("/proc/self/fd", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (dir < 0) return 0;
  close(dir);
  return 1;
}
"""
.}
proc moeCanCloseFrom(): cint {.importc, nodecl.}

let
  # Looked up rather than linked: an older libc would refuse to start moe.
  # glibc has had the first since 2.29 and the second since 2.34.
  libc = loadLib()
  addChdir = cast[AddChdir](libc.symAddr("posix_spawn_file_actions_addchdir_np"))
  addClosefrom =
    cast[AddClosefrom](libc.symAddr("posix_spawn_file_actions_addclosefrom_np"))
  closefromWorks = not addClosefrom.isNil and moeCanCloseFrom() != 0

proc canChdirInChild*(): bool =
  not addChdir.isNil

proc chdirInChild*(actions: var Tposix_spawn_file_actions, dir: string): cint =
  ## Have the child enter `dir` before it runs, leaving moe's own directory
  ## alone. Only when `canChdirInChild`.
  addChdir(addr actions, dir.cstring)

proc canCloseInherited*(): bool =
  closefromWorks

proc closeInherited*(actions: var Tposix_spawn_file_actions): cint =
  ## Have the child close every descriptor from 3 up. Not everything moe opens
  ## is close-on-exec (`osproc` pipes for git and the clipboard are not), and a
  ## child holding a pipe's write end keeps its reader from ever seeing EOF.
  ## 0, doing nothing, where libc cannot.
  if addClosefrom.isNil:
    return 0
  addClosefrom(addr actions, 3)

proc initChildAttrs(attrs: var Tposix_spawnattr, ownGroup: bool): cint =
  ## Initialise `attrs`: nothing blocked, SIGPIPE back to its default (chronos
  ## ignores it in moe, and an ignored signal survives exec), and a process
  ## group of its own when `ownGroup`. 0, and the caller destroys `attrs`; or
  ## the error, and there is nothing to destroy.
  result = posix_spawnattr_init(attrs)
  if result != 0:
    return
  var mask, defaults: Sigset
  if sigemptyset(mask) != 0 or sigemptyset(defaults) != 0 or
      sigaddset(defaults, SIGPIPE) != 0:
    result = errno
  var flags = POSIX_SPAWN_SETSIGMASK or POSIX_SPAWN_SETSIGDEF
  if result == 0:
    result = posix_spawnattr_setsigmask(attrs, mask)
  if result == 0:
    result = posix_spawnattr_setsigdefault(attrs, defaults)
  if result == 0 and ownGroup:
    flags = flags or POSIX_SPAWN_SETPGROUP
    result = posix_spawnattr_setpgroup(attrs, 0)
  if result == 0:
    result = posix_spawnattr_setflags(attrs, flags)
  if result != 0:
    discard posix_spawnattr_destroy(attrs)

proc spawnChild*(
    pid: var Pid,
    file: string,
    argv: openArray[string],
    ownGroup: bool,
    addActions: AddActions = nil,
): cint =
  ## Start `file`, looked up on PATH unless it has a slash, with the
  ## attributes of `initChildAttrs` and the file actions `addActions` adds.
  ## 0, or the error.
  var attrs: Tposix_spawnattr
  result = initChildAttrs(attrs, ownGroup)
  if result != 0:
    return
  defer:
    discard posix_spawnattr_destroy(attrs)
  var actions: Tposix_spawn_file_actions
  result = posix_spawn_file_actions_init(actions)
  if result != 0:
    return
  defer:
    discard posix_spawn_file_actions_destroy(actions)
  if not addActions.isNil:
    result = addActions(actions)
    if result != 0:
      return

  let args = allocCStringArray(argv)
  defer:
    deallocCStringArray(args)
  result = posix_spawnp(pid, file.cstring, actions, attrs, args, environ)
