import Lean
import Lean.Elab.Import
import Lean.Util.Path
import Lean.Data.Name
import Init.System

/-!
bn : build lean

Usage:
  bn gen    (c | lib | exe | olean) <Pkg> -- generate ninja rules
  bn build  (c | lib | exe | olean) <Pkg> -- build the corresponding target
  bn clean                                -- remove the build artifacts

where
  c   : c files
  lib : a static library
  exe : an executable
  olean : olean files
-/

open Lean

def String.joinWith (sep : String) (l : List String) : String :=
  l.foldl (fun r s => r ++ sep ++ s) ""

def ruleLean := s!"
outpath = out
libraries =

rule leano
  command = LEAN_PATH=$outpath lean $in -o $out
  description = compiling $in (.olean)

rule leanc
  command = LEAN_PATH=$outpath lean $in -c $out
  description = compiling $in (.c)

rule cobj
  command = leanc -c $in -o $out -L out $libraries
  description = compiling $in (.o)

rule cexe
  command = leanc $in -L out $libraries -o $out
  description = linking $out

rule ar
  command = ar rcs $out $in
  description = linking $out

rule clone_dep:
  command = [ ! -d $out ] && git clone $url $depdir || true
  description = cloning $dep from $url
"

def buildo (out : System.FilePath) (input : System.FilePath) (deps : List String) := s!"build {toString out}: leano {toString input} | {" ".joinWith deps}"
def buildc (out : System.FilePath) (input : System.FilePath) (deps : List String) := s!"build {toString out}: leanc {toString input} | {" ".joinWith deps}"
def buildcobj (out : System.FilePath) (input : System.FilePath) := s!"build {toString out}: cobj {toString input}"
def buildcexe (out : System.FilePath) (objs : List String) (libraries : List Name):= s!"build {toString out}: cexe {" ".joinWith objs} | {" ".joinWith (List.map (fun l =>  (Lean.modToFilePath "out" l "a").toString) libraries)}
  libraries = {" ".joinWith (List.map (fun l => s!"-l{l}") libraries)}
"
def buildar (out : System.FilePath) (objs : List String) (libraries : List Name) :=
  let libnames := List.map (fun l =>  (Lean.modToFilePath "out" ("lib" ++ l.toString).toName "a").toString) libraries
  s!"build {toString out}: ar {" ".joinWith objs} | {" ".joinWith libnames}
  libraries = {" ".joinWith (List.map (fun l => s!"-l{l}") libraries)}"

partial def insertAll (self : NameSet) (names : List Name) :=
  let rec insertRemaining (names : List Name) (acc : NameSet) := match names with
  | [] => acc
  | List.cons n ns => insertRemaining ns (NameSet.insert acc n)
  insertRemaining names self

structure Context where
  pkg : Name
  externalDependencies : List Name := []
  emitC : Bool := true
  emitOLean : Bool := true
  buildC : Bool := true
  buildExe : Bool := true
  buildStaticLib : Bool := false
  trackExternalDeps : Bool := false
  outDir : System.FilePath := "out"
  deriving Repr, BEq

def getImports (name : Name) : IO (Array Name) := do
  let leanFile := System.FilePath.toString $ Lean.modToFilePath "." name "lean"
  try
    let contents ← IO.FS.readFile leanFile
    let (imports, _, _) ← Lean.Elab.parseImports contents leanFile
    return imports.map (·.module)
  catch _ =>
    IO.println s!"Error: File not found: {leanFile}"
    return #[]

def buildDep (ctx : Context) (name : Name) (foundModules : NameSet) (h : IO.FS.Handle) : IO (List Name × NameSet) := do
  let leanFile := System.FilePath.toString $ Lean.modToFilePath "." name "lean"
  let imports ← getImports name
  let directImports := imports |>.filter (·.getRoot == ctx.pkg) |> Array.toList
  let filePaths : List String := directImports.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "olean")
  let oleanFile := Lean.modToFilePath "out" name "olean" |>.toString
  let cFile := Lean.modToFilePath "out/c" name "c" |>.toString
  let cObjFile := Lean.modToFilePath "out/o" name "o" |>.toString
  if ctx.emitOLean then h.putStrLn $ buildo oleanFile leanFile filePaths
  if ctx.emitC then h.putStrLn $ buildc cFile leanFile filePaths
  if ctx.buildC then h.putStrLn $ buildcobj cObjFile cFile
  return (directImports |>.filter (fun m => not $ foundModules.contains m), insertAll (NameSet.insert foundModules name) directImports)


