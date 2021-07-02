
import strutils
import pnode_parse
from algorithm import binarySearch
import highlite
include syntaxnim

proc initNimToken(kind: TokenClass; start: int, buf: string): GeneralTokenizer {.inline.} =
  result = GeneralTokenizer(kind: kind, start: start, length: buf.len, buf: buf.cstring)

proc initNimKeyword(start: int, buf: string): GeneralTokenizer {.inline.} =
  result = GeneralTokenizer(kind: TokenClass.gtKeyword, start: start, length: buf.len, buf: buf.cstring)

proc initNimKeyword(n: PNode, buf: string): GeneralTokenizer =
  let start = n.info.offsetA
  let length = if n.info.offsetB == n.info.offsetA: buf.len else: n.info.offsetB - n.info.offsetA + 1
  result = GeneralTokenizer(kind: TokenClass.gtKeyword, start: start, length: length, buf: buf.cstring)

const CallNodes = {nkCall, nkInfix, nkPrefix, nkPostfix, nkCommand,
             nkCallStrLit, nkHiddenCallConv}

proc flatNode(par: PNode, outNodes: var seq[PNode]) =
  # outNodes.add par
  var d: PNode
  for n in par:
    d = n
    case n.kind
    of nkEmpty:
      continue
    of nkForStmt:
      for s in n.sons[^2 .. ^1]:
        flatNode(s, outNodes)
      outNodes.add d
      continue
    of nkProcDef:
      for s in n.sons[1 .. ^1]:
        flatNode(s, outNodes)
      d.sons.setLen(1)
      outNodes.add d
      continue
    of {nkCall, nkCommand}:
      d.sons.setLen(1)
      outNodes.add d
      for s in n.sons[1 .. ^1]:
        flatNode(s, outNodes)
      continue
    else:
      discard
    outNodes.add n
    flatNode(n, outNodes)

proc `$`*(node: PNode): string =
  ## Get the string of an identifier node.
  case node.kind
  of nkPostfix, nkInfix:
    result = $node[0].ident.s
  of nkIdent:
    result = $node.ident.s
  of nkPrefix:
    result = $node.ident.s
  of nkStrLit..nkTripleStrLit, nkCommentStmt, nkSym:
    result = node.strVal
  # of nnkOpenSymChoice, nnkClosedSymChoice:
  #   result = $node[0]
  of nkAccQuoted:
    result = $node[0]
  else:
    discard

proc basename*(a: PNode): PNode {.raises: [].} =
  ## Pull an identifier from prefix/postfix expressions.
  case a.kind
  of nkIdent: result = a
  of nkPostfix, nkPrefix:result = a[1]
  of nkPragmaExpr: result = basename(a[0])
  of nkExprColonExpr: result = a[0]
  else:
    discard

