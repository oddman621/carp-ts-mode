;;; carp-ts-mode.el --- Tree-sitter major mode for Carp -*- lexical-binding: t; -*-

;; Copyright (C) 2026
;; Version: 0.1.0
;; Keywords: languages, carp, tree-sitter
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; A small Tree-sitter major mode for the Carp programming language.
;; It uses the grammar from https://github.com/titan/tree-sitter-carp
;; and optionally integrates with Flycheck to run `carp --check'.
;;
;; Install the grammar with:
;;   M-x treesit-install-language-grammar RET carp RET
;;
;; Then add this file's directory to `load-path' and load this mode.

;;; Code:

(require 'prog-mode)
(require 'treesit)

;; Flycheck is an optional dependency.
(declare-function flycheck-mode "ext:flycheck" (&optional arg))
(declare-function flycheck-define-checker "ext:flycheck"
  (name docstring &rest properties) t)

(defgroup carp-ts-mode nil
  "Major mode for the Carp programming language using Tree-sitter."
  :group 'languages
  :prefix "carp-ts-mode-")

(defcustom carp-ts-mode-indent-offset 2
  "Indentation offset for nested Carp expressions."
  :type 'integer
  :group 'carp-ts-mode)

(defcustom carp-ts-mode-enable-flycheck t
  "Whether to enable Flycheck automatically when it is available."
  :type 'boolean
  :group 'carp-ts-mode)

(defface carp-ts-mode-operator-face
  '((t :inherit font-lock-builtin-face))
  "Face used for Carp operators."
  :group 'carp-ts-mode)

(defface carp-ts-mode-bracket-face
  '((t :inherit shadow))
  "Face used for Carp brackets."
  :group 'carp-ts-mode)

(defvar carp-ts-mode-syntax-table
  (let ((table (make-syntax-table prog-mode-syntax-table)))
    ;; Carp comments start with a semicolon and continue to the end of line.
    (modify-syntax-entry ?\; "<" table)
    (modify-syntax-entry ?\n ">" table)
    table)
  "Syntax table for `carp-ts-mode'.")

(defvar carp-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'carp
   :feature 'comment
   '((comment) @font-lock-comment-face)

   :language 'carp
   :feature 'string
   '([(char) (string) (rawstring) (pattern)] @font-lock-string-face)

   :language 'carp
   :feature 'number
   '([(byte) (integer) (long) (float) (floatnoperiod) (double)]
     @font-lock-constant-face)

   :language 'carp
   :feature 'constant
   '((bool) @font-lock-constant-face
     ((symbol) @font-lock-constant-face
      (:match "\\`[A-Z][A-Z0-9_]+\\'" @font-lock-constant-face)))

   :language 'carp
   :feature 'conditional
   '((symbol) @font-lock-keyword-face
     (:match "\\`\\(if\\|match\\|match-ref\\|cond\\|unless\\)\\'" @font-lock-keyword-face))

   :language 'carp
   :feature 'keyword
   '((symbol) @font-lock-keyword-face
     (:match "\\`\\(doc\\|sig\\|hidden\\|private\\|register\\|register-type\\|implements\\|do\\|and\\|or\\|else\\|let\\|let-do\\|ref\\|the\\|aset!\\|set!\\|quote\\|unquote\\|quote-splicing\\|quasiquote\\|unquote-splicing\\|with\\|address\\|def\\|defn\\|defn-do\\|deftype\\|defmacro\\|defmodule\\|defdynamic\\|defndynamic\\|definterface\\|deftemplate\\|Fn\\|λ\\)\\'" @font-lock-keyword-face))

   :language 'carp
   :feature 'import
   '((symbol) @font-lock-preprocessor-face
     (:match "\\`\\(load\\|use\\|system-include\\|local-include\\)\\'" @font-lock-preprocessor-face))

   :language 'carp
   :feature 'repeat
   '((symbol) @font-lock-keyword-face
     (:match "\\`\\(while\\|while-do\\|for\\|foreach\\|when\\|break\\)\\'" @font-lock-keyword-face))

   :language 'carp
   :feature 'function
   '((list
      :anchor (symbol) @_head
      :anchor (symbol) @font-lock-function-name-face
      (:match "\\`\\(defn\\|defn-do\\|sig\\|defdynamic\\|defndynamic\\)\\'" @_head)))

   :language 'carp
   :feature 'type
   '((list
      :anchor (symbol) @_head
      :anchor (symbol) @font-lock-type-face
      (:match "\\`\\(deftype\\|register-type\\)\\'" @_head)))

   :language 'carp
   :feature 'namespace
   '((list
      :anchor (symbol) @_head
      :anchor (symbol) @font-lock-constant-face
      (:match "\\`defmodule\\'" @_head)))

   :language 'carp
   :feature 'operator
   '((symbol) @carp-ts-mode-operator-face
     (:match "\\`\\([+*/<>=-]\\|<=\\|>=\\|=>\\)\\'" @carp-ts-mode-operator-face))

   :language 'carp
   :feature 'bracket
   '(["(" ")" "[" "]" "{" "}"] @carp-ts-mode-bracket-face))
  "Tree-sitter font-lock queries for Carp.")