def scanDep (ctx : Context) (name : Name) (foundModules : NameSet) (dependencies : NameSet) : IO (List Name × NameSet × NameSet) := do
  let imports ← getImports name
  let directImports := imports |>.filter (·.getRoot == ctx.pkg) |> Array.toList
  let dependencies := insertAll dependencies (imports |>.filter (·.getRoot != ctx.pkg) |>.map (·.getRoot) |>.toList)
  return (directImports |>.filter (fun m => not $ foundModules.contains m), insertAll (NameSet.insert foundModules name) directImports, dependencies)

partial def scan (ctx : Context) : IO NameSet := do
  let dependencies := NameSet.empty
  let modules := NameSet.empty

  let rec scanDeps (directImports : List Name) (foundModules : NameSet) (dependencies : NameSet): IO NameSet :=
    match directImports with
    | [] => return dependencies
    | List.cons di dis => do
          let (additionalImports, foundModules, dependencies) ← scanDep ctx di foundModules dependencies
          scanDeps (dis ++ additionalImports) foundModules dependencies

  let pkgFile := Lean.modToFilePath "." ctx.pkg "lean"
  let contents ← IO.FS.readFile pkgFile
  let (imports, _, _) ← Lean.Elab.parseImports contents (toString ctx.pkg)
  let imports := imports.map (·.module)
  let dependencies := insertAll dependencies (imports |>.filter (·.getRoot != ctx.pkg) |>.map (·.getRoot) |> Array.toList)
  let directImports := imports |>.filter (·.getRoot == ctx.pkg) |> Array.toList

  let modules := modules.insert ctx.pkg
  return (← scanDeps directImports modules dependencies)

partial def build (ctx : Context) (h : IO.FS.Handle) : IO UInt32 := do
  let modules := NameSet.empty
  let rec buildDeps (directImports : List Name) (foundModules : NameSet) (emittedModules : NameSet): IO NameSet :=
    match directImports with
    | [] => return foundModules
    | List.cons di dis => do
        if not $ emittedModules.contains di then
          let emittedModules := emittedModules.insert di
          let (additionalImports, foundModules) ← buildDep ctx di foundModules h
          buildDeps (dis ++ additionalImports) foundModules emittedModules
        else
          buildDeps dis foundModules emittedModules

  let modules := modules.insert ctx.pkg
  let pkgFile := Lean.modToFilePath "." ctx.pkg "lean"

  let contents ← IO.FS.readFile pkgFile
  let (imports, _, _) ← Lean.Elab.parseImports contents (toString ctx.pkg)
  let imports := imports.map (·.module)
  let directImports := imports |>.filter (·.getRoot == ctx.pkg) |> Array.toList
  let foundModules ← buildDeps directImports modules modules

  let filePaths : List String := directImports.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out" n "olean")

  let oleanFile := Lean.modToFilePath "out" ctx.pkg "olean"
  let cFile := Lean.modToFilePath "out/c" ctx.pkg "c"
  let cObjFile := Lean.modToFilePath "out/o" ctx.pkg "o" |>.toString

  if ctx.emitOLean then h.putStrLn $ buildo oleanFile pkgFile (filePaths ++ if ctx.trackExternalDeps then (ctx.externalDependencies.map $ fun n => Lean.modToFilePath "out" n "olean" |> toString) else [])
  if ctx.emitC then h.putStrLn $ buildc cFile pkgFile (filePaths ++ if ctx.trackExternalDeps then  (ctx.externalDependencies.map $ fun n => Lean.modToFilePath "out" n "olean" |> toString) else [])
  if ctx.buildC then h.putStrLn $ buildcobj cObjFile cFile

  let objs := foundModules.toList.map (fun n => System.FilePath.toString $ Lean.modToFilePath "out/o" n "o")
  if ctx.buildExe then
    let exe := Lean.modToFilePath "out/exe" ctx.pkg ""
    h.putStrLn $ buildcexe exe objs ctx.externalDependencies

  if ctx.buildStaticLib then
    let lib := Lean.modToFilePath "out" ("lib" ++ ctx.pkg.toString).toName "a"
    h.putStrLn $ buildar lib objs ctx.externalDependencies

  return 0

