;;; garamond.el --- Sentence spacing the document carries itself  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Michael A Jones

;; Author: Michael A Jones <yardquit@pm.me>
;; Maintainer: Michael A Jones <yardquit@pm.me>
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, text, wp
;; URL: https://github.com/yardquit/garamond

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Everything governing the space between sentences lives here: the two
;; commands that declare what a buffer uses, the minor mode that doubles
;; the space as it is typed, and the hook that lets a file speak for
;; itself.
;;
;; Two spaces after a full stop are a typist's convention, and Emacs
;; believes in them: `sentence-end-double-space' is what tells
;; \\[fill-paragraph] and \\[forward-sentence] where one sentence stops
;; and the next begins.  The trouble is keeping the text and the variable
;; in agreement, and keeping the second space out of everything that is
;; laid out rather than written -- code, tables, link targets, maths.
;; That is the whole of this package.
;;
;; Nothing here is a global setting.  How a document is spaced is a
;; property of that document, so it is kept in the document rather than
;; in anybody's configuration: `garamond-set-spacing' and
;; `garamond-adjust-spacing' write `sentence-end-double-space' into the
;; file as a local variable, and `garamond-follow-declarations-mode'
;; reads it back when the file is next opened, switching the typing on to
;; match.  There is no list of prose modes, and no buffer is altered
;; because of what mode it happens to be in; the one list of modes here,
;; `garamond-unsuitable-modes', names the buffers nobody types in, where
;; the typing mode refuses to run at all.
;;
;; What is consulted is the declaration, not the value.  Emacs ships with
;; `sentence-end-double-space' set to t, so every buffer in every Emacs
;; already "has" double spacing; a package that read the value would
;; follow that global into files which never asked for it.  So the hook
;; asks `file-local-variables-alist' instead, which holds only what the
;; file itself said.
;;
;; A file declares itself in the usual way:
;;
;;   # Local Variables:
;;   # sentence-end-double-space: t
;;   # End:
;;
;; A whole prose repository declares itself in .dir-locals.el:
;;
;;   ((org-mode . ((sentence-end-double-space . t))))
;;
;; Or, for the typing alone, in the first line of the file:
;;
;;   -*- mode: markdown; mode: garamond -*-
;;
;; Three entry points:
;;
;;   `garamond-set-spacing'     say what this buffer uses, and record it
;;                              in the file; not a character is touched.
;;
;;   `garamond-adjust-spacing'  the same, and rewrite the text to match.
;;
;;   `garamond-mode'            a buffer-local minor mode: type one space
;;                              after a sentence end and get two.
;;
;; One line of setup:
;;
;;   (require 'garamond)
;;   (garamond-follow-declarations-mode 1)
;;
;; It does not run itself on load; a library that switches itself on is a
;; library you cannot load in order to read it.  The globals it does have
;; -- the abbreviation lists, `garamond-double-space-on-typing',
;; `garamond-lighter', `garamond-persist', `garamond-unsuitable-modes' --
;; say nothing about any document's spacing.
;;
;; When the indicator is not where you expect it, `garamond-doctor' says
;; what garamond is doing in the buffer and why.

;;; Code:

(require 'seq)

(defgroup garamond nil
  "Sentence spacing, kept in the document rather than in a setting."
  :group 'fill
  :prefix "garamond-")


;;; ---------------------------------------------------------------------------
;;; ABBREVIATIONS
;;; ---------------------------------------------------------------------------

(defcustom garamond-abbreviations
  '(;; Latin and editorial.
    "e.g." "i.e." "cf." "viz." "vs." "etc." "al." "et seq." "ibid." "q.v."
    "ca." "approx." "esp." "incl." "excl." "resp." "misc." "a.k.a." "ff."
    ;; Bibliographic.
    "p." "pp." "ed." "eds." "edn." "trans." "repr." "suppl."
    "No." "Nos." "Fig." "Figs." "Ch." "Chap." "Vol." "Vols." "Sec." "Secs."
    "Eq." "Eqs." "Ref." "Refs." "App."
    ;; Forms of address.
    "Mr." "Mrs." "Ms." "Mx." "Messrs." "Dr." "Prof." "Rev." "Fr." "Msgr."
    "Sr." "Jr." "St." "Hon." "Pres." "Gov." "Sen." "Rep." "Amb."
    ;; Rank.
    "Adm." "Capt." "Cmdr." "Col." "Cpl." "Det." "Gen." "Insp." "Lt."
    "Maj." "Pvt." "Sgt." "Supt."
    ;; Organisations and places.
    "Co." "Corp." "Bros." "Dept." "Univ." "Inst." "Mt." "Ft." "Ave."
    "Blvd." "Rd." "U.S." "U.K." "U.N." "D.C."
    ;; Months.
    "Jan." "Feb." "Mar." "Apr." "Jun." "Jul." "Aug." "Sep." "Sept."
    "Oct." "Nov." "Dec."
    ;; Days.
    "Mon." "Tue." "Tues." "Wed." "Weds." "Thu." "Thur." "Thurs." "Fri."
    "Sat." "Sun."
    ;; The clock, and the two notes.
    "a.m." "p.m." "A.M." "P.M." "N.B." "P.S.")
  "Abbreviations whose trailing period does not end a sentence.
Consulted by `garamond-mode' while typing.  The wholesale rewrite done by
`garamond-adjust-spacing' ignores this, so that its result is uniform.

These are the defaults: the Latin and editorial shorthand, the
bibliographic marks, forms of address and of rank, the months and the
days.  What is absent is absent on purpose: academic degrees such as
\"Ph.D.\", company suffixes such as \"Inc.\", and units such as \"lb.\"
follow the thing they qualify, and so end a sentence about as often as
they sit inside one; listed here, they would cost the second space every
time they did.  Write the ones you use into
`garamond-extra-abbreviations'.

To add your own without retyping the defaults, or to drop some, use
`garamond-extra-abbreviations' and `garamond-removed-abbreviations'; all
three are read afresh, so a `setq' in a configuration file takes effect
at the next keystroke.

Case matters, with one allowance: an entry that begins with a lower-case
letter also counts capitalised, as it is at the start of a sentence --
\"e.g.\" covers \"E.g.\".  An entry given capitalised, \"No.\" or \"Dr.\",
is matched only so, since \"no.\" and \"dr.\" do end sentences.  That is
why the days and months are here in their written form alone: \"Sat.\"
is an abbreviation where \"he sat.\" is a sentence.

An entry of several words is matched whole, but only its last word may
carry a period.  The space after \"op.\" in \"op. cit.\" is a sentence
end as the hook meets it, one word too early for the entry to be
reached, so \"et seq.\" can be here and \"op. cit.\" cannot."
  :type '(repeat string)
  :group 'garamond)

(defcustom garamond-extra-abbreviations nil
  "Abbreviations of your own, added to `garamond-abbreviations'.
