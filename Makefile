OCAMLBUILD := ocamlbuild -classic-display -use-ocamlfind -j 0

build:
	$(OCAMLBUILD) src/tildelib.cma src/tildelink.d.byte src/tildelink.native

doc:
	ocamlbuild -use-ocamlfind doc/api.docdir/index.html \
	           -docflags -t -docflag "API reference for tildelink" \
	           -docflags '-colorize-code -short-functors -charset utf-8' \
	           -docflags '-css-style style.css'
	cp doc/style.css api.docdir/

test: build
	$(OCAMLBUILD) src_test/test_tildelink.byte --

clean:
	$(OCAMLBUILD) -clean

top: build
	utop -require 'base64 uri containers lwt.ppx lwt.unix ZMQ lwt-zmq sodium' \
	     -require 'ppx_deriving_yojson cmdliner' \
	     -I _build/src _build/src/tildelib.cma

gh-pages: doc
	git clone `git config --get remote.origin.url` .gh-pages --reference .
	git -C .gh-pages checkout --orphan gh-pages
	git -C .gh-pages reset
	git -C .gh-pages clean -dxf
	cp -t .gh-pages/ api.docdir/*
	git -C .gh-pages add .
	git -C .gh-pages commit -m "Update Pages"
	git -C .gh-pages push origin gh-pages -f
	rm -rf .gh-pages

.PHONY: build doc test clean top gh-pages
