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
  description = compiling $in (.olean)

rule leanc
  command = LEAN_PATH=$outpath lean $in -c $out
  description = compiling $in (.c)

rule cobj
  command = leanc -c $in -o $out
  description = compiling $in (.o)

rule cexe
  command = leanc $in -o $out
  description = linking $out

rule ar
  command = ar rcs $out $in
  description = linking $out
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
  buildExe : Bool := true
  buildStaticLib : Bool := false

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

partial def build (ctx : Context) : IO UInt32 := do
  let modules := NameSet.empty
  let rec buildDeps (directImports : List Name) (foundModules : NameSet) (emittedModules : NameSet): IO NameSet := 
    match directImports with
    | [] => return foundModules
    | List.cons di dis => do
        if not $ emittedModules.contains di then
          let emittedModules := emittedModules.insert di
          let (additionalImports, foundModules) ← buildDep ctx di foundModules
          buildDeps (dis ++ additionalImports) foundModules emittedModules
        else 
          buildDeps dis foundModules emittedModules

  let modules := modules.insert ctx.pkg
  let pkgFile := Lean.modToFilePath "." ctx.pkg "lean"

  let contents ← IO.FS.readFile pkgFile
  let (imports, _, _) ← Lean.Elab.parseImports contents (toString ctx.pkg)
  let imports := imports.map (·.module)
  let directImports := imports |>.filter (·.getRoot == ctx.pkg)

  IO.println ruleLean
  let foundModules ← buildDeps directImports modules modules

  let filePaths : List String := directImports.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "olean")

  let oleanFile := Lean.modToFilePath "out" ctx.pkg "olean"
  let cFile := Lean.modToFilePath "out" ctx.pkg "c"
  let cObjFile := System.FilePath.toString $ Lean.modToFilePath "out" ctx.pkg "o"

  if ctx.emitOLean then IO.println $ buildo oleanFile pkgFile filePaths
  if ctx.emitC then IO.println $ buildc cFile pkgFile filePaths
  if ctx.buildC then IO.println $ buildcobj cObjFile cFile

  let objs := foundModules.toList.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "o")
  if ctx.buildExe then
    let exe := Lean.modToFilePath "out" ctx.pkg "exe"
    IO.println $ buildcexe exe objs

  if ctx.buildStaticLib then
    let lib := Lean.modToFilePath "out" s!"lib{ctx.pkg.toString}" "a"
    IO.println $ buildar lib objs

  return 0  

def help := "bl : Build Lean Package

Usage: 
  bl gen <Pkg> -- generate ninja rules to build .c and .olean files
  bl gen-lib <Pkg> -- generate ninja rules to build a static library
  bl gen-exe <Pkg> -- generate ninja rules to build an executable
"

def main (args : List String) : IO UInt32 := do
  if not $ args.length == 2 then
    IO.print help
    return 0
  let pkg :=  args.toArray[1].toName
  match args.toArray[0] with
  | "gen" => build { pkg := pkg, buildC := false, buildExe := false : Context }
  | "gen-lib" => build { pkg := pkg, buildC := true, buildExe := false, buildStaticLib := true : Context }
  | "gen-exe" =>  build { pkg := pkg : Context }
  | other => do 
    IO.print help
    return 0

