# pyhunspell — CPython bindings for hunspell (PyPI "hunspell", not in nixpkgs).
#
# Why: ibus-typing-booster's spellcheck/spell-suggestion layer needs a Python
# backend (pyenchant OR pyhunspell, hunspell_suggest.py tries them in that
# order). nixpkgs ships the engine with NEITHER, so on stock NixOS the engine
# is completion-only: no typo corrections at all ("teh" can never suggest
# "the"). pyhunspell is the right backend here because the engine constructs
# it from explicit .dic/.aff paths it resolved via DICPATH — no enchant-style
# provider/dictionary discovery, which doesn't work on nix.
#
# For python3.pkgs.callPackage (see hosts/fajita/default.nix ibus.engines).
{
  buildPythonPackage,
  fetchPypi,
  setuptools,
  pkg-config,
  hunspell, # the C library (resolves from top-level pkgs, no python attr exists)
  hunspellDicts,
}:

buildPythonPackage rec {
  pname = "hunspell";
  version = "0.5.5";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-D4MLaL2MOS9NW04hw44ogJ4U1k7Ge95IJyySC2Nob1M=";
  };

  build-system = [ setuptools ];
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ hunspell ];

  # setup.py hardcodes /usr/include/hunspell and links plain -lhunspell;
  # nixpkgs ships versioned libhunspell-1.x only — shim both, then pin the
  # runtime path with an explicit rpath.
  env.NIX_CFLAGS_COMPILE = "-I${hunspell.dev}/include/hunspell";
  preBuild = ''
    mkdir -p $TMPDIR/libshim
    ln -s ${hunspell.out}/lib/libhunspell-*.so $TMPDIR/libshim/libhunspell.so
    export NIX_LDFLAGS="$NIX_LDFLAGS -L$TMPDIR/libshim -L${hunspell.out}/lib"
  '';
  postFixup = ''
    find $out -name "hunspell*.so" -exec patchelf --add-rpath ${hunspell.out}/lib {} \;
  '';

  # Smoke test with a real dictionary: exactly the call path typing-booster's
  # Dictionary.spellcheck_suggest_pyhunspell uses.
  checkPhase = ''
    python -c "
    import hunspell
    h = hunspell.HunSpell(
        '${hunspellDicts.en_US}/share/hunspell/en_US.dic',
        '${hunspellDicts.en_US}/share/hunspell/en_US.aff')
    assert not h.spell('teh')
    assert 'the' in h.suggest('teh')
    print('pyhunspell OK')
    "
  '';

  pythonImportsCheck = [ "hunspell" ];
}
