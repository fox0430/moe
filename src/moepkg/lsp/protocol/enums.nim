## Copyright (c) 2023 The core Nim team
## https://github.com/nim-lang/langserver

# NOTE: Language Server Protocol Specification - 3.17
# https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/

type
  ErrorCode* = enum
    RequestCancelled = -32800 # All the other error codes are from JSON-RPC
    ParseError = -32700,
    InternalError = -32603,
    InvalidParams = -32602,
    MethodNotFound = -32601,
    InvalidRequest = -32600,
    ServerErrorStart = -32099,
    ServerNotInitialized = -32002,
    ServerErrorEnd = -32000,

# Anything below here comes from the LSP specification
type
  LanguageIdExtension* {.pure.} = enum
    abap = "abap"
    bat = "bat"
    bibtex = "bibtex"
    clojure = "clojure "
    coffeescript = "coffeescript"
    c = "c"
    cpp = "cpp"
    csharp = "csharp"
    css = "css"
    diff = "diff"
    dart = "dart"
    dockerfile = "dockerfile"
    elixir = "elixir"
    erlang = "erlang"
    fsharp = "fsharp"
    gitCommit = "git-commit"
    gitRebase = "git-rebase"
    go = "go"
    groovry = "groovry"
    handlebars = "handlebars"
    haskell = "haskell"
    html = "html"
    ini = "ini"
    java = "java"
    javascript = "javascript"
    json = "json"
    latex = "latex"
    less = "less"
    lua = "lua"
    makefile = "makefile"
    nim = "nim"
    objectiveC = "objective-c"
    objectiveCpp = "objective-cpp"
    perl = "perl"
    perl6 = "perl6"
    php= "php"
    powershell = "powershell"
    pug = "jade"
    python = "python"
    r = "r"
    razor = "razor"
    ruby = "ruby"
    rust = "rust"
    scss = "scss"
    scala = "scala"
    shaderLab = "shaderlab"
    bash = "shellscript"
    sql = "sql"
    swift = "swift"
    typeScript = "typescript"
    typeScriptReact = "typescriptreact"
    tex = "tex"
    visualBasic = "vb"
    xml = "xml"
    xsl = "xsl"
    yaml = "yaml"

  DiagnosticSeverity* {.pure.} = enum
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4

  SymbolKind* {.pure.} = enum
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26

  SymbolTag* {.pure.} = enum
    Deprecated = 1

  CompletionItemKind* {.pure.} = enum
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25

  TextDocumentSyncKind* {.pure.} = enum
    None = 0,
    Full = 1,
    Incremental = 2

  MessageType* {.pure.} = enum
    Error = 1,
    Warning = 2,
    Info = 3,
    Log = 4

  FileChangeType* {.pure.} = enum
    Created = 1,
    Changed = 2,
    Deleted = 3

  WatchKind* {.pure.} = enum
    Create = 1,
    Change = 2,
    Delete = 4

  TextDocumentSaveReason* {.pure.} = enum
    Manual = 1,
    AfterDelay = 2,
    FocusOut = 3

  CompletionTriggerKind* {.pure.} = enum
    Invoked = 1,
    TriggerCharacter = 2,
    TriggerForIncompleteCompletions = 3

  InsertTextFormat* {.pure.} = enum
    PlainText = 1,
    Snippet = 2

  DocumentHighlightKind* {.pure.} = enum
    Text = 1,
    Read = 2,
    Write = 3

  SignatureHelpTriggerKind* {.pure.} = enum
    Invoked = 1,
    TriggerCharacter = 2,
    ContentChange = 3

  TraceValue* {.pure.} = enum
    off
    messages
    verbose

  SemanticTokenTypes* {.pure.} = enum
    namespace
    `type`
    `class`
    `enum`
    `interface`
    struct
    typeParameter
    parameter
    variable
    property
    enumMember
    event
    function
    `method`
    `macro`
    keyword
    modifier
    comment
    string
    number
    regexp
    operator
    decorator

  SemanticTokenModifiers* {.pure.} = enum
    declaration
    definition
    readonly
    `static`
    deprecated
    abstract
    async
    modification
    documentation
    defaultLibrary

  FoldingRangeKind* {.pure.} = enum
    comment
    imports
    region
