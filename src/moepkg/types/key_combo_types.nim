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

## Key combinations and what Insert mode records of them, kept out of
## `key_bindings/registry` so `types` need not import the binding tables.

type
  ## Key modifiers that can be combined
  KeyModifier* = enum
    kmNone
    kmCtrl
    kmAlt
    kmShift
    kmMeta

  ## A key combination with potential modifiers
  ## We store the key as char and special key kind separately
  ## to avoid direct dependency on celina.Key type
  SpecialKey* = enum
    skNone
    skEnter
    skTab
    skBackTab
    skBackspace
    skDelete
    skEscape
    skUp
    skDown
    skLeft
    skRight
    skPageUp
    skPageDown
    skHome
    skEnd
    skFunction

  KeyCombo* = object
    case isSpecial*: bool
    of true:
      special*: SpecialKey
      fnNum*: int ## For function keys
    of false:
      char*: string
    modifiers*: set[KeyModifier]

  TypedInputKind* = enum
    tiKey # A key, typed again as it was
    tiText # Text that came in otherwise (a paste, a completion)

  TypedInput* = object ## One thing typed in Insert mode
    case kind*: TypedInputKind
    of tiKey:
      key*: KeyCombo
    of tiText:
      removeBefore*: int # Characters before the cursor the text replaces
      removeAfter*: int # and after it
      text*: string
      cursorAt*: int # Characters into `text` the cursor ends up at
