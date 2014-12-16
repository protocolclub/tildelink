#!/usr/bin/env ocaml
#directory "pkg"
#use "topkg.ml"

let () =
  Pkg.describe "tildelink" ~builder:`OCamlbuild [
    Pkg.bin ~auto:true "src/tildelink" ~dst:"tildelink";
    Pkg.doc "README.md";
    Pkg.doc "LICENSE.txt";
    Pkg.doc "CHANGELOG.md"; ]