Write each with its period, as it is typed: \"Ph.D.\", \"et al.\",
\"Inc.\".  Set it in a configuration file with `setq'; the list in force
is recomputed whenever any of the three lists is replaced."
  :type '(repeat string)
  :group 'garamond)

(defcustom garamond-removed-abbreviations nil
  "Abbreviations from `garamond-abbreviations' that should not count.
Name them as they appear there -- \"St.\", say, if your streets and
saints end sentences more often than they abbreviate."
  :type '(repeat string)
  :group 'garamond)

(defun garamond--abbreviations-in-force ()
  "Return the abbreviations that count: the defaults, less removed, plus extra.
Anything that is not a non-empty string is dropped on the way: an empty
string would match everywhere and silence the typing altogether."
  (seq-filter (lambda (abbrev) (and (stringp abbrev) (not (string= abbrev ""))))
              (append (seq-remove (lambda (abbrev)
                                    (member abbrev garamond-removed-abbreviations))
                                  garamond-abbreviations)
                      garamond-extra-abbreviations)))

(defun garamond--with-sentence-initial-capitals (abbreviations)
  "Return ABBREVIATIONS with a capitalised twin for each lower-case one.
\"e.g.\" opens a sentence as \"E.g.\", and is no less an abbreviation for
it; \"No.\" and \"Dr.\" are given capitalised and get no lower-case twin,
since \"no.\" and \"dr.\" do end sentences."
  (append abbreviations
          (delq nil
                (mapcar (lambda (abbrev)
                          (let ((first (aref abbrev 0)))
                            (and (/= first (upcase first))
                                 (concat (string (upcase first))
                                         (substring abbrev 1)))))
                        abbreviations))))

(defvar garamond--abbreviation-regexp nil
  "One regexp matching any abbreviation in force, built on demand.
A single match replaces a `buffer-substring' and a `string=' for each
abbreviation in turn.  Rebuilt whenever one of the three lists is a
different object, so a `setq' in a configuration file takes effect at
the next keystroke; a list edited in place with `setcar' is not seen,
which is why the knobs are lists to set rather than to edit.")

(defvar garamond--abbreviation-regexp-for nil
  "The three lists `garamond--abbreviation-regexp' was built from.")

(defvar garamond--abbreviation-reach 0
  "How far back an abbreviation can start, in characters.
The longest abbreviation in force, and the character before it, which
must not be part of a word.")

(defun garamond--abbreviation-regexp ()
  "Return the regexp for the abbreviations in force, rebuilding it if they changed."
  ;; Three `eq' tests and no consing: this runs at every sentence end.
  (let ((for garamond--abbreviation-regexp-for))
    (unless (and (eq (nth 0 for) garamond-abbreviations)
                 (eq (nth 1 for) garamond-extra-abbreviations)
                 (eq (nth 2 for) garamond-removed-abbreviations))
      (let ((in-force (garamond--abbreviations-in-force)))
        (setq garamond--abbreviation-regexp-for
              (list garamond-abbreviations
                    garamond-extra-abbreviations
                    garamond-removed-abbreviations)
              garamond--abbreviation-reach
              (1+ (apply #'max 0 (mapcar #'length in-force)))
              garamond--abbreviation-regexp
              (and in-force
                   ;; At the start of the line, or after a non-word
                   ;; character: "e.g." is an abbreviation, "Xe.g." is not.
                   (concat "\\(?:^\\|\\W\\)"
                           (regexp-opt
                            (garamond--with-sentence-initial-capitals in-force))))))))
  garamond--abbreviation-regexp)

(defun garamond--abbreviation-p (pos)
  "Return non-nil when the text ending at POS is an abbreviation in force.
Case matters, as `garamond-abbreviations' explains: a lower-case entry
also counts capitalised, a capitalised one only as given."
  (let ((regexp (garamond--abbreviation-regexp)))
    (and regexp
         (save-excursion
           (goto-char pos)
           (let ((case-fold-search nil))
             (looking-back regexp
                           (max (line-beginning-position)
                                (- pos garamond--abbreviation-reach))))))))


;;; ---------------------------------------------------------------------------
;;; WHAT IS WRITTEN, AND WHAT IS ONLY LAID OUT
;;; ---------------------------------------------------------------------------

;; This is the one judgement the package makes without being asked, and it
;; is made per position rather than per mode: inside a buffer that has
;; declared itself double spaced, a second space still has no business in
;; a source block, a table column or a link target.

(declare-function org-at-table-p "org-table" (&optional table-type))
(declare-function org-element-context "org-element" (&optional element))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function org-element-property "org-element-ast" (property node &optional dflt force-undefer))
(declare-function org-element-parse-buffer "org-element" (&optional granularity visible-only keep-deferred))
(declare-function org-element-map "org-element" (data types fun &optional info first-match no-recursion with-affiliated no-undefer))
(declare-function markdown-code-block-at-point-p "markdown-mode" (&optional pos))
(declare-function markdown-inline-code-at-point-p "markdown-mode" ())
(declare-function markdown-link-p "markdown-mode" ())
(declare-function texmathp "texmathp" ())
(declare-function LaTeX-verbatim-p "latex" (&optional face))

(defconst garamond--org-verbatim-types
  '(src-block example-block export-block comment-block fixed-width
    table table-row table-cell
    link code verbatim inline-src-block
    latex-fragment latex-environment macro
    citation citation-reference footnote-reference timestamp
    keyword node-property property-drawer)
  "Org constructs that are laid out or read verbatim rather than written.
A second space inside one of these is at best cosmetic and at worst an
error: code in a source block, a path in a link, the columns of a table.")

(defvar-local garamond--block-scan nil
  "How far the block scan has got, as (POS . OPEN), or nil to start over.
OPEN is the block the lines above POS leave open: for Org the name after
#+begin_, for Markdown the fence as (CHAR . LENGTH), or nil when every
block above is closed.  Position POS is a line beginning.

The scan is what makes a keystroke cheap in a large file.  Counting the
delimiters above point from the top costs a millisecond or two per
megabyte, and the earlier versions did it on every space typed; carrying
the answer forward costs the lines typed since.")

(defun garamond--block-scan-forget (beg &rest _)
  "Forget the block scan when a change at BEG lies above where it reached.
On `after-change-functions' while `garamond-mode' is on.  Typing at the
end of a file, which is how prose mostly grows, touches nothing above
the scan and keeps it; an edit higher up throws it away, and the next
keystroke rebuilds it from the top."
  (when (and garamond--block-scan (< beg (car garamond--block-scan)))
    (setq garamond--block-scan nil)))

(defconst garamond--org-block-regexp
  "^\\(?:\\*+ \\|[ \t]*#\\+\\(begin\\|end\\)_\\([^ \t\n]+\\)\\)"
  "A headline, or a block delimiter: group 1 begin or end, group 2 its name.
Headlines are matched because no Org block survives one; the parser ends
the enclosing section there, delimiter or no delimiter.")

(defconst garamond--markdown-fence-regexp
  "^ \\{0,3\\}\\(`\\{3,\\}\\|~\\{3,\\}\\)"
  "A code fence, indented by up to three spaces as CommonMark allows.")

(defconst garamond--org-verbatim-blocks '("src" "example" "export" "comment")
  "Org blocks whose contents are not prose.
A quote or verse block is prose and is spaced like it; these are code,
or copied through untouched, and a second space in them is an error.")

(defun garamond--org-block-step (open)
  "Return the block open after the delimiter just matched, OPEN being open before.
A headline closes whatever was open.  A begin opens a block only when none
is open, and an end closes only the block of the same name, so that a
delimiter quoted inside an example block is taken as content."
  (let ((kind (match-string 1))
        (name (and (match-beginning 2) (downcase (match-string 2)))))
    (cond ((null kind) nil)
          ;; Ignoring case, like the search that found it: #+BEGIN_SRC.
          ((string-prefix-p "begin" kind t) (or open name))
          ((equal open name) nil)
          (t open))))

(defun garamond--markdown-fence-step (open)
  "Return the fence open after the fence just matched, OPEN being open before.
A fence closes a block only when it is of the same character and at least
as long as the one that opened it, as CommonMark has it; any other fence
inside a block is content."
  (let* ((fence (match-string 1))
         (char (aref fence 0))
         (length (length fence)))
    (cond ((null open) (cons char length))
          ((and (eq char (car open)) (>= length (cdr open))) nil)
          (t open))))

(defun garamond--block-open-above (regexp step)
  "Return the block the lines above point leave open, scanning incrementally.
REGEXP finds delimiters; STEP is called at each with the match data set
and the block open so far, and returns the block open after it.  The
scan resumes from `garamond--block-scan' when that lies at or above the
current line, and from the top otherwise."
  (save-excursion
    (save-restriction
      ;; Blocks are a property of the whole buffer, not of the part in
      ;; view; a narrowed scan would cache answers a widened one denies,
      ;; and a line beginning taken inside the narrowing might not be one.
      (widen)
      (let* ((bol (line-beginning-position))
             (scan garamond--block-scan)
             (resume (and scan (<= (car scan) bol)))
             (open (and resume (cdr scan))))
        (save-match-data
          (goto-char (if resume (car scan) (point-min)))
          (let ((case-fold-search t))
            (while (re-search-forward regexp bol t)
              (setq open (funcall step open)))))
        (setq garamond--block-scan (cons bol open))
        open))))

(defun garamond--in-verbatim-block-p ()
  "Non-nil when point is inside a code block, whether or not it is closed yet.
The scan is what lets the typing hook see a block whose end has not been
typed: the mode parsers see complete syntax only, and Org reads an
unfinished src block as a paragraph.  It also answers before they are
asked, which spares `org-element-context' inside every closed block."
  (cond ((derived-mode-p 'org-mode)
         (member (garamond--block-open-above garamond--org-block-regexp
                                             #'garamond--org-block-step)
                 garamond--org-verbatim-blocks))
        ((derived-mode-p 'markdown-mode)
         (garamond--block-open-above garamond--markdown-fence-regexp
                                     #'garamond--markdown-fence-step))))

(defun garamond--half-typed-p ()
  "Non-nil when point sits inside an inline construct that is not finished.
The mode predicates parse complete syntax, so while a link or a code
span is still being typed they see nothing, and the typing hook would
happily double a space inside a path.  Each check is local to the line
and costs well under a microsecond."
  (cond
   ((derived-mode-p 'org-mode)
    ;; A link target under construction: [[... with no closing bracket.
    (looking-back "\\[\\[[^]\n]*" (line-beginning-position)))
   ((derived-mode-p 'markdown-mode)
    (or
     ;; The URL half of a link: ]( with no closing parenthesis yet.
     (looking-back "\\]([^)\n]*" (line-beginning-position))
     ;; An inline code span still open: an odd number of backticks
     ;; between the start of the line and point.
     (let ((ticks 0)
           (bol (line-beginning-position))
           (pos (point)))
       (save-excursion
         (goto-char bol)
         (while (search-forward "`" pos t) (setq ticks (1+ ticks))))
       (= 1 (mod ticks 2)))))))

(defun garamond--org-verbatim-ranges ()
  "Return the stretches of this Org buffer that are laid out rather than written.
A list of (START . END), sorted by START, one for each construct of
`garamond--org-verbatim-types' in the whole buffer, from a single parse.
END is the construct\\='s own end, trailing whitespace included, which is
also where `org-element-context' stops calling a position part of it.

One parse of a megabyte takes a sixth of a second; asking
`org-element-context' at every sentence break instead costs more in
total, and its cost grows with the length of the paragraph, since it
reads the paragraph from its start each time."
  (let (ranges)
    (org-element-map (org-element-parse-buffer) garamond--org-verbatim-types
      (lambda (node)
        (push (cons (org-element-property :begin node)
                    (org-element-property :end node))
              ranges)))
    (sort ranges #'car-less-than-car)))

(defun garamond--in-ranges-predicate (ranges)
  "Return a function saying whether a position lies within one of RANGES.
RANGES is a list of (START . END) sorted by START, and the function is
to be called with positions that never decrease, which lets it drop the
ranges it has passed and look no further than the ranges that start
before the position it is given."
  (lambda (pos)
    (while (and ranges (<= (cdr (car ranges)) pos))
      (setq ranges (cdr ranges)))
    (let ((rest ranges) (found nil))
      (while (and rest (not found) (<= (car (car rest)) pos))
        (when (< pos (cdr (car rest))) (setq found t))
        (setq rest (cdr rest)))
      found)))

(defun garamond--verbatim-predicate ()
  "Return the function `garamond-adjust-spacing' asks at each sentence break.
For a pass over a whole buffer or region that is `garamond--verbatim-p'
except in Org, where the parser\\='s part of the question is answered from
one parse of the buffer rather than a call per break.  The block scan and
the line-local checks stay: the parse reads an unfinished block as a
paragraph and cannot see a link still being typed."
  (if (derived-mode-p 'org-mode)
      (let ((in-range (garamond--in-ranges-predicate (garamond--org-verbatim-ranges))))
        (lambda ()
          (or (garamond--in-verbatim-block-p)
              (funcall in-range (point))
              (garamond--half-typed-p))))
    #'garamond--verbatim-p))

(defun garamond--verbatim-p ()
  "Non-nil when point is in text that is laid out rather than written.
Blocks are settled first by the incremental scan, which is cheap and
sees unfinished ones.  Then Org is asked `org-element-context' about
what surrounds point, compared with `garamond--org-verbatim-types': the
single call covers tables, links and inline code alike, through Org\\='s
element cache.  It costs a tenth of a millisecond or so in a paragraph
of ordinary length, and grows with the paragraph, which Org reads from
its start each time; a whole pass uses `garamond--verbatim-predicate'
instead, which parses once.
Markdown contributes its inline code and links, LaTeX its maths and
verbatim environments, and any buffer its `orgtbl-mode' tables.  Last
come the line-local checks for constructs still being typed."
  ;; `org-element-context' and friends search, and so clobber the match
  ;; data that `garamond-adjust-spacing' is midway through using.
  (save-match-data
    (or
     (garamond--in-verbatim-block-p)
     (garamond--parsers-say-verbatim-p)
     (garamond--half-typed-p))))

(defun garamond--parsers-say-verbatim-p ()
  "Ask the major mode\\='s own parser whether point is in laid-out text.
Split out of `garamond--verbatim-p' so that the one part of the question
answered by other packages can be fenced: an error from `org-element' or
`markdown-mode' mid-keystroke would otherwise abort `self-insert-command'
on every space, and a typing hook that can break typing is worse than
one that occasionally stays its hand.  On an error the answer is taken
to be verbatim -- the change that cannot be wrong is no change -- and
the error is shown."
  (condition-case err
      (cond ((derived-mode-p 'org-mode)
            (and (fboundp 'org-element-context)
                 (memq (org-element-type (org-element-context))
                       garamond--org-verbatim-types)))
           ((derived-mode-p 'markdown-mode)
            (or (and (fboundp 'markdown-code-block-at-point-p)
                     (markdown-code-block-at-point-p))
                (and (fboundp 'markdown-inline-code-at-point-p)
                     (markdown-inline-code-at-point-p))
                ;; True inside the description as well as the path; the
                ;; description is harmless, the path is not.
                (and (fboundp 'markdown-link-p) (markdown-link-p))))
           ;; Two calls, not one with a list: the list form of
           ;; `derived-mode-p' is Emacs 30, and this runs on 29.
           ((or (derived-mode-p 'TeX-mode) (derived-mode-p 'tex-mode))
            (or (and (fboundp 'texmathp) (texmathp))
                (and (fboundp 'LaTeX-verbatim-p) (LaTeX-verbatim-p))))
           ((bound-and-true-p orgtbl-mode)
            (and (fboundp 'org-at-table-p) (org-at-table-p))))
    (error
     (message "garamond: %s; leaving this space alone" (error-message-string err))
     t)))

(defconst garamond--closers "]\"'”’)}»›"
  "Characters that may close a sentence after its punctuation.
A `skip-chars-backward' set; the same characters appear as a class in
`garamond--sentence-end-regexp'.")

(defun garamond--after-sentence-end-p ()
  "Non-nil when the text before point ends a sentence, moving to its punctuation.
A sentence ends in a letter, one of .?!…‽, and any closing quotes or
brackets.  On success point is left just after the punctuation, before
the closers, where `garamond--abbreviation-p' wants it; on failure point
is wherever the closers, if any, began.  Call it inside `save-excursion'.

Constant time, whatever the length of the line.  The `looking-back' this
replaces searched backward through the whole line for a match it could
not find -- the usual case, a space between words -- which on the
paragraph-long lines of `visual-line-mode' cost hundreds of microseconds
per space typed."
  (skip-chars-backward garamond--closers)
  (and (memq (char-before) '(?. ?? ?! ?… ?‽))
       ;; Room for a letter before the punctuation, and it is a letter:
       ;; this is what rules out list numbering ("1. ") and decimals.
       (>= (- (point) 2) (point-min))
       (save-excursion (backward-char 2) (looking-at-p "[[:alpha:]]"))))

(defconst garamond--sentence-end-regexp
  "[.?!…‽][]\"'”’)}»›]*\\( +\\)[^ \t\n]"
  "A sentence break: punctuation, any closers, the gap, and what follows.
The punctuation and closers match `sentence-end-base', so a break this
finds is one the stock sentence commands also see.  Group 1 is the run of
spaces, which is what gets rewritten.")

(defun garamond--enumerator-p ()
  "Non-nil when the period before point is a list number rather than a stop.
Point is just after the punctuation, where the rewrite leaves it once it
has stepped back over any closers.  An ordered list in Org or Markdown
opens its line with \"1.\", and doubling the space there widens the list
rather than the prose.  Only digits count: a single letter and a period
opens a lettered list, but it is far more often an initial -- \"A. Smith\"
-- or a one-letter sentence, and those are prose.

`looking-at' would otherwise overwrite the match data that
`garamond-adjust-spacing' is midway through using."
  (save-match-data
    (save-excursion
      (let ((punct (point)))
        (beginning-of-line)
        (and (looking-at "[ \t]*[0-9]+\\.")
             (= (match-end 0) punct))))))


;;; ---------------------------------------------------------------------------
;;; DECLARING WHAT A BUFFER USES
;;; ---------------------------------------------------------------------------

(defcustom garamond-persist t
  "Whether the spacing commands offer to record their choice in the file.
When non-nil they ask, once a whole buffer visiting a file is involved,
whether to write `sentence-end-double-space' into it as a file-local
variable -- which is how the document comes to carry its own spacing
rather than depend on whose Emacs opens it.  The question is never asked
when only a region was adjusted, since a region says nothing about the
rest of the file, and nil suppresses it everywhere, leaving just the
buffer-local setting."
  :type 'boolean
  :group 'garamond)

(defun garamond-declared-p (&optional buffer)
  "Non-nil when BUFFER's file declared `sentence-end-double-space' itself.
BUFFER defaults to the current one.  This is what the package acts on,
rather than the variable's value: Emacs sets it to t globally, so the
value says only what Emacs assumes, while `file-local-variables-alist'
holds what this file -- or a .dir-locals.el above it -- actually said."
  (with-current-buffer (or buffer (current-buffer))
    (and (assq 'sentence-end-double-space file-local-variables-alist) t)))

(defun garamond--declared-in-file-p ()
  "Non-nil when the declaration is in this file\\='s own text.
`garamond-declared-p' also counts a .dir-locals.el speaking for the
file, which is right for following it and wrong for updating it: a
directory-wide choice should not be turned into a block inside one
file without asking.  A file that has the variable and is not under a
directory that sets it too has it in its own text."
  (and (garamond-declared-p)
       (not (assq 'sentence-end-double-space dir-local-variables-alist))))

(defun garamond--read-spacing (whole-buffer)
  "Read a spacing, and whether to record it, for an interactive command.
WHOLE-BUFFER says that the command is about the entire buffer, which is
what makes recording it in the file meaningful.  A numeric prefix
argument gives the spacing without a question; otherwise it is read in
the minibuffer, defaulting to what the buffer uses now."
  (list (if current-prefix-arg
            (prefix-numeric-value current-prefix-arg)
          (read-number "Spaces between sentences: "
                       (if sentence-end-double-space 2 1)))
        (and whole-buffer
             buffer-file-name
             (or
              ;; Declared in the file itself: update it rather than let
              ;; it lie.  Declared by a .dir-locals.el: ask, as for any
              ;; other file -- the directory\\='s word is not this file\\='s.
              (garamond--declared-in-file-p)
              (and garamond-persist
                   (y-or-n-p "Record this spacing in the file? "))))))

(defun garamond--declare (spaces persist)
  "Make this buffer a buffer of SPACES spaces between sentences.
`sentence-end-double-space' is set buffer-locally, so that the fill and
sentence commands agree with the text, and `garamond-mode' is switched
on, so that what you type agrees with it too and the mode line says which
spacing is in force -- unless the buffer is one the mode refuses, in
which case the variable is still set and the report says why the typing
is not.  With PERSIST the value is written into the file as a local
variable; the buffer is left modified, not saved.  Returns how the
command\\='s message should end."
  ;; Anything that can refuse, refuses before anything changes: a
  ;; read-only buffer must not end up declared in memory and not on disk.
  (when (and persist buffer-file-name)
    (barf-if-buffer-read-only))
  (setq-local sentence-end-double-space (= spaces 2))
  ;; On for either spacing: at one space the typing hook is dormant, but
  ;; the mode line then says so -- `1S' means declared and quiet, while
  ;; no lighter at all means nobody has said anything about this buffer.
  ;; Unless the buffer is one the mode refuses, in which case the
  ;; variable is still set -- filling and sentence motion want it -- and
  ;; the report says why the typing is not.
  (let ((refused (garamond--unsuitable-reason)))
    (unless refused (garamond-mode 1))
    (concat
     (if refused (format "; the typing stays off, %s" refused) "")
     (garamond--record spaces persist))))

(defun garamond--record (spaces persist)
  "Write SPACES into the file if PERSIST, returning how the message should end."
  (cond ((not (and persist buffer-file-name)) "")
        ;; `add-file-local-variable' would only print a message and do
        ;; nothing; say so rather than claim a record that was not made.
        ((not enable-local-variables)
         "; not recorded, file-local variables being disabled")
        (t
         (save-excursion
           (save-restriction
             (add-file-local-variable 'sentence-end-double-space (= spaces 2))))
         ;; Record it as declared, so a later call updates it silently.
         (setf (alist-get 'sentence-end-double-space file-local-variables-alist)
               (= spaces 2))
         "; recorded in the file")))

;;;###autoload
(defun garamond-set-spacing (spaces &optional persist)
  "Declare SPACES spaces between the sentences of this buffer.
SPACES is 1 or 2.  Not a character of the buffer is touched: this only
declares what is already true, which is what you want for a document that
arrived with its own convention -- `sentence-end-double-space' is set
buffer-locally so that filling and sentence motion agree with the text,
and `garamond-mode' is switched on so that what you type next agrees with
it as well -- dormant at one space, and refused, with the reason given,
in a buffer nobody types in.

With optional PERSIST, or interactively when the file does not say yet
and `garamond-persist' allows the question, the value is also written
into the file as a local variable, so that the document carries its own
spacing from then on; the buffer is left modified, not saved.

Interactively SPACES comes from a numeric prefix argument, so
\\[universal-argument] 2 declares double spacing outright; without one it
is read in the minibuffer.  Use \\[garamond-adjust-spacing] instead when
the text needs changing to match."
  (interactive (garamond--read-spacing t))
  (unless (memq spaces '(1 2))
    (user-error "Sentence spacing must be 1 or 2, not %s" spaces))
  (let ((recorded (garamond--declare spaces persist)))
    (message "This buffer uses %d space%s between sentences%s"
             spaces (if (= spaces 1) "" "s") recorded)))

;;;###autoload
(defun garamond-adjust-spacing (beg end spaces &optional persist)
  "Put SPACES spaces after every sentence end between BEG and END.
SPACES is 1 or 2, and the whole stretch is made uniform: each run of
spaces that follows sentence-ending punctuation -- a period, question
mark, exclamation mark, ellipsis or interrobang, plus any closing
quotes or brackets -- becomes exactly that many.  The punctuation and
closers match `sentence-end-base', so a break this rewrites is one the
stock sentence commands also see.  Line breaks, indentation and
trailing whitespace are left alone, as is anything `garamond--verbatim-p'
recognises as laid out rather than written -- source blocks, tables,
link paths and the like -- since a second space there is an error, not a
style.  The period that opens an ordered list item is left alone too.

Interactively BEG and END are the region, or the whole buffer when no
region is active, and SPACES comes from a numeric prefix argument, so
\\[universal-argument] 1 gives single spacing; without one it is read in
the minibuffer, defaulting to what the buffer uses now.

The buffer is then declared to use that spacing, exactly as
\\\[garamond-set-spacing] would: `sentence-end-double-space' is set
buffer-locally -- otherwise the next \\[fill-paragraph] would put the old
spacing straight back -- and `garamond-mode' is switched on.

Optional PERSIST additionally writes the value into the file as a local
variable, so the choice survives reopening; the buffer is left modified,
not saved.  Interactively it is asked about only when the whole buffer
was adjusted and `garamond-persist' is non-nil -- with an active region
nothing is asked and nothing is written to the file.  A file that already
declares `sentence-end-double-space' is kept accurate without asking, so
its local variable never contradicts its text."
  (interactive
   (let* ((region (use-region-p))
          (beg (if region (region-beginning) (point-min)))
          (end (if region (region-end) (point-max))))
     (cons beg (cons end (garamond--read-spacing (not region))))))
  (unless (memq spaces '(1 2))
    (user-error "Sentence spacing must be 1 or 2, not %s" spaces))
  ;; Refuse before any work is done, not at the first replacement.
  (barf-if-buffer-read-only)
  (when (> beg end)
    (setq beg (prog1 end (setq end beg))))
  ;; The mode, and with it the hook that keeps the block scan honest, may
  ;; have been off while this buffer was edited; start the scan over.  It
  ;; then moves forward with the pass, so the whole pass stays linear.
  (setq garamond--block-scan nil)
  (let ((replacement (make-string spaces ?\s))
        (verbatim-p (garamond--verbatim-predicate))
        (gaps nil))
    ;; Two passes.  The first only reads: it finds every gap to change and
    ;; leaves the buffer as it was, so the parsers are never asked about
    ;; text that was edited a moment ago -- for Org that edit would
    ;; invalidate the element cache and cost a re-sync at every break.
    ;; The second replaces, last gap first, so that the positions found
    ;; stay true as the earlier text is untouched by later replacements.
    (save-excursion
      (goto-char beg)
      (while (re-search-forward garamond--sentence-end-regexp end t)
        (let ((gap-start (match-beginning 1))
              (gap-end (match-end 1)))
          ;; Resume inside the gap, so back-to-back sentences are all seen.
          (goto-char gap-end)
          (unless (or (= (- gap-end gap-start) spaces)
                      (save-excursion
                        (goto-char gap-start)
                        (save-match-data
                          (or (funcall verbatim-p)
                              (progn (skip-chars-backward garamond--closers)
                                     (garamond--enumerator-p))))))
            (push (cons gap-start gap-end) gaps))))
      (dolist (gap gaps)
        (goto-char (car gap))
        (delete-region (car gap) (cdr gap))
        (insert replacement)))
    (let ((changed (length gaps))
          (recorded (garamond--declare spaces persist)))
      (message "Set %d sentence break%s to %d space%s%s"
               changed (if (= changed 1) "" "s")
               spaces (if (= spaces 1) "" "s")
               recorded))))


;;; ---------------------------------------------------------------------------
;;; THE TYPING
;;; ---------------------------------------------------------------------------

(defcustom garamond-double-space-on-typing t
  "Whether `garamond-mode' doubles the space as you type it.
Set this to nil in a configuration file to keep everything else -- the
spacing commands, the file-local bookkeeping, a declared file still
setting `sentence-end-double-space' so that filling behaves -- while
never having a second space appear under your hands.  It is read afresh
at each keystroke, so a keybinding can flip it mid-sentence and the mode
need not be cycled.

It says nothing about how any document is spaced, which is why it is
allowed to be a global."
  :type 'boolean
  :group 'garamond)

(defcustom garamond-lighter t
  "Whether `garamond-mode' puts its own indicator in the mode line.
Set this to nil to place the indicator yourself, or to be rid of it.
`garamond-mode-line-string' is what to place: a function returning \"2S\",
\"1S\", their bracketed forms, or the empty string in a buffer the mode is
not on in.  Either add the ready-made construct

  (add-to-list \\='global-mode-string garamond-mode-line-format t)

or write it into a mode line of your own, which is what a configuration
that hides minor mode lighters altogether will want:

  (:eval (garamond-mode-line-string))

Leaving this at t and adding it by hand as well shows it twice."
  :type 'boolean
  :group 'garamond)

;; Defined below, by `define-minor-mode'; named here because the mode line
;; has to ask whether the mode is on, and it is built one section earlier.
(defvar garamond-mode)

(defun garamond--mode-line-entry (text echo)
  "Return TEXT twice over, bare and padded, both carrying the tooltip ECHO.
The mode line is rebuilt on every redisplay, so both forms are made here,
once, rather than a fresh string being consed each frame.  The padded one
goes in the minor mode lighter, which is expected to bring its own
leading space; the bare one is for placing by hand, where a stray space
is the caller's business and not this package's."
  (cons (propertize text 'help-echo echo)
        ;; Propertized whole, leading space included, so that the tooltip
        ;; answers to the whole of what the mode line shows.
        (propertize (concat " " text) 'help-echo echo)))

(defconst garamond--mode-line-double
  (garamond--mode-line-entry
   "2S" "Two spaces between sentences; typing one gives two")
  "Shown while this buffer is double spaced and the typing is live.")

(defconst garamond--mode-line-single
  (garamond--mode-line-entry
   "1S" "One space between sentences; the typing is dormant")
  "Shown while this buffer is single spaced, which leaves the typing idle.")

(defconst garamond--mode-line-double-muted
  (garamond--mode-line-entry
   "(2S)" "Two spaces between sentences; typing muted by \
garamond-double-space-on-typing")
  "Shown while the buffer is double spaced but the typing is switched off.")

(defconst garamond--mode-line-single-muted
  (garamond--mode-line-entry
   "(1S)" "One space between sentences; typing muted by \
garamond-double-space-on-typing")
  "Shown while the buffer is single spaced and the typing is switched off.")

(defun garamond--mode-line-entry-for-buffer ()
  "Return the (BARE . PADDED) pair describing how this buffer is spaced."
  (cond ((not garamond-double-space-on-typing)
         (if sentence-end-double-space
             garamond--mode-line-double-muted
           garamond--mode-line-single-muted))
        (sentence-end-double-space garamond--mode-line-double)
        (t garamond--mode-line-single)))

;;;###autoload
(defun garamond-mode-line-string ()
  "Return this buffer\\='s spacing as a string, for a mode line of your own.
\"2S\" or \"1S\", bracketed while `garamond-double-space-on-typing' is nil,
and the empty string wherever `garamond-mode' is off -- which reads as
nobody having said anything about that buffer.  The string carries a
tooltip, and is one of four made at load, so calling this on every
redisplay costs nothing.

Set `garamond-lighter' to nil before placing it, or the mode will show
its own indicator as well.  See `garamond-mode-line-format' for the
construct to add to `global-mode-string'."
  (if garamond-mode (car (garamond--mode-line-entry-for-buffer)) ""))

;;;###autoload
(defconst garamond-mode-line-format '(:eval (garamond-mode-line-string))
  "A mode-line construct showing which spacing the current buffer uses.
For adding the indicator by hand, once `garamond-lighter' is nil:

  (add-to-list \\='global-mode-string garamond-mode-line-format t)

It is safe anywhere, buffers garamond has nothing to do with included:
there it evaluates to the empty string.")

(defun garamond--lighter ()
  "Return the mode line lighter, or nil while `garamond-lighter' is nil.
Evaluated only while the mode is on, `minor-mode-alist' seeing to that."
  (and garamond-lighter
       (cdr (garamond--mode-line-entry-for-buffer))))

(defcustom garamond-unsuitable-modes
  '(special-mode dired-mode comint-mode term-mode eshell-mode vterm-mode)
  "Major modes in whose buffers nobody writes prose, derived modes included.
`garamond-mode' refuses to switch on in them, as it does in any read-only
buffer and in the minibuffer, whatever asked for it -- a declaration in
a .dir-locals.el for all modes, or a hand on \\[garamond-mode].  Dired and
the `special-mode' family are read-only in any case; the shells are here
because a space typed at a prompt is a command\\='s business, not prose.

This is a guard against the absurd, not a list of where prose is
written: a `conf-mode' or `prog-mode' buffer is not here, and switching
the mode on in one by hand is taken at its word."
  :type '(repeat symbol)
  :group 'garamond)

(defun garamond--unsuitable-reason ()
  "Return why `garamond-mode' cannot run in this buffer, or nil when it can."
  (cond ((minibufferp) "this is the minibuffer")
        (buffer-read-only "the buffer is read-only")
        ;; One mode per call: the several-modes form of `derived-mode-p'
        ;; is deprecated in Emacs 30 and the list form new there.
        ((seq-some #'derived-mode-p garamond-unsuitable-modes)
         (format "nobody writes prose in %s" major-mode))))

(defun garamond--maybe-double-space ()
  "Make the run of spaces just typed after a sentence end exactly two.
One space becomes two; a longer run typed by hand is trimmed back, so the
result does not depend on how many times the key was pressed.

Does nothing while `garamond-double-space-on-typing' is nil.  On any key
but the space bar it costs one comparison; on a space between words, a
look at the two characters before it, whatever the length of the line;
only a space after a sentence end goes on to ask what the text around it
is."
  (when (and (eq last-command-event ?\s)
             garamond-double-space-on-typing
             sentence-end-double-space
             (not (minibufferp))
             ;; A space typed over a character is meant to replace it,
             ;; not to shift the rest of the line along by one.
             (not overwrite-mode))
    (let* ((end (point))
           (run-start (save-excursion (skip-chars-backward " ") (point))))
      ;; The cheap question first: most spaces fall between words, and
      ;; only one after a sentence end is worth asking the parsers about.
      (when (and (save-excursion
                   (goto-char run-start)
                   (and (garamond--after-sentence-end-p)
                        ;; Point is now just after the punctuation, so
                        ;; "(e.g.)" is still e.g.
                        (not (garamond--abbreviation-p (point)))))
                 (not (garamond--verbatim-p)))
        (let ((spaces (- end run-start)))
          (cond ((= spaces 1) (insert " "))
                ((> spaces 2) (delete-region (+ run-start 2) end))))))))

;;;###autoload
(define-minor-mode garamond-mode
  "Type one space after a sentence end and get two.

Buffer-local, and switched on for you in three ways: by
\\\[garamond-set-spacing] or \\[garamond-adjust-spacing] declaring this
buffer double spaced, by `garamond-follow-declarations-mode' when a file
that declares itself is opened, or by `mode: garamond' in a file's first
line.  Turning it on by hand is taken at its word in any buffer prose
could be written in; it refuses, saying why, in a read-only buffer, the
minibuffer, and the modes in `garamond-unsuitable-modes', where a typing
mode has nothing to do.

Does nothing while `sentence-end-double-space' is nil, so a buffer
declared single spaced leaves it dormant, and nothing while
`garamond-double-space-on-typing' is nil, which is the switch to reach
for in a configuration file.

The lighter says which spacing is in force: `2S' or `1S', bracketed as
`(2S)' while the typing is muted.  No lighter at all means the mode is
off, and so that nothing has declared this buffer either way.  To put
that indicator somewhere else in the mode line, set `garamond-lighter' to
nil and place `garamond-mode-line-format' yourself."
  :lighter (:eval (garamond--lighter))
  :group 'garamond
  (let ((refused (and garamond-mode (garamond--unsuitable-reason))))
    (when refused
      (setq garamond-mode nil))
    (setq garamond--block-scan nil)
    (if garamond-mode
        (progn
          (add-hook 'post-self-insert-hook #'garamond--maybe-double-space -10 t)
          (add-hook 'after-change-functions #'garamond--block-scan-forget nil t))
      (remove-hook 'post-self-insert-hook #'garamond--maybe-double-space t)
      (remove-hook 'after-change-functions #'garamond--block-scan-forget t))
    ;; Last, once the hooks agree with the variable: a refusal by hand is
    ;; an error, one from Lisp a message, so that a declaration reaching a
    ;; buffer that cannot take it does not abort whatever brought it.
    (when refused
      (if (called-interactively-p 'any)
          (user-error "Garamond will not run here: %s" refused)
        (message "garamond: not switched on, %s" refused)))))


;;; ---------------------------------------------------------------------------
;;; LETTING A FILE SPEAK FOR ITSELF
;;; ---------------------------------------------------------------------------

(defun garamond--heed-declaration ()
  "Switch `garamond-mode' on when this file declared its own spacing.
Run from `hack-local-variables-hook', where the file's own variables have
just been applied and `file-local-variables-alist' says which of them
came from the file.  The mode goes on for either spacing -- at one space
it is dormant, and its lighter says `1S' -- so that the mode line tells
declared apart from unspoken.  A file that says nothing is left alone:
that, and not the value of `sentence-end-double-space', is the whole
difference between following the document and following a global."
  ;; A file reverted or reloaded has been rewritten under the scan.
  (setq garamond--block-scan nil)
  (when (garamond-declared-p)
    ;; Quietly: a .dir-locals.el entry for all modes reaches Dired and
    ;; the like too, and the mode would only say so.  A read-only file
    ;; is caught up with when it is made writable, by
    ;; `garamond--heed-read-only-toggle'.
    (garamond-mode (if (garamond--unsuitable-reason) -1 1))))

(defun garamond--heed-read-only-toggle ()
  "Bring `garamond-mode' into line after `read-only-mode' was toggled.
On `read-only-mode-hook'.  A declared file opened read-only gets the
typing the moment \\[read-only-mode] makes it writable, and loses it
again when it is made read-only; a buffer that declared nothing is not
touched either way."
  (when (garamond-declared-p)
    (garamond-mode (if (garamond--unsuitable-reason) -1 1))))

;;;###autoload
(define-minor-mode garamond-follow-declarations-mode
  "Let files that declare their sentence spacing switch `garamond-mode' on.
This is the one line of setup the package asks for, and the only thing in
it that is global -- not a spacing, but a willingness to read the ones
documents state:

  (garamond-follow-declarations-mode 1)

A file declares itself in its own local variables block, by setting
`sentence-end-double-space' there; a whole repository declares itself at
once in a .dir-locals.el:

  ((org-mode . ((sentence-end-double-space . t))))

See the Commentary at the top of garamond.el for the file-local form,
which cannot be spelled out here: a literal local variables block this
near the end of the file is one Emacs would try to apply to garamond.el
itself.

Files that declare nothing are untouched, whatever mode they are in.  Use
\\\[garamond-set-spacing] to write the declaration into a document that
does not have one yet."
  :global t
  :group 'garamond
  (if garamond-follow-declarations-mode
      (progn
        (add-hook 'hack-local-variables-hook #'garamond--heed-declaration)
        (add-hook 'read-only-mode-hook #'garamond--heed-read-only-toggle))
    (remove-hook 'hack-local-variables-hook #'garamond--heed-declaration)
    (remove-hook 'read-only-mode-hook #'garamond--heed-read-only-toggle)))

;;; ---------------------------------------------------------------------------
;;; WHY NOTHING IS HAPPENING
;;; ---------------------------------------------------------------------------

(declare-function lm-header "lisp-mnt" (header))

(defun garamond--version ()
  "Return the version in garamond.el\\='s own header, or nil if unreadable.
Read rather than recorded, so that it cannot drift from the header."
  (require 'lisp-mnt)
  (let* ((loaded (symbol-file 'garamond-mode 'defun))
         ;; The copy that was loaded, its source if it was the compiled
         ;; file; `locate-library' would find whichever comes first on
         ;; the load path, which need not be the one running.
         (file (or (and loaded
                        (let ((el (replace-regexp-in-string "\\.elc\\'" ".el" loaded)))
                          (and (file-readable-p el) el)))
                   (locate-library "garamond.el"))))
    (and file
         (with-temp-buffer
           (insert-file-contents file)
           (lm-header "version")))))

(defun garamond--mode-line-shows-lighter ()
  "Say whether this buffer\\='s mode line actually displays the indicator.
Returns `yes', `no', `none' when the buffer has no mode line at all, or
`unknown' when there is nothing to show or no window to render against,
as under --batch, where `format-mode-line' is empty for everything and
so proves nothing."
  (let ((rendered (format-mode-line mode-line-format))
        (wanted (garamond-mode-line-string)))
    (cond ((null mode-line-format) 'none)
          ((or (string= "" rendered) (string= "" wanted)) 'unknown)
          ((string-match-p (regexp-quote wanted) rendered) 'yes)
          (t 'no))))

(defun garamond--diagnosis (&optional shown)
  "Return the likeliest reason the indicator is not showing, as a string.
Ordered as the causes actually occur: a buffer nobody has spoken for
first, a mode line that hides minor modes last.  SHOWN is what
`garamond--mode-line-shows-lighter' said, if the caller already asked;
rendering a heavy mode line is not free, and it is asked once."
  (let ((shown (or shown (garamond--mode-line-shows-lighter))))
    (garamond--diagnosis-1 shown)))

(defun garamond--diagnosis-1 (shown)
  "The cases of `garamond--diagnosis', given SHOWN from the mode line."
  (cond
   ((not garamond-mode)
    (cond
     ((and (garamond-declared-p) (garamond--unsuitable-reason))
      (format "This buffer is declared, but `garamond-mode' will not run here: %s.  \
Nothing is wrong; there is nothing for a typing mode to do."
              (garamond--unsuitable-reason)))
     ((and (not (garamond-declared-p)) (not buffer-file-name))
      "This buffer visits no file and has not been declared.  Use \\[garamond-set-spacing] to declare it here and now.")
     ((not (garamond-declared-p))
      "Nothing has declared this buffer, so garamond is doing nothing in it -- which is the design, not a fault.  Use \\[garamond-set-spacing] to say what it uses; the choice is written into the file, and the indicator appears at once.")
     ((not (memq #'garamond--heed-declaration hack-local-variables-hook))
      (if garamond-follow-declarations-mode
          "The file declares its spacing, and `garamond-follow-declarations-mode' reads as on, but its hook is not installed: the variable was set with `setq' rather than the mode switched on.  Call (garamond-follow-declarations-mode 1) instead, then revert this buffer."
        "The file declares its spacing, but `garamond-follow-declarations-mode' is off, so nothing read that declaration.  Switch it on in your configuration, then revert this buffer."))
     (t
      "The file declares its spacing and the mode is off all the same, which means the file was opened before `garamond-follow-declarations-mode' was switched on.  Reverting the buffer will settle it.")))
   ((not garamond-lighter)
    "The mode is on, and `garamond-lighter' is nil, so it shows nothing of its own: place `garamond-mode-line-format' where you want it, or set `garamond-lighter' back to t.")
   ((eq shown 'none)
    "The mode is on and has an indicator to show, but this buffer has no mode line at all -- `mode-line-format' is nil here, as `hide-mode-line-mode' and its kin leave it.  There is nowhere to show it.")
   ((eq shown 'no)
    "The mode is on and has an indicator to show, but this buffer's mode line does not display it -- a mode line that hides minor mode lighters, as doom-modeline does unless `doom-modeline-minor-modes' is t.  Either show minor modes, or set `garamond-lighter' to nil and place `garamond-mode-line-format' yourself.")
   ((eq shown 'yes)
    "The mode is on and its indicator is in the mode line.  Nothing to report.")
   (t
    "The mode is on and has an indicator to show.  Whether this mode line \
displays it cannot be told from here -- look at the mode line itself, or ask \
again from a real window.")))

;;;###autoload
(defun garamond-version ()
  "Return garamond\\='s version, from the header of the file that was loaded.
Interactively, say it as well."
  (interactive)
  (let ((version (or (garamond--version) "unknown")))
    (when (called-interactively-p 'interactive)
      (message "garamond %s" version))
    version))

;;;###autoload
(defun garamond-doctor ()
  "Report what garamond is doing in this buffer, and why.
Answers the question the mode line cannot: whether this buffer has been
declared, whether anything read that declaration, and whether the
indicator is being shown, hidden, or simply has nothing to say."
  (interactive)
  (let* ((source (current-buffer))
         (version (garamond--version))
         (mode major-mode)
         (declared (cond ((not (garamond-declared-p)) "no")
                         ((garamond--declared-in-file-p) "yes, in the file")
                         (t "yes, by a .dir-locals.el")))
         (double sentence-end-double-space)
         (on garamond-mode)
         (shows (garamond-mode-line-string))
         (in-mode-line (garamond--mode-line-shows-lighter))
         (diagnosis (garamond--diagnosis in-mode-line)))
    (with-output-to-temp-buffer "*garamond-doctor*"
      (princ (format "garamond %s, on %s\n\n" (or version "(version unknown)")
                     (buffer-name source)))
      (princ "This buffer\n")
      (princ (format "  major mode                 %s\n" mode))
      (princ (format "  declared                   %s\n" declared))
      (princ (format "  sentence-end-double-space  %s%s\n" double
                     (if (equal declared "no")
                         "  (Emacs's global default, not a declaration)"
                       "")))
      (princ (format "  garamond-mode              %s%s\n" (if on "on" "off")
                     (let ((why (garamond--unsuitable-reason)))
                       (if why (format "  (refused here: %s)" why) ""))))
      (princ (format "  indicator                  %s\n"
                     (if (string= "" shows) "(nothing to show)" shows)))
      (princ (format "  shown in the mode line     %s\n"
                     (pcase in-mode-line
                       ('yes "yes")
                       ('no "no")
                       ('none "no mode line in this buffer")
                       (_ "cannot tell -- no window to render against"))))
      (princ "\nConfiguration\n")
      (princ (format "  garamond-follow-declarations-mode  %s\n"
                     (if garamond-follow-declarations-mode "on" "off")))
      (princ (format "  garamond-lighter                   %s\n" garamond-lighter))
      (princ (format "  garamond-double-space-on-typing    %s\n"
                     garamond-double-space-on-typing))
      (princ (format "  garamond-persist                   %s\n" garamond-persist))
      (princ (format "  abbreviations in force             %d (%d default, %d removed, %d extra)\n"
                     (length (garamond--abbreviations-in-force))
                     (length garamond-abbreviations)
                     (length garamond-removed-abbreviations)
                     (length garamond-extra-abbreviations)))
      (when (boundp 'doom-modeline-minor-modes)
        (princ (format "  doom-modeline-minor-modes          %s\n"
                       (symbol-value 'doom-modeline-minor-modes))))
      (princ "\nDiagnosis\n  ")
      (princ (substitute-command-keys diagnosis))
      (princ "\n"))))

(provide 'garamond)
;;; garamond.el ends here
