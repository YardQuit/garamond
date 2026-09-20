EMACS ?= emacs
BATCH  = $(EMACS) -Q --batch -L .

.PHONY: all compile test lint clean

all: compile test

compile:
	@rm -f garamond.elc
	@$(BATCH) --eval '(setq byte-compile-error-on-warn t)' \
		-f batch-byte-compile garamond.el

test: compile
	@$(BATCH) -l test/garamond-test.el -f ert-run-tests-batch-and-exit

lint:
	@$(BATCH) --eval '(progn (require (quote checkdoc)) (checkdoc-file "garamond.el") (let ((w (get-buffer "*Warnings*"))) (when (and w (> (buffer-size w) 0)) (kill-emacs 1))))'

clean:
	@rm -f garamond.elc test/*.elc
