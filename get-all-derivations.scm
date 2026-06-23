(use-modules (gnu packages) (guix packages) (guix store) (guix derivations) (srfi srfi-1) (ice-9 match))

(with-store %store
  (for-each
    (lambda (package)
      (catch #t
        (lambda ()
          (let ((drv (package-derivation %store package "x86_64-linux" #:graft? #f)))
            (format #t "~a\t~a\n" (package-name package) (derivation-file-name drv))))
        (lambda (key . args)
          (format (current-error-port) "Failed: ~a\n" (package-name package)))))
    (fold-packages cons '())))
