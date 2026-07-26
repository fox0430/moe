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
## only its dynamic `[Lsp.<languageId>]` entries stay hand-written.
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

proc buildLoaderBody(
    td, t, cfgVar, vr: NimNode, sec: string, checkUnknown = true
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
  result = newStmtList()

  var loadCalls = newStmtList()

  for (fieldName, typeNode, pragmas, key) in serializableFields(td):
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

    # Deprecation notice: emit after the type-dispatched load so the value is
    # still assigned (backward-compatible). The key stays in validKeys so it
    # does not surface as an unknown-key notice.
    let deprecatedP = findPragma(pragmas, "cfgDeprecated")
    if deprecatedP != nil:
      let msgArg = pragmaArg(deprecatedP)
      if msgArg == nil or msgArg.kind != nnkStrLit:
        error("cfgDeprecated requires a string literal message", deprecatedP)
      let msgLit = newLit(msgArg.strVal)
      loadCalls.add quote do:
        if `t`.hasKey(`keyLit`):
          `vr`.addDeprecated(fullKey(`secLit`, `keyLit`), `msgLit`)

  # Build `const validKeys = [...]`. Use gensym'd names so the const block
  # the macro injects into the caller's proc scope cannot be referenced by
  # surrounding code (preventing implicit dependencies on internal symbols).
  if checkUnknown:
    var arrLit = newNimNode(nnkBracket)
    for k in scalarKeys(td):
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
  buildLoaderBody(td, t, cfgVar, vr, sectionName(td))

proc buildSerializerBody(td, lines, cfgVar: NimNode, sec: string): NimNode =
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

  let headerLit = newLit("[" & sec & "]")
  result.add quote do:
    `lines`.add `headerLit`

  for (fieldName, typeNode, pragmas, key) in serializableFields(td):
    # Deprecated fields still load (see loader) but must not be written back,
    # so user configs shed the obsolete key on the next save cycle.
    if hasPragma(pragmas, "cfgDeprecated"):
      continue

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
  for (fieldName, fieldType, pragmas) in sectionFields(innerTd):
    if hasPragma(pragmas, "cfgSkip"):
      continue
    if not hasPragma(pragmas, "cfg"):
      continue
    if hasPragma(pragmas, "cfgNoUi"):
      continue
    if hasPragma(pragmas, "cfgDeprecated"):
      # Deprecated fields are transitional: keep them loading but hide them
      # from the config-mode UI so users are not prompted to edit them.
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

    let path = newDotExpr(base, ident(fieldName))

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
        let optsExpr = newCall(ident("@"), arr)
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

## Section groups
##
## A *section group* owns both scalar keys of its own parent table and a set
## of `{.cfgSubSection.}` sub-tables. The four macros below all derive from
## one walk of the group type, so loader, key list, serializer and UI cannot
## drift apart.
##
## Groups are deliberately NOT `{.cfgSection.}` types: the whole-config walk
## would then emit a strict unknown-key check on the parent table, which is
## wrong when the parent also accepts caller-defined keys (`[Lsp.<languageId>]`).
## The owner module calls the macros and owns that policy instead.

proc subSectionFields(
    ownerTd: NimNode
): seq[tuple[field: string, typ: NimNode, name: string, pragmas: NimNode]] =
  ## Walk `ownerTd`'s fields and return those carrying `{.cfgSubSection.}`,
  ## paired with the sub-table name from the pragma. Sub-table names must be
  ## unique and distinct from the group's own scalar keys: a duplicate would
  ## emit two TOML entries of the same name and load one table into two
  ## fields, which no later stage can detect.
  result = @[]
  var ownKeys = toHashSet(scalarKeys(ownerTd))
  var seenNames = initHashSet[string]()
  for (fieldName, typeNode, pragmas) in sectionFields(ownerTd):
    let p = findPragma(pragmas, "cfgSubSection")
    if p == nil:
      continue
    if hasPragma(pragmas, "cfg"):
      error(
        "field `" & fieldName &
          "` carries both {.cfg.} and {.cfgSubSection.}: a sub-table is not a scalar key",
        typeNode,
      )
    let arg = pragmaArg(p)
    if arg == nil or arg.kind != nnkStrLit:
      error("cfgSubSection requires a string literal", p)
    if typeNode.kind notin {nnkIdent, nnkSym} or typeNode.getImpl == nil:
      error("cfgSubSection requires a named object type", typeNode)
    let name = arg.strVal
    if name in seenNames:
      error(
        "duplicate {.cfgSubSection: \"" & name & "\".} on field `" & fieldName &
          "`: another field already claims that sub-table name",
        p,
      )
    if name in ownKeys:
      error(
        "{.cfgSubSection: \"" & name & "\".} on field `" & fieldName &
          "` collides with a scalar {.cfg.} key of the same name",
        p,
      )
    seenNames.incl name
    result.add (fieldName, typeNode, name, pragmas)
  if result.len == 0:
    error("no {.cfgSubSection.} fields found on " & ownerTd.repr, ownerTd)

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

macro cfgGroupName*(T: typedesc): untyped =
  ## The parent TOML table name of a section group, as a string literal.
  newLit(groupName(groupOwner(T)))

macro generateSectionGroupLoader*(t, cfgVar, vr: typed, T: typedesc): untyped =
  ## Emit the loader for a section group: the parent table's own `{.cfg.}`
  ## fields, then one `if expectTable(t, "Child", ...): <sub-table loader>` per
  ## sub-section. No unknown-key check — see `generateSectionGroupKeys`.
  let ownerTd = groupOwner(T)
  let section = groupName(ownerTd)
  # Validate the sub-section pragmas before building the owner's body: the
  # scalar-key builders reject an object-typed field first and would mask a
  # {.cfg.} / {.cfgSubSection.} conflict with a bare "unsupported field type".
  let subs = subSectionFields(ownerTd)
  result = buildLoaderBody(ownerTd, t, cfgVar, vr, section, checkUnknown = false)
  for (field, typ, name, _) in subs:
    let nameLit = newLit(name)
    let fieldAcc = newDotExpr(cfgVar, ident(field))
    let tbl = genSym(nskLet, "tbl")
    let body = buildLoaderBody(typ.getImpl, tbl, fieldAcc, vr, section & "." & name)
    let secLit = newLit(section)
    result.add quote do:
      if expectTable(`t`, `nameLit`, `vr`, `secLit`):
        let `tbl` = `t`[`nameLit`].getTable()
        `body`

macro generateSectionGroupKeys*(T: typedesc): untyped =
  ## Return an array literal of every key the group owns in its parent table
  ## (scalar `{.cfg.}` keys, then sub-table names). The owner uses it to tell
  ## its dynamic keys from typos.
  let ownerTd = groupOwner(T)
  var arr = newNimNode(nnkBracket)
  for key in scalarKeys(ownerTd):
    arr.add newLit(key)
  for (_, _, name, _) in subSectionFields(ownerTd):
    arr.add newLit(name)
  result = arr

macro generateSectionGroupSerializer*(lines, cfgVar: typed, T: typedesc): untyped =
  ## Emit the serializer for a section group: the `[Parent]` header and its
  ## scalar keys, then one `[Parent.Child]` block per sub-section. Dynamic
  ## entries are appended by the owner afterwards.
  let ownerTd = groupOwner(T)
  let section = groupName(ownerTd)
  let subs = subSectionFields(ownerTd)
  result = buildSerializerBody(ownerTd, lines, cfgVar, section)
  for (field, typ, name, _) in subs:
    let fieldAcc = newDotExpr(cfgVar, ident(field))
    result.add buildSerializerBody(typ.getImpl, lines, fieldAcc, section & "." & name)

macro generateSectionGroupDescriptors*(
    target: typed, ownerField: untyped, T: typedesc
): untyped =
  ## Emit the config-mode UI descriptors for a section group reached from an
  ## `EditorConfig` named `c` via `ownerField` (e.g. `lsp`): the parent section
  ## plus one per sub-section.
  let ownerTd = groupOwner(T)
  let section = groupName(ownerTd)
  let subs = subSectionFields(ownerTd)
  let ownerBase = newDotExpr(ident("c"), ident(ownerField.strVal))
  result = buildDescriptorsBody(target, ownerTd, ownerBase, section)
  for (field, typ, name, _) in subs:
    let base = newDotExpr(ownerBase, ident(field))
    result.add buildDescriptorsBody(target, typ.getImpl, base, section & "." & name)

proc groupTomlName*(T: NimNode): string {.compileTime.} =
  ## Compile-time accessor for a section group's parent table name, for macros
  ## that need it outside `generateSectionGroup*`. `T` is a typedesc node.
  groupName(groupOwner(T))

proc subSectionSpecs*(
    T: NimNode
): seq[tuple[field: string, typ: NimNode, name: string, subject: string]] {.
    compileTime
.} =
  ## Compile-time accessor for a section group's sub-tables, for macros that
  ## emit one declaration per sub-table. `T` is a typedesc node; returns
  ## (field, type symbol, sub-table name, subject) in declaration order, where
  ## the subject is the sub-table's `{.cfgDocDescription.}` (see
  ## `DocSubjectPlaceholder`). The type is returned as a symbol so callers
  ## interpolate it directly instead of re-resolving it by name.
  result = @[]
  for (field, typ, name, pragmas) in subSectionFields(groupOwner(T)):
    var subject = ""
    let p = findPragma(pragmas, "cfgDocDescription")
    if p != nil:
      let arg = pragmaArg(p)
      if arg == nil or arg.kind != nnkStrLit:
        error("cfgDocDescription requires a string literal", p)
      subject = arg.strVal
    result.add (field, typ, name, subject)

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

const DocSubjectPlaceholder* = "{}"
  ## Placeholder in a `{.cfgDocDescription.}`, replaced with the sub-table's
  ## own subject: `"Enable {}"` on the shared `LspFeatureConfig` renders as
  ## "Enable LSP Completion" under `[Lsp.Completion]`. Outside a sub-table
  ## there is nothing to substitute, so leaving it in is a compile-time error.

macro generateSectionMarkdown*(
    cfg: typed,
    sectionField: untyped,
    sectionType: typedesc,
    subject: static string = "",
): untyped =
  ## Render the markdown table for one EditorConfig section. The call:
  ##   generateSectionMarkdown(cfg, standard, StandardConfig)
  ## expands to a `block:` expression whose value is the full table string
  ## (header + separator + one row per `{.cfg.}` field that also carries
  ## `{.cfgDocDescription.}`). The default-value column uses
  ## `formatDocDefault(cfg.<section>.<field>)`, expecting overloaded
  ## `formatDocDefault` helpers to be in scope at the call site.
  ##
  ## `subject` fills the `DocSubjectPlaceholder` in field descriptions; the
  ## sub-table entries of a section group pass their own name for it.
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
    if hasPragma(pragmas, "cfgDeprecated"):
      # Deprecated fields are omitted from the docs so the reference does not
      # advertise them; the loader still accepts them for backward compat.
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
    if DocSubjectPlaceholder in descArg.strVal and subject.len == 0:
      error(
        "field `" & fieldName & "`: `" & DocSubjectPlaceholder &
          "` in {.cfgDocDescription.} has nothing to expand to. Only a section " &
          "group's sub-tables supply a subject; give the sub-table a " &
          "{.cfgDocDescription.} of its own, or drop the placeholder.",
        docDescP,
      )
    let desc = descArg.strVal.replace(DocSubjectPlaceholder, subject)

    # Static cells (name / type / description) are known at macro-expansion
    # time, so escape them now and emit literals — no runtime cost.
    let nameLit = newLit(escapeMdCell(fieldName))
    let typeLit = newLit(escapeMdCell(docTypeLabel(typeNode)))
    let descLit = newLit(escapeMdCell(desc))

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
        escapeMdCell(formatDocDefault(`defaultExpr`)) & " | " & `descLit` & " |\n"

  result = nnkBlockStmt.newTree(newEmptyNode(), newStmtList(result, resVar))
