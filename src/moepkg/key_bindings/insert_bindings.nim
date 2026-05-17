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

## Default Insert and Replace mode key bindings.
##
## Both modes share the same exit-to-Normal bindings, so they are applied via
## a single mode-list loop.

import ../[modes, key_bindings]

const InsertReplaceBindings: seq[tuple[key, cmd: string]] =
  @[("Escape", "switch-to-normal"), ("C-c", "switch-to-normal")]

proc bindInsertAndReplaceModes*(registry: KeyBindingRegistry) =
  ## Apply default Insert and Replace mode bindings.
  for mode in [EditorMode.Insert, EditorMode.Replace]:
    for (key, cmd) in InsertReplaceBindings:
      registry.bindKey(mode, key, cmd)
