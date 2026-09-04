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

## StylePatch: an explicit representation of partial style overrides.
##
## Rendering layers may want to override only the background, only the
## foreground, or augment modifiers while preserving the rest of the
## syntax-derived style. Expressing those intents as direct `style.bg = X.bg`
## assignments scattered across the renderer makes the override semantics
## implicit and hard to extend. `StylePatch` makes the intent first-class.
##
## Modifier semantics: union. The `modifiers` field is always set-union'd
## into the base; an empty set means "no change". To replace a base style
## entirely (including modifiers), use `full(s)` which packages every
## field of the source Style.

import std/options

import celina_backend as celina

type StylePatch* = object
  fg*: Option[ColorValue]
  bg*: Option[ColorValue]
  modifiers*: set[StyleModifier]

const noPatch* = StylePatch()

func merge*(base: Style, patch: StylePatch): Style {.inline.} =
  ## Apply `patch` on top of `base`. fg/bg are replaced when the patch
  ## specifies them; modifiers are unioned.
  result = base
  if patch.fg.isSome:
    result.fg = patch.fg.get
  if patch.bg.isSome:
    result.bg = patch.bg.get
  result.modifiers = base.modifiers + patch.modifiers

func bgOnly*(bg: ColorValue): StylePatch {.inline.} =
  StylePatch(bg: some(bg))

func fgOnly*(fg: ColorValue): StylePatch {.inline.} =
  StylePatch(fg: some(fg))

func withModifiers*(mods: set[StyleModifier]): StylePatch {.inline.} =
  StylePatch(modifiers: mods)

func full*(s: Style): StylePatch {.inline.} =
  ## Patch that replaces fg, bg, and unions modifiers from `s`.
  StylePatch(fg: some(s.fg), bg: some(s.bg), modifiers: s.modifiers)
