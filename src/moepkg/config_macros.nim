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

## Declarative config metadata via custom pragmas + code-generating macros.
##
## Goal: a single source of truth (the struct definitions in `config.nim`)
## drives both the TOML loader (`config_loader.nim`) and the config-mode UI
## descriptor list (`config_mode.nim`). The macros walk the typed AST of an
## annotated type and emit the equivalent `loadBool/loadInt/...` calls or
## `ConfigItemDescriptor(...)` entries.
##
## Adding a new setting:
##   1. Add the field to the appropriate section type in `config.nim` with
##      `{.cfg.}` and any constraint pragmas (cfgMin, cfgMax, cfgEnum, ...).
##   2. If the field has no UI representation, add `{.cfgNoUi.}`.
##   3. Provide a default in `newEditorConfig()`.
##   That's it — the loader call and the UI descriptor are auto-generated.
##
## Adding a new enum-typed field:
##   The loader macro relies on naming conventions to find the parser and
##   validation table for an enum `XxxType`:
##     - a `proc parseXxx(s: string): XxxType` to convert string -> variant
##     - a `const ValidXxxs = [...]` listing accepted TOML string values
##   A trailing `Config` in the enum type name is stripped: e.g.
##   `ClipboardTool` looks up `parseClipboardTool` / `ValidClipboardTools`.
##   Both must be defined in (or imported into) `config_loader.nim` before the
##   macro expands; otherwise the generated code will fail to compile.
##
##   All enum members must declare an explicit string literal value
##   (e.g. `seA = "a", seB = "b"`). The descriptor macro derives the UI
##   option list from those literals; bare members fall back to the Nim
##   ident, which will not round-trip through `parseEnum` / the loader's
##   `parseXxx`.
##
## Pragma summary:
##   On the type:      cfgSection: "TomlSectionName"
##   On a field:       cfg, cfgSkip, cfgNoUi
##                     cfgSubSection: "Child"             (the field's type is the
##                                                         [Parent.Child] sub-table
##                                                         of a section group)
##                     cfgArrayOfTables: "name"           (seq[T] loaded from the
##                                                         [[Parent.name]] array of
##                                                         tables of a section group)
##                     cfgEntryRules: pred                (extra validation for one
##                                                         array-of-tables element)
##                     cfgArrayRules: pred                (extra validation for the
##                                                         array-of-tables field as
##                                                         a whole)
##                     cfgOnlyWhen(pred, "note")          (the key applies only when
##                                                         pred(value) holds; note
##                                                         says when, for docs and
##                                                         completion)
##                     cfgMin: v, cfgMax: v, cfgStep: v  (numerics)
##                     cfgKey: "TomlKey"                  (TOML/Nim name diverges)
##                     cfgUiName: "Label"                 (UI display name)
##                     cfgDirPath                         (Option[string] + dir validation)
##                     cfgVisible: pred                   (visibleWhen callback;
##                                                         pred must accept an
##                                                         `EditorConfig` and
##                                                         return `bool`)
##                     cfgEnum: ["a", "b", ...]           (override the enum option
##                                                         order/subset shown in the UI)
##                     cfgEnumStrings: ["a", "b"] | Const (post-validate a string
##                                                         or seq[string] field
##                                                         against an option set,
##                                                         written out or named)
##                     cfgDeprecated: "msg"                (transitional deprecation:
##                                                         loader accepts the value
##                                                         but records a notice;
##                                                         serializer / UI / docs
##                                                         skip the field)
##
## Supported field types:
##   loader + descriptor: bool, int, float, string, enum
##   loader only:         Option[string], seq[string]  (mark field with cfgNoUi)
##
## `LspConfig` is a *section group* (see the `generateSectionGroup*` macros);
## only its dynamic `[Lsp.<languageId>]` entries stay hand-written. A group may
## also own a `{.cfgArrayOfTables.}` field, whose `[[Parent.name]]` elements are
## derived the same way, with cross-field rules in `{.cfgEntryRules.}`.
##
## Sections intentionally not migrated (hand-written): ThemeConfig (conditional
## file/string handling), KeyMappingConfig (OrderedTable + parsing),
## CommandAliases/ShellCommands (nested objects).

import std/[macros, sets, strutils]

import help_description

## Apply to a section type to give it a TOML section name.
##   StandardConfig* {.cfgSection: "Standard".} = object
template cfgSection*(name: string) {.pragma.}

## Marker: this field is loaded/described automatically.
template cfg*() {.pragma.}

## Mark a field as the `[Parent.Name]` sub-table of a section group:
##   completion* {.cfgSubSection: "Completion".}: LspFeatureConfig
##
## Unlike `{.cfgSection.}` (a *type* pragma) the name lives on the field, so
## several fields may share one type. Must not be combined with `{.cfg.}`.
template cfgSubSection*(name: string) {.pragma.}

## Mark a type as a *section group* and name its parent TOML table:
##   LspConfig* {.cfgGroup: "Lsp".} = object
##
## Every `generateSectionGroup*` macro reads the name from here, so loader,
## serializer, UI and docs cannot disagree about what the user must type.
template cfgGroup*(name: string) {.pragma.}

## Mark a field as the `[[Parent.Name]]` array of tables of a section group:
##   entries* {.cfgArrayOfTables: "entries".}: seq[HookEntry]
##
## Each element is loaded from its table the way a section is, so the key list,
## the unknown-key check, the serializer and the completion schema all come off
## the element type.
##
## An element starts from the element type's own field defaults
## (`enabled*: bool = true`), not from `newEditorConfig`: entries are built per
## TOML table, so there is no single instance to initialise.
template cfgArrayOfTables*(name: string) {.pragma.}

## Name the predicate that validates one element of a `{.cfgArrayOfTables.}`
## field, after the generated loads and the unknown-key check have run:
##   entries* {.cfgArrayOfTables: "entries", cfgEntryRules: checkHookEntry.}:
##     seq[HookEntry]
##
## `proc (t: TomlTableRef, entry: var Elem, label: string,
##        vr: var ValidationResult): bool`
##
## It sees the element's own table, so it can tell a key left out from one
## written with the default value, and may amend the entry. Returning false
## drops the entry.
template cfgEntryRules*(pred: untyped) {.pragma.}

## Name the predicate that validates a `{.cfgArrayOfTables.}` field as a whole,
## once every element has loaded and `{.cfgEntryRules.}` has had its say:
##   entries* {.cfgArrayOfTables: "entries", cfgArrayRules: checkHookOrder.}:
##     seq[HookEntry]
##
## `proc (entries: var seq[Elem], label: string, vr: var ValidationResult)`
##
## For rules about the entries together -- names that must not repeat, an
## ordering, a mutually exclusive pair -- which an element predicate cannot see.
template cfgArrayRules*(pred: untyped) {.pragma.}

## This key belongs to its object only when `pred(value)` holds, where `value`
## is the object the field is part of, and `note` says in words when that is:
##   io* {.cfg, cfgOnlyWhen(isFilterEntry, "kind is \"filter\"").}: HookIo
##
## One rule on every surface: the serializer leaves the key out, the loader
## rejects it and keeps the default, and the docs and completion popup show
## `note` instead of offering the key everywhere.
##
## `pred` reads other fields of the same object, so the checks run after the
## whole object has loaded and the declaration order does not matter.
template cfgOnlyWhen*(pred: untyped, note: static string) {.pragma.}

## Apply to a field or section type to opt out of macro generation.
template cfgSkip*() {.pragma.}

## Numeric lower bound, validated at load time.
template cfgMin*(v: untyped) {.pragma.}

## Numeric upper bound.
template cfgMax*(v: untyped) {.pragma.}

## Step size for float fields in the config-mode UI.
template cfgStep*(v: float) {.pragma.}

## Override the field's UI display name.
template cfgUiName*(name: string) {.pragma.}

## Attach a `visibleWhen` predicate by identifier. The referenced predicate
## must accept an `EditorConfig` and return `bool`; the descriptor macro
## emits `proc(c: EditorConfig): bool {.noSideEffect.} = pred(c)` as the
## `visibleWhen` field of the generated descriptor. The pragma itself does
## not check the predicate's signature — mismatches surface as type errors
## at the descriptor macro's expansion site.
template cfgVisible*(fn: untyped) {.pragma.}

## For enum-typed fields, the cycle order of options in the UI.
template cfgEnum*(opts: untyped) {.pragma.}

## Restrict a `string` or `seq[string]` field to a fixed option set. The set is
## either written out, or named when it is computed elsewhere and too long or
## too derived to spell:
##   popupPosition* {.cfg, cfgEnumStrings: ["topRight", "topLeft"].}: string
##   filetype* {.cfg, cfgNoUi, cfgEnumStrings: sourceLanguageToStr.}: seq[string]
##
## The loader enforces the set, the schema advertises it as an enum and the
## docs list it, whichever form it takes. A value outside the set is reported
## and the field keeps its default, as every other load helper does.
template cfgEnumStrings*(opts: untyped) {.pragma.}

## Override the TOML key when it differs from the Nim identifier.
template cfgKey*(name: string) {.pragma.}

## Field is auto-loaded but is not surfaced in the config-mode UI. Use for
## fields whose type has no descriptor representation (seq[T]) or that the
## UI intentionally hides.
template cfgNoUi*() {.pragma.}

## For Option[string] fields, validate that the resolved path is an existing
## directory at load time (uses loadOptionDirPath instead of loadOptionString).
template cfgDirPath*() {.pragma.}

## Mark a field as deprecated. When the key is present in the loaded TOML,
## the loader records a deprecation notice on the ValidationResult (via
## `addDeprecated`) but still assigns the value, keeping existing user
## configs working. The field is excluded from the serializer output and
## the config-mode UI (and from the auto-generated markdown docs) so it
## fades out of user configs naturally.
##
## Example:
##   oldFlag* {.cfg, cfgDeprecated: "use newFlag instead".}: bool
##
## When the migration window closes, remove the field entirely. Old configs
## will then surface as regular unknown-key notices.
template cfgDeprecated*(msg: string) {.pragma.}

## Human-readable description used by the `gen_config_docs` tool to render
## `documents/configfile.md`. Required for every field that participates in
## auto-generated documentation. The string is emitted verbatim as the
## fourth column of the markdown table row.
template cfgDocDescription*(desc: string) {.pragma.}

## Override the default value shown in `documents/configfile.md`. Use this
## when `newEditorConfig()` returns a system-dependent value (e.g. the
## auto-detected clipboard tool) and the documentation needs a stable
## representative literal instead. Accepts an untyped expression and the
## tool stringifies it.
template cfgDocDefault*(v: untyped) {.pragma.}

