(use-modules (gnu packages) (guix packages) (guix store) (guix derivations) (srfi srfi-1) (ice-9 match))

(with-store %store
  (for-each
    (lambda (pkg-name)
      (catch #t
        (lambda ()
          (let* ((package (specification->package pkg-name))
                 (drv (package-derivation %store package "x86_64-linux" #:graft? #f)))
            (format #t "~a\t~a\n" (package-name package) (derivation-file-name drv))))
        (lambda (key . args)
          (format (current-error-port) "Failed: ~a\n" pkg-name))))
    ;; Unknown names are caught and skipped above, so this list is safe to extend.
    '("hello"
      "bash"
      "coreutils"
      ;; Guile libraries packaged in Guix but absent from nixpkgs — these make
      ;; the strongest "transfer" demo (nixpkgs simply has no equivalent).
      "guile-png"      ; pure-Scheme PNG encoder/decoder
      "guile-dsv"      ; delimiter-separated values (CSV/DSV) parser
      "guile-ics"      ; iCalendar (RFC 5545) parser/printer
      "guile-wisp"     ; whitespace-significant Scheme syntax (SRFI-119)
      "guile-pipe"     ; threading/pipe macros
      "g-golf"         ; GObject-introspection bindings (drive GTK from Scheme)
      "guile-cv"       ; computer-vision library
      "guile-studio")))
