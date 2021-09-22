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

def buildDep (pkg : Name) (name : Name) (foundModules : NameSet) : IO (List Name × NameSet) := do
  let leanFile := System.FilePath.toString $ Lean.modToFilePath "." name "lean"
  let contents ← IO.FS.readFile leanFile
  let (imports, _, _) ← Lean.Elab.parseImports contents leanFile
  let imports := imports.map (·.module)
  let directImports := imports |>.filter (·.getRoot == pkg)
  let filePaths : List String := directImports.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "olean")
  let oleanFile := System.FilePath.toString $ Lean.modToFilePath "out" name "olean"
  let cFile := System.FilePath.toString $ Lean.modToFilePath "out" name "c"
  let cObjFile := System.FilePath.toString $ Lean.modToFilePath "out" name "o"

  IO.println $ buildo oleanFile leanFile filePaths
  IO.println $ buildc cFile leanFile filePaths
  IO.println $ buildcobj cObjFile cFile
  return (directImports |>.filter (fun m => not $ foundModules.contains m), insertAll (NameSet.insert foundModules name) directImports)

partial def build (pkg : Name) : IO Unit := do
  let modules := NameSet.empty
  let rec buildDeps (directImports : List Name) (foundModules : NameSet): IO NameSet := 
    match directImports with
    | [] => return foundModules
    | List.cons di dis => do
        let (additionalImports, foundModules) ← buildDep pkg di foundModules
        buildDeps (dis ++ additionalImports) foundModules

  let modules := modules.insert pkg
  let pkgFile := Lean.modToFilePath "." pkg "lean"

  let contents ← IO.FS.readFile pkgFile
  let (imports, _, _) ← Lean.Elab.parseImports contents (toString pkg)
  let imports := imports.map (·.module)
  let directImports := imports |>.filter (·.getRoot == pkg)

  IO.println ruleLean
  let foundModules ← buildDeps directImports modules

  let filePaths : List String := directImports.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "olean")

  let oleanFile := Lean.modToFilePath "out" pkg "olean"
  let cFile := Lean.modToFilePath "out" pkg "c"
  let cObjFile := System.FilePath.toString $ Lean.modToFilePath "out" pkg "o"

  IO.println $ buildo oleanFile pkgFile filePaths
  IO.println $ buildc cFile pkgFile filePaths
  IO.println $ buildcobj cObjFile cFile

  let objs := foundModules.toList.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "o")
  let exe := Lean.modToFilePath "out" pkg "exe"

  IO.println $ buildcexe exe objs

def help := "bl : Build Lean

Usage: 
  bl <Target>
"

def main (args : List String) : IO UInt32 := do
  if args.length == 0 || args.length > 1 then
    IO.print help
    return 0
  else 
    let pkg :=  args.toArray[0].toName
    build pkg
    return 0