## Opt a field out of the auto-generated `documents/configfile.md` tables
## while keeping it active for the TOML loader and the config-mode UI.
## Without this pragma, every `{.cfg.}` field in a section whose markdown
## table is auto-generated MUST carry `{.cfgDocDescription.}` — otherwise
## the macro raises a compile-time error to prevent silently undocumented
## settings.
template cfgDocSkip*() {.pragma.}

proc unwrapName(node: NimNode): NimNode =
  ## Strip `*` postfix from an ident.
  if node.kind == nnkPostfix:
    node[1]
  else:
    node

proc pragmaName(p: NimNode): string =
  ## Return the name of a pragma node, "" if not nameable.
  case p.kind
  of nnkIdent, nnkSym:
    p.strVal
  of nnkCall, nnkExprColonExpr:
    if p[0].kind in {nnkIdent, nnkSym}:
      p[0].strVal
    else:
      ""
  else:
    ""

proc findPragma(pragmas: NimNode, name: string): NimNode =
  ## Return the pragma node matching `name`, or nil.
  if pragmas.kind == nnkEmpty:
    return nil
  for p in pragmas:
    if pragmaName(p) == name:
      return p
  nil

proc hasPragma(pragmas: NimNode, name: string): bool =
  findPragma(pragmas, name) != nil

proc pragmaArg(p: NimNode): NimNode =
  ## Extract the single argument from `{.name: val.}` / `{.name(val).}`.
  if p == nil:
    return nil
  case p.kind
  of nnkExprColonExpr:
    p[1]
  of nnkCall:
    if p.len >= 2:
      p[1]
    else:
      nil
  else:
    nil

proc pragmaArgN(p: NimNode, i: int): NimNode =
  ## Extract the `i`-th argument of a multi-argument `{.name(a, b).}` pragma,
  ## or nil. `pragmaArg` is the one-argument case, which also accepts the
  ## `{.name: val.}` spelling.
  if p == nil or p.kind != nnkCall or p.len < i + 2:
    return nil
  p[i + 1]

proc typeDef(T: NimNode): NimNode =
  ## Return the TypeDef AST for a typedesc symbol.
  ## Handles `typedesc[X]` by recursing into the inner symbol.
  var sym = T
  if sym.kind == nnkBracketExpr and sym.len >= 2:
    sym = sym[1]
  sym.getImpl

proc typePragmas(td: NimNode): NimNode =
  ## Extract the pragma list from a TypeDef.
  ## TypeDef shape: TypeDef(name, generics, body) where name may be
  ## `nnkPragmaExpr(ident, pragmas)`.
  if td.kind != nnkTypeDef:
    return newEmptyNode()
  let nameNode = td[0]
  if nameNode.kind == nnkPragmaExpr:
    nameNode[1]
  else:
    newEmptyNode()

proc sectionName(td: NimNode): string =
  ## Read the `cfgSection: "Name"` pragma from a TypeDef.
  let pragmas = typePragmas(td)
  let p = findPragma(pragmas, "cfgSection")
  if p == nil:
    error("type has no {.cfgSection: \"...\".} pragma", td)
  let arg = pragmaArg(p)
  if arg == nil or arg.kind != nnkStrLit:
    error("cfgSection requires a string literal", p)
  arg.strVal

iterator sectionFields(
    td: NimNode
): tuple[name: string, typ: NimNode, pragmas: NimNode] =
  ## Yield (fieldName, fieldType, pragmaList) for each field of an object.
  ## Transparently unwraps `ref object` / `ptr object`.
  ## `pragmas` is nnkEmpty for unannotated fields.
  if td.kind == nnkTypeDef:
    var body = td[2]
    if body.kind in {nnkRefTy, nnkPtrTy} and body.len >= 1:
      body = body[0]
    if body.kind == nnkObjectTy:
      let recList = body[2]
      if recList.kind == nnkRecList:
        for identDef in recList:
          if identDef.kind == nnkIdentDefs:
            let typeNode = identDef[^2]
            for i in 0 ..< identDef.len - 2:
              var fieldNode = identDef[i]
              var pragmas: NimNode = newEmptyNode()
              if fieldNode.kind == nnkPragmaExpr:
                pragmas = fieldNode[1]
                fieldNode = fieldNode[0]
              let nameNode = unwrapName(fieldNode)
              yield (nameNode.strVal, typeNode, pragmas)

proc enumParseName(typeIdent: NimNode): NimNode =
  ## For enum type `ClipboardTool` -> `parseClipboardTool`.
  ## Trailing `Config` is stripped (e.g. `FooConfig` -> `parseFoo`).
  let bare = typeIdent.strVal
  let stripped =
    if bare.endsWith("Config"):
      bare[0 ..< bare.len - "Config".len]
    else:
      bare
  ident("parse" & stripped)

proc enumValidName(typeIdent: NimNode): NimNode =
  ## For enum `ClipboardTool` -> `ValidClipboardTools` (pluralized).
  let bare = typeIdent.strVal
  let stripped =
    if bare.endsWith("Config"):
      bare[0 ..< bare.len - "Config".len]
    else:
      bare
  ident("Valid" & stripped & "s")

proc isEnumTypeIdent(typeNode: NimNode): bool =
  ## True if the field type is an enum.
  if typeNode.kind notin {nnkIdent, nnkSym}:
    return false
  let impl = typeNode.getImpl
  if impl == nil or impl.kind != nnkTypeDef:
    return false
  let body = impl[2]
  body.kind == nnkEnumTy

proc isObjectTypeIdent(typeNode: NimNode): bool =
  ## True if the type name refers to an object type.
  if typeNode.kind notin {nnkIdent, nnkSym}:
    return false
  let impl = typeNode.getImpl
  if impl == nil or impl.kind != nnkTypeDef:
    return false
  var body = impl[2]
  if body.kind in {nnkRefTy, nnkPtrTy} and body.len >= 1:
    body = body[0]
  body.kind == nnkObjectTy

proc isSeqOfString(typeNode: NimNode): bool =
  ## True if the field type is `seq[string]`.
  typeNode.kind == nnkBracketExpr and typeNode.len >= 2 and
    typeNode[0].kind in {nnkIdent, nnkSym} and typeNode[0].strVal == "seq" and
    typeNode[1].kind in {nnkIdent, nnkSym} and typeNode[1].strVal == "string"

proc isOptionOfString(typeNode: NimNode): bool =
  ## True if the field type is `Option[string]`.
  typeNode.kind == nnkBracketExpr and typeNode.len >= 2 and
    typeNode[0].kind in {nnkIdent, nnkSym} and typeNode[0].strVal == "Option" and
    typeNode[1].kind in {nnkIdent, nnkSym} and typeNode[1].strVal == "string"

proc parseStringArrayLit(node: NimNode): seq[string] =
  ## Parse `["a", "b", ...]` or `@["a", "b", ...]` into a string seq.
  ## Returns @[] if the node is not a well-formed array of string literals.
  if node == nil:
    return @[]
  var bracket = node
  if bracket.kind == nnkPrefix and bracket.len >= 2 and
      bracket[0].kind in {nnkIdent, nnkSym} and bracket[0].strVal == "@":
    bracket = bracket[1]
  if bracket.kind != nnkBracket:
    return @[]
  result = @[]
  for v in bracket:
    if v.kind == nnkStrLit:
      result.add v.strVal
    else:
      return @[]

proc optionSetNode(p: NimNode): NimNode =
  ## The expression naming a `{.cfgEnumStrings.}` option set: the array written
  ## in the pragma, or the constant it names. Both work as an
  ## `openArray[string]` at the load site.
  result = pragmaArg(p)
  if result == nil:
    error("cfgEnumStrings requires an array of string literals or a constant", p)

proc optionSetLiterals(p: NimNode): seq[string] =
  ## The members of a `{.cfgEnumStrings.}` set when it is written out. Empty
  ## when the set is only named: `getImpl` fatals on an unresolved identifier,
  ## so a named set is read at the call site instead.
  let node = optionSetNode(p)
  if node.kind in {nnkBracket, nnkPrefix}:
    result = parseStringArrayLit(node)
    if result.len == 0:
      error(
        "cfgEnumStrings requires a non-empty array of string literals " &
          "(e.g. `{.cfgEnumStrings: [\"a\", \"b\"].}`) or the name of a " &
          "non-empty option set",
        p,
      )
  else:
    result = @[]

proc optionSetNonEmptyCheck(p: NimNode): NimNode =
  ## A stanza rejecting an empty named option set at compile time. A set
  ## written out is already checked by `optionSetLiterals`; a length that is
  ## not compile-time known falls through to the runtime guard at the load site.
  let node = optionSetNode(p)
  quote:
    when compiles(static(`node`.len)):
      static:
        doAssert `node`.len > 0, "cfgEnumStrings requires a non-empty option set"

proc enumStringValues(typeNode: NimNode): seq[string] =
  ## For `ClipboardTool = enum cbtXsel = "xsel" ...` -> @["xsel", ...].
  ##
  ## NOTE: every enum member is expected to declare an explicit string
  ## literal value. Bare members fall back to the Nim ident name here,
  ## which the loader's `parseXxx` / `ValidXxxs` table will not recognize.
  ## Mixed declarations (some valued, some bare) silently produce a
  ## non-round-tripping option list — keep `Valid…` arrays and the enum
  ## body in sync by always supplying a string literal.
  let impl = typeNode.getImpl
  if impl == nil or impl.kind != nnkTypeDef:
    return @[]
  let body = impl[2]
  if body.kind != nnkEnumTy:
    return @[]
  result = @[]
  for i in 1 ..< body.len: # body[0] is empty (parent enum)
    let field = body[i]
    case field.kind
    of nnkEnumFieldDef:
      # EnumFieldDef(name, value)
      let v = field[1]
      if v.kind == nnkStrLit:
        result.add v.strVal
      else:
        result.add field[0].strVal
    of nnkIdent, nnkSym:
      result.add field.strVal
    else:
      discard

iterator serializableFields(
    td: NimNode
): tuple[fieldName: string, typeNode: NimNode, pragmas: NimNode, key: string] =
  ## Yield each `{.cfg.}` field of the section TypeDef `td` (skipping
  ## `{.cfgSkip.}` and un-annotated fields), already paired with its resolved
  ## TOML key (the `{.cfgKey.}` override, or the field name). Shared by
  ## `buildLoaderBody` and `buildSerializerBody` so the skip filter and key
  ## resolution live in exactly one place and the two bodies cannot drift.
  for (fieldName, typeNode, pragmas) in sectionFields(td):
    if hasPragma(pragmas, "cfgSkip"):
      continue
    if not hasPragma(pragmas, "cfg"):
      continue
    let keyOverride = findPragma(pragmas, "cfgKey")
    let key =
      if keyOverride != nil:
        let a = pragmaArg(keyOverride)
        if a == nil or a.kind != nnkStrLit:
          error("cfgKey requires a string literal", keyOverride)
        a.strVal
      else:
        fieldName
    yield (fieldName, typeNode, pragmas, key)

