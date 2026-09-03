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

## Handler module re-export surface
##
## Single source of truth for the dispatcher layer's handler-module list.
## `handler_manager.nim` re-exports this so external callers (`editor.nim`,
## `handler.nim`, tests) see the same public surface, and `mode_dispatchers.nim`
## imports it to reach the per-mode key handlers it forwards to.
##
## Previously this module list was hand-maintained in three places (the import
## *and* export blocks of `handler_manager.nim`, plus the import block of
## `mode_dispatchers.nim`). Centralizing it here means adding a sub-state mode
## touches the list once, not three times.
##
## Excludes `mode_dispatchers` itself (it imports this module, so re-exporting
## it from here would be circular) and `command_passthrough` (an
## implementation detail of `handler_manager`, never part of the public
## surface). `handler_manager` exports `mode_dispatchers` separately.

import
  handler_types, handler_result, normal_handler, insert_handler, insert_commands,
  command_handler, visual_handler, replace_handler, filer_handler, filetree_handler,
  log_viewer_handler, help_handler, buffer_manager_handler, bookmark_manager_handler,
  backup_manager_handler, diff_viewer_handler, recent_file_mode_handler, debug_handler,
  config_handler, references_handler, documentsymbol_handler, callhierarchy_handler

export
  handler_types, handler_result, normal_handler, insert_handler, insert_commands,
  command_handler, visual_handler, replace_handler, filer_handler, filetree_handler,
  log_viewer_handler, help_handler, buffer_manager_handler, bookmark_manager_handler,
  backup_manager_handler, diff_viewer_handler, recent_file_mode_handler, debug_handler,
  config_handler, references_handler, documentsymbol_handler, callhierarchy_handler

when not defined(moe.embedded):
  import terminal_handler
  export terminal_handler
