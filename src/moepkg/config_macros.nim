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
##                     cfgEnumStrings: ["a", "b", ...]    (post-validate a string
##                                                         field against a fixed
##                                                         option set; first entry
##                                                         is the fallback default)
##
## Supported field types:
##   loader + descriptor: bool, int, float, string, enum
##   loader only:         Option[string], seq[string]  (mark field with cfgNoUi)
##
## Sections intentionally not migrated (hand-written): ThemeConfig (conditional
## file/string handling), LspConfig (dynamic server Table), KeyMappingConfig
## (OrderedTable + parsing), CommandAliases/ShellCommands (nested objects).

import std/[macros, strutils]

## Apply to a section type to give it a TOML section name.
##   StandardConfig* {.cfgSection: "Standard".} = object
template cfgSection*(name: string) {.pragma.}

## Marker: this field is loaded/described automatically.
template cfg*() {.pragma.}

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

## For string fields, restrict the loaded value to a fixed option set. On
## mismatch, the loader records an error and resets the field to the first
## option. Example:
##   popupPosition* {.cfg, cfgEnumStrings: ["topRight", "topLeft"].}: string
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

proc escapeMarkdownCell*(s: string): string =
  ## Escape characters that would corrupt a single markdown table cell:
  ## unescaped `|` ends the cell, and a literal newline starts a new row.
  ## Backslash is escaped so a stray `\|` in source data round-trips faithfully.
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\\':
      result.add("\\\\")
    of '|':
      result.add("\\|")
    of '\n', '\r':
      result.add(' ')
    else:
      result.add(c)

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

