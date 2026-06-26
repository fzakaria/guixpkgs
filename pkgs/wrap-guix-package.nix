{ pkgs, package, runtimeEnv }:

pkgs.runCommand "${package.name or "guix-package"}-wrapped"
  {
    nativeBuildInputs = [ pkgs.makeWrapper ];
    passthru.unwrapped = package;
    passthru.runtimeEnv = runtimeEnv;
  }
  ''
    mkdir -p "$out"

    shopt -s dotglob nullglob
    for entry in ${package}/*; do
      base=$(basename "$entry")
      case "$base" in
        bin|sbin) ;;
        *) ln -s "$entry" "$out/$base" ;;
      esac
    done

    for dir in bin sbin; do
      if [ -d "${package}/$dir" ]; then
        mkdir -p "$out/$dir"
        for program in "${package}/$dir"/*; do
          [ -e "$program" ] || continue
          name=$(basename "$program")
          if [ -f "$program" ] && [ -x "$program" ]; then
            makeWrapper "$program" "$out/$dir/$name" \
              --run ". ${runtimeEnv}/etc/profile"
          else
            ln -s "$program" "$out/$dir/$name"
          fi
        done
      fi
    done
  ''
