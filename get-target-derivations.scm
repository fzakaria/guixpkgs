(use-modules (gnu packages) (guix packages) (guix store) (guix derivations) (srfi srfi-1) (ice-9 match))

(define target-packages '("hello" "zile"))

(with-store %store
  (for-each
    (lambda (pkg-name)
      (let ((packages (find-packages-by-name pkg-name)))
        (match packages
          ((package . rest)
           (catch #t
             (lambda ()
               (let ((drv (package-derivation %store package "x86_64-linux" #:graft? #f)))
                 (format #t "~a\t~a\n" pkg-name (derivation-file-name drv))))
             (lambda (key . args)
               (format (current-error-port) "Failed: ~a\n" pkg-name))))
          (() (format (current-error-port) "Not found: ~a\n" pkg-name)))))
    target-packages))