proc buildLoaderBody(td, t, cfgVar, vr: NimNode): NimNode =
  ## Build the loader statements for the section TypeDef `td`, reading from the
  ## TOML table expression `t` into the config accessor `cfgVar`, recording
  ## issues in `vr`. Shared by `generateConfigLoader` (single section) and
  ## `generateSectionLoaders` (whole-config dispatch) so the per-field type
  ## handling lives in exactly one place.
  let sec = sectionName(td)
  result = newStmtList()

  # Collect field names + emit per-field load calls.
  var validKeys: seq[string] = @[]
  var loadCalls = newStmtList()

  for (fieldName, typeNode, pragmas, key) in serializableFields(td):
    validKeys.add key

    let fieldAcc = newDotExpr(cfgVar, ident(fieldName))
    let secLit = newLit(sec)
    let keyLit = newLit(key)

    # Dispatch by type
    case classifyConfigFieldType(typeNode)
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
      loadCalls.add quote do:
        loadString(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
      # cfgEnumStrings: post-validate against a fixed option list.
      let enumStrP = findPragma(pragmas, "cfgEnumStrings")
      if enumStrP != nil:
        let opts = parseStringArrayLit(pragmaArg(enumStrP))
        if opts.len == 0:
          error(
            "cfgEnumStrings requires a non-empty array of string literals " &
              "(e.g. `{.cfgEnumStrings: [\"a\", \"b\"].}`)",
            enumStrP,
          )
        var arr = newNimNode(nnkBracket)
        for o in opts:
          arr.add newLit(o)
        let defaultLit = newLit(opts[0])
        let expectedLit = newLit("one of: " & opts.join(", "))
        loadCalls.add quote do:
          if `t`.hasKey(`keyLit`) and `fieldAcc` notin `arr`:
            `vr`.addError(fullKey(`secLit`, `keyLit`), `fieldAcc`, `expectedLit`)
            `fieldAcc` = `defaultLit`
    of cfkEnum:
      let parseFn = enumParseName(typeNode)
      let validArr = enumValidName(typeNode)
      loadCalls.add quote do:
        loadEnum(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`, `parseFn`, `validArr`)
    of cfkSeqString:
      loadCalls.add quote do:
        loadStringArray(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
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

  # Build `const validKeys = [...]`. Use gensym'd names so the const block
  # the macro injects into the caller's proc scope cannot be referenced by
  # surrounding code (preventing implicit dependencies on internal symbols).
  var arrLit = newNimNode(nnkBracket)
  for k in validKeys:
    arrLit.add newLit(k)
  let validKeysIdent = genSym(nskConst, "validKeys")
  let sectionIdent = genSym(nskConst, "section")
  let secLit = newLit(sec)

  result.add quote do:
    const `sectionIdent` = `secLit`
    const `validKeysIdent` = `arrLit`
    checkUnknownKeys(`t`, `validKeysIdent`, `sectionIdent`, `vr`)
  result.add loadCalls

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
  buildLoaderBody(td, t, cfgVar, vr)

proc buildSerializerBody(td, lines, cfgVar: NimNode): NimNode =
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
  ## only when `isSome`.
  let sec = sectionName(td)
  result = newStmtList()

  let headerLit = newLit("[" & sec & "]")
  result.add quote do:
    `lines`.add `headerLit`

  for (fieldName, typeNode, _, key) in serializableFields(td):
    let keyPrefix = newLit(key & " = ")
    let fieldAcc = newDotExpr(cfgVar, ident(fieldName))

    case classifyConfigFieldType(typeNode)
    of cfkBool:
      result.add quote do:
        `lines`.add `keyPrefix` & toTomlBool(`fieldAcc`)
    of cfkInt, cfkFloat:
      result.add quote do:
        `lines`.add `keyPrefix` & $`fieldAcc`
    of cfkString:
      result.add quote do:
        `lines`.add `keyPrefix` & toTomlString(`fieldAcc`)
    of cfkEnum:
      validateEnumStringValues(typeNode)
      result.add quote do:
        `lines`.add `keyPrefix` & toTomlString($`fieldAcc`)
    of cfkSeqString:
      result.add quote do:
        `lines`.add `keyPrefix` & toTomlStringArray(`fieldAcc`)
    of cfkOptionString:
      result.add quote do:
        if `fieldAcc`.isSome:
          `lines`.add `keyPrefix` & toTomlString(`fieldAcc`.get)
    of cfkUnsupported:
      error(
        "config serializer: unsupported field type `" & typeNode.repr & "` for field `" &
          fieldName & "`. Skip it with {.cfgSkip.} or " & "extend the macro.",
        typeNode,
      )

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
  ##   if toml.hasKey("Section"):
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
    let loadBody = buildLoaderBody(innerTd, tbl, fieldAcc, vr)
    result.add quote do:
      if `toml`.hasKey(`secLit`):
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
    result.add buildSerializerBody(innerTd, lines, fieldAcc)

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

macro generateConfigDescriptors*(
    target: typed, OuterT: typedesc, accessor: untyped
): untyped =
  ## Emit `target.add ConfigItemDescriptor(...)` entries for the section
  ## reached via `OuterT.<accessor>`. Produces:
  ##   target.add ConfigItemDescriptor(kind: cvkSection, ...)
  ##   target.add ConfigItemDescriptor(kind: cvkBool, ...)  -- for each field
  ##   ...
  if accessor.kind notin {nnkIdent, nnkSym}:
    error("accessor must be an identifier", accessor)

  # Find the inner section type by looking up `accessor` in OuterT's fields.
  let outerTd = typeDef(OuterT)
  if outerTd == nil:
    error("cannot get impl for outer type", OuterT)
  var innerTypeNode: NimNode = nil
  for (name, typeNode, _) in sectionFields(outerTd):
    if name == accessor.strVal:
      innerTypeNode = typeNode
      break
  if innerTypeNode == nil:
    error("field `" & accessor.strVal & "` not found on outer type", accessor)

  let innerTd = innerTypeNode.getImpl
  if innerTd == nil or innerTd.kind != nnkTypeDef:
    error("cannot resolve inner type impl", innerTypeNode)
  let sec = sectionName(innerTd)
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
  for (fieldName, fieldType, pragmas) in sectionFields(innerTd):
    if hasPragma(pragmas, "cfgSkip"):
      continue
    if hasPragma(pragmas, "cfgNoUi"):
      continue
    if not hasPragma(pragmas, "cfg"):
      continue

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

    # Accessor: c.<accessor>.<field>
    let path = newDotExpr(newDotExpr(cIdent, accessor), ident(fieldName))

    # cfgVisible: pred -> wrap as `proc(c: EditorConfig): bool = pred(c)`.
    # pred is invoked with the EditorConfig and must return bool. Using a
    # wrapper (rather than passing pred verbatim) means callers can supply a
    # plain template/proc by name without worrying about pragma annotations
    # on the predicate matching descriptor.visibleWhen's signature.
    let visibleP = findPragma(pragmas, "cfgVisible")
    var visibleExpr: NimNode = newNilLit()
    if visibleP != nil:
      let fn = pragmaArg(visibleP)
      if fn == nil:
        error("cfgVisible requires a predicate expression", visibleP)
      visibleExpr = quote:
        proc(`cIdent`: EditorConfig): bool {.noSideEffect.} =
          `fn`(`cIdent`)

    let typeName = if fieldType.kind in {nnkIdent, nnkSym}: fieldType.strVal else: ""

    case typeName
    of "bool":
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
    of "int":
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
    of "float":
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
    of "string":
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
    else:
      if isEnumTypeIdent(fieldType):
        # cfgEnum overrides the auto-derived option order. Useful when the UI
        # cycle order should differ from the declaration order, or when only
        # a subset of variants should be selectable.
        let cfgEnumP = findPragma(pragmas, "cfgEnum")
        var opts: seq[string]
        if cfgEnumP != nil:
          let arg = pragmaArg(cfgEnumP)
          opts = parseStringArrayLit(arg)
          if opts.len == 0:
            error(
              "cfgEnum requires a non-empty array of string literals " &
                "(e.g. `{.cfgEnum: [\"a\", \"b\"].}`)",
              cfgEnumP,
            )
        else:
          opts = enumStringValues(fieldType)
          if opts.len == 0:
            error("could not derive enum options for `" & typeName & "`", fieldType)
        var arr = newNimNode(nnkBracket)
        for o in opts:
          arr.add newLit(o)
        let optsExpr = newCall(ident("@"), arr)
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
      else:
        error(
          "generateConfigDescriptors: unsupported field type `" & fieldType.repr &
            "` for field `" & fieldName & "`. Hide it from the UI with " &
            "{.cfgNoUi.}, skip it entirely with {.cfgSkip.}, or extend the macro.",
          fieldType,
        )

proc docTypeLabel(typeNode: NimNode): string =
  ## Map a Nim field type to the human-readable label used by
  ## `documents/configfile.md`. Enum-typed fields render as
  ## `string (enum: a, b, ...)` — the TOML value is always a string, and
  ## listing the accepted variants inline is more actionable than the bare
  ## Nim type name. Falls back to stripping a trailing `Config` for any
  ## non-enum custom type.
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

macro generateSectionMarkdown*(
    cfg: typed, sectionField: untyped, sectionType: typedesc
): untyped =
  ## Render the markdown table for one EditorConfig section. The call:
  ##   generateSectionMarkdown(cfg, standard, StandardConfig)
  ## expands to a `block:` expression whose value is the full table string
  ## (header + separator + one row per `{.cfg.}` field that also carries
  ## `{.cfgDocDescription.}`). The default-value column uses
  ## `formatDocDefault(cfg.<section>.<field>)`, expecting overloaded
  ## `formatDocDefault` helpers to be in scope at the call site.
  let sectionAccess = newDotExpr(cfg, sectionField)
  let td = typeDef(sectionType)
  if td == nil:
    error("cannot get impl for section type", sectionField)

  let resVar = genSym(nskVar, "docTableResult")
  result = newStmtList()

  # Compile-time guard: catch `generateSectionMarkdown(cfg, tabLine,
  # FilerConfig)`-style swaps where the named field on `cfg` doesn't have
  # the declared section type. Without this, the mismatch surfaces deep
  # inside macro-expanded code with a confusing "undeclared field" error.
  let sectionMismatchMsg = newLit(
    "generateSectionMarkdown: cfg." & sectionField.repr & " is not of type " &
      sectionType.repr
  )
  result.add quote do:
    static:
      doAssert typeof(`sectionAccess`) is `sectionType`, `sectionMismatchMsg`

  result.add quote do:
    var `resVar` = "| Name | Type | Default Value | Description |\n"
    `resVar` &= "|:---|:---|:---|:---|\n"

  for (fieldName, typeNode, pragmas) in sectionFields(td):
    if hasPragma(pragmas, "cfgSkip"):
      continue
    if not hasPragma(pragmas, "cfg"):
      continue
    if hasPragma(pragmas, "cfgDocSkip"):
      # Field is intentionally excluded from auto-gen docs but still loaded.
      continue
    let docDescP = findPragma(pragmas, "cfgDocDescription")
    if docDescP == nil:
      error(
        "field `" & fieldName &
          "` has {.cfg.} but no {.cfgDocDescription.}: every cfg field in an " &
          "auto-generated section must be documented. Add a description, or " &
          "opt out with {.cfgDocSkip.}.",
        typeNode,
      )
    let descArg = pragmaArg(docDescP)
    if descArg == nil or descArg.kind != nnkStrLit:
      error("cfgDocDescription requires a string literal", docDescP)

    # Static cells (name / type / description) are known at macro-expansion
    # time, so escape them now and emit literals — no runtime cost.
    let nameLit = newLit(escapeMarkdownCell(fieldName))
    let typeLit = newLit(escapeMarkdownCell(docTypeLabel(typeNode)))
    let descLit = newLit(escapeMarkdownCell(descArg.strVal))

    # Default value: prefer cfgDocDefault override if present (for fields
    # whose runtime default varies by environment), otherwise read the
    # actual field on the passed-in config instance. The formatted result
    # is escaped at runtime since it depends on the config instance.
    let docDefaultP = findPragma(pragmas, "cfgDocDefault")
    let fieldAccess = newDotExpr(sectionAccess, ident(fieldName))
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
        "| " & `nameLit` & " | " & `typeLit` & " | " &
        escapeMarkdownCell(formatDocDefault(`defaultExpr`)) & " | " & `descLit` & " |\n"

  result = nnkBlockStmt.newTree(newEmptyNode(), newStmtList(result, resVar))
