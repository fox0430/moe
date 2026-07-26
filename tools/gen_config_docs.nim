## Regenerate the auto-generated portions of `documents/configfile.md`.
##
## Usage: `nim r tools/gen_config_docs.nim`
##
## Each `### Xxx table` section in the markdown file that is wrapped in
## `<!-- AUTO-GEN:start Xxx -->` / `<!-- AUTO-GEN:end Xxx -->` markers is
## replaced with a freshly generated table built from the corresponding
## `XxxConfig` type in `src/moepkg/config.nim`. The remaining content
## (intro, enum sections, hand-maintained tables) is left untouched.
##
## Fields surface in the table only if they carry both `{.cfg.}` and
## `{.cfgDocDescription: "...".}`. The default-value column is read from
## the running `newEditorConfig()` instance unless the field overrides it
## with `{.cfgDocDefault: <literal>.}`.

import std/[macros, options, os, sequtils, strutils]

import ../src/moepkg/[color, config, config_macros, help_description]

# default-value formatters used by `generateSectionMarkdown`

proc formatDocDefault*(v: bool): string =
  $v

proc formatDocDefault*(v: int): string =
  $v

proc formatDocDefault*(v: float): string =
  $v

proc formatDocDefault*(v: string): string =
  ## Empty strings render as a blank cell (matching the convention used by
  ## the hand-written tables, e.g. QuickRun.command). Non-empty values are
  ## wrapped in double quotes so they are visually distinguishable from
  ## numeric or enum defaults in the same column.
  if v.len == 0:
    ""
  else:
    "\"" & v & "\""

proc formatDocDefault*(v: Option[string]): string =
  if v.isSome:
    formatDocDefault(v.get)
  else:
    "none"

proc formatDocDefault*(v: seq[string]): string =
  "[" & v.mapIt("\"" & it & "\"").join(", ") & "]"

proc formatDocDefault*[T: enum](v: T): string =
  ## Enum defaults are shown unquoted; their string form (set via the enum
  ## member's literal value, e.g. `cm256color = "256"`) is the TOML value.
  $v

# in-place marker replacement

const DocsPath* =
  currentSourcePath().parentDir.parentDir / "documents" / "configfile.md"
  ## Anchored to this source file so the tool works regardless of the
  ## process working directory — `nimble gendocs` happens to run from
  ## the project root, but `nim r tools/gen_config_docs.nim` from a
  ## subdirectory must resolve the same file.

macro defineSections(specs: untyped): untyped =
  ## Single source of truth for the doc generator's section table. Each
  ## statement in `specs` is `("MarkerName", cfg.<path>, SectionType)` —
  ## the marker is the `<!-- AUTO-GEN:start ... -->` name, `cfg.<path>` is
  ## the accessor on a `EditorConfig` value (e.g. `cfg.standard` or
  ## `cfg.debug.windowNode`), and `SectionType` is the matching config
  ## type that `generateSectionMarkdown` walks for `{.cfg.}` fields.
  ##
  ## Emits two top-level declarations:
  ##   const SectionNames* = @[<marker>, ...]
  ##   proc bodyFor(name: string, cfg: EditorConfig): string =
  ##     case name
  ##     of <marker>: generateSectionMarkdown(<parent>, <leaf>, SectionType)
  ##     ...
  ##     else: raise ValueError
  ##
  ## Adding a section is one new tuple — the names list and the dispatch
  ## case stay in lockstep automatically.
  ##
  ## Section groups are declared separately with `defineGroupSections`.
  expectKind(specs, nnkStmtList)
  # `quote do` applies hygiene by default — bare idents inside the
  # template become fresh `gensym` symbols, hiding the declarations from
  # any later reference. Interpolating idents via backticks (built with
  # `ident"..."`) opts out of that, so the case selector, proc params,
  # and the public `SectionNames` / `bodyFor` names all resolve as plain
  # module-scope identifiers after expansion.
  let nameParam = ident"name"
  let cfgParam = ident"cfg"
  let sectionNamesIdent = ident"SectionNames"
  let bodyForIdent = ident"bodyFor"
  let editorConfigIdent = ident"EditorConfig"
  let stringIdent = ident"string"
  var namesArr = nnkBracket.newTree()
  let caseStmt = nnkCaseStmt.newTree(nameParam)

  proc addSection(nameLit, accessor, typeIdent: NimNode) =
    if nameLit.kind != nnkStrLit:
      error("first element must be a string literal", nameLit)
    if accessor.kind != nnkDotExpr:
      error("second element must be a dotted access starting at `cfg`", accessor)
    namesArr.add nameLit
    let call =
      newCall(ident"generateSectionMarkdown", accessor[0], accessor[1], typeIdent)
    caseStmt.add nnkOfBranch.newTree(nameLit, newStmtList(call))

  for entry in specs:
    if entry.kind notin {nnkTupleConstr, nnkPar} or entry.len != 3:
      error("expected `(\"MarkerName\", cfg.<path>, SectionType)` tuple", entry)
    addSection(entry[0], entry[1], entry[2])
  caseStmt.add nnkElse.newTree(
    newStmtList(
      nnkRaiseStmt.newTree(
        newCall(
          ident"newException",
          ident"ValueError",
          infix(newLit("unknown section: "), "&", nameParam),
        )
      )
    )
  )

  let seqExpr = prefix(namesArr, "@")
  result = quote:
    const `sectionNamesIdent`* = `seqExpr`

    proc `bodyForIdent`(
        `nameParam`: `stringIdent`, `cfgParam`: `editorConfigIdent`
    ): `stringIdent` =
      `caseStmt`

