# bl - build a lean package

This is a minimal build generator for Lean4. It generates a ```build.ninja``` file to either compile a Lean package to olean and c outputs, to a static library or into an executable. It does not do any dependency management, so it will fail if the package depends on other packages not in the LEAN_PATH. 

This is just an experiment, so please don't expect it to be super useful or bugfree :). 


## compile

```
./build.sh
```
this will produce an executable ```bl```, you can copy it somewhere in your path. 

## generate ninja file for an executable

```
bl gen-exe <Pkg> > build.ninja
```
for example to generated the Lake executable
```
git clone https://github.com/leanprover/lake
cd lake
bl gen-exe Lake > build.ninja
ninja
./out/Lake.exe
```

## generate ninja file for a static library

```
bl gen-lib <Pkg> > build.ninja
ninja # results in out/libPkg.a (together with all the necessary .olean files)
```
for example to generate the Mathport library
```
git clone https://github.com/leanprover/mathport.git
cd mathport
bl gen-lib Mathport > build.ninja
ninja # results in out/libMathport.a and .olean files in out/
```
one can then generate additional build files that will correctly link to the library just created:
```
bl gen-exe MathportApp > build-app.ninja
ninja -f build-app.ninja # results in out/MathportApp.exe
```

## generate ninja file to generate .c and .olean files

```
bl gen <Pkg> > build.ninja
ninja
```