proc scalarKeys(td: NimNode): seq[string] =
  ## The TOML keys of a section's `{.cfg.}` fields, in declaration order.
  ## Single producer for the loader's unknown-key check, the sub-section name
  ## collision guard and `generateSectionGroupKeys`, so those cannot disagree
  ## about what counts as a key of the section.
  for (_, _, _, key) in serializableFields(td):
    result.add key

proc validateEnumStringValues(typeNode: NimNode) =
  ## Compile-time guard for enum-typed config fields: every member must declare
  ## an explicit string value (e.g. `seA = "a"`). The serializer emits enum
  ## fields via `$value` and the loader only accepts the `ValidXxx` string-literal
  ## set, so a bare member (whose `$` yields the Nim ident) would silently fail
  ## to round-trip. Reject it here with a clear message instead.
  let impl = typeNode.getImpl
  if impl == nil or impl.kind != nnkTypeDef:
    return
  let body = impl[2]
  if body.kind != nnkEnumTy:
    return
  for i in 1 ..< body.len: # body[0] is empty (parent enum)
    let field = body[i]
    if field.kind != nnkEnumFieldDef or field[1].kind != nnkStrLit:
      let memberName =
        if field.kind == nnkEnumFieldDef:
          field[0].strVal
        else:
          field.strVal
      error(
        "enum `" & typeNode.strVal & "` member `" & memberName &
          "` has no explicit string value; the config serializer emits enums as " &
          "`$value` and the loader only accepts the string-literal set, so a bare " &
          "member cannot round-trip. Give every member a string value " &
          "(e.g. `xA = \"a\"`).",
        typeNode,
      )

type CfgFieldKind = enum
  ## The supported field-type taxonomy the loader and serializer both dispatch
  ## on. Centralizing it here means adding a new supported type touches one
  ## classifier, not two parallel `case` statements that could drift apart.
  cfkBool
  cfkInt
  cfkFloat
  cfkString
  cfkEnum
  cfkSeqString
  cfkOptionString
  cfkUnsupported

proc classifyConfigFieldType(typeNode: NimNode): CfgFieldKind =
  ## Map a section field's declared type to its `CfgFieldKind`. Shared by
  ## `buildLoaderBody` and `buildSerializerBody` so the set of types they accept
  ## cannot diverge.
  let typeName = if typeNode.kind in {nnkIdent, nnkSym}: typeNode.strVal else: ""
  case typeName
  of "bool":
    cfkBool
  of "int":
    cfkInt
  of "float":
    cfkFloat
  of "string":
    cfkString
  else:
    if isEnumTypeIdent(typeNode):
      cfkEnum
    elif isSeqOfString(typeNode):
      cfkSeqString
    elif isOptionOfString(typeNode):
      cfkOptionString
    else:
      cfkUnsupported

proc docTypeLabel(typeNode: NimNode): string =
  ## Map a Nim field type to the human-readable label used by
  ## `documents/configfile.md`. Enum-typed fields render as
  ## `string (enum: a, b, ...)`, since the TOML value is always a string.
  ## Falls back to stripping a trailing `Config` for any non-enum custom type.
  if typeNode.kind in {nnkIdent, nnkSym}:
    case typeNode.strVal
    of "bool":
      return "bool"
    of "int":
      return "integer"
    of "float":
      return "float"
    of "string":
      return "string"
    else:
      if isEnumTypeIdent(typeNode):
        let vals = enumStringValues(typeNode)
        if vals.len > 0:
          return "string (enum: " & vals.join(", ") & ")"
      let bare = typeNode.strVal
      if bare.endsWith("Config"):
        return bare[0 ..< bare.len - "Config".len]
      return bare
  if typeNode.kind == nnkBracketExpr and typeNode.len >= 2:
    let outer =
      if typeNode[0].kind in {nnkIdent, nnkSym}:
        typeNode[0].strVal
      else:
        ""
    let inner =
      if typeNode[1].kind in {nnkIdent, nnkSym}:
        typeNode[1].strVal
      else:
        ""
    case outer
    of "Option":
      if inner == "string":
        return "string (optional)"
      return inner & " (optional)"
    of "seq":
      if inner == "string":
        return "string array"
      return inner & " array"
    else:
      discard
  typeNode.repr

func cfgOptionSetLabel*(base: string, values: openArray[string]): string =
  ## The `<base> (enum: a, b)` label for a named `{.cfgEnumStrings.}` set,
  ## whose members are only a value at the call site.
  base & " (enum: " & values.join(", ") & ")"

proc optionSetLabel(base: string, values: openArray[string]): string =
  ## Compile-time twin of `cfgOptionSetLabel`, for a set written out in the
  ## pragma.
  base & " (enum: " & values.join(", ") & ")"

proc typeName(td: NimNode): string =
  ## The declared name of a TypeDef, with any pragma expression unwrapped.
  if td.kind != nnkTypeDef:
    return td.repr
  var nameNode = td[0]
  if nameNode.kind == nnkPragmaExpr:
    nameNode = nameNode[0]
  unwrapName(nameNode).strVal

type FieldSpec = object
  ## What one `{.cfg.}` field means, read off its pragmas exactly once.
  ##
  ## Holds the attributes more than one builder (loader, serializer, UI, docs,
  ## completion schema) reads, so they cannot drift. Attributes a single
  ## builder reads (cfgMin/cfgMax/cfgStep/cfgUiName/cfgVisible/cfgEnum, all the
  ## UI's) stay in `pragmas`.
  name: string
  key: string
  typ: NimNode
  kind: CfgFieldKind
  pragmas: NimNode
  optionSet: NimNode ## `{.cfgEnumStrings.}` set expression, nil without one
  optionSetLits: seq[string] ## its members; empty when the set is only named
  onlyWhen: NimNode ## `{.cfgOnlyWhen.}` predicate, nil without one
  onlyWhenNote: string ## when the key applies, in words
  deprecated: string
  isDeprecated: bool
  docDesc: string
  hasDocDesc: bool
  docSkip: bool
  noUi: bool

proc describeField(name: string, typ, pragmas: NimNode, key: string): FieldSpec =
  ## The single place a field's pragmas turn into meaning. Malformed pragmas
  ## are rejected here too, so a bad declaration fails once.
  result = FieldSpec(
    name: name,
    key: key,
    typ: typ,
    kind: classifyConfigFieldType(typ),
    pragmas: pragmas,
    noUi: hasPragma(pragmas, "cfgNoUi"),
    docSkip: hasPragma(pragmas, "cfgDocSkip"),
  )

  let enumStrP = findPragma(pragmas, "cfgEnumStrings")
  if enumStrP != nil:
    # An option set constrains free text, so it applies only to `string` and,
    # element by element, to `seq[string]`.
    if result.kind notin {cfkString, cfkSeqString}:
      error("cfgEnumStrings requires a string or seq[string] field", enumStrP)
    result.optionSet = optionSetNode(enumStrP)
    result.optionSetLits = optionSetLiterals(enumStrP)

  let onlyWhenP = findPragma(pragmas, "cfgOnlyWhen")
  if onlyWhenP != nil:
    let pred = pragmaArg(onlyWhenP)
    let note = pragmaArgN(onlyWhenP, 1)
    if pred == nil or note == nil or note.kind != nnkStrLit:
      error(
        "cfgOnlyWhen takes a predicate and a note saying when the key " &
          "applies, e.g. `{.cfgOnlyWhen(isFilterEntry, \"kind is \\\"filter\\\"\").}`. " &
          "The note is what the docs and the completion popup show.",
        onlyWhenP,
      )
    if note.strVal.len == 0:
      error("cfgOnlyWhen requires a non-empty note", onlyWhenP)
    result.onlyWhen = pred
    result.onlyWhenNote = note.strVal

  let deprecatedP = findPragma(pragmas, "cfgDeprecated")
  if deprecatedP != nil:
    let arg = pragmaArg(deprecatedP)
    if arg == nil or arg.kind != nnkStrLit:
      error("cfgDeprecated requires a string literal", deprecatedP)
    result.isDeprecated = true
    result.deprecated = arg.strVal

  let docDescP = findPragma(pragmas, "cfgDocDescription")
  if docDescP != nil:
    let arg = pragmaArg(docDescP)
    if arg == nil or arg.kind != nnkStrLit:
      error("cfgDocDescription requires a string literal", docDescP)
    result.hasDocDesc = true
    result.docDesc = arg.strVal

iterator specFields(td: NimNode): FieldSpec =
  ## Yield one `FieldSpec` per `{.cfg.}` field of the section TypeDef `td`.
  for (fieldName, typeNode, pragmas, key) in serializableFields(td):
    yield describeField(fieldName, typeNode, pragmas, key)

proc optionSetNonEmptyCheck(spec: FieldSpec): NimNode =
  ## A stanza rejecting an empty named option set at compile time, or an empty
  ## statement list when the field has no set to check.
  if spec.optionSet == nil:
    return newStmtList()
  optionSetNonEmptyCheck(findPragma(spec.pragmas, "cfgEnumStrings"))

proc optionSetDefaultCheck(spec: FieldSpec, elem: NimNode): NimNode =
  ## A stanza rejecting, at compile time, a `{.cfgEnumStrings.}` field of the
  ## element type `elem` whose declared default falls outside the set. Such a
  ## default would be serialized and then rejected on every load.
  ##
  ## Only element types are checked: a section starts from `newEditorConfig`,
  ## not from the field default the macro can see. A named set whose length is
  ## not compile-time known falls through, as in `optionSetNonEmptyCheck`.
  if spec.optionSet == nil:
    return newStmtList()
  let
    optionSet = spec.optionSet
    fieldIdent = ident(spec.name)
    msg = newLit(
      "the default of `" & spec.name &
        "` is outside its cfgEnumStrings set: it would be saved and then " &
        "rejected on the next load. Give the field a default the set accepts."
    )
  case spec.kind
  of cfkString:
    quote:
      when compiles(static(`optionSet`.len)):
        static:
          doAssert default(`elem`).`fieldIdent` in `optionSet`, `msg`
  of cfkSeqString:
    quote:
      when compiles(static(`optionSet`.len)):
        static:
          for d in default(`elem`).`fieldIdent`:
            doAssert d in `optionSet`, `msg`
  else:
    newStmtList()

proc typeLabelExpr(spec: FieldSpec): NimNode =
  ## The human-readable type shown by the reference docs and the completion
  ## popup, with any option set folded in (`string array (enum: ...)`).
  ## An expression, because a named set is only a value at the call site.
  let base = docTypeLabel(spec.typ)
  if spec.optionSet == nil:
    return newLit(base)
  if spec.optionSetLits.len > 0:
    return newLit(optionSetLabel(base, spec.optionSetLits))
  newCall(ident("cfgOptionSetLabel"), newLit(base), spec.optionSet)

