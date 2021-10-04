# bn - build lean

This is a minimal build generator for Lean4. It generates a ```build.ninja``` file to either compile a Lean package to olean and c outputs, to a static library or into an executable. It does not do any dependency management, so it will fail if the package depends on other packages not in either the LEAN_PATH or that have been previously compiled and can be found in the ```out/``` directory.

## compile

```
./build.sh
```
this will produce an executable ```bn```, you can copy it somewhere in your path. 

## building a library or executable including dependencies

It is possible to use bl to compile an executable and its dependencies by invoking
```
bn build exe <PkgName>
```
similarly one can build a library and its dependencies by invoking
```
bn build lib <PkgName>
```
it is currently assumed that all root module files can be found in the root
directory.

## generate ninja file for an executable

```
bn gen exe <Pkg>
```
for example to generated the Lake executable
```
git clone https://github.com/leanprover/lake
cd lake
bn gen exe Lake
ninja
./out/Lake
```

## generate ninja file for a static library

```
bn gen lib <Pkg>
ninja # results in out/libPkg.a (together with all the necessary .olean files)
```
One can then generate additional build files that will correctly link to the library just created
(at the moment it is assumed that all libraries can be either found in out/ or in the LEAN_PATH).
```
bn gen exe <Pkg>
ninja
```

## generate ninja file to generate .c and .olean files

```
bn gen <Pkg>
ninja
```