(defvar carp-ts-mode--font-lock-feature-list
  '((comment string number constant)
    (conditional keyword import repeat)
    (function type namespace)
    (operator bracket))
  "Font-lock feature levels for `carp-ts-mode'.")

(defvar carp-ts-mode--indent-rules
  `((carp
     ;; Closing delimiters line up with the line containing their opener.
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "}") parent-bol 0)
     ;; Indent elements within lists, arrays, and dictionaries by one level.
     ((parent-is "list") parent-bol carp-ts-mode-indent-offset)
     ((parent-is "array") parent-bol carp-ts-mode-indent-offset)
     ((parent-is "dictionary") parent-bol carp-ts-mode-indent-offset)
     ;; Top-level expressions begin in column zero.
     ((parent-is "source") column-0 0)
     (no-node parent-bol 0)))
  "Basic indentation rules for Carp syntax trees.")

;;;###autoload
(define-derived-mode carp-ts-mode prog-mode "Carp[TS]"
  "Major mode for Carp using Tree-sitter.

The mode requires Emacs 29 or newer and an installed `carp' Tree-sitter
parser, such as the one provided by titan/tree-sitter-carp."
  :group 'carp-ts-mode
  :syntax-table carp-ts-mode-syntax-table
  (unless (treesit-ready-p 'carp)
    (user-error
     "Carp Tree-sitter grammar is unavailable; run M-x treesit-install-language-grammar RET carp"))
  (treesit-parser-create 'carp)
  (setq-local comment-start ";")
  (setq-local comment-end "")
  (setq-local comment-start-skip ";+\\s-*")
  (setq-local indent-tabs-mode nil)
  (setq-local treesit-font-lock-settings carp-ts-mode--font-lock-settings)
  (setq-local treesit-font-lock-feature-list
              carp-ts-mode--font-lock-feature-list)
  (setq-local treesit-simple-indent-rules carp-ts-mode--indent-rules)
  (treesit-major-mode-setup))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.carp\\'" . carp-ts-mode))

;; Optional `carp --check' integration.  The patterns follow the output formats
;; used by the existing carp-emacs Flycheck checker.
(with-eval-after-load 'flycheck
  (flycheck-define-checker carp-ts-checker
    "Check Carp source files with `carp --check'."
    :command ("carp" "--check" source)
    :error-patterns
    ((error line-start space (message) "\n  At line " line
            ", column " column " in '" (file-name) "'" line-end)
     (error line-start (file-name) ":" line ":" column " "
            (message) line-end))
    :modes (carp-ts-mode))
  (add-to-list 'flycheck-checkers 'carp-ts-checker))

(defun carp-ts-mode--maybe-enable-flycheck ()
  "Enable Flycheck in Carp buffers when it is installed and configured."
  (when carp-ts-mode-enable-flycheck
    (when (require 'flycheck nil t)
      (flycheck-mode 1))))

(add-hook 'carp-ts-mode-hook #'carp-ts-mode--maybe-enable-flycheck)

(provide 'carp-ts-mode)

;;; carp-ts-mode.el ends here
