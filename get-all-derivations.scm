;;; SPDX-FileCopyrightText: 2026 Farid Zakaria
;;; SPDX-License-Identifier: MIT
;;;
;;; Emit, for every requested package, a TSV row of three columns:
;;;
;;;     <name>\t<package-derivation>\t<runtime-env-derivation>
;;;
;;; The package derivation is the package translated faithfully into Nix. The
;;; runtime-env derivation is a tiny extra derivation we synthesize here: it
;;; contains only an `etc/profile` generated from Guix's own search-path
;;; specifications. We need it because Guix does NOT bake every runtime search
;;; path (PATH, GUILE_LOAD_PATH, GUILE_LOAD_COMPILED_PATH, XDG_DATA_DIRS,
;;; certificate paths, ...) into each executable. Normally those are exported by
;;; sourcing a profile's `etc/profile`; the Nix-side wrapper sources this one so
;;; translated programs run correctly outside a Guix profile.

(use-modules (gnu packages)
             (guix derivations)
             (guix gexp)
             (guix packages)
             (guix profiles)
             (guix search-paths)
             (guix store)
             (ice-9 match)
             (srfi srfi-1))

(define %package-names
  ;; Unknown names are caught and skipped below, so this list is safe to extend.
  '("hello" "bash"
    "coreutils"
    ;; Guile libraries packaged in Guix but absent from nixpkgs -- these make
    ;; the strongest "transfer" demo (nixpkgs simply has no equivalent).
    "guile-png" ;pure-Scheme PNG encoder/decoder
    "guile-dsv" ;delimiter-separated values (CSV/DSV) parser
    "guile-ics" ;iCalendar (RFC 5545) parser/printer
    "guile-wisp" ;whitespace-significant Scheme syntax (SRFI-119)
    "guile-pipe" ;threading/pipe macros
    "g-golf" ;GObject-introspection bindings (drive GTK from Scheme)
    "guile-cv" ;computer-vision library
    "guile-studio"))

