{
  stdenvNoCC,
  fetchurl,
  python3,
  sqlite,
  lib,
}:

let
  # Pinned commit of Helium314/aosp-dictionaries the wordlists are fetched from.
  # Bump this AND both hashes together when refreshing the source data.
  commit = "69afafc3887d189515fa0be8b4585b91df80b92d";

  # en_US: OpenBoard en_wordlist (AOSP LatinIME derived), Apache-2.0.
  enSrc = fetchurl {
    url = "https://codeberg.org/Helium314/aosp-dictionaries/raw/commit/${commit}/wordlists/main_en_US.combined";
    hash = "sha256-czCFGf8InHO6o14I8lCHu2LtSmvy+Wrz77QCGH98nts=";
  };

  # es: Leipzig Corpora derived experimental list, CC BY 4.0.
  esSrc = fetchurl {
    url = "https://codeberg.org/Helium314/aosp-dictionaries/raw/commit/${commit}/wordlists_experimental/main_es.combined";
    hash = "sha256-eGcXz5ynpp9rC/KX+NvcJKceIYIEYvAU4RqiyKYtOpc=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "aosp-freq-dict";
  version = "unstable-2026-07-08";

  # We fetch two individual wordlists rather than a tarball; nothing to unpack.
  dontUnpack = true;

  # python3 ships the sqlite3 stdlib module, so convert.py / voseo.py run with no
  # extra deps; the sqlite CLI is available too if a build step ever needs it.
  nativeBuildInputs = [ python3 sqlite ];

  buildPhase = ''
    runHook preBuild

    mkdir -p $out/share/aosp-freq-dict

    # --drop-offensive is sensible for a phone keyboard: we do not want the
    # spatial autocorrect engine surfacing slurs from the corpus tail.
    python3 ${./convert.py} --input ${enSrc} --output en_US.db --drop-offensive
    python3 ${./convert.py} --input ${esSrc} --output es.db --drop-offensive

    # Layer the Argentine voseo verb paradigm into the Spanish DB (in place).
    python3 ${./voseo.py} --db es.db

    install -m 0444 en_US.db $out/share/aosp-freq-dict/en_US.db
    install -m 0444 es.db $out/share/aosp-freq-dict/es.db

    cat > $out/share/aosp-freq-dict/NOTICE <<'EOF'
    aosp-freq-dict — frequency dictionaries for the ibus-typing-booster spatial autocorrect engine.
    Built from Helium314/aosp-dictionaries at commit 69afafc3887d189515fa0be8b4585b91df80b92d
    (https://codeberg.org/Helium314/aosp-dictionaries).

    en_US.db
      Source: wordlists/main_en_US.combined (OpenBoard v1.4.5 en_wordlist, derived from
      the AOSP LatinIME dictionary).
      License: Apache License 2.0.

    es.db
      Source: wordlists_experimental/main_es.combined, generated from the Leipzig Corpora
      Collection word lists (https://wortschatz.uni-leipzig.de/en/download/).
      License: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).
      Attribution: Leipzig Corpora Collection. Data used and redistributed under CC BY 4.0.
      Modifications: converted to SQLite; an Argentine voseo verb paradigm (present-indicative
      vos and affirmative-imperative vos forms over a curated verb list) was generated and
      merged in by voseo.py. These additions are original to this package.
    EOF

    runHook postBuild
  '';

  # buildPhase already installs everything into $out; no separate install step.
  dontInstall = true;

  meta = {
    description = "AOSP-derived en_US + es frequency DBs (SQLite) with an Argentine voseo layer, for the phone keyboard spatial autocorrect engine";
    license = [ lib.licenses.asl20 lib.licenses.cc-by-40 ];
    platforms = lib.platforms.linux;
  };
}