proc parseTokens*(source: string): seq[GeneralTokenizer] =
  let node = parsePNodeStr(source)
  var outNodes = newSeq[PNode]()
  flatNode(node, outNodes)

  for n in outNodes:
    case n.kind
    of nkObjConstr:
      result.add initNimToken(TokenClass.gtTypeName, n[0].info.offsetA, n[0].ident.s)
    of nkEmpty, nkPar, nkBracket, nkAsgn, nkConstSection:
      continue
    of nkYieldStmt:
      result.add initNimKeyword(n, "yield")
    of nkVarTy:
      result.add initNimKeyword(n, "var")
    of nkPragma:
      result.add initNimKeyword(n[0], $n[0].basename())
    of nkProcDef:
      result.add initNimKeyword(n, "proc")
      result.add initNimToken(TokenClass.gtFunctionName, n[0].info.offsetA, $ n[0].basename())
    of nkIncludeStmt:
      result.add initNimKeyword(n, "include")
    of nkFromStmt:
      result.add initNimKeyword(n[0].info.offsetA, "from")
    of nkImportExceptStmt:
      result.add initNimKeyword(n, "import")
      let inStart = n[0].info.offsetB
      result.add initNimKeyword(inStart, "except")
    of nkExportStmt:
      result.add initNimKeyword(n, "export")
    of nkExportExceptStmt:
      result.add initNimKeyword(n, "export")
    of nkConstDef:
      result.add initNimKeyword(n, "const")
    of nkMacroDef:
      result.add initNimKeyword(n, "macro")
    of nkVarSection:
      result.add initNimKeyword(n, "var")
    of nkLetSection:
      result.add initNimKeyword(n, "let")
    of nkIteratorDef:
      result.add initNimKeyword(n, "iterator")
    of nkIfStmt:
      result.add initNimKeyword(n, "if")
    of nkReturnStmt:
      result.add initNimKeyword(n, "return")
    of nkBlockStmt:
      result.add initNimKeyword(n, "block")
    of nkExceptBranch:
      result.add initNimKeyword(n, "except")
    of nkWhileStmt:
      result.add initNimKeyword(n, "while")
    of nkTryStmt:
      result.add initNimKeyword(n, "try")
    of nkForStmt:
      let inStart = n[^2].info.offsetA - 3
      result.add initNimKeyword(n, "for")
      result.add initNimKeyword(inStart, "in")
    of nkCaseStmt:
      result.add initNimKeyword(n, "case")
    of nkContinueStmt:
      result.add initNimKeyword(n, "continue")
    of nkAsmStmt:
      result.add initNimKeyword(n, "asm")
    of nkDiscardStmt:
      result.add initNimKeyword(n, "discard")
    of nkBreakStmt:
      result.add initNimKeyword(n, "break")
    of nkElifBranch:
      result.add initNimKeyword(n, "elif")
    of nkElse:
      result.add initNimKeyword(n, "else")
    of nkOfBranch:
      result.add initNimKeyword(n, "of")
    of nkCast:
      result.add initNimKeyword(n, "cast")
    of nkMixinStmt:
      result.add initNimKeyword(n, "mixin")
    of nkTemplateDef:
      result.add initNimKeyword(n, "template")
    of nkImportStmt:
      result.add initNimKeyword(n, "import")
    of nkNilLit:
      result.add initNimKeyword(n, "nil")
    of nkCharLit:
      let val = $n.intVal.char
      result.add initNimToken(TokenClass.gtOctNumber, n.info.offsetA, val)
    of nkIntLit .. nkUInt64Lit:
      # intVal
      let val = $n.getInt
      result.add initNimToken(TokenClass.gtOctNumber, n.info.offsetA, val)
    of nkFloatLit..nkFloat128Lit:
      # floatVal*: BiggestFloat
      result.add initNimToken(TokenClass.gtDecNumber, n.info.offsetA, $n.floatVal)
    of nkStrLit .. nkTripleStrLit:
      # strVal*: string
      result.add initNimToken(TokenClass.gtStringLit, n.info.offsetA, n.strVal)
    of nkTypeSection:
      discard
    of nkGenericParams:
      discard
    of nkDotExpr:
      discard
    of nkTypeClassTy:
      discard
    of nkBracketExpr:
      discard
    of nkFormalParams:
      discard
    of nkProcTy:
      result.add initNimKeyword(n, "proc")
    of nkTypeDef:
      result.add initNimKeyword(n, "type")
    of nkObjectTy:
      result.add initNimKeyword(n, "object")
    of nkStmtList:
      discard
    of nkRecList:
      discard
    of nkIdentDefs:
      discard
    of nkExprColonExpr:
      discard
    of nkTableConstr:
      discard
    of nkIdentKinds - {nkAccQuoted}:
      # ident*: PIdent
      result.add initNimToken(nimGetKeyword(n.ident.s), n.info.offsetA, n.ident.s)
    of nkAccQuoted:
      discard
    of nkCallKinds - {nkInfix, nkPostfix, nkDotExpr}:
      let id = $n[0]
      let tok = initNimToken(TokenClass.gtFunctionName, n[0].info.offsetA, id)
      if tok.buf.len > 0:
        result.add tok
    of nkInfix:
      if $n[0] == "as":
        result.add initNimKeyword(n[0].info.offsetA, "as")
      else:
        result.add initNimToken(TokenClass.gtOperator, n[0].info.offsetA, $n)
    of nkPostfix:
      result.add initNimToken(TokenClass.gtSpecialVar, n[0].info.offsetA, $n)
    else:
      result.add initNimToken(TokenClass.gtIdentifier, n.info.offsetA, $n)

