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

## User hooks: commands attached to editor events.
##
## Matching by event; running them belongs to `editor_hooks`. Matching by file
## and argv expansion are shared with QuickRun in `file_command`.

import file_command
import syntax/tokenizer
import types/config_types

export
  HookConfig, HookEntry, HookEvent, HookFailAction, ValidHookEvents,
  ValidHookFailActions, DefaultHookTimeout, isExHook
export file_command

type HookCommand* = object
  ## One entry resolved against one file, ready to exec: tokenized, expanded,
  ## with an absolute path.
  event*: HookEvent
  path*: string ## Absolute path the hook fired for.
  command*: string ## The command line as written, to label its output.
  cmd*: string
  args*: seq[string]
  workingDir*: string
  timeout*: int
  showOutput*: bool
  onFail*: HookFailAction

proc parseHookEvent*(s: string): HookEvent =
  ## Parse `s` as `HookEvent`. Called by name from `config_macros`' enum
  ## loader once `s` is in `ValidHookEvents`, so the fallback to the first
  ## event is never reached from a config file.
  for event in HookEvent:
    if $event == s:
      return event
  HookEvent.low

proc parseHookFailAction*(s: string): HookFailAction =
  ## Parse `s` as `HookFailAction`; see `parseHookEvent`.
  for action in HookFailAction:
    if $action == s:
      return action
  HookFailAction.low

proc matches*(
    entry: HookEntry, event: HookEvent, path: string, language: SourceLanguage
): bool =
  ## True when `entry` applies to this event and file.
  ## An unparsable `filter` matches nothing.
  entry.event == event and entry.matchesFile(path, language)

proc hooksFor*(
    config: HookConfig, event: HookEvent, path: string, language: SourceLanguage
): seq[HookEntry] =
  ## Every enabled entry that applies, in config order.
  if not config.enable or path.len == 0:
    return @[]
  for entry in config.entries:
    if entry.matches(event, path, language):
      result.add entry
