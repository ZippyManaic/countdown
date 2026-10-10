OCAMLFIND = ocamlfind
OCAMLFLAGS ?= -unsafe -inline 200

countdown: solver.ml round.ml countdown.ml
	$(OCAMLFIND) ocamlopt $(OCAMLFLAGS) -package bigarray -linkpkg solver.ml round.ml countdown.ml -o countdown

test: solver.ml round.ml tests.ml
	$(OCAMLFIND) ocamlopt $(OCAMLFLAGS) -package bigarray -linkpkg solver.ml round.ml tests.ml -o tests
	./tests

clean:
	rm -f countdown tests *.cm[iox] *.o

.PHONY: test clean
