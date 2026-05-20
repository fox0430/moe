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
##   `BufferBackendConfig` looks up `parseBufferBackend` / `ValidBufferBackends`.
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
  ## For `BufferBackendConfig` -> `parseBufferBackend` (strips trailing `Config`).
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
  let sec = sectionName(td)
  result = newStmtList()

  # Collect field names + emit per-field load calls.
  var validKeys: seq[string] = @[]
  var loadCalls = newStmtList()

  for (fieldName, typeNode, pragmas) in sectionFields(td):
    if hasPragma(pragmas, "cfgSkip"):
      continue
    if not hasPragma(pragmas, "cfg"):
      continue

    # TOML key override
    let keyOverride = findPragma(pragmas, "cfgKey")
    let key =
      if keyOverride != nil:
        let a = pragmaArg(keyOverride)
        if a == nil or a.kind != nnkStrLit:
          error("cfgKey requires a string literal", keyOverride)
        a.strVal
      else:
        fieldName
    validKeys.add key

    let fieldAcc = newDotExpr(cfgVar, ident(fieldName))
    let secLit = newLit(sec)
    let keyLit = newLit(key)

    # Dispatch by type
    let typeName = if typeNode.kind in {nnkIdent, nnkSym}: typeNode.strVal else: ""

    case typeName
    of "bool":
      loadCalls.add quote do:
        loadBool(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
    of "int":
      let minP = findPragma(pragmas, "cfgMin")
      let maxP = findPragma(pragmas, "cfgMax")
      var call = newCall(ident("loadInt"), t, keyLit, fieldAcc, vr, secLit)
      if minP != nil:
        call.add newTree(nnkExprEqExpr, ident("minVal"), pragmaArg(minP))
      if maxP != nil:
        call.add newTree(nnkExprEqExpr, ident("maxVal"), pragmaArg(maxP))
      loadCalls.add call
    of "float":
      let minP = findPragma(pragmas, "cfgMin")
      let maxP = findPragma(pragmas, "cfgMax")
      var call = newCall(ident("loadFloat"), t, keyLit, fieldAcc, vr, secLit)
      if minP != nil:
        call.add newTree(nnkExprEqExpr, ident("minVal"), pragmaArg(minP))
      if maxP != nil:
        call.add newTree(nnkExprEqExpr, ident("maxVal"), pragmaArg(maxP))
      loadCalls.add call
    of "string":
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
    else:
      if isEnumTypeIdent(typeNode):
        let parseFn = enumParseName(typeNode)
        let validArr = enumValidName(typeNode)
        loadCalls.add quote do:
          loadEnum(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`, `parseFn`, `validArr`)
      elif isSeqOfString(typeNode):
        loadCalls.add quote do:
          loadStringArray(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
      elif isOptionOfString(typeNode):
        if hasPragma(pragmas, "cfgDirPath"):
          loadCalls.add quote do:
            loadOptionDirPath(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
        else:
          loadCalls.add quote do:
            loadOptionString(`t`, `keyLit`, `fieldAcc`, `vr`, `secLit`)
      else:
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
