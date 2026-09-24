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

## What `waitid` reports, for waiting on a child without reaping it.

import std/posix

# Own names: some systems' `std/posix` declares these and others do not.
var
  idPid* {.importc: "P_PID", header: "<sys/wait.h>".}: cint
  cldExited* {.importc: "CLD_EXITED", header: "<signal.h>".}: cint
  cldStopped* {.importc: "CLD_STOPPED", header: "<signal.h>".}: cint

proc decodeSiginfo*(info: SigInfo): int =
  ## Decode a `waitid` result to an exit code as a shell reports it.
  if info.si_code == cldExited:
    return info.si_status.int
  return 128 + info.si_status.int
