
echo "unpacking bootstrap Guile to '$out'..."
/nix/store/w0js0b6vhpwcmyxz3ikd6gwsza6vlvyd-mkdir $out
cd $out
/nix/store/y1vqlvmrdbvmxs887fs72ilb847zmswp-xz -dc < $GUILE_TARBALL | /nix/store/8k8bp20mpgp5m2gfdgzza3dafdm52pda-tar xv

# Use the bootstrap guile to create its own wrapper to set the load path.
GUILE_SYSTEM_PATH=$out/share/guile/2.0 GUILE_SYSTEM_COMPILED_PATH=$out/lib/guile/2.0/ccache $out/bin/guile -c "(begin (use-modules (ice-9 match)) (match (command-line) ((_ out bash) (let ((bin-dir (string-append out \"/bin\")) (guile (string-append out \"/bin/guile\")) (guile-real (string-append out \"/bin/.guile-real\")) (dollar (string (integer->char 36)))) (chmod bin-dir 493) (rename-file guile guile-real) (call-with-output-file guile (lambda (p) (format p \"#!~a\\nexport GUILE_SYSTEM_PATH=~a/share/guile/2.0\\nexport GUILE_SYSTEM_COMPILED_PATH=~a/lib/guile/2.0/ccache\\nexec -a \\\"~a0\\\" ~a \\\"~a@\\\"\\n\" bash out out dollar guile-real dollar))) (chmod guile 365) (chmod bin-dir 365)))))" $out /nix/store/yv28cmnzqbyn17lmqknnzkp9pj5m2yc0-bash

# Sanity check.
$out/bin/guile --version