def builtinLibraries : NameSet := insertAll NameSet.empty [`Init, `Std, `Lean]

partial def buildDependencies (ctx : Context) (h : IO.FS.Handle) : IO NameSet :=
  let rec buildDeps (dependencies : List Name) (alreadyBuild : NameSet) : IO NameSet :=
    match dependencies with
    | [] => return alreadyBuild
    | List.cons dep deps => do
        let immediateDependencies := (← scan { pkg := dep : Context }).toList
        |> List.filter (fun x => not $ builtinLibraries.contains x.getRoot )
        let additionalDependencies := immediateDependencies |> List.filter (fun x => not $ alreadyBuild.contains x.getRoot )
        let _ ← build { ctx with pkg := dep, buildC := true, buildExe := false, buildStaticLib := true, externalDependencies := immediateDependencies : Context} h
        let alreadyBuild := alreadyBuild.insert dep
        buildDeps (additionalDependencies ++ deps) alreadyBuild
  buildDeps ctx.externalDependencies (NameSet.empty.insert ctx.pkg)


def help := "bn : build lean

Usage:
  bn gen    (c | lib | exe) <Pkg> -- generate ninja rules
  bn build  (c | lib | exe) <Pkg> -- build the corresponding target
  bn clean                        -- remove the build artifacts

where
  c   : c files
  lib : a static library
  exe : an executable
"

def main (args : List String) : IO UInt32 := do
  if args.length < 1 then
    IO.print help
    return 0

  if args.toArray[0]! == "clean" then
    let child ← IO.Process.spawn {cmd := "ninja", args := #["-t", "clean"]}
    let _ ← child.wait
    let child ← IO.Process.spawn {cmd := "rm", args := #["build.ninja"]}
    let _ ← child.wait
    return 0

  if args.length != 3 then
    IO.print help
    return 0

  let pkg :=  args.toArray[2]!.toName
  let externalDependencies := (← scan { pkg := pkg : Context }).toList |> List.filter (fun x => not $ builtinLibraries.contains x.getRoot )

  match args.toArray[0]!, args.toArray[1]! with
  | "gen", "c" => IO.FS.withFile "build.ninja" IO.FS.Mode.write $ fun h => do
      h.putStrLn ruleLean
      build { pkg := pkg, buildC := false, buildExe := false : Context } h
  | "gen", "lib" => IO.FS.withFile "build.ninja" IO.FS.Mode.write $ fun h => do
      h.putStrLn ruleLean
      build { pkg := pkg, buildC := true, buildExe := false, buildStaticLib := true, externalDependencies := externalDependencies : Context } h
  | "gen", "exe" => IO.FS.withFile "build.ninja" IO.FS.Mode.write $ fun h => do
      h.putStrLn ruleLean
      build { pkg := pkg, externalDependencies := externalDependencies : Context } h
  | "build", "c" => do
    let _ ← IO.FS.withFile "build.ninja" IO.FS.Mode.write $ fun h => do
      h.putStrLn ruleLean
      build { pkg := pkg, buildC := false, buildExe := false : Context } h
    let child ← IO.Process.spawn {cmd := "ninja", args := #[]}
    child.wait
  | "build", "exe" => do
    let _ ← IO.FS.withFile "build.ninja" IO.FS.Mode.write $ fun h => do
      h.putStrLn ruleLean
      let ctx := { pkg := pkg, buildC := true, buildExe := true, buildStaticLib := false, externalDependencies := externalDependencies, trackExternalDeps := true : Context }
      let _ ← buildDependencies ctx h
      build ctx h
    let child ← IO.Process.spawn {cmd := "ninja", args := #[]}
    child.wait
  | "build", "lib" => do
    let _ ← IO.FS.withFile "build.ninja" IO.FS.Mode.write $ fun h => do
      h.putStrLn ruleLean
      let ctx := { pkg := pkg, buildC := true, buildExe := false, buildStaticLib := true, externalDependencies := externalDependencies, trackExternalDeps := true : Context }
      let _ ← buildDependencies ctx h
      build ctx h
    let child ← IO.Process.spawn {cmd := "ninja", args := #[]}
    child.wait
  | _, _ => do
    IO.print help
    return 0
