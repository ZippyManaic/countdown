SBCL = sbcl --noinform --non-interactive

countdown: solver.lisp countdown.lisp
	$(SBCL) --load solver.lisp --load countdown.lisp \
		--eval '(sb-ext:save-lisp-and-die "countdown" :executable t :toplevel (function countdown:main))'

test: solver.lisp countdown.lisp tests.lisp
	$(SBCL) --load solver.lisp --load countdown.lisp --load tests.lisp

clean:
	rm -f countdown

.PHONY: test clean