proc valuesExpr(spec: FieldSpec): NimNode =
  ## The values the key accepts when they are a closed set, as an expression:
  ## booleans, an enum's members (`{.cfgEnum.}` overrides the derived order) or
  ## a `{.cfgEnumStrings.}` option set. An empty sequence for open-ended types.
  proc lits(values: openArray[string]): NimNode =
    var arr = newNimNode(nnkBracket)
    for v in values:
      arr.add newLit(v)
    newCall(ident("@"), arr)

  case spec.kind
  of cfkBool:
    lits(["true", "false"])
  of cfkEnum:
    let p = findPragma(spec.pragmas, "cfgEnum")
    if p != nil:
      lits(parseStringArrayLit(pragmaArg(p)))
    else:
      lits(enumStringValues(spec.typ))
  of cfkString, cfkSeqString:
    if spec.optionSet == nil:
      lits([])
    elif spec.optionSetLits.len > 0:
      lits(spec.optionSetLits)
    else:
      newCall(ident("@"), spec.optionSet)
  else:
    lits([])

proc conditionNote(spec: FieldSpec): string =
  ## The `{.cfgOnlyWhen.}` note, as the docs and the completion popup phrase
  ## it. Empty for a key that always applies.
  if spec.onlyWhen == nil:
    ""
  else:
    "only when " & spec.onlyWhenNote

proc checkNoChildTablePragmas(td: NimNode) =
  ## `{.cfgSubSection.}` and `{.cfgArrayOfTables.}` expand only for
  ## `{.cfgGroup.}` types; elsewhere they expand to nothing and leave a dead
  ## field behind. Reject the misplaced pragma instead of building around it.
  let owner = typeName(td)
  for (fieldName, _, pragmas) in sectionFields(td):
    for pragmaName in [
      "cfgSubSection", "cfgArrayOfTables", "cfgEntryRules", "cfgArrayRules"
    ]:
      let p = findPragma(pragmas, pragmaName)
      if p != nil:
        let msg =
          "field `" & fieldName & "` carries {." & pragmaName & ".} but `" & owner &
          "` is not a {.cfgGroup.} type: the pragma would expand to nothing"
        error(msg, p)

