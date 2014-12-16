OCAMLBUILD := ocamlbuild -classic-display -use-ocamlfind -j 0

build:
	$(OCAMLBUILD) src/tildelink.native

test: build
	$(OCAMLBUILD) src_test/test_tildelink.byte --

clean:
	$(OCAMLBUILD) -clean

.PHONY: build test clean