(define (input->manifest-entries input)
  "Convert a single package INPUT tuple into a list of manifest entries.

A Guix input looks like (LABEL PACKAGE [OUTPUTS ...]). We only care about the
package object and the outputs it contributes; everything else (plain files,
origins, ...) yields no entries. When no outputs are named we default to
\"out\", matching Guix's own behavior."
  (match input
    ((_ (? package? package) outputs ...)
     (map (lambda (output)
            (package->manifest-entry package output))
          (if (null? outputs)
              '("out") outputs)))
    (_ '())))

(define (package-runtime-entries package)
  "Return the manifest entries that should populate PACKAGE's runtime profile.

This is the package itself plus its transitive *target* (runtime) inputs. We
include those inputs deliberately: many Guix packages keep language modules as
ordinary (non-propagated) inputs, yet their executables still need the matching
search paths at runtime. For example guile-png needs guile-zlib's module path,
otherwise `png --help` fails with \"no code for module (zlib)\"."
  (delete-duplicates (cons (package->manifest-entry package)
                           (append-map input->manifest-entries
                                       (package-transitive-target-inputs
                                        package))) manifest-entry=?))

(define (search-path-key spec)
  "Return a comparable key describing a search-path SPEC.

`search-path-specification' records have no useful structural equality, so we
project each one onto the fields that actually matter and compare those."
  (list (search-path-specification-variable spec)
        (search-path-specification-files spec)
        (search-path-specification-separator spec)
        (search-path-specification-file-type spec)
        (search-path-specification-file-pattern spec)))

(define (same-search-path? a b)
  "True when search-path specs A and B describe the same environment variable."
  (equal? (search-path-key a)
          (search-path-key b)))

(define (runtime-search-paths entries)
  "Collect the de-duplicated search-path specs for a list of manifest ENTRIES.

This mirrors what `guix package`/profile activation would compute, but without
building a union profile -- the wrapper only needs the resulting shell
definitions. $PATH and $GUIX_EXTENSIONS_PATH are always included because Guix's
profile machinery always provides them."
  (delete-duplicates (cons* $PATH $GUIX_EXTENSIONS_PATH
                            (append-map manifest-entry-search-paths entries))
                     same-search-path?))

(define (runtime-env-derivation store package)
  "Build a derivation containing only PACKAGE's runtime `etc/profile'.

The derivation writes the search-path definitions (evaluated over the package
and its runtime inputs) into etc/profile, exactly the form a Guix profile would
generate. When the package contributes no search paths, etc/profile is omitted
entirely so the Nix wrapper can skip wrapping its binaries. Build options:
  #:local-build?   build locally -- it is a trivial text file, not worth
                   offloading to a remote builder.
  #:substitutable? never fetch from a substitute server; it is generated on the
                   fly and exists in no cache, so a lookup would only add a
                   pointless round-trip.
  #:properties     tag the derivation type so it is identifiable downstream."
  (let* ((entries (package-runtime-entries package))
         (roots (map (lambda (entry)
                       (gexp-input (manifest-entry-item entry)
                                   (manifest-entry-output entry))) entries))
         (search-paths (runtime-search-paths entries)))
    (parameterize ((%graft? #f))
      (run-with-store store
                      (gexp->derivation (string-append (package-name package)
                                                       "-runtime-env")
                                        (with-imported-modules '((guix build
                                                                       utils)
                                                                 (guix records)
                                                                 (guix
                                                                  search-paths))
                                                               #~(begin
                                                                   (use-modules
                                                                    (guix
                                                                     build
                                                                     utils)
                                                                    (guix
                                                                     search-paths)
                                                                    (ice-9
                                                                     match))
                                                                   (define roots
                                                                     (list #$@roots))
                                                                   (define search-paths
                                                                     (map
                                                                      sexp->search-path-specification
                                                                      '#$(sexp->gexp
                                                                          (map
                                                                           search-path-specification->sexp
                                                                           search-paths))))
                                                                   ;; The shell definitions this package actually contributes.
                                                                   (define definitions
                                                                     (map (match-lambda
                                                                            ((search-path . value)
                                                                             (search-path-definition
                                                                              search-path
                                                                              value
                                                                              #:kind 'prefix)))
                                                                          (evaluate-search-paths
                                                                           search-paths
                                                                           roots
                                                                           (lambda _
                                                                             #f))))
                                                                   ;; $output must always exist, but only emit etc/profile when there
                                                                   ;; is something to set. Its absence lets the Nix wrapper cheaply
                                                                   ;; detect "no runtime environment needed" and skip wrapping.
                                                                   (mkdir-p #$output)
                                                                   (when (pair?
                                                                          definitions)
                                                                     (mkdir-p (string-append #$output
                                                                               "/etc"))
                                                                     (call-with-output-file 
                                                                                            (string-append #$output
                                                                                             "/etc/profile")
                                                                       (lambda 
                                                                               (port)
                                                                         (display
                                                                          "# Generated by GuixPkgs from Guix search path specifications.
"
                                                                          port)
                                                                         (for-each (lambda 
                                                                                           (definition)
                                                                                     
                                                                                     (display
                                                                                      definition
                                                                                      port)
                                                                                     
                                                                                     (newline
                                                                                      port))
                                                                          definitions))))))
                                        #:system "x86_64-linux"
                                        #:local-build? #t
                                        #:substitutable? #f
                                        #:properties '((type . guixpkgs-runtime-env)))))))

(define (emit-package store pkg-name)
  "Print the TSV row for PKG-NAME, or a diagnostic on failure.

Resolves the package, computes its faithful Nix-bound derivation and its
runtime-env derivation, and prints \"name\\tpackage-drv\\truntime-env-drv\".
Any failure (unknown package, build-graph error) is caught and logged to stderr
so one bad name never aborts the whole run. Grafts are disabled so the emitted
derivations match exactly what guix-transfer will translate."
  (catch #t
         (lambda ()
           (parameterize ((%graft? #f))
             (let* ((package
                      (specification->package pkg-name))
                    (package-drv (package-derivation store package
                                                     "x86_64-linux"
                                                     #:graft? #f))
                    (runtime-env-drv (runtime-env-derivation store package)))
               (format #t "~a\t~a\t~a\n"
                       (package-name package)
                       (derivation-file-name package-drv)
                       (derivation-file-name runtime-env-drv)))))
         (lambda _
           (format (current-error-port) "Failed: ~a\n" pkg-name))))

(with-store store
            (for-each (lambda (name)
                        (emit-package store name)) %package-names))
