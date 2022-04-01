# bn - build lean

This is a minimal build generator for Lean4. It generates a ```build.ninja``` file to either compile a Lean package to olean and c outputs, to a static library or into an executable. It does not do any dependency management, so it will fail if the package depends on other packages not in either the LEAN_PATH or that have been previously compiled and can be found in the ```out/``` directory.

## compile

```
./build.sh
```
this will produce an executable ```bn```, you can copy it somewhere in your path. 

## building a library or executable including dependencies

It is possible to use ```bn``` to compile an executable and its dependencies by invoking
```
bn build exe <PkgName>
```
for example to build the Lake executable
```
git clone https://github.com/leanprover/lake
cd lake
bn build exe Lake/Main
```
Note that this will correctly build the ```Lake``` library as a dependency and link to it.

Similarly one can build a library and its dependencies by invoking
```
bn build lib <PkgName>
```
to continue the example above we could invoke
```
bn build lib Lake
```

## generate ninja file for an executable

```
bn gen exe <Pkg>
```
for example to generated the Lake executable
```
git clone https://github.com/leanprover/lake
cd lake
bn gen exe Lake/Main
ninja
./out/exe/«lake/main»
```
as you can see from this example, the generated executable name is not necessarily ideal. 

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

## performance

Since most of the work is done by ```ninja```, ```bn``` is pretty fast. For example on mathlib4 

```
git clone git@github.com:leanprover-community/mathlib4.git
cd mathlib4/
time bn build olean Mathlib
```
results in
```
150.85s user 22.96s system 416% cpu 41.744 total
```
on my laptop. Whereas
```
time lake build
```
results in
```
151.47s user 23.65s system 409% cpu 42.780 total
```