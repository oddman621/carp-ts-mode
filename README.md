# Usage

```
;; in `~/.emacs.d/init.el`

(setenv "CARP_DIR" "~/Carp")

(require 'treesit)

(add-to-list
 'treesit-language-source-alist
 '(carp "https://github.com/titan/tree-sitter-carp" "master"))

(use-package carp-ts-mode
  :vc (:url "https://github.com/oddman621/carp-ts-mode"
            :rev :newest))

```
