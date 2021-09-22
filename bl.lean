import Lean.Elab.Import
import Lean.Util.Path
import Lean.Data.Name

open Lean

def String.joinWith (sep : String) (l : List String) : String :=
  l.foldl (fun r s => r ++ sep ++ s) ""

def ruleLean := s!"
outpath = out

rule leano
  command = LEAN_PATH=$outpath lean $in -o $out

rule leanc
  command = LEAN_PATH=$outpath lean $in -c $out

rule cobj
  command = leanc -c $in -o $out

rule cexe
  command = leanc $in -o $out

rule ar
  command = ar rcs $out $in
"

def buildo (out : System.FilePath) (input : System.FilePath) (deps : List String) := s!"build {toString out}: leano {toString input} | {" ".joinWith deps}"
def buildc (out : System.FilePath) (input : System.FilePath) (deps : List String) := s!"build {toString out}: leanc {toString input} | {" ".joinWith deps}"
def buildcobj (out : System.FilePath) (input : System.FilePath) := s!"build {toString out}: cobj {toString input}"
def buildcexe (out : System.FilePath) (objs : List String) := s!"build {toString out}: cexe {" ".joinWith objs}"
def buildar (out : System.FilePath) (objs : List String) := s!"build {toString out}: ar {" ".joinWith objs}"


partial def insertAll (self : NameSet) (names : List Name) :=
  let rec insertRemaining (names : List Name) (acc : NameSet) := match names with
  | [] => acc
  | List.cons n ns => insertRemaining ns (NameSet.insert acc n)  
  insertRemaining names self

structure Context where
  pkg : Name
  emitC : Bool := true
  emitOLean : Bool := true
  buildC : Bool := true

def buildDep (ctx : Context) (name : Name) (foundModules : NameSet) : IO (List Name × NameSet) := do
  let leanFile := System.FilePath.toString $ Lean.modToFilePath "." name "lean"
  let contents ← IO.FS.readFile leanFile
  let (imports, _, _) ← Lean.Elab.parseImports contents leanFile
  let imports := imports.map (·.module)
  let directImports := imports |>.filter (·.getRoot == ctx.pkg)
  let filePaths : List String := directImports.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "olean")
  let oleanFile := System.FilePath.toString $ Lean.modToFilePath "out" name "olean"
  let cFile := System.FilePath.toString $ Lean.modToFilePath "out" name "c"
  let cObjFile := System.FilePath.toString $ Lean.modToFilePath "out" name "o"

  if ctx.emitOLean then IO.println $ buildo oleanFile leanFile filePaths
  if ctx.emitC then IO.println $ buildc cFile leanFile filePaths
  if ctx.buildC then IO.println $ buildcobj cObjFile cFile
  return (directImports |>.filter (fun m => not $ foundModules.contains m), insertAll (NameSet.insert foundModules name) directImports)

partial def build (ctx : Context) : IO Unit := do
  let modules := NameSet.empty
  let rec buildDeps (directImports : List Name) (foundModules : NameSet): IO NameSet := 
    match directImports with
    | [] => return foundModules
    | List.cons di dis => do
        let (additionalImports, foundModules) ← buildDep ctx di foundModules
        buildDeps (dis ++ additionalImports) foundModules

  let modules := modules.insert ctx.pkg
  let pkgFile := Lean.modToFilePath "." ctx.pkg "lean"

  let contents ← IO.FS.readFile pkgFile
  let (imports, _, _) ← Lean.Elab.parseImports contents (toString ctx.pkg)
  let imports := imports.map (·.module)
  let directImports := imports |>.filter (·.getRoot == ctx.pkg)

  IO.println ruleLean
  let foundModules ← buildDeps directImports modules

  let filePaths : List String := directImports.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "olean")

  let oleanFile := Lean.modToFilePath "out" ctx.pkg "olean"
  let cFile := Lean.modToFilePath "out" ctx.pkg "c"
  let cObjFile := System.FilePath.toString $ Lean.modToFilePath "out" ctx.pkg "o"

  if ctx.emitOLean then IO.println $ buildo oleanFile pkgFile filePaths
  if ctx.emitC then IO.println $ buildc cFile pkgFile filePaths
  if ctx.buildC then IO.println $ buildcobj cObjFile cFile

  let objs := foundModules.toList.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "o")
  let exe := Lean.modToFilePath "out" ctx.pkg "exe"

  IO.println $ buildcexe exe objs

def help := "bl : Build Lean Package

Usage: 
  bl <Pkg>
"

def main (args : List String) : IO UInt32 := do
  if args.length == 0 || args.length > 1 then
    IO.print help
    return 0
  else 
    let pkg :=  args.toArray[0].toName
    build { pkg := pkg : Context }
    return 0