defineSections:
  ("Standard", cfg.standard, StandardConfig)
  ("BufferBackend", cfg.bufferBackend, BufferBackendConfig)
  ("Clipboard", cfg.clipboard, ClipboardConfig)
  ("TabLine", cfg.tabLine, TabLineConfig)
  ("BuildOnSave", cfg.buildOnSave, BuildOnSaveConfig)
  ("Filer", cfg.filer, FilerConfig)
  ("FileTree", cfg.fileTree, FileTreeConfig)
  ("Autocomplete", cfg.autocomplete, AutocompleteConfig)
  ("AutoSave", cfg.autoSave, AutoSaveConfig)
  ("SmoothScroll", cfg.smoothScroll, SmoothScrollConfig)
  ("StatusLine", cfg.statusLine, StatusLineConfig)
  ("Highlight", cfg.highlight, HighlightConfig)
  ("AutoBackup", cfg.autoBackup, AutoBackupConfig)
  ("QuickRun", cfg.quickRun, QuickRunConfig)
  ("Notification", cfg.notification, NotificationConfig)
  ("Persist", cfg.persist, PersistConfig)
  ("Log", cfg.log, LogConfig)
  ("Git", cfg.git, GitConfig)
  ("SyntaxChecker", cfg.syntaxChecker, SyntaxCheckerConfig)
  ("StartUp.FileOpen", cfg.startUpFileOpen, StartUpFileOpenConfig)
  ("StartUp.FileTree", cfg.startUpFileTree, StartUpFileTreeConfig)
  ("EditorConfig", cfg.editorConfig, EditorConfigSettings)
  ("Debug.WindowNode", cfg.debug.windowNode, DebugWindowNodeConfig)
  ("Debug.EditorView", cfg.debug.editorView, DebugEditorViewConfig)
  ("Debug.BufferStatus", cfg.debug.bufferStatus, DebugBufferStatusConfig)
  ("Debug.Search", cfg.debug.search, DebugSearchConfig)
  ("Debug.MacroState", cfg.debug.macroState, DebugMacroConfig)
  ("Debug.Visual", cfg.debug.visual, DebugVisualConfig)
  ("Debug.JumpList", cfg.debug.jumpList, DebugJumpListConfig)
  ("Debug.Lsp", cfg.debug.lsp, DebugLspConfig)

macro defineGroupSections(ownerField: untyped, GroupT: typedesc): untyped =
  ## Counterpart of `defineSections` for a section group: the parent table
  ## plus one `Marker.Sub` section per `{.cfgSubSection.}` field of `GroupT`.
  ## Both the marker name and the sub-table list come from the type, so adding
  ## a feature table needs no edit here — only its AUTO-GEN marker pair in the
  ## markdown.
  ##
  ## Emits `<Marker>SectionNames*` and `<marker>BodyFor`, mirroring the
  ## `SectionNames` / `bodyFor` pair.
  let marker = groupTomlName(GroupT)
  let nameParam = ident"name"
  let cfgParam = ident"cfg"
  let namesIdent = ident(marker & "SectionNames")
  let bodyForIdent = ident(toLowerAscii(marker[0]) & marker[1 ..^ 1] & "BodyFor")
  let editorConfigIdent = ident"EditorConfig"
  let stringIdent = ident"string"

  var namesArr = nnkBracket.newTree(newLit(marker))
  let caseStmt = nnkCaseStmt.newTree(nameParam)
  caseStmt.add nnkOfBranch.newTree(
    newLit(marker),
    newStmtList(newCall(ident"generateSectionMarkdown", cfgParam, ownerField, GroupT)),
  )
  let ownerAccess = newDotExpr(cfgParam, ownerField)
  for (field, typ, subName, subject) in subSectionSpecs(GroupT):
    let subMarker = newLit(marker & "." & subName)
    namesArr.add subMarker
    # Interpolate the type symbol the walk already resolved rather than
    # rebuilding an ident from its name: a sub-table whose type this module
    # does not import would otherwise fail with a bare "undeclared
    # identifier", or bind to an unrelated same-named type in scope here.
    let subType = nnkBracketExpr.newTree(ident"typedesc", typ)
    caseStmt.add nnkOfBranch.newTree(
      subMarker,
      newStmtList(
        newCall(
          ident"generateSectionMarkdown",
          ownerAccess,
          ident(field),
          subType,
          newLit(subject),
        )
      ),
    )
  caseStmt.add nnkElse.newTree(
    newStmtList(
      nnkRaiseStmt.newTree(
        newCall(
          ident"newException",
          ident"ValueError",
          infix(newLit("unknown section: "), "&", nameParam),
        )
      )
    )
  )

  let seqExpr = prefix(namesArr, "@")
  result = quote:
    const `namesIdent`* = `seqExpr`

    proc `bodyForIdent`(
        `nameParam`: `stringIdent`, `cfgParam`: `editorConfigIdent`
    ): `stringIdent` =
      `caseStmt`

