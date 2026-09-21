;;; garamond-test.el --- Tests for garamond  -*- lexical-binding: t; -*-

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Run them with `make test', or:
;;
;;   emacs -Q --batch -L . -l test/garamond-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'garamond)
(require 'org)
(require 'dired)

(defun garamond-test--rewrite (text spaces &optional mode)
  "Return TEXT with SPACES spaces between its sentences.
MODE, a major mode, is turned on first; it defaults to `text-mode'."
  (with-temp-buffer
    (funcall (or mode #'text-mode))
    (insert text)
    (garamond-adjust-spacing (point-min) (point-max) spaces)
    (buffer-string)))

(defun garamond-test--type (text &optional mode)
  "Type TEXT into a buffer in MODE with `garamond-mode' on, return the result.
Each character goes through `self-insert-command', so the typing hook
sees them one at a time, as it would from the keyboard."
  (with-temp-buffer
    (funcall (or mode #'text-mode))
    (setq-local sentence-end-double-space t)
    (garamond-mode 1)
    (dolist (char (string-to-list text))
      (let ((last-command-event char))
        (self-insert-command 1 char)))
    (buffer-string)))

;; Assembled rather than written out, so that this test file does not
;; itself end up with a local variables block Emacs would try to apply.
(defconst garamond-test--declaration-format
  (concat "# Local " "Variables:\n"
          "# sentence-end-double-space: %s\n"
          "# End:\n")
  "A file-local declaration, to be formatted with t or nil.")

(defmacro garamond-test--with-file (name contents &rest body)
  "Write CONTENTS to a temporary file, visit it, and run BODY there.
NAME is bound to the file name.  The buffer and the file are cleaned up
afterwards, and BODY runs with the file's own local variables applied."
  (declare (indent 2) (debug (symbolp form body)))
  `(let ((,name (make-temp-file "garamond-test" nil ".txt" ,contents)))
     (unwind-protect
         (save-current-buffer
           (find-file ,name)
           (unwind-protect (progn ,@body)
             (set-buffer-modified-p nil)
             (kill-buffer)))
       (delete-file ,name))))


;;; The rewrite

(ert-deftest garamond-test-single-to-double ()
  (should (equal (garamond-test--rewrite "One. Two. Three." 2)
                 "One.  Two.  Three.")))

(ert-deftest garamond-test-double-to-single ()
  (should (equal (garamond-test--rewrite "One.  Two.  Three." 1)
                 "One. Two. Three.")))

(ert-deftest garamond-test-run-is-made-uniform ()
  "However many spaces were there, the result is exactly SPACES."
  (should (equal (garamond-test--rewrite "One.     Two.  Three. Four." 2)
                 "One.  Two.  Three.  Four.")))

(ert-deftest garamond-test-other-punctuation ()
  (should (equal (garamond-test--rewrite "What? Now! Wait… Really‽ Yes." 2)
                 "What?  Now!  Wait…  Really‽  Yes.")))

(ert-deftest garamond-test-closers ()
  (should (equal (garamond-test--rewrite "He said \"go.\" She left. (Alone.) Yes." 2)
                 "He said \"go.\"  She left.  (Alone.)  Yes.")))

(ert-deftest garamond-test-leaves-line-structure-alone ()
  "Newlines, indentation and trailing whitespace are not touched."
  (let ((text "One.\nTwo.\n\n    Indented. Here.  \n"))
    (should (equal (garamond-test--rewrite text 2)
                   "One.\nTwo.\n\n    Indented.  Here.  \n"))))

(ert-deftest garamond-test-back-to-back-sentences ()
  "Every break is seen, not every other one."
  (should (equal (garamond-test--rewrite "A. B. C. D. E." 2)
                 "A.  B.  C.  D.  E.")))

(ert-deftest garamond-test-rejects-other-counts ()
  (with-temp-buffer
    (insert "One. Two.")
    (should-error (garamond-adjust-spacing (point-min) (point-max) 3)
                  :type 'user-error)
    (should-error (garamond-set-spacing 0) :type 'user-error)))

(ert-deftest garamond-test-region-only ()
  "Text outside BEG..END is left as it was."
  (with-temp-buffer
    (text-mode)
    (insert "One. Two.\n")
    (let ((split (point)))
      (insert "Three. Four.\n")
      (garamond-adjust-spacing split (point-max) 2))
    (should (equal (buffer-string) "One. Two.\nThree.  Four.\n"))))

(ert-deftest garamond-test-enumerator-is-not-a-sentence ()
  "The period of an ordered list item is numbering, not a full stop."
  (should (equal (garamond-test--rewrite "1. First item here." 2)
                 "1. First item here."))
  (should (equal (garamond-test--rewrite "  12. Indented item. Two sentences." 2)
                 "  12. Indented item.  Two sentences.")))

(ert-deftest garamond-test-initials-are-not-enumerators ()
  "A letter and a period opens a sentence far more often than a list."
  (should (equal (garamond-test--rewrite "A. B. C. D." 2)
                 "A.  B.  C.  D."))
  (should (equal (garamond-test--rewrite "I. Then me." 2)
                 "I.  Then me.")))


;;; What must be left verbatim

(ert-deftest garamond-test-org-src-block-untouched ()
  (let ((text (concat "Prose here. And more.\n"
                      "#+begin_src emacs-lisp\n"
                      "(list 1. 2.)\n"
                      "(setq a 1) ; done. next\n"
                      "#+end_src\n"
                      "After. Text.\n")))
    (should (equal (garamond-test--rewrite text 2 #'org-mode)
                   (concat "Prose here.  And more.\n"
                           "#+begin_src emacs-lisp\n"
                           "(list 1. 2.)\n"
                           "(setq a 1) ; done. next\n"
                           "#+end_src\n"
                           "After.  Text.\n")))))

(ert-deftest garamond-test-org-table-untouched ()
  (let ((text "| a. b | c. d |\n\nProse. Here.\n"))
    (should (equal (garamond-test--rewrite text 2 #'org-mode)
                   "| a. b | c. d |\n\nProse.  Here.\n"))))

(ert-deftest garamond-test-org-link-path-untouched ()
  (let ((text "See [[file:a.org::x. y][the note. here]] now. Done.\n"))
    (should (equal (garamond-test--rewrite text 2 #'org-mode)
                   "See [[file:a.org::x. y][the note. here]] now.  Done.\n"))))

(ert-deftest garamond-test-org-inline-code-untouched ()
  (let ((text "Call ~foo(1. 2)~ first. Then stop.\n"))
    (should (equal (garamond-test--rewrite text 2 #'org-mode)
                   "Call ~foo(1. 2)~ first.  Then stop.\n"))))


;;; The block scan

(defun garamond-test--open-block ()
  "Return the block the scan says is open above point, in the current buffer."
  (garamond--block-open-above garamond--org-block-regexp #'garamond--org-block-step))

(ert-deftest garamond-test-scan-sees-a-closed-block-as-closed ()
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\n(f)\n#+end_src\nProse.")
    (should-not (garamond-test--open-block))
    (should-not (garamond--in-verbatim-block-p))))

(ert-deftest garamond-test-scan-sees-an-unclosed-block-as-open ()
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\n(f)\n\n(g)")
    (should (equal "src" (garamond-test--open-block)))
    (should (garamond--in-verbatim-block-p))))

(ert-deftest garamond-test-scan-ignores-case-of-delimiters ()
  (with-temp-buffer
    (org-mode)
    (insert "#+BEGIN_SRC emacs-lisp\n(f)\n#+END_SRC\nProse.")
    (should-not (garamond-test--open-block))))

(ert-deftest garamond-test-scan-quote-blocks-are-prose ()
  "An open quote block is tracked, but is not verbatim."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_quote\nWords. More words.")
    (should (equal "quote" (garamond-test--open-block)))
    (should-not (garamond--in-verbatim-block-p))))

(ert-deftest garamond-test-scan-matches-end-to-begin-by-name ()
  "A delimiter quoted inside an example block is content, not structure."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_example\n#+begin_src sh\necho\n#+end_src\nstill inside")
    (should (equal "example" (garamond-test--open-block)))
    (should (garamond--in-verbatim-block-p))))

(ert-deftest garamond-test-scan-headline-closes-a-block ()
  "No Org block survives a headline; the parser ends the section there."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src sh\necho\n* A heading\nProse again.")
    (should-not (garamond-test--open-block))))

(ert-deftest garamond-test-scan-resumes-rather-than-restarts ()
  "Typing below the scan continues it; it is not redone from the top."
  (with-temp-buffer
    (org-mode)
    (garamond-mode 1)
    (insert "#+begin_src sh\necho\n#+end_src\nOne.\n")
    (garamond-test--open-block)
    (let ((reached (car garamond--block-scan)))
      (should (= reached (line-beginning-position)))
      (insert "Two.\n")
      (garamond-test--open-block)
      (should (> (car garamond--block-scan) reached)))))

(ert-deftest garamond-test-scan-forgets-after-an-edit-above ()
  "An edit above the scan invalidates it; the next answer is right."
  (with-temp-buffer
    (org-mode)
    (garamond-mode 1)
    (insert "Prose.\n\n\nMore prose.")
    (should-not (garamond-test--open-block))
    (should garamond--block-scan)
    ;; Open a block above what has been scanned.
    (save-excursion (goto-char 8) (insert "#+begin_src sh\n"))
    (should-not garamond--block-scan)
    (should (equal "src" (garamond-test--open-block)))))

(ert-deftest garamond-test-scan-keeps-through-an-edit-below ()
  (with-temp-buffer
    (org-mode)
    (garamond-mode 1)
    (insert "Prose.\nMore.")
    (garamond-test--open-block)
    (let ((scan garamond--block-scan))
      (insert " And more.")
      (should (eq scan garamond--block-scan)))))

(ert-deftest garamond-test-scan-is-cleared-when-the-mode-goes-off ()
  "Without the mode there is no invalidation hook, so no cache either."
  (with-temp-buffer
    (org-mode)
    (garamond-mode 1)
    (insert "Prose.")
    (garamond-test--open-block)
    (should garamond--block-scan)
    (garamond-mode -1)
    (should-not garamond--block-scan)
    (should-not (memq #'garamond--block-scan-forget after-change-functions))))

(ert-deftest garamond-test-markdown-fence-rules ()
  "A fence closes only with the same character and at least the same length."
  (cl-flet ((open-after (text)
              (with-temp-buffer
                (insert text)
                (garamond--block-open-above garamond--markdown-fence-regexp
                                            #'garamond--markdown-fence-step))))
    (should (equal '(?` . 3) (open-after "```\ncode\n")))
    (should-not (open-after "```\ncode\n```\nprose"))
    ;; A shorter or different fence inside is content.
    (should (equal '(?` . 4) (open-after "````\n```\nstill code\n")))
    (should (equal '(?` . 3) (open-after "```\n~~~\nstill code\n")))
    ;; A longer one of the same kind closes.
    (should-not (open-after "```\ncode\n`````\nprose"))
    ;; Up to three spaces of indentation are allowed.
    (should (equal '(?~ . 3) (open-after "   ~~~\ncode\n")))
    (should-not (open-after "    ~~~\nnot a fence, an indented code line\n"))))

(ert-deftest garamond-test-typing-inside-a-closed-org-block-is-spared ()
  "The scan answers for closed blocks too, before Org is even asked."
  (with-temp-buffer
    (org-mode)
    (setq-local sentence-end-double-space t)
    (garamond-mode 1)
    (insert "#+begin_src emacs-lisp\n\n#+end_src\n")
    ;; Into the empty line inside the block, and type a comment there.
    (goto-char (point-min)) (forward-line 1)
    (dolist (char (string-to-list ";; done. next"))
      (let ((last-command-event char))
        (self-insert-command 1 char)))
    (should (equal (buffer-string)
                   "#+begin_src emacs-lisp\n;; done. next\n#+end_src\n"))))

(ert-deftest garamond-test-rewrite-is-linear-over-blocks ()
  "The scan moves forward with the rewrite rather than restarting per break."
  (with-temp-buffer
    (org-mode)
    (dotimes (_ 200) (insert "One. Two.\n#+begin_src sh\na. b\n#+end_src\n"))
    (garamond-adjust-spacing (point-min) (point-max) 2)
    (should (= 200 (count-matches "^One\\.  Two\\.$" (point-min) (point-max))))
    (should (= 200 (count-matches "^a\\. b$" (point-min) (point-max))))))


;;; What the review found

(ert-deftest garamond-test-scan-opens-an-uppercase-block ()
  "#+BEGIN_SRC is a delimiter too; the earlier case test only saw a closed one."
  (with-temp-buffer
    (org-mode)
    (insert "#+BEGIN_SRC sh\necho\n\nstill code")
    (should (equal "src" (garamond-test--open-block)))
    (should (garamond--in-verbatim-block-p))))

(ert-deftest garamond-test-typing-in-overwrite-mode-is-left-alone ()
  "A space typed over a character replaces it; nothing is shifted along."
  (with-temp-buffer
    (text-mode)
    (setq-local sentence-end-double-space t)
    (garamond-mode 1)
    (insert "One.Two more")
    (goto-char 5)
    (overwrite-mode 1)
    (let ((last-command-event ?\s)) (self-insert-command 1 ?\s))
    (should (equal "One. wo more" (buffer-string)))))

(ert-deftest garamond-test-abbreviation-inside-closers ()
  "The abbreviation ends at its period; a closer after it changes nothing."
  (should (equal (garamond-test--type "(see e.g.) this. ") "(see e.g.) this.  ")))

(ert-deftest garamond-test-set-spacing-keeps-narrowing ()
  (garamond-test--with-file _ "First line.\nSecond. Line.\n"
    (narrow-to-region (point-min) (line-end-position))
    (garamond-set-spacing 2 t)
    (should (buffer-narrowed-p))))

(ert-deftest garamond-test-persist-refuses-a-read-only-buffer-before-acting ()
  "Nothing changes in memory when the file cannot be written."
  (garamond-test--with-file _ "One. Two.\n"
    (setq buffer-read-only t)
    (should-error (garamond-set-spacing 2 t) :type 'buffer-read-only)
    (should-not garamond-mode)
    (should-not (local-variable-p 'sentence-end-double-space))
    ;; Without persisting, a read-only buffer can still be declared: the
    ;; variable is set for filling's sake, but the typing mode refuses.
    (garamond-set-spacing 2)
    (should sentence-end-double-space)
    (should-not garamond-mode)))

(ert-deftest garamond-test-persist-does-not-claim-when-locals-are-disabled ()
  (garamond-test--with-file _ "One. Two.\n"
    (let ((enable-local-variables nil))
      (garamond-set-spacing 2 t))
    (should-not (garamond-declared-p))
    (should-not (buffer-modified-p))
    (should garamond-mode)))

(ert-deftest garamond-test-dir-locals-do-not-write-into-the-file-unasked ()
  "A directory's word is not the file's: recording is asked about, not assumed."
  (let* ((dir (make-temp-file "garamond-test-dir" t))
         (file (expand-file-name "prose.txt" dir))
         (asked nil))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".dir-locals.el" dir)
            (prin1 '((text-mode . ((sentence-end-double-space . t)))) (current-buffer)))
          (with-temp-file file (insert "One. Two.\n"))
          (save-current-buffer
            (find-file file)
            (unwind-protect
                (cl-letf (((symbol-function 'y-or-n-p)
                           (lambda (&rest _) (setq asked t) nil)))
                  (should (garamond-declared-p))
                  (should-not (garamond--declared-in-file-p))
                  (let ((current-prefix-arg 2))
                    (should (equal '(2 nil) (garamond--read-spacing t))))
                  (should asked))
              (set-buffer-modified-p nil)
              (kill-buffer))))
      (delete-directory dir t))))

(ert-deftest garamond-test-follows-nothing-in-a-read-only-non-file-buffer ()
  "A dir-locals entry for all modes reaches Dired; a typing mode stays out."
  (let ((dir (make-temp-file "garamond-test-dired" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".dir-locals.el" dir)
            (prin1 '((nil . ((sentence-end-double-space . t)))) (current-buffer)))
          (garamond-test--following
            (with-current-buffer (dired-noselect dir)
              (unwind-protect
                  (progn (should (garamond-declared-p))
                         (should-not garamond-mode))
                (kill-buffer)))))
      (delete-directory dir t))))

(ert-deftest garamond-test-a-failing-parser-does-not-break-typing ()
  "An error from the oracle is reported and the space left alone."
  (with-temp-buffer
    (org-mode)
    (setq-local sentence-end-double-space t)
    (garamond-mode 1)
    (insert "One.")
    (cl-letf (((symbol-function 'org-element-context)
               (lambda (&rest _) (error "boom"))))
      (let ((last-command-event ?\s))
        (self-insert-command 1 ?\s)))
    (should (equal "One. " (buffer-string)))))

(ert-deftest garamond-test-doctor-spots-a-setq-follow-mode ()
  (garamond-test--with-file _
      (concat "One. Two.\n\n" (format garamond-test--declaration-format "t"))
    (garamond-follow-declarations-mode -1)
    (let ((garamond-follow-declarations-mode t))
      (should (string-match-p "set with .setq." (garamond--diagnosis))))))

(ert-deftest garamond-test-doctor-knows-a-missing-mode-line ()
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (setq-local mode-line-format nil)
    (should (eq 'none (garamond--mode-line-shows-lighter)))
    (should (string-match-p "no mode line at all" (garamond--diagnosis)))))


;;; The efficiency review

(ert-deftest garamond-test-after-sentence-end-p-agrees-with-the-regexp ()
  "The constant-time test says what the old `looking-back' pattern said."
  (dolist (case '(("word. " . t) ("word! " . t) ("word?) " . t) ("word.\"’ " . t)
                  ("1. " . nil) ("3.14 " . nil) ("word " . nil) (". " . nil)
                  ("(foo.) " . t) ("é. " . t) ("word.\n " . nil)))
    (with-temp-buffer
      (insert (car case))
      (skip-chars-backward " ")
      (should (eq (cdr case)
                  (and (save-excursion (garamond--after-sentence-end-p)) t)))
      (should (eq (cdr case)
                  (and (looking-back "[[:alpha:]][.?!…‽][]\"'”’)}»›]*"
                                     (line-beginning-position))
                       t))))))

(ert-deftest garamond-test-after-sentence-end-p-stops-at-the-punctuation ()
  (with-temp-buffer
    (insert "(e.g.) ")
    (skip-chars-backward " ")
    (should (garamond--after-sentence-end-p))
    (should (eq ?. (char-before)))
    (should (eq ?\) (char-after)))))

(ert-deftest garamond-test-abbreviation-changes-take-effect ()
  "The cached regexp follows the list; a `setq' needs no reload."
  (should (equal (garamond-test--type "Use foo. next ") "Use foo.  next "))
  (let ((garamond-abbreviations (cons "foo." garamond-abbreviations)))
    (should (equal (garamond-test--type "Use foo. next ") "Use foo. next ")))
  (should (equal (garamond-test--type "Use foo. next ") "Use foo.  next ")))

(ert-deftest garamond-test-abbreviation-needs-a-word-boundary ()
  "\"Xe.g.\" is not e.g.; at the start of a line e.g. still is."
  (with-temp-buffer
    (insert "e.g.")
    (should (garamond--abbreviation-p (point)))
    (erase-buffer) (insert "Xe.g.")
    (should-not (garamond--abbreviation-p (point)))
    (erase-buffer) (insert "see e.g.")
    (should (garamond--abbreviation-p (point)))
    (erase-buffer) (insert "see E.G.")
    (should-not (garamond--abbreviation-p (point)))))

(ert-deftest garamond-test-ranges-predicate ()
  "Nested and adjacent ranges, asked in increasing order."
  (let ((in (garamond--in-ranges-predicate '((10 . 50) (12 . 20) (30 . 35) (60 . 70)))))
    (should-not (funcall in 5))
    (should (funcall in 10))
    (should (funcall in 15))
    (should (funcall in 25))     ; in the outer range only
    (should (funcall in 49))
    (should-not (funcall in 50)) ; END is exclusive
    (should-not (funcall in 55))
    (should (funcall in 60))
    (should-not (funcall in 70))))

(ert-deftest garamond-test-rewrite-refuses-a-read-only-buffer-first ()
  (with-temp-buffer
    (text-mode)
    (insert "One. Two.")
    (setq buffer-read-only t)
    (should-error (garamond-adjust-spacing (point-min) (point-max) 2)
                  :type 'buffer-read-only)
    (should-not garamond-mode)
    (should (equal "One. Two." (buffer-string)))))

(ert-deftest garamond-test-rewrite-agrees-with-the-typing-oracle-after-a-link ()
  "The gap after a link whose description ends a sentence belongs to the link."
  (should (equal (garamond-test--rewrite "See [[file:x][the end.]] Next. Done." 2 #'org-mode)
                 "See [[file:x][the end.]] Next.  Done.")))

(ert-deftest garamond-test-rewrite-handles-nested-org-constructs ()
  "A link inside a table cell, code inside a quote block: only prose changes."
  (should (equal (garamond-test--rewrite
                  (concat "| [[x][a. b]] | c. d |\n\n"
                          "#+begin_quote\nQuoted. Prose with ~code. here~ too.\n#+end_quote\n")
                  2 #'org-mode)
                 (concat "| [[x][a. b]] | c. d |\n\n"
                         "#+begin_quote\nQuoted.  Prose with ~code. here~ too.\n#+end_quote\n"))))

(ert-deftest garamond-test-rewrite-leaves-an-unclosed-block-alone ()
  "The parse reads an unfinished block as a paragraph; the scan still sees it."
  (should (equal (garamond-test--rewrite "Prose. Here.\n#+begin_src sh\na. b\n" 2 #'org-mode)
                 "Prose.  Here.\n#+begin_src sh\na. b\n")))


;;; The guard

(ert-deftest garamond-test-mode-refuses-a-read-only-buffer ()
  (with-temp-buffer
    (text-mode)
    (setq buffer-read-only t)
    (garamond-mode 1)
    (should-not garamond-mode)
    (should-not (memq #'garamond--maybe-double-space post-self-insert-hook))))

(ert-deftest garamond-test-mode-refuses-unsuitable-modes ()
  (dolist (mode '(dired-mode special-mode))
    (with-temp-buffer
      (funcall mode)
      (setq buffer-read-only nil)          ; the mode alone must be reason enough
      (garamond-mode 1)
      (should-not garamond-mode)))
  (let ((garamond-unsuitable-modes '(text-mode)))
    (with-temp-buffer
      (org-mode)                            ; derives from text-mode
      (garamond-mode 1)
      (should-not garamond-mode))))

(ert-deftest garamond-test-mode-refusal-by-hand-is-an-error ()
  (with-temp-buffer
    (text-mode)
    (setq buffer-read-only t)
    (should-error (call-interactively #'garamond-mode) :type 'user-error)
    (should-not garamond-mode)))

(ert-deftest garamond-test-mode-still-runs-where-prose-might-be ()
  "The guard is against the absurd, not a list of prose modes."
  (dolist (mode '(conf-mode emacs-lisp-mode text-mode))
    (with-temp-buffer
      (funcall mode)
      (garamond-mode 1)
      (should garamond-mode))))

(ert-deftest garamond-test-mode-turns-off-when-refusing ()
  "Switching the mode on again in a buffer gone read-only takes it off."
  (with-temp-buffer
    (text-mode)
    (garamond-mode 1)
    (should garamond-mode)
    (setq buffer-read-only t)
    (garamond-mode 1)
    (should-not garamond-mode)
    (should-not (memq #'garamond--maybe-double-space post-self-insert-hook))))

(ert-deftest garamond-test-follows-a-read-only-toggle ()
  "A declared file opened read-only gets the typing when made writable."
  (garamond-test--following
    (garamond-test--with-file _
        (concat "One. Two.\n\n" (format garamond-test--declaration-format "t"))
      (read-only-mode 1)
      (should-not garamond-mode)
      (read-only-mode -1)
      (should garamond-mode)
      (read-only-mode 1)
      (should-not garamond-mode))))

(ert-deftest garamond-test-read-only-toggle-ignores-undeclared-buffers ()
  (garamond-test--following
    (garamond-test--with-file _ "One. Two.\n"
      (read-only-mode 1)
      (read-only-mode -1)
      (should-not garamond-mode))))

(ert-deftest garamond-test-doctor-explains-the-guard ()
  (garamond-test--with-file _
      (concat "One. Two.\n\n" (format garamond-test--declaration-format "t"))
    (setq buffer-read-only t)
    (garamond-mode -1)
    (should (string-match-p "will not run here: the buffer is read-only"
                            (garamond--diagnosis)))))


;;; Abbreviations, added and removed

(ert-deftest garamond-test-extra-abbreviations-count ()
  (should (equal (garamond-test--type "A Ph.D. is ") "A Ph.D.  is "))
  (let ((garamond-extra-abbreviations '("Ph.D.")))
    (should (equal (garamond-test--type "A Ph.D. is ") "A Ph.D. is "))))

(ert-deftest garamond-test-removed-abbreviations-stop-counting ()
  (should (equal (garamond-test--type "On Main St. Then ") "On Main St. Then "))
  (let ((garamond-removed-abbreviations '("St.")))
    (should (equal (garamond-test--type "On Main St. Then ") "On Main St.  Then "))))

(ert-deftest garamond-test-abbreviations-in-force ()
  (let ((garamond-abbreviations '("a." "b." "c."))
        (garamond-removed-abbreviations '("b."))
        (garamond-extra-abbreviations '("d.")))
    (should (equal '("a." "c." "d.") (garamond--abbreviations-in-force)))))

(ert-deftest garamond-test-every-default-abbreviation-is-spared ()
  "Each default, typed between two words, keeps its single space.
A guard on the list itself: an entry that does not end in a period, or
whose period falls anywhere but its last word, is never reached by
`garamond--abbreviation-p' and would quietly do nothing."
  (dolist (abbrev garamond-abbreviations)
    (let ((typed (concat "See " abbrev " next ")))
      (should (equal (garamond-test--type typed) typed)))))

(ert-deftest garamond-test-default-abbreviations-are-well-formed ()
  "Every default is a distinct non-empty string ending in a period."
  (should-not (seq-remove (lambda (abbrev)
                            (and (stringp abbrev)
                                 (not (string= abbrev ""))
                                 (string-suffix-p "." abbrev)))
                          garamond-abbreviations))
  (should (= (length garamond-abbreviations)
             (length (delete-dups (copy-sequence garamond-abbreviations))))))

(ert-deftest garamond-test-the-wider-defaults-are-abbreviations ()
  "A sample of each group the defaults cover holds its single space."
  (dolist (line '("Met Capt. Ahab "               ; rank
                  "The Rt Hon. Member "           ; address
                  "Filed by Acme Corp. after "    ; organisation
                  "Due in Sept. next "            ; month
                  "On Tues. we "                  ; day
                  "At 9 a.m. we "                 ; the clock
                  "See Sec. 4 of "                ; bibliographic
                  "The U.S. Navy "                ; initialism
                  "Read viz. that "               ; Latin
                  "As et seq. shows "))           ; two words
    (should (equal (garamond-test--type line) line))))

(ert-deftest garamond-test-capitalised-defaults-keep-their-case ()
  "\"Sat.\" abbreviates a day; \"he sat.\" ends a sentence."
  (should (equal (garamond-test--type "On Sat. Then ") "On Sat. Then "))
  (should (equal (garamond-test--type "He sat. Then ") "He sat.  Then "))
  (should (equal (garamond-test--type "They wed. Then ") "They wed.  Then ")))


;;; The pre-release pass

(ert-deftest garamond-test-docstrings-have-no-broken-escapes ()
  "A lone \\= in a docstring reads as =, so \\='s renders as ='s.
Every garamond docstring, function or variable, is checked for the residue."
  (let (bad)
    (mapatoms
     (lambda (sym)
       (when (string-prefix-p "garamond" (symbol-name sym))
         (dolist (doc (list (and (fboundp sym) (ignore-errors (documentation sym)))
                            (documentation-property sym 'variable-documentation)))
           (when (and (stringp doc) (string-match-p "='\\|=\"" doc))
             (push sym bad))))))
    (should-not bad)))

(ert-deftest garamond-test-empty-abbreviation-is-ignored ()
  "An empty string would match everywhere and silence the typing."
  (let ((garamond-extra-abbreviations '("")))
    (should (equal (garamond-test--type "One. Two. ") "One.  Two.  ")))
  (let ((garamond-extra-abbreviations '(nil "" 42)))
    (should (equal (garamond-test--type "One. Two. ") "One.  Two.  "))))

(ert-deftest garamond-test-sentence-initial-capital-abbreviations ()
  "e.g. at the start of a sentence is E.g., and still an abbreviation."
  (should (equal (garamond-test--type "E.g. this. ") "E.g. this.  "))
  (should (equal (garamond-test--type "Cf. that. ") "Cf. that.  "))
  ;; A capitalised entry gets no lower-case twin: no. ends a sentence.
  (should (equal (garamond-test--type "I said no. Then ") "I said no.  Then "))
  (should (equal (garamond-test--type "Ask Dr. Who ") "Ask Dr. Who ")))

(ert-deftest garamond-test-adjust-spacing-accepts-reversed-bounds ()
  (with-temp-buffer
    (text-mode)
    (insert "One. Two. Three.")
    (garamond-adjust-spacing (point-max) (point-min) 2)
    (should (equal "One.  Two.  Three." (buffer-string)))))

(ert-deftest garamond-test-scan-sees-past-a-narrowing ()
  "Narrowed to the inside of a block, the scan still knows it is in one."
  (with-temp-buffer
    (org-mode)
    (insert "Prose.\n#+begin_src sh\necho one\necho two\n#+end_src\n")
    (goto-char (point-min)) (search-forward "echo two")
    (narrow-to-region (line-beginning-position) (line-end-position))
    (should (garamond--in-verbatim-block-p))))

(ert-deftest garamond-test-rewrite-src-inside-quote-block ()
  "A src block nested in a quote block is code; the quote's prose is prose."
  (should (equal (garamond-test--rewrite
                  "#+begin_quote\nQuoted. Words.\n#+begin_src sh\na. b\n#+end_src\n#+end_quote\n"
                  2 #'org-mode)
                 "#+begin_quote\nQuoted.  Words.\n#+begin_src sh\na. b\n#+end_src\n#+end_quote\n")))

(ert-deftest garamond-test-guard-list-can-be-emptied ()
  (let ((garamond-unsuitable-modes nil))
    (with-temp-buffer
      (dired-mode)
      (setq buffer-read-only nil)
      (garamond-mode 1)
      (should garamond-mode))))

(ert-deftest garamond-test-sentence-end-at-buffer-start ()
  (should (equal (garamond-test--type "A. ") "A.  "))
  (should (equal (garamond-test--type ". ") ". ")))


;;; Declaring, without rewriting

(ert-deftest garamond-test-set-spacing-touches-no-text ()
  (with-temp-buffer
    (text-mode)
    (insert "One. Two.  Three.")
    (garamond-set-spacing 2)
    (should (equal (buffer-string) "One. Two.  Three."))
    (should sentence-end-double-space)))

(ert-deftest garamond-test-set-spacing-switches-the-typing-to-match ()
  "Declaring a buffer is what turns the mode on in it, either spacing."
  (with-temp-buffer
    (text-mode)
    (should-not garamond-mode)
    (garamond-set-spacing 2)
    (should garamond-mode)
    (garamond-set-spacing 1)
    (should garamond-mode)              ; on, but dormant
    (should-not sentence-end-double-space)))

(ert-deftest garamond-test-adjust-spacing-declares-too ()
  (with-temp-buffer
    (text-mode)
    (insert "One. Two.")
    (garamond-adjust-spacing (point-min) (point-max) 2)
    (should sentence-end-double-space)
    (should garamond-mode)
    (garamond-adjust-spacing (point-min) (point-max) 1)
    (should-not sentence-end-double-space)
    (should garamond-mode)))

(ert-deftest garamond-test-persist-writes-the-declaration ()
  (garamond-test--with-file file "One. Two.\n"
    (should-not (garamond-declared-p))
    (garamond-set-spacing 2 t)
    (should (garamond-declared-p))
    (save-buffer)
    (should (string-match-p "sentence-end-double-space: t"
                            (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string))))))


;;; Declaration, not value

(ert-deftest garamond-test-declared-p-ignores-the-global-default ()
  "Emacs sets the variable to t everywhere; only the file's word counts."
  (should (default-value 'sentence-end-double-space)) ; the premise
  (garamond-test--with-file _ "One. Two.\n"
    (should sentence-end-double-space)          ; inherited from the global
    (should-not (garamond-declared-p))))        ; but the file said nothing

(ert-deftest garamond-test-declared-p-sees-a-declaration ()
  (garamond-test--with-file _
      (concat "One. Two.\n\n"
              (format garamond-test--declaration-format "t"))
    (should (garamond-declared-p))
    (should sentence-end-double-space)))

(ert-deftest garamond-test-declared-p-takes-a-buffer ()
  (garamond-test--with-file _
      (concat "One. Two.\n\n"
              (format garamond-test--declaration-format "t"))
    (let ((declared (current-buffer)))
      (with-temp-buffer
        (should-not (garamond-declared-p))
        (should (garamond-declared-p declared))))))


;;; Following what a file says

(defmacro garamond-test--following (&rest body)
  "Run BODY with `garamond-follow-declarations-mode' on, then restore it."
  (declare (indent 0) (debug t))
  `(let ((was garamond-follow-declarations-mode))
     (unwind-protect (progn (garamond-follow-declarations-mode 1) ,@body)
       (garamond-follow-declarations-mode (if was 1 -1)))))

(ert-deftest garamond-test-follows-a-declared-file ()
  (garamond-test--following
    (garamond-test--with-file _
        (concat "One. Two.\n\n"
                (format garamond-test--declaration-format "t"))
      (should garamond-mode))))

(ert-deftest garamond-test-leaves-a-silent-file-alone ()
  "A file that declares nothing gets nothing done to it."
  (garamond-test--following
    (garamond-test--with-file _ "One. Two.\n"
      (should-not garamond-mode))))

(ert-deftest garamond-test-follows-a-single-spaced-declaration ()
  "A file declaring single spacing is followed too: the mode stays quiet."
  (garamond-test--following
    (garamond-test--with-file _
        (concat "One. Two.\n\n"
                (format garamond-test--declaration-format "nil"))
      (should garamond-mode)                    ; declared, so managed
      (should-not sentence-end-double-space)    ; and dormant
      (should (equal " 1S" (garamond-test--lighter))))))

(ert-deftest garamond-test-does-not-follow-when-the-mode-is-off ()
  (garamond-follow-declarations-mode -1)
  (garamond-test--with-file _
      (concat "One. Two.\n\n"
              (format garamond-test--declaration-format "t"))
    (should (garamond-declared-p))
    (should-not garamond-mode)))

(ert-deftest garamond-test-follows-dir-locals ()
  "A .dir-locals.el declares a whole directory, and counts as the file's word."
  (let* ((dir (make-temp-file "garamond-test-dir" t))
         (file (expand-file-name "prose.txt" dir)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".dir-locals.el" dir)
            (prin1 '((text-mode . ((sentence-end-double-space . t)))) (current-buffer)))
          (with-temp-file file (insert "One. Two.\n"))
          (garamond-test--following
            (save-current-buffer
              (find-file file)
              (unwind-protect
                  (progn (should (garamond-declared-p))
                         (should garamond-mode))
                (kill-buffer)))))
      (delete-directory dir t))))

(ert-deftest garamond-test-follow-mode-manages-its-hook ()
  (let ((was garamond-follow-declarations-mode))
    (unwind-protect
        (progn
          (garamond-follow-declarations-mode 1)
          (should (memq #'garamond--heed-declaration hack-local-variables-hook))
          (garamond-follow-declarations-mode -1)
          (should-not (memq #'garamond--heed-declaration hack-local-variables-hook)))
      (garamond-follow-declarations-mode (if was 1 -1)))))


;;; The typing

(ert-deftest garamond-test-typing-doubles-the-space ()
  (should (equal (garamond-test--type "One. Two. ") "One.  Two.  ")))

(ert-deftest garamond-test-typing-trims-a-long-run ()
  "Three presses of the space bar still leave two spaces."
  (should (equal (garamond-test--type "One.   ") "One.  ")))

(ert-deftest garamond-test-typing-spares-abbreviations ()
  (should (equal (garamond-test--type "Use e.g. this. ") "Use e.g. this.  "))
  (should (equal (garamond-test--type "Ask Dr. Who. ") "Ask Dr. Who.  ")))

(ert-deftest garamond-test-typing-spares-list-numbering ()
  "A digit before the period is numbering, so the letter test rules it out."
  (should (equal (garamond-test--type "1. Item ") "1. Item ")))

(ert-deftest garamond-test-typing-is-dormant-when-single-spaced ()
  (with-temp-buffer
    (text-mode)
    (setq-local sentence-end-double-space nil)
    (garamond-mode 1)
    (dolist (char (string-to-list "One. Two. "))
      (let ((last-command-event char))
        (self-insert-command 1 char)))
    (should (equal (buffer-string) "One. Two. "))))

(ert-deftest garamond-test-typing-stops-at-an-unfinished-org-link ()
  "Half a link is still a link: the space inside the path stays single."
  (should (equal (garamond-test--type "See [[file:a. b" #'org-mode)
                 "See [[file:a. b")))

(ert-deftest garamond-test-typing-stops-inside-an-unclosed-org-block ()
  (should (equal (garamond-test--type
                  "#+begin_src emacs-lisp\n(f 1. 2) " #'org-mode)
                 "#+begin_src emacs-lisp\n(f 1. 2) ")))

(ert-deftest garamond-test-mode-manages-its-hook ()
  (with-temp-buffer
    (text-mode)
    (garamond-mode 1)
    (should (memq #'garamond--maybe-double-space post-self-insert-hook))
    (garamond-mode -1)
    (should-not (memq #'garamond--maybe-double-space post-self-insert-hook))))

(ert-deftest garamond-test-mode-by-hand-is-taken-at-its-word ()
  "No mode list stands between the user and a mode they asked for."
  (with-temp-buffer
    (conf-mode)
    (setq-local sentence-end-double-space t)
    (garamond-mode 1)
    (should garamond-mode)
    (dolist (char (string-to-list "One. "))
      (let ((last-command-event char))
        (self-insert-command 1 char)))
    (should (equal (buffer-string) "One.  "))))


(defun garamond-test--lighter ()
  "Return the lighter the mode line would show for this buffer.
`format-mode-line' returns the empty string under --batch, there being no
window to format against, so the construct `garamond-mode' installed in
`minor-mode-alist' is evaluated here as the display engine would: shown
only while the mode's own variable is non-nil."
  (let ((entry (cadr (assq 'garamond-mode minor-mode-alist))))
    (if (and garamond-mode (eq (car-safe entry) :eval))
        (substring-no-properties (or (eval (cadr entry) t) ""))
      "")))

(ert-deftest garamond-test-lighter-is-wired-into-the-mode-line ()
  "The mode installs the live construct, not a fixed string."
  (should (equal '(:eval (garamond--lighter))
                 (cadr (assq 'garamond-mode minor-mode-alist)))))

(ert-deftest garamond-test-lighter-names-the-spacing ()
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (should (equal " 2S" (garamond-test--lighter)))
    (garamond-set-spacing 1)
    (should (equal " 1S" (garamond-test--lighter)))))

(ert-deftest garamond-test-lighter-brackets-a-muted-typing ()
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (let ((garamond-double-space-on-typing nil))
      (should (equal " (2S)" (garamond-test--lighter))))
    (garamond-set-spacing 1)
    (let ((garamond-double-space-on-typing nil))
      (should (equal " (1S)" (garamond-test--lighter))))))

(ert-deftest garamond-test-lighter-is-absent-when-the-mode-is-off ()
  "Nothing in the mode line means nothing has declared this buffer."
  (with-temp-buffer
    (text-mode)
    (should-not garamond-mode)
    (should (equal "" (garamond-test--lighter)))
    (garamond-set-spacing 2)
    (should (equal " 2S" (garamond-test--lighter)))
    (garamond-mode -1)
    (should (equal "" (garamond-test--lighter)))))

(ert-deftest garamond-test-lighter-carries-a-tooltip ()
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (should (get-text-property 0 'help-echo (garamond--lighter)))))

(ert-deftest garamond-test-lighter-can-be-switched-off ()
  "With `garamond-lighter' nil the mode contributes nothing of its own."
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (should (equal " 2S" (garamond-test--lighter)))
    (let ((garamond-lighter nil))
      (should-not (garamond--lighter))
      (should (equal "" (garamond-test--lighter))))))

(ert-deftest garamond-test-mode-line-string-is-bare ()
  "What you place by hand carries no leading space of its own."
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (should (equal "2S" (substring-no-properties (garamond-mode-line-string))))
    (garamond-set-spacing 1)
    (should (equal "1S" (substring-no-properties (garamond-mode-line-string))))
    (let ((garamond-double-space-on-typing nil))
      (should (equal "(1S)"
                     (substring-no-properties (garamond-mode-line-string)))))))

(ert-deftest garamond-test-mode-line-string-is-empty-when-off ()
  "It is safe in a global mode line: silent wherever garamond is not on."
  (with-temp-buffer
    (fundamental-mode)
    (should-not garamond-mode)
    (should (equal "" (garamond-mode-line-string)))))

(ert-deftest garamond-test-mode-line-string-ignores-the-lighter-switch ()
  "`garamond-lighter' governs the mode's own indicator, not yours."
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (let ((garamond-lighter nil))
      (should (equal "2S"
                     (substring-no-properties (garamond-mode-line-string)))))))

(ert-deftest garamond-test-mode-line-format-is-placeable ()
  "The ready-made construct evaluates to the same string."
  (should (equal '(:eval (garamond-mode-line-string)) garamond-mode-line-format))
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (should (equal "2S" (substring-no-properties
                         (eval (cadr garamond-mode-line-format) t))))))

(ert-deftest garamond-test-lighter-allocates-nothing ()
  "It picks one of four strings made at load, not a fresh one each redisplay."
  (with-temp-buffer
    (text-mode)
    (garamond-set-spacing 2)
    (should (eq (garamond--lighter) (garamond--lighter)))))


;;; The typing switch

(ert-deftest garamond-test-typing-switch-silences-the-hook ()
  (let ((garamond-double-space-on-typing nil))
    (should (equal (garamond-test--type "One. Two. ") "One. Two. ")))
  (let ((garamond-double-space-on-typing t))
    (should (equal (garamond-test--type "One. Two. ") "One.  Two.  "))))

(ert-deftest garamond-test-typing-switch-leaves-the-rest-alone ()
  "The switch is about typing only; declaring and rewriting carry on."
  (let ((garamond-double-space-on-typing nil))
    (should (equal (garamond-test--rewrite "One. Two." 2) "One.  Two."))
    (with-temp-buffer
      (text-mode)
      (garamond-set-spacing 2)
      (should sentence-end-double-space))))

(ert-deftest garamond-test-typing-switch-is-live ()
  "It is read at each keystroke, so the mode need not be cycled."
  (with-temp-buffer
    (text-mode)
    (setq-local sentence-end-double-space t)
    (garamond-mode 1)
    (cl-flet ((type (text)
                (dolist (char (string-to-list text))
                  (let ((last-command-event char))
                    (self-insert-command 1 char)))))
      (let ((garamond-double-space-on-typing nil))
        (type "One. "))
      (let ((garamond-double-space-on-typing t))
        (type "Two. ")))
    (should (equal (buffer-string) "One. Two.  "))))

;;; The doctor

(defun garamond-test--doctor-text ()
  "Run the doctor on the current buffer and return what it printed."
  (garamond-doctor)
  (with-current-buffer "*garamond-doctor*"
    (buffer-substring-no-properties (point-min) (point-max))))

(ert-deftest garamond-test-doctor-reports-an-undeclared-buffer ()
  (garamond-test--with-file _ "One. Two.\n"
    (let ((report (garamond-test--doctor-text)))
      (should (string-match-p "declared                   no" report))
      (should (string-match-p "garamond-mode              off" report))
      (should (string-match-p "Nothing has declared this buffer" report))
      ;; The advice has to be reachable, not a dangling reference.
      (should (string-match-p "M-x garamond-set-spacing" report)))))

(ert-deftest garamond-test-doctor-reports-a-declared-buffer ()
  (garamond-test--with-file _ "One. Two.\n"
    (garamond-set-spacing 2 t)
    (let ((report (garamond-test--doctor-text)))
      (should (string-match-p "declared                   yes, in the file" report))
      (should (string-match-p "garamond-mode              on" report))
      (should (string-match-p "indicator                  2S" report)))))

(ert-deftest garamond-test-doctor-names-the-lighter-switch ()
  (garamond-test--with-file _ "One. Two.\n"
    (garamond-set-spacing 2)
    (let* ((garamond-lighter nil)
           (report (garamond-test--doctor-text)))
      (should (string-match-p "garamond-lighter                   nil" report))
      (should (string-match-p "place .garamond-mode-line-format." report)))))

(ert-deftest garamond-test-doctor-does-not-claim-what-it-cannot-see ()
  "Under --batch no mode line renders, and the report must say so."
  (garamond-test--with-file _ "One. Two.\n"
    (garamond-set-spacing 2)
    (let ((report (garamond-test--doctor-text)))
      (should (string-match-p "cannot be told from here" report))
      (should-not (string-match-p "Nothing to report" report)))))

(ert-deftest garamond-test-version-is-public-and-a-string ()
  (should (stringp (garamond-version)))
  (should (equal (garamond-version) (garamond--version))))

(ert-deftest garamond-test-doctor-reads-its-own-version ()
  (should (string-match-p "\\`[0-9]+\\.[0-9]+" (or (garamond--version) ""))))

(ert-deftest garamond-test-mode-line-check-is-honest-when-empty ()
  "An empty indicator must not match every mode line ever rendered."
  (with-temp-buffer
    (fundamental-mode)
    (should-not garamond-mode)
    (should (eq 'unknown (garamond--mode-line-shows-lighter)))))

(provide 'garamond-test)
;;; garamond-test.el ends here