proc buildLoaderBody(
    td, t, cfgVar, vr: NimNode,
    sec: string,
    checkUnknown = true,
    secExpr: NimNode = nil,
    allowChildTables = false,
    extraKeys: seq[string] = @[],
): NimNode =
  ## Build the loader statements for the section TypeDef `td`, reading from the
  ## TOML table expression `t` into the config accessor `cfgVar`, recording
  ## issues in `vr`. Shared by `generateConfigLoader` (single section),
  ## `generateSectionLoaders` (whole-config dispatch) and the section-group
  ## macros so the per-field type handling lives in exactly one place.
  ##
  ## `sec` is the TOML section name to report issues under. `checkUnknown` is
  ## false for section groups, whose parent table also holds sub-tables and
  ## caller-defined dynamic keys.
  ##
  ## `secExpr` reports under a name known only at run time, such as one
  ## array-of-tables element's `Parent.name[3]`. It is bound to a local so the
  ## loads of one element do not each rebuild the string.
  ##
  ## `allowChildTables` is true only for a type whose child-table pragmas a
  ## later pass expands, and `extraKeys` are the names those children claim, so
  ## the unknown-key check does not report them as typos.
  ##
  ## Every helper this emits a call to follows the same refusal policy: a
  ## rejected key is reported and its field keeps its default (never partially
  ## adopted), and a rejected `[[...]]` element is dropped while the rest of
  ## the array loads. Either way the refusal is recorded in `vr`.
  if not allowChildTables:
    checkNoChildTablePragmas(td)

  result = newStmtList()

  var
    savedDefaults = newStmtList()
    loadCalls = newStmtList()
    conditionChecks = newStmtList()
    savedFor: seq[tuple[spec: FieldSpec, saved: NimNode]] = @[]

  var secLit = newLit(sec)
  if secExpr != nil:
    let secSym = genSym(nskLet, "section")
    result.add newLetStmt(secSym, secExpr)
    secLit = secSym

  for spec in specFields(td):
    let
      fieldName = spec.name
      typeNode = spec.typ
      pragmas = spec.pragmas
      fieldAcc = newDotExpr(cfgVar, ident(fieldName))
      keyLit = newLit(spec.key)
      optionSet = spec.optionSet

    # A conditional field needs its pre-load value, to put back when the
    # predicate does not hold.
    if spec.onlyWhen != nil:
      let saved = genSym(nskLet, "default")
      savedDefaults.add newLetStmt(saved, fieldAcc)
      savedFor.add (spec, saved)

    loadCalls.add optionSetNonEmptyCheck(spec)

    # Dispatch by type
    case spec.kind
    of cfkBool:
      loadCalls.add quote do:
        loadBool(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
    of cfkInt:
      let minP = findPragma(pragmas, "cfgMin")
      let maxP = findPragma(pragmas, "cfgMax")
      var call = newCall(ident("loadInt"), t, keyLit, fieldAcc, vr, secLit)
      if minP != nil:
        call.add newTree(nnkExprEqExpr, ident("minVal"), pragmaArg(minP))
      if maxP != nil:
        call.add newTree(nnkExprEqExpr, ident("maxVal"), pragmaArg(maxP))
      loadCalls.add call
    of cfkFloat:
      let minP = findPragma(pragmas, "cfgMin")
      let maxP = findPragma(pragmas, "cfgMax")
      var call = newCall(ident("loadFloat"), t, keyLit, fieldAcc, vr, secLit)
      if minP != nil:
        call.add newTree(nnkExprEqExpr, ident("minVal"), pragmaArg(minP))
      if maxP != nil:
        call.add newTree(nnkExprEqExpr, ident("maxVal"), pragmaArg(maxP))
      loadCalls.add call
    of cfkString:
      if optionSet == nil:
        loadCalls.add quote do:
          loadString(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
      else:
        loadCalls.add quote do:
          loadEnumString(`t`, `keyLit`, `fieldAcc`, `optionSet`, `vr`, `secLit`)
    of cfkEnum:
      let parseFn = enumParseName(typeNode)
      let validArr = enumValidName(typeNode)
      loadCalls.add quote do:
        loadEnum(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`, `parseFn`, `validArr`)
    of cfkSeqString:
      if optionSet == nil:
        loadCalls.add quote do:
          loadStringArray(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
      else:
        loadCalls.add quote do:
          loadEnumStringArray(`t`, `keyLit`, `fieldAcc`, `optionSet`, `vr`, `secLit`)
    of cfkOptionString:
      if hasPragma(pragmas, "cfgDirPath"):
        loadCalls.add quote do:
          loadOptionDirPath(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
      else:
        loadCalls.add quote do:
          loadOptionString(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
    of cfkUnsupported:
      error(
        "generateConfigLoader: unsupported field type `" & typeNode.repr &
          "` for field `" & fieldName & "`. Skip it with {.cfgSkip.} or " &
          "extend the macro.",
        typeNode,
      )

    # Deprecation notice: emit after the type-dispatched load so the value is
    # still assigned (backward-compatible). The key stays in validKeys so it
    # does not surface as an unknown-key notice.
    if spec.isDeprecated:
      let msgLit = newLit(spec.deprecated)
      loadCalls.add quote do:
        if `t`.hasKey(`keyLit`):
          `vr`.addDeprecated(fullKey(`secLit`, `keyLit`), `msgLit`)

  # A key that does not apply to this shape of the object is rejected, not
  # ignored. The checks run together once the whole object has loaded, so the
  # declaration order of the fields a predicate reads does not matter.
  for (spec, saved) in savedFor:
    let
      keyLit = newLit(spec.key)
      fieldAcc = newDotExpr(cfgVar, ident(spec.name))
      pred = newCall(spec.onlyWhen, cfgVar)
      expected = newLit("no '" & spec.key & "' key unless " & spec.onlyWhenNote)
    conditionChecks.add quote do:
      if `t`.hasKey(`keyLit`) and not `pred`:
        `vr`.addError(fullKey(`secLit`, `keyLit`), $`t`[`keyLit`], `expected`)
        # Refused values never stick, as everywhere else in the loader.
        `fieldAcc` = `saved`

  # Build `const validKeys = [...]`. Use gensym'd names so the const block
  # the macro injects into the caller's proc scope cannot be referenced by
  # surrounding code (preventing implicit dependencies on internal symbols).
  if checkUnknown:
    var arrLit = newNimNode(nnkBracket)
    for k in scalarKeys(td):
      arrLit.add newLit(k)
    for k in extraKeys:
      arrLit.add newLit(k)
    let validKeysIdent = genSym(nskConst, "validKeys")
    if secExpr == nil:
      let sectionIdent = genSym(nskConst, "section")
      let sectionLit = newLit(sec)
      result.add quote do:
        const `sectionIdent` = `sectionLit`
        const `validKeysIdent` = `arrLit`
        checkUnknownKeys(`t`, `validKeysIdent`, `sectionIdent`, `vr`)
    else:
      # `secLit` is already the local bound from `secExpr` above.
      result.add quote do:
        const `validKeysIdent` = `arrLit`
        checkUnknownKeys(`t`, `validKeysIdent`, `secLit`, `vr`)
  result.add savedDefaults
  result.add loadCalls
  result.add conditionChecks

macro generateConfigLoader*(t, cfgVar, vr: typed, T: typedesc): untyped =
  ## Emit a section loader body for type `T`. Expects the call to sit inside
  ## a proc with parameters `t: TomlTableRef`, `cfg: var T`, `vr: var ValidationResult`.
  ##
  ## Produces:
  ##   const section = "<from cfgSection>"
  ##   const validKeys = ["k1", "k2", ...]
  ##   checkUnknownKeys(t, validKeys, section, vr)
  ##   loadBool(t, "k1", cfg.k1, vr, section)
  ##   loadInt(t, "k2", cfg.k2, vr, section, minVal = ..., maxVal = ...)
  ##   ...
  let td = typeDef(T)
  if td == nil:
    error("cannot get impl for type", T)
  buildLoaderBody(td, t, cfgVar, vr, sectionName(td))

proc buildSerializerBody(
    td, lines, cfgVar: NimNode, sec: string, header = ""
): NimNode =
  ## Build the serializer statements for the section TypeDef `td`, appending
  ## TOML lines to `lines` from the config accessor `cfgVar`. The inverse of
  ## `buildLoaderBody`; field order follows the struct declaration so saved
  ## output stays parseable by the loader. Scalar formatters (`toTomlBool`,
  ## `toTomlString`, `toTomlStringArray`) must be in scope at the call site
  ## (re-exported from `config_loader/save_base`).
  ##
  ## Normalization note: `seq[string]` fields are emitted unconditionally (even
  ## when empty -> `key = []`); the loader reads an empty array back to an empty
  ## seq, so the round-trip is value-stable. `Option[string]` fields are emitted
  ## only when `isSome`. `sec` is the TOML header name to emit.
  result = newStmtList()

  # `header` overrides the `[Section]` form for an array-of-tables element,
  # written `[[Parent.name]]` once per element.
  let headerLit = newLit(
    if header.len > 0:
      header
    else:
      "[" & sec & "]"
  )
  result.add quote do:
    `lines`.add `headerLit`

  for spec in specFields(td):
    # Deprecated fields still load (see loader) but must not be written back,
    # so user configs shed the obsolete key on the next save cycle.
    if spec.isDeprecated:
      continue

    let
      fieldName = spec.name
      typeNode = spec.typ
      keyPrefix = newLit(spec.key & " = ")
      fieldAcc = newDotExpr(cfgVar, ident(fieldName))

    var emit = newStmtList()
    case spec.kind
    of cfkBool:
      emit.add quote do:
        `lines`.add `keyPrefix` & toTomlBool(`fieldAcc`)
    of cfkInt, cfkFloat:
      emit.add quote do:
        `lines`.add `keyPrefix` & $`fieldAcc`
    of cfkString:
      emit.add quote do:
        `lines`.add `keyPrefix` & toTomlString(`fieldAcc`)
    of cfkEnum:
      validateEnumStringValues(typeNode)
      emit.add quote do:
        `lines`.add `keyPrefix` & toTomlString($`fieldAcc`)
    of cfkSeqString:
      emit.add quote do:
        `lines`.add `keyPrefix` & toTomlStringArray(`fieldAcc`)
    of cfkOptionString:
      emit.add quote do:
        if `fieldAcc`.isSome:
          `lines`.add `keyPrefix` & toTomlString(`fieldAcc`.get)
    of cfkUnsupported:
      error(
        "config serializer: unsupported field type `" & typeNode.repr & "` for field `" &
          fieldName & "`. Skip it with {.cfgSkip.} or " & "extend the macro.",
        typeNode,
      )

    # The loader would reject the key on this object, so do not write it.
    if spec.onlyWhen == nil:
      result.add emit
    else:
      result.add newIfStmt((newCall(spec.onlyWhen, cfgVar), emit))

  result.add quote do:
    `lines`.add ""

## Single-source section registry
##
## Historically the section list was managed in three places that had to be
## kept in sync by hand: the loader dispatch (`loadConfigFromToml`), the
## serializer dispatch (`saveConfigToToml`), and the top-level section-name
## list used for unknown-key validation. Adding a section meant editing all
## three; forgetting one failed silently (not saved / not loaded / spurious
## "unknown section" error).
##
## The macros below instead derive all three from a single walk of the
## `EditorConfig` type — the same source of truth the loader/serializer
## field macros already use. A section is "registered" simply by being a
## `{.cfgSection.}`-typed field of `EditorConfig`; nothing else is required.
##
## Nested vs flat sections are distinguished structurally, with no hand-kept
## list: a section whose `{.cfgSection.}` name contains a dot (e.g.
## `[StartUp.FileOpen]`) is NOT a top-level table — it lives under a parent
## (`[StartUp]`). Such sections are still serialized as flat `[Parent.Child]`
## headers, but are loaded by hand under their parent and are excluded from
## the top-level unknown-key list. Because nested-ness is derived from the
## section name itself, the loader / serializer / section-name lists cannot
## diverge: adding a nested section needs no registry edit.

proc cfgSectionFields(
    outerTd: NimNode
): seq[tuple[field: string, typ: NimNode, sec: string]] =
  ## Walk `outerTd`'s fields and return those whose declared type carries a
  ## `{.cfgSection.}` pragma. Fields with non-section types (Table, ThemeConfig,
  ## LspConfig, …) are skipped — they are handled by hand-written code.
  result = @[]
  for (name, typeNode, _) in sectionFields(outerTd):
    if typeNode.kind notin {nnkIdent, nnkSym}:
      continue
    let impl = typeNode.getImpl
    if impl == nil or impl.kind != nnkTypeDef:
      continue
    let p = findPragma(typePragmas(impl), "cfgSection")
    if p == nil:
      continue
    result.add (name, typeNode, sectionName(impl))

macro generateSectionLoaders*(toml, cfg, vr: typed, OuterT: typedesc): untyped =
  ## Emit the per-section load dispatch for every top-level `{.cfgSection.}`
  ## field of `OuterT` (excluding nested sections — those whose section name
  ## contains a dot, which are loaded by hand under their parent table).
  ## Produces, for each section:
  ##   if expectTable(toml, "Section", vr):
  ##     generateConfigLoader(toml["Section"].getTable(), cfg.field, vr, FieldType)
  let outerTd = typeDef(OuterT)
  if outerTd == nil:
    error("cannot get impl for outer type", OuterT)
  result = newStmtList()
  for (field, typ, sec) in cfgSectionFields(outerTd):
    if '.' in sec:
      # Nested section (e.g. "StartUp.FileOpen"): loaded by hand under [StartUp].
      continue
    let secLit = newLit(sec)
    let fieldAcc = newDotExpr(cfg, ident(field))
    let tbl = genSym(nskLet, "tbl")
    let innerTd = typ.getImpl
    let loadBody = buildLoaderBody(innerTd, tbl, fieldAcc, vr, sec)
    result.add quote do:
      if expectTable(`toml`, `secLit`, `vr`):
        let `tbl` = `toml`[`secLit`].getTable()
        `loadBody`

macro generateSectionSerializers*(lines, cfg: typed, OuterT: typedesc): untyped =
  ## Emit the per-section save dispatch for every `{.cfgSection.}` field of
  ## `OuterT`. Nested sections are included — their flat `[Parent.Child]`
  ## header serializes correctly without special handling. Produces, for each
  ## section, the serializer body for `cfg.field` (header line, one `key = value`
  ## line per `{.cfg.}` field, trailing blank).
  let outerTd = typeDef(OuterT)
  if outerTd == nil:
    error("cannot get impl for outer type", OuterT)
  result = newStmtList()
  for (field, typ, sec) in cfgSectionFields(outerTd):
    let fieldAcc = newDotExpr(cfg, ident(field))
    let innerTd = typ.getImpl
    result.add buildSerializerBody(innerTd, lines, fieldAcc, sec)

macro generateSimpleSectionNames*(OuterT: typedesc): untyped =
  ## Return an array literal of the top-level TOML section names produced from
  ## `OuterT`'s `{.cfgSection.}` fields (excluding nested sections — those whose
  ## section name contains a dot). Use as the basis for unknown-key validation:
  ##   const SimpleSectionNames = generateSimpleSectionNames(EditorConfig)
  let outerTd = typeDef(OuterT)
  if outerTd == nil:
    error("cannot get impl for outer type", OuterT)
  var arr = newNimNode(nnkBracket)
  for (field, typ, sec) in cfgSectionFields(outerTd):
    if '.' in sec:
      continue
    arr.add newLit(sec)
  if arr.len == 0:
    error("no {.cfgSection.} fields found on " & OuterT.repr, OuterT)
  result = arr

proc buildDescriptorsBody(target, innerTd, base: NimNode, sec: string): NimNode =
  ## Emit `target.add ConfigItemDescriptor(...)` entries for the section type
  ## `innerTd`, whose value is reached from an `EditorConfig` named `c` via the
  ## accessor expression `base` (e.g. `c.standard`, or `c.lsp.completion` for a
  ## sub-section). Produces:
  ##   target.add ConfigItemDescriptor(kind: cvkSection, ...)
  ##   target.add ConfigItemDescriptor(kind: cvkBool, ...)  -- for each field
  ##   ...
  let secLit = newLit(sec)

  result = newStmtList()

  # Section header descriptor.
  result.add quote do:
    `target`.add ConfigItemDescriptor(
      kind: cvkSection, displayName: `secLit`, section: `secLit`
    )

  # Per-field descriptors.
  let cIdent = ident("c")
  let vIdent = ident("v")
  for spec in specFields(innerTd):
    if spec.noUi:
      continue
    if spec.isDeprecated:
      # Deprecated fields are transitional: keep them loading but hide them
      # from the config-mode UI so users are not prompted to edit them.
      continue
    let
      fieldName = spec.name
      fieldType = spec.typ
      pragmas = spec.pragmas

    let uiNameP = findPragma(pragmas, "cfgUiName")
    let displayName =
      if uiNameP != nil:
        let a = pragmaArg(uiNameP)
        if a == nil or a.kind != nnkStrLit:
          error("cfgUiName requires a string literal", uiNameP)
        a.strVal
      else:
        fieldName
    let dispLit = newLit(displayName)

    let path = newDotExpr(base, ident(fieldName))

    # When the key is visible: `cfgVisible` asks about the whole config,
    # `cfgOnlyWhen` about the owning object, and both have to hold. Editing a
    # key whose `cfgOnlyWhen` fails would be dropped on the next save. The
    # wrapper lets a caller name a plain proc without matching `visibleWhen`'s
    # pragmas.
    let visibleP = findPragma(pragmas, "cfgVisible")
    var conditions: seq[NimNode] = @[]
    if visibleP != nil:
      let fn = pragmaArg(visibleP)
      if fn == nil:
        error("cfgVisible requires a predicate expression", visibleP)
      conditions.add newCall(fn, cIdent)
    if spec.onlyWhen != nil:
      conditions.add newCall(spec.onlyWhen, base)
    var visibleExpr: NimNode = newNilLit()
    if conditions.len > 0:
      var test = conditions[0]
      for i in 1 ..< conditions.len:
        test = infix(test, "and", conditions[i])
      visibleExpr = quote:
        proc(`cIdent`: EditorConfig): bool {.noSideEffect.} =
          `test`

    let typeName = if fieldType.kind in {nnkIdent, nnkSym}: fieldType.strVal else: ""

    case spec.kind
    of cfkBool:
      result.add quote do:
        `target`.add ConfigItemDescriptor(
          kind: cvkBool,
          displayName: `dispLit`,
          section: `secLit`,
          visibleWhen: `visibleExpr`,
          boolGet: proc(`cIdent`: EditorConfig): bool =
            `path`,
          boolSet: proc(`cIdent`: EditorConfig, `vIdent`: bool) =
            `path` = `vIdent`,
        )
    of cfkInt:
      let minP = findPragma(pragmas, "cfgMin")
      let maxP = findPragma(pragmas, "cfgMax")
      let minVal =
        if minP != nil:
          pragmaArg(minP)
        else:
          newLit(int.low)
      let maxVal =
        if maxP != nil:
          pragmaArg(maxP)
        else:
          newLit(int.high)
      result.add quote do:
        `target`.add ConfigItemDescriptor(
          kind: cvkInt,
          displayName: `dispLit`,
          section: `secLit`,
          visibleWhen: `visibleExpr`,
          intGet: proc(`cIdent`: EditorConfig): int =
            `path`,
          intSet: proc(`cIdent`: EditorConfig, `vIdent`: int) =
            `path` = `vIdent`,
          intMin: `minVal`,
          intMax: `maxVal`,
        )
    of cfkFloat:
      let minP = findPragma(pragmas, "cfgMin")
      let maxP = findPragma(pragmas, "cfgMax")
      let stepP = findPragma(pragmas, "cfgStep")
      let minVal =
        if minP != nil:
          pragmaArg(minP)
        else:
          newLit(float.low)
      let maxVal =
        if maxP != nil:
          pragmaArg(maxP)
        else:
          newLit(float.high)
      let stepVal =
        if stepP != nil:
          pragmaArg(stepP)
        else:
          newLit(1.0)
      result.add quote do:
        `target`.add ConfigItemDescriptor(
          kind: cvkFloat,
          displayName: `dispLit`,
          section: `secLit`,
          visibleWhen: `visibleExpr`,
          floatGet: proc(`cIdent`: EditorConfig): float =
            `path`,
          floatSet: proc(`cIdent`: EditorConfig, `vIdent`: float) =
            `path` = `vIdent`,
          floatMin: `minVal`,
          floatMax: `maxVal`,
          floatStep: `stepVal`,
        )
    of cfkString:
      if spec.optionSet != nil:
        let optsExpr = valuesExpr(spec)
        result.add optionSetNonEmptyCheck(spec)
        result.add quote do:
          `target`.add ConfigItemDescriptor(
            kind: cvkEnum,
            displayName: `dispLit`,
            section: `secLit`,
            visibleWhen: `visibleExpr`,
            enumGet: proc(`cIdent`: EditorConfig): string =
              `path`,
            enumSet: proc(`cIdent`: EditorConfig, `vIdent`: string) =
              `path` = `vIdent`,
            enumOptions: `optsExpr`,
          )
      else:
        result.add quote do:
          `target`.add ConfigItemDescriptor(
            kind: cvkString,
            displayName: `dispLit`,
            section: `secLit`,
            visibleWhen: `visibleExpr`,
            stringGet: proc(`cIdent`: EditorConfig): string =
              `path`,
            stringSetter: proc(`cIdent`: EditorConfig, `vIdent`: string) =
              `path` = `vIdent`,
          )
    of cfkEnum:
      block:
        # cfgEnum overrides the auto-derived option order. Useful when the UI
        # cycle order should differ from the declaration order, or when only
        # a subset of variants should be selectable.
        let cfgEnumP = findPragma(pragmas, "cfgEnum")
        if cfgEnumP != nil and parseStringArrayLit(pragmaArg(cfgEnumP)).len == 0:
          error(
            "cfgEnum requires a non-empty array of string literals " &
              "(e.g. `{.cfgEnum: [\"a\", \"b\"].}`)",
            cfgEnumP,
          )
        if cfgEnumP == nil and enumStringValues(fieldType).len == 0:
          error("could not derive enum options for `" & typeName & "`", fieldType)
        let optsExpr = valuesExpr(spec)
        let enumT = fieldType
        result.add quote do:
          `target`.add ConfigItemDescriptor(
            kind: cvkEnum,
            displayName: `dispLit`,
            section: `secLit`,
            visibleWhen: `visibleExpr`,
            enumGet: proc(`cIdent`: EditorConfig): string =
              $`path`,
            enumSet: proc(`cIdent`: EditorConfig, `vIdent`: string) =
              `path` = parseEnum[`enumT`](`vIdent`),
            enumOptions: `optsExpr`,
          )
    of cfkSeqString, cfkOptionString, cfkUnsupported:
      error(
        "generateAllConfigDescriptors: unsupported field type `" & fieldType.repr &
          "` for field `" & fieldName & "`. Hide it from the UI with " &
          "{.cfgNoUi.}, skip it entirely with {.cfgSkip.}, or extend the macro.",
        fieldType,
      )

macro generateAllConfigDescriptors*(target: typed, OuterT: typedesc): untyped =
  ## Emit the config-mode UI descriptors for every `{.cfgSection.}` field of
  ## `OuterT`, in field-declaration order. Counterpart of
  ## `generateSectionLoaders` / `generateSectionSerializers`: a section reaches
  ## the UI simply by being a `{.cfgSection.}`-typed field, so the UI cannot
  ## drift from the loader and the serializer.
  ##
  ## Nested sections (dotted names such as `StartUp.FileOpen`) are included;
  ## their header is the dotted name, matching the serialized TOML.
  let outerTd = typeDef(OuterT)
  if outerTd == nil:
    error("cannot get impl for outer type", OuterT)
  result = newStmtList()
  for (field, typ, sec) in cfgSectionFields(outerTd):
    let base = newDotExpr(ident("c"), ident(field))
    result.add buildDescriptorsBody(target, typ.getImpl, base, sec)

## The config tree
##
## `FieldSpec` keeps the surfaces from disagreeing about what one *key* means;
## `ConfigNode` does the same for what one *table* means. The tree is built
## once and every surface folds over it with a `case node.kind` and no `else`,
## so a new table shape does not compile until every surface handles it.
##
## A plain `{.cfgSection.}` type is a leaf: `checkNoChildTablePragmas` rejects
## the pragma that would give it a child.

type ConfigNodeKind* = enum
  cnkTable ## `[Name]`: the root of a section or of a section group
  cnkSubSection ## `{.cfgSubSection.}`: one `[Parent.Name]` table
  cnkArrayOfTables ## `{.cfgArrayOfTables.}`: repeated `[[Parent.Name]]` tables

type ConfigNode* = object ## One table of the config tree.
  kind*: ConfigNodeKind
  name*: string ## TOML name of this table within its parent
  path*: string ## dotted TOML path, what the user writes in a header
  field*: string ## the Nim field owning it; empty for a root
  typ*: NimNode ## its object type -- the *element* type for an array
  td*: NimNode ## that type's TypeDef
  pragmas*: NimNode ## the owning field's pragmas; nnkEmpty for a root
  subject*: string ## the owning field's `{.cfgDocDescription.}`
  children*: seq[ConfigNode]

proc childDocSubject(pragmas: NimNode): string =
  ## A child table's `{.cfgDocDescription.}`, substituted for
  ## `DocSubjectPlaceholder` in its keys' descriptions.
  let p = findPragma(pragmas, "cfgDocDescription")
  if p == nil:
    return ""
  let arg = pragmaArg(p)
  if arg == nil or arg.kind != nnkStrLit:
    error("cfgDocDescription requires a string literal", p)
  arg.strVal

proc childNames(node: ConfigNode): seq[string] =
  ## The names the node's child tables claim in its own table.
  for child in node.children:
    result.add child.name

proc childTables(ownerTd: NimNode, parentPath: string): seq[ConfigNode]

proc childTableNode(
    fieldName: string, typeNode, pragmas, p: NimNode, isArray: bool, parentPath: string
): ConfigNode =
  ## One child table, with every rule it must satisfy checked here.
  let arg = pragmaArg(p)
  if arg == nil or arg.kind != nnkStrLit:
    error(pragmaName(p) & " requires a string literal", p)
  let name = arg.strVal

  result = ConfigNode(
    kind: (if isArray: cnkArrayOfTables else: cnkSubSection),
    name: name,
    path: (if parentPath.len > 0: parentPath & "." & name else: name),
    field: fieldName,
    pragmas: pragmas,
    subject: childDocSubject(pragmas),
  )

  for rulesName in ["cfgEntryRules", "cfgArrayRules"]:
    let rules = findPragma(pragmas, rulesName)
    if rules == nil:
      continue
    if not isArray:
      # The predicate would be emitted nowhere and validate nothing.
      error(
        "field `" & fieldName & "` carries {." & rulesName &
          ".} together with {.cfgSubSection.}: there are no entries for it " &
          "to validate",
        rules,
      )
    if pragmaArg(rules) == nil:
      error(rulesName & " requires the name of a validation predicate", rules)

  if isArray:
    if typeNode.kind != nnkBracketExpr or typeNode.len != 2 or
        typeNode[0].strVal != "seq":
      error("cfgArrayOfTables requires a seq of a named object type", typeNode)
    result.typ = typeNode[1]
  else:
    result.typ = typeNode

  if not isObjectTypeIdent(result.typ):
    error(pragmaName(p) & " requires a named object type", result.typ)
  result.td = result.typ.getImpl
  # `isObjectTypeIdent` sees through `ref`/`ptr`, but the loader declares
  # `var entry: Elem` and writes through it: nil for a ref.
  if result.td[2].kind in {nnkRefTy, nnkPtrTy}:
    error(
      pragmaName(p) & " requires a value object type: `" & result.typ.repr &
        "` is a ref or ptr object, which the generated loader cannot allocate",
      result.typ,
    )

  result.children = childTables(result.td, result.path)
  if isArray and result.children.len > 0:
    # `[Parent.name.child]` says nothing about which element it belongs to.
    error(
      "field `" & fieldName &
        "` is an array of tables whose element type owns child tables: a table " &
        "below a repeated one cannot be addressed unambiguously",
      p,
    )

proc childTables(ownerTd: NimNode, parentPath: string): seq[ConfigNode] =
  ## The child tables of `ownerTd`, in declaration order. Their names share
  ## one namespace with the parent's scalar keys, so collisions are rejected.
  result = @[]
  var taken = toHashSet(scalarKeys(ownerTd))

  for (fieldName, typeNode, pragmas) in sectionFields(ownerTd):
    let
      subP = findPragma(pragmas, "cfgSubSection")
      arrP = findPragma(pragmas, "cfgArrayOfTables")

    if subP == nil and arrP == nil:
      for orphan in ["cfgEntryRules", "cfgArrayRules"]:
        let rules = findPragma(pragmas, orphan)
        if rules != nil:
          error(
            "field `" & fieldName & "` carries {." & orphan &
              ".} without {.cfgArrayOfTables.}: there are no entries for it " &
              "to validate",
            rules,
          )
      continue

    if subP != nil and arrP != nil:
      error(
        "field `" & fieldName &
          "` carries both {.cfgSubSection.} and {.cfgArrayOfTables.}: a child " &
          "table is either single or repeated",
        typeNode,
      )
    if hasPragma(pragmas, "cfg"):
      error(
        "field `" & fieldName & "` carries {.cfg.} together with {." &
          (if subP != nil: "cfgSubSection" else: "cfgArrayOfTables") &
          ".}: a child table is not a scalar key",
        typeNode,
      )

    let node =
      if subP != nil:
        childTableNode(fieldName, typeNode, pragmas, subP, false, parentPath)
      else:
        childTableNode(fieldName, typeNode, pragmas, arrP, true, parentPath)
    if node.name in taken:
      error(
        "{." & (if subP != nil: "cfgSubSection" else: "cfgArrayOfTables") & ": \"" &
          node.name & "\".} on field `" & fieldName &
          "` collides with a key or child table of the same name",
        (if subP != nil: subP else: arrP),
      )
    taken.incl node.name
    result.add node

proc configTree(td: NimNode, path: string): ConfigNode {.compileTime.} =
  ## The table `td` declares, with every table below it.
  ConfigNode(
    kind: cnkTable,
    name: path,
    path: path,
    typ: newEmptyNode(),
    td: td,
    pragmas: newEmptyNode(),
    children: childTables(td, path),
  )

## Section groups
##
## A *section group* owns both scalar keys of its own parent table and a set of
## child tables.
##
## Groups are deliberately NOT `{.cfgSection.}` types: the whole-config walk
## would then emit a strict unknown-key check on the parent table, which is
## wrong when it also accepts caller-defined keys (`[Lsp.<languageId>]`). The
## owner module calls the macros and owns that policy instead.

proc groupOwner(T: NimNode): NimNode =
  let td = typeDef(T)
  if td == nil:
    error("cannot get impl for section group type", T)
  td

proc groupName(td: NimNode): string =
  ## Read the `cfgGroup: "Name"` pragma from a section group's TypeDef.
  let p = findPragma(typePragmas(td), "cfgGroup")
  if p == nil:
    error("type has no {.cfgGroup: \"...\".} pragma", td)
  let arg = pragmaArg(p)
  if arg == nil or arg.kind != nnkStrLit:
    error("cfgGroup requires a string literal", p)
  arg.strVal

proc groupTree*(T: NimNode): ConfigNode {.compileTime.} =
  ## The config tree of a section group. A group must own at least one child
  ## table, or a lost pragma would expand every generator to nothing.
  let ownerTd = groupOwner(T)
  result = configTree(ownerTd, groupName(ownerTd))
  if result.children.len == 0:
    error(
      "no {.cfgSubSection.} or {.cfgArrayOfTables.} fields found on " & ownerTd.repr,
      ownerTd,
    )

macro cfgGroupName*(T: typedesc): untyped =
  ## The parent TOML table name of a section group, as a string literal.
  newLit(groupName(groupOwner(T)))

proc groupTomlName*(T: NimNode): string {.compileTime.} =
  ## Compile-time accessor for a section group's parent table name, for macros
  ## that need it outside `generateSectionGroup*`. `T` is a typedesc node.
  groupName(groupOwner(T))

## The surfaces: one fold each, none with an `else`.

proc buildTableLoader(
    node: ConfigNode, t, cfgVar, vr: NimNode, checkUnknown: bool
): NimNode =
  ## The loader for `node`'s own keys, then one stanza per child table. `t` is
  ## the TOML table it reads from, `cfgVar` the value it loads into.
  result = buildLoaderBody(
    node.td,
    t,
    cfgVar,
    vr,
    node.path,
    checkUnknown = checkUnknown,
    allowChildTables = true,
    extraKeys = node.childNames,
  )
  for child in node.children:
    let
      nameLit = newLit(child.name)
      pathLit = newLit(child.path)
      parentLit = newLit(node.path)
      fieldAcc = newDotExpr(cfgVar, ident(child.field))
    case child.kind
    of cnkTable:
      error("a root table cannot appear as a child table", child.typ)
    of cnkSubSection:
      let tbl = genSym(nskLet, "tbl")
      let body = buildTableLoader(child, tbl, fieldAcc, vr, checkUnknown = true)
      result.add quote do:
        if expectTable(`t`, `nameLit`, `vr`, `parentLit`):
          let `tbl` = `t`[`nameLit`].getTable()
          `body`
    of cnkArrayOfTables:
      let
        arr = genSym(nskLet, "arr")
        acc = genSym(nskVar, "acc")
        item = genSym(nskForVar, "item")
        idx = genSym(nskForVar, "i")
        label = genSym(nskLet, "label")
        tbl = genSym(nskLet, "tbl")
        entry = genSym(nskVar, "entry")
        elem = child.typ
      let loads = buildLoaderBody(child.td, tbl, entry, vr, "", secExpr = label)
      # A save writes the element's declared defaults for the keys the TOML
      # omits, so they have to be values the loader accepts.
      let elemTypedesc = nnkBracketExpr.newTree(ident("typedesc"), elem)
      for spec in specFields(child.td):
        result.add optionSetDefaultCheck(spec, elemTypedesc)
      let accInit = newCall(nnkBracketExpr.newTree(ident("newSeq"), elem), newLit(0))
      # An entry starts at the element type's declared defaults; `var entry:
      # Elem` would zero the object instead. The resolved symbol only reaches
      # `default` as an explicit `typedesc[...]`.
      let entryDecl = nnkVarSection.newTree(
        nnkIdentDefs.newTree(
          entry,
          newEmptyNode(),
          newCall(ident("default"), nnkBracketExpr.newTree(ident("typedesc"), elem)),
        )
      )
      let rulesP = findPragma(child.pragmas, "cfgEntryRules")
      let keep =
        if rulesP == nil:
          newCall(ident("add"), acc, entry)
        else:
          newIfStmt(
            (
              newCall(pragmaArg(rulesP), tbl, entry, label, vr),
              newCall(ident("add"), acc, entry),
            )
          )
      # Runs once, after the per-entry rules have dropped what they drop.
      let arrayRulesP = findPragma(child.pragmas, "cfgArrayRules")
      let arrayRules =
        if arrayRulesP == nil:
          newStmtList()
        else:
          newCall(pragmaArg(arrayRulesP), acc, pathLit, vr)
      result.add quote do:
        if `t`.hasKey(`nameLit`):
          let `arr` = `t`[`nameLit`]
          if `arr`.kind != TomlValueKind.Array:
            `vr`.addError(`pathLit`, $`arr`, "array of tables")
          else:
            # Assigned at the end, so a failed load leaves no half array.
            var `acc` = `accInit`
            for `idx`, `item` in `arr`.getElems:
              let `label` = `pathLit` & "[" & $`idx` & "]"
              if `item`.kind != TomlValueKind.Table:
                `vr`.addError(`label`, $`item`, "table")
              else:
                let `tbl` = `item`.getTable
                `entryDecl`
                `loads`
                `keep`
            `arrayRules`
            `fieldAcc` = `acc`

proc buildTableKeys(node: ConfigNode, arr: NimNode) =
  ## Append every name `node` claims in its own table: its scalar keys, then
  ## one per child table.
  for key in scalarKeys(node.td):
    arr.add newLit(key)
  for child in node.children:
    case child.kind
    of cnkTable:
      error("a root table cannot appear as a child table", child.typ)
    of cnkSubSection, cnkArrayOfTables:
      # Both claim their name in the parent table; only the brackets differ.
      arr.add newLit(child.name)

proc buildTableSerializer(node: ConfigNode, lines, cfgVar: NimNode): NimNode =
  ## The serializer for `node` and every table below it.
  result = buildSerializerBody(node.td, lines, cfgVar, node.path)
  # An emptied array writes `name = []`, like an empty `seq[string]`: with no
  # `[[Parent.name]]` blocks, a file silent about the field would load the
  # default back. Emitted before the first child header, or it would land in
  # that header's table.
  for child in node.children:
    if child.kind != cnkArrayOfTables:
      continue
    let
      fieldAcc = newDotExpr(cfgVar, ident(child.field))
      emptyLit = newLit(child.name & " = []")
    result.add quote do:
      if `fieldAcc`.len == 0:
        `lines`.add `emptyLit`
        `lines`.add ""
  for child in node.children:
    let fieldAcc = newDotExpr(cfgVar, ident(child.field))
    case child.kind
    of cnkTable:
      error("a root table cannot appear as a child table", child.typ)
    of cnkSubSection:
      result.add buildTableSerializer(child, lines, fieldAcc)
    of cnkArrayOfTables:
      let
        entry = genSym(nskForVar, "entry")
        header = "[[" & child.path & "]]"
        body = buildSerializerBody(child.td, lines, entry, child.path, header)
      # `buildSerializerBody` ends each block with a blank line, which already
      # separates the elements.
      result.add quote do:
        for `entry` in `fieldAcc`:
          `body`

proc buildTableDescriptors(node: ConfigNode, target, base: NimNode): NimNode =
  ## The config-mode UI descriptors for `node` and every table below it, whose
  ## value is reached from an `EditorConfig` named `c` via `base`.
  result = buildDescriptorsBody(target, node.td, base, node.path)
  for child in node.children:
    case child.kind
    of cnkTable:
      error("a root table cannot appear as a child table", child.typ)
    of cnkSubSection:
      let childBase = newDotExpr(base, ident(child.field))
      result.add buildTableDescriptors(child, target, childBase)
    of cnkArrayOfTables:
      # The UI edits one value per row and cannot add, remove or reorder
      # entries, so a repeated table has no descriptors.
      discard

macro generateSectionGroupLoader*(t, cfgVar, vr: typed, T: typedesc): untyped =
  ## Emit the loader for a section group: the parent table's own `{.cfg.}`
  ## fields, one `if expectTable(t, "Child", ...): <sub-table loader>` per
  ## sub-section, then one `[[Parent.Name]]` loop per `{.cfgArrayOfTables.}`
  ## field. No unknown-key check on the parent table -- see
  ## `generateSectionGroupKeys`.
  ##
  ## Each element of an array of tables gets the unknown-key check and the
  ## per-type loads a section gets, then the field's `{.cfgEntryRules.}`
  ## predicate, which drops the element by returning false.
  ##
  ## A present array replaces the field, keeping the elements that survive; a
  ## present non-array is reported and leaves the default alone.
  buildTableLoader(groupTree(T), t, cfgVar, vr, checkUnknown = false)

macro generateSectionGroupKeys*(T: typedesc): untyped =
  ## Return an array literal of every key the group owns in its parent table
  ## (scalar `{.cfg.}` keys, then child-table names). The owner uses it to tell
  ## its dynamic keys from typos.
  var arr = newNimNode(nnkBracket)
  buildTableKeys(groupTree(T), arr)
  result = arr

macro generateSectionGroupSerializer*(lines, cfgVar: typed, T: typedesc): untyped =
  ## Emit the serializer for a section group: the `[Parent]` header and its
  ## scalar keys, then one block per child table. Dynamic entries are appended
  ## by the owner afterwards.
  ##
  ## An array of tables with no elements writes `name = []` among the parent's
  ## keys, so an emptied array reads back empty.
  buildTableSerializer(groupTree(T), lines, cfgVar)

macro generateSectionGroupDescriptors*(
    target: typed, ownerField: untyped, T: typedesc
): untyped =
  ## Emit the config-mode UI descriptors for a section group reached from an
  ## `EditorConfig` named `c` via `ownerField` (e.g. `lsp`).
  buildTableDescriptors(
    groupTree(T), target, newDotExpr(ident("c"), ident(ownerField.strVal))
  )

const DocSubjectPlaceholder* = "{}"
  ## Placeholder in a `{.cfgDocDescription.}`, replaced with the sub-table's
  ## own subject: `"Enable {}"` on the shared `LspFeatureConfig` renders as
  ## "Enable LSP Completion" under `[Lsp.Completion]`. Outside a sub-table
  ## there is nothing to substitute, so leaving it in is a compile-time error.

proc buildMarkdownTable(instance, td, prelude: NimNode, subject: string): NimNode =
  ## The markdown table for the section type `td`, as a `block:` expression
  ## whose value is the whole table string (header + separator + one row per
  ## `{.cfg.}` field that also carries `{.cfgDocDescription.}`). Defaults are
  ## read off `instance` through `formatDocDefault`, which the call site
  ## supplies overloads of. `prelude` is emitted inside the block ahead of the
  ## table, for guards belonging to one caller.
  ##
  ## `subject` fills the `DocSubjectPlaceholder` in field descriptions.
  let resVar = genSym(nskVar, "docTableResult")
  result = newStmtList(prelude)

  result.add quote do:
    var `resVar` = "| Name | Type | Default Value | Description |\n"
    `resVar` &= "|:---|:---|:---|:---|\n"

  for spec in specFields(td):
    let
      fieldName = spec.name
      typeNode = spec.typ
      pragmas = spec.pragmas
    if spec.docSkip:
      # Field is intentionally excluded from auto-gen docs but still loaded.
      continue
    if spec.isDeprecated:
      # Deprecated fields are omitted from the docs so the reference does not
      # advertise them; the loader still accepts them for backward compat.
      continue
    if not spec.hasDocDesc:
      error(
        "field `" & fieldName &
          "` has {.cfg.} but no {.cfgDocDescription.}: every cfg field in an " &
          "auto-generated section must be documented. Add a description, or " &
          "opt out with {.cfgDocSkip.}.",
        typeNode,
      )
    if DocSubjectPlaceholder in spec.docDesc and subject.len == 0:
      error(
        "field `" & fieldName & "`: `" & DocSubjectPlaceholder &
          "` in {.cfgDocDescription.} has nothing to expand to. Only a section " &
          "group's child tables supply a subject; give the child table a " &
          "{.cfgDocDescription.} of its own, or drop the placeholder.",
        findPragma(pragmas, "cfgDocDescription"),
      )
    var desc = spec.docDesc.replace(DocSubjectPlaceholder, subject)
    # Otherwise a conditional key reads as unconditional in the table.
    if spec.onlyWhen != nil:
      desc &= " (" & conditionNote(spec) & ")"

    # Static cells (name / description) are known at macro-expansion time, so
    # escape them now and emit literals — no runtime cost. The type cell is an
    # expression, since a named `{.cfgEnumStrings.}` set is only a value at the
    # call site.
    let nameLit = newLit(escapeMdCell(fieldName))
    let typeLabel = typeLabelExpr(spec)
    let descLit = newLit(escapeMdCell(desc))

    # Default value: prefer cfgDocDefault override if present (for fields
    # whose runtime default varies by environment), otherwise read the
    # actual field on the passed-in config instance. The formatted result
    # is escaped at runtime since it depends on the config instance.
    let docDefaultP = findPragma(pragmas, "cfgDocDefault")
    let fieldAccess = newDotExpr(instance, ident(fieldName))
    let defaultExpr =
      if docDefaultP != nil:
        pragmaArg(docDefaultP)
      else:
        fieldAccess

    # When an override is supplied, assert at compile time that its type
    # matches the field's — otherwise overload resolution for
    # `formatDocDefault` could pick a different overload than what the
    # TOML serializer would use, and the rendered default would diverge
    # silently from the actual config behavior.
    if docDefaultP != nil:
      let defaultMismatchMsg = newLit(
        "cfgDocDefault for `" & fieldName & "`: override type does not match field type"
      )
      result.add quote do:
        static:
          doAssert typeof(`defaultExpr`) is typeof(`fieldAccess`), `defaultMismatchMsg`

    result.add quote do:
      `resVar` &=
        "| " & `nameLit` & " | " & escapeMdCell(`typeLabel`) & " | " &
        escapeMdCell(formatDocDefault(`defaultExpr`)) & " | " & `descLit` & " |\n"

  result = nnkBlockStmt.newTree(newEmptyNode(), newStmtList(result, resVar))

macro generateSectionMarkdown*(
    cfg: typed,
    sectionField: untyped,
    sectionType: typedesc,
    subject: static string = "",
): untyped =
  ## Render the markdown table for one config section:
  ##   generateSectionMarkdown(cfg, standard, StandardConfig)
  let sectionAccess = newDotExpr(cfg, sectionField)
  let td = typeDef(sectionType)
  if td == nil:
    error("cannot get impl for section type", sectionField)

  # Catch `generateSectionMarkdown(cfg, tabLine, FilerConfig)`-style swaps,
  # which otherwise surface as a confusing "undeclared field" deep inside the
  # expansion.
  let sectionMismatchMsg = newLit(
    "generateSectionMarkdown: cfg." & sectionField.repr & " is not of type " &
      sectionType.repr
  )
  let prelude = quote:
    static:
      doAssert typeof(`sectionAccess`) is `sectionType`, `sectionMismatchMsg`

  buildMarkdownTable(sectionAccess, td, prelude, subject)

macro generateArrayTableMarkdown*(
    elemType: typedesc, subject: static string = ""
): untyped =
  ## Render the markdown table for one element of a `{.cfgArrayOfTables.}`
  ## field. The array can be empty, so there is no config value to read
  ## defaults off: the column shows what a freshly declared entry holds.
  var sym = elemType
  if sym.kind == nnkBracketExpr and sym.len >= 2:
    sym = sym[1]
  let td = sym.getImpl
  if td == nil or td.kind != nnkTypeDef:
    error("cannot get impl for array element type", elemType)
  # The same default the loader starts an entry from.
  let instance = genSym(nskVar, "elemDefault")
  let decl = nnkVarSection.newTree(
    nnkIdentDefs.newTree(
      instance,
      newEmptyNode(),
      newCall(ident("default"), nnkBracketExpr.newTree(ident("typedesc"), sym)),
    )
  )
  buildMarkdownTable(instance, td, decl, subject)

## Config schema
##
## The same walk as the loader/serializer/docs, exposed as runtime data so
## editing helpers can offer exactly the keys the loader accepts.

proc schemaValueTypeIdent(spec: FieldSpec): NimNode =
  ## The `ConfigValueType` member matching a field's declared type. It names
  ## the *shape* the user must type, so a `{.cfgEnumStrings.}` string is an
  ## enum while a `seq[string]` drawn from the same set stays an array. The
  ## members themselves travel in `values`.
  case spec.kind
  of cfkBool:
    ident("cvtBool")
  of cfkInt:
    ident("cvtInt")
  of cfkFloat:
    ident("cvtFloat")
  of cfkString:
    if spec.optionSet != nil:
      ident("cvtEnum")
    else:
      ident("cvtString")
  of cfkEnum:
    ident("cvtEnum")
  of cfkSeqString:
    ident("cvtStringArray")
  of cfkOptionString:
    ident("cvtString")
  of cfkUnsupported:
    ident("cvtString")

proc typeDocDescription(td: NimNode): string =
  ## A `{.cfgDocDescription.}` on the type rather than a field: what the section
  ## itself is, for the completion popup on its `[header]`.
  let p = findPragma(typePragmas(td), "cfgDocDescription")
  if p == nil:
    return ""
  let arg = pragmaArg(p)
  if arg == nil or arg.kind != nnkStrLit:
    error("cfgDocDescription requires a string literal", p)
  arg.strVal

proc buildSchemaBody(
    target, innerTd: NimNode, sec: string, subject = "", isArray = false
): NimNode =
  ## Emit `target.add ConfigSchemaSection(...)` for the section TypeDef
  ## `innerTd` under the TOML name `sec`. Deprecated keys are left out: still
  ## accepted by the loader, but not to be advertised.
  var keys = newNimNode(nnkBracket)
  var setChecks = newStmtList()
  for spec in specFields(innerTd):
    if spec.isDeprecated:
      continue

    setChecks.add optionSetNonEmptyCheck(spec)

    keys.add nnkObjConstr.newTree(
      ident("ConfigSchemaKey"),
      newColonExpr(ident("name"), newLit(spec.key)),
      newColonExpr(ident("valueType"), schemaValueTypeIdent(spec)),
      newColonExpr(ident("typeLabel"), typeLabelExpr(spec)),
      newColonExpr(
        ident("description"),
        newLit(spec.docDesc.replace(DocSubjectPlaceholder, subject)),
      ),
      newColonExpr(ident("condition"), newLit(conditionNote(spec))),
      newColonExpr(ident("values"), valuesExpr(spec)),
    )

  let sectionExpr = nnkObjConstr.newTree(
    ident("ConfigSchemaSection"),
    newColonExpr(ident("name"), newLit(sec)),
    newColonExpr(
      ident("description"),
      newLit(
        if subject.len > 0:
          subject
        else:
          typeDocDescription(innerTd)
      ),
    ),
    newColonExpr(ident("isArrayOfTables"), newLit(isArray)),
    newColonExpr(ident("keys"), newCall(ident("@"), keys)),
  )
  result =
    newStmtList(setChecks, newCall(newDotExpr(target, ident("add")), sectionExpr))

macro generateConfigSchema*(target: typed, OuterT: typedesc): untyped =
  ## Emit one `ConfigSchemaSection` per `{.cfgSection.}` field of `OuterT`, in
  ## declaration order. Works for any object owning section-typed fields.
  let outerTd = typeDef(OuterT)
  if outerTd == nil:
    error("cannot get impl for outer type", OuterT)
  result = newStmtList()
  for (_, typ, sec) in cfgSectionFields(outerTd):
    result.add buildSchemaBody(target, typ.getImpl, sec)

proc buildTableSchema(node: ConfigNode, target: NimNode): NimNode =
  ## The completion schema for `node` and every table below it.
  result = newStmtList(buildSchemaBody(target, node.td, node.path, node.subject))
  for child in node.children:
    case child.kind
    of cnkTable:
      error("a root table cannot appear as a child table", child.typ)
    of cnkSubSection:
      result.add buildTableSchema(child, target)
    of cnkArrayOfTables:
      # Same keys, under a `[[...]]` header the user may repeat.
      result.add buildSchemaBody(
        target, child.td, child.path, child.subject, isArray = true
      )

macro generateSectionGroupSchema*(target: typed, T: typedesc): untyped =
  ## Emit the schema for a section group: the parent table, then one section
  ## per child table.
  buildTableSchema(groupTree(T), target)