defineGroupSections(lsp, LspConfig)

proc replaceMarkers(text: string, name, body: string): string =
  ## Replace the content between `<!-- AUTO-GEN:start name -->` and
  ## `<!-- AUTO-GEN:end name -->` with the new `body`. Raises if either
  ## marker is missing, or if any marker name appears more than once
  ## (which would leave duplicate blocks silently stale on regeneration).
  let startMarker = "<!-- AUTO-GEN:start " & name & " -->"
  let endMarker = "<!-- AUTO-GEN:end " & name & " -->"
  let startIdx = text.find(startMarker)
  if startIdx < 0:
    raise newException(ValueError, "missing start marker for " & name)
  if text.find(startMarker, startIdx + startMarker.len) >= 0:
    raise
      newException(ValueError, "duplicate <!-- AUTO-GEN:start " & name & " --> marker")
  let endIdx = text.find(endMarker, startIdx + startMarker.len)
  if endIdx < 0:
    raise newException(ValueError, "missing end marker for " & name)
  if text.find(endMarker, endIdx + endMarker.len) >= 0:
    raise
      newException(ValueError, "duplicate <!-- AUTO-GEN:end " & name & " --> marker")
  let before = text[0 ..< startIdx + startMarker.len]
  let after = text[endIdx ..^ 1]
  before & "\n" & body & after

proc generateColorsMarkdown(): string =
  ## Render the markdown table for the Theme `[Colors]` section. Unlike the
  ## struct-driven sections, this one iterates `EditorColorPairIndex` and
  ## reads descriptions from `EditorColorPairDocDescription` in color.nim;
  ## the TOML key for each enum value comes from `toTomlColorKey`. The two
  ## top-level keys `foreground` / `background` are emitted manually since
  ## they overlay the `default` pair rather than appearing as enum members.
  result = "| Name | Description |\n"
  result &= "|:---|:---|\n"
  result &= "| foreground | Default foreground color (overrides `Colors.default.fg`) |\n"
  result &= "| background | Default background color (overrides `Colors.default.bg`) |\n"
  for index in EditorColorPairIndex:
    if index == EditorColorPairIndex.default:
      continue
    let key = escapeMdCell(toTomlColorKey(index))
    let desc = escapeMdCell(EditorColorPairDocDescription[index])
    result &= "| " & key & " | " & desc & " |\n"

const ExtraSectionNames* = @["Colors"]
  ## Section names handled outside the struct-driven `defineSections`
  ## dispatch. Each entry has a one-off generator invoked from
  ## `regenerateConfigDocs` after the standard sections.

proc bodyForExtra(name: string): string =
  case name
  of "Colors":
    generateColorsMarkdown()
  else:
    raise newException(ValueError, "unknown extra section: " & name)

proc regenerateConfigDocs*(input: string): string =
  ## Apply every section's AUTO-GEN replacement to `input` and return the
  ## new markdown content. Pure function — does not touch the filesystem.
  ## Used both by the CLI runner (read → regenerate → write) and by the
  ## sync test (read → regenerate → compare), so they share one code path.
  let cfg = newEditorConfig()
  result = input
  for name in SectionNames:
    result = replaceMarkers(result, name, bodyFor(name, cfg))
  for name in LspSectionNames:
    result = replaceMarkers(result, name, lspBodyFor(name, cfg))
  for name in ExtraSectionNames:
    result = replaceMarkers(result, name, bodyForExtra(name))

proc main() {.used.} =
  if not fileExists(DocsPath):
    echo "missing: ", DocsPath
    quit 1

  let original = readFile(DocsPath)
  let regenerated = regenerateConfigDocs(original)
  let totalSections = SectionNames.len + LspSectionNames.len + ExtraSectionNames.len
  if regenerated != original:
    writeFile(DocsPath, regenerated)
    echo "regenerated ", totalSections, " section(s) in ", DocsPath
  else:
    echo "up-to-date: ", DocsPath, " (", totalSections, " section(s) checked)"

when isMainModule:
  main()
