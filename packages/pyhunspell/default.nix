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
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  hunspell, # the C library (resolves from top-level pkgs, no python attr exists)
  hunspellDicts,
}:

buildPythonPackage rec {
  pname = "hunspell";
  version = "0.5.5";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-D4MLaL2MOS9NW04hw44ogJ4U1k7Ge95IJyySC2Nob1M=";
  };

  # setup.py links plain -lhunspell but nixpkgs ships only the versioned
  # libhunspell-1.x; point it at the real name (linux branch):
  postPatch = ''
    substituteInPlace setup.py --replace-fail \
      "main_module_kwargs['libraries'] = ['hunspell']" \
      "main_module_kwargs['libraries'] = ['hunspell-${lib.versions.majorMinor hunspell.version}']"
  '';

  build-system = [ setuptools ];
  buildInputs = [ hunspell ];

  # setup.py's own hook: each $INCLUDE_PATH entry gets /hunspell appended.
  env.INCLUDE_PATH = "${lib.getDev hunspell}/include";

  # Smoke test with a real dictionary: exactly the call path typing-booster's
  # Dictionary.spellcheck_suggest_pyhunspell uses.
  checkPhase = ''
    runHook preCheck
    python -c "
    import hunspell
    h = hunspell.HunSpell(
        '${hunspellDicts.en_US}/share/hunspell/en_US.dic',
        '${hunspellDicts.en_US}/share/hunspell/en_US.aff')
    assert not h.spell('teh')
    assert 'the' in h.suggest('teh')
    print('pyhunspell OK')
    "
    runHook postCheck
  '';

  pythonImportsCheck = [ "hunspell" ];

  meta = {
    description = "Python bindings for the Hunspell spellchecker engine";
    homepage = "https://github.com/pyhunspell/pyhunspell";
    changelog = "https://github.com/pyhunspell/pyhunspell/releases/tag/${version}";
    license = lib.licenses.lgpl3Plus;
    platforms = lib.platforms.linux;
  };
}
