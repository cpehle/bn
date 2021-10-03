# bl - build a lean package

This is a minimal build generator for Lean4. It generates a ```build.ninja``` file to either compile a Lean package to olean and c outputs, to a static library or into an executable. It does not do any dependency management, so it will fail if the package depends on other packages not in either the LEAN_PATH or that have been previously compiled and can be found in the ```out/``` directory.

## compile

```
./build.sh
```
this will produce an executable ```bl```, you can copy it somewhere in your path. 

## building a library or executable including dependencies

It is possible to use bl to compile an executable and its dependencies by invoking
```
bl build exe <PkgName>
```
for example
```
git clone https://github.com/leanprover/mathport.git
cd mathport
bl build exe MathportApp
```
similarly one can build a library and its dependencies by invoking
```
bl build lib <PkgName>
```
for example
```
bl build lib Mathport
```

## generate ninja file for an executable

```
bl gen exe <Pkg>
```
for example to generated the Lake executable
```
git clone https://github.com/leanprover/lake
cd lake
bl gen exe Lake
ninja
./out/Lake
```

## generate ninja file for a static library

```
bl gen lib <Pkg>
ninja # results in out/libPkg.a (together with all the necessary .olean files)
```
for example to generate the Mathport library
```
git clone https://github.com/leanprover/mathport.git
cd mathport
bl gen lib Mathport
ninja # results in out/libMathport.a and .olean files in out/
```
one can then generate additional build files that will correctly link to the library just created
(at the moment it is assumed that all libraries can be either found in out/ or in the LEAN_PATH).
```
bl gen exe MathportApp
ninja # results in out/MathportApp
```

## generate ninja file to generate .c and .olean files

```
bl gen <Pkg>
ninja
```
