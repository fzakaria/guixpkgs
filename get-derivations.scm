(use-modules (gnu packages) (guix packages) (guix store) (guix derivations) (srfi srfi-1))

(with-store %store
  (let* ((all-packages (fold-packages cons '()))
         (first-10 (take all-packages 10)))
    (for-each
      (lambda (package)
        (format #t "Package: ~a\n" (package-name package))
        (catch #t
          (lambda ()
            (let ((drv (package-derivation %store package "x86_64-linux" #:graft? #f)))
              (format #t "  Drv: ~a\n" (derivation-file-name drv))))
          (lambda (key . args)
            (format #t "  Failed: ~a\n" key))))
      first-10)))
