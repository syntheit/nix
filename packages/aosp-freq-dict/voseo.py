#!/usr/bin/env python3
"""Merge an Argentine voseo verb paradigm into an existing AOSP es.db frequency DB.

This is a post-processing pass over the SQLite DB produced by convert.py. The AOSP
`main_es.combined` wordlist (Leipzig Corpora) is corpus-derived European/pan-Hispanic
Spanish: it has the `tú` present forms (hablas, tienes, ...) and only a handful of
stray voseo forms (sos, tenés, hacés, podés, querés, vas, vos, dale). It is MISSING
the overwhelming majority of Argentine voseo verb forms (hablás, vení, andá, decí,
mirá, ...), so on a phone keyboard those correct Argentine spellings look like
out-of-vocabulary typos. This script fills that gap.

We take a curated list of common everyday `-ar/-er/-ir` verbs, regenerate their voseo
paradigm, and merge the forms into the `unigrams` table. We NEVER touch bigrams and we
NEVER lower an existing AOSP frequency (see MERGE SEMANTICS).

=== VOSEO GRAMMAR RULES (the whole point: these are REGULAR) ===
Rioplatense voseo present-indicative and affirmative-imperative are exceptionless and
regular for every verb whose infinitive is regular in shape — INCLUDING verbs that are
stem-changing in the `tú`/standard paradigm. The stem change simply does not happen in
voseo, because the accent lands on the ending, not the stem. So we deliberately apply
NO stem-change logic:

    stem = infinitive[:-2]   (drop the -ar/-er/-ir)

    Present indicative (vos):
        -ar  ->  stem + "ás"    hablar -> hablás,  contar -> contás,  pensar -> pensás
        -er  ->  stem + "és"    comer  -> comés,   poder  -> podés,   querer -> querés
        -ir  ->  stem + "ís"    vivir  -> vivís,   venir  -> venís,   dormir -> dormís

    Affirmative imperative (vos):
        -ar  ->  stem + "á"     hablar -> hablá,   contar -> contá,   pensar -> pensá
        -er  ->  stem + "é"     comer  -> comé,    poder  -> podé,    querer -> queré
        -ir  ->  stem + "í"     vivir  -> viví,    venir  -> vení,    dormir -> dormí

    The last vowel of the ending always carries the acute accent (á/é/í).

A small set of verbs is genuinely irregular in voseo or has hand-worthy high-frequency
forms (ser->sos, ir->andá/vas, decir->decí, hacer->hacé, tener->tené, ...). These live
in the IRREGULARS dict with explicit frequencies and OVERRIDE / augment the generated
paradigm. Any infinitive that would produce a wrong regular form (ser, ir, dar, ver —
their two-char stem stripping collapses the word, e.g. ser->"s"->"sés") is EXCLUDED
from the regular generator and handled only via IRREGULARS.

=== FREQUENCY ASSIGNMENT (same 0-255 AOSP log scale convert.py uses) ===
AOSP `f` is a log-scaled integer 0..255 (255 = max), NOT a linear count. In es.db the
common infinitives sit ~110-160 and the `tú` present forms ~85-105. We slot the
generated voseo forms deliberately BELOW those so they never outrank core vocabulary,
but well ABOVE the long tail so they stay discoverable and rankable by the engine:

    generated present-indicative vos forms : freq 70
    generated affirmative-imperative forms : freq 65
    IRREGULARS dict forms                  : their explicit hand-tuned freq

MERGE SEMANTICS: we `INSERT OR IGNORE` every form. If the word already exists in the
AOSP data (any of the stray voseo forms, or a form that collides with an existing
word), the existing row — and its higher AOSP freq — is left completely untouched. We
only ever ADD missing forms; we never rewrite or lower anything. flags is always ''
(the AOSP es rows all have empty flags too). The whole merge runs in one transaction.
"""

import argparse
import sqlite3
import sys

# Frequencies for the two GENERATED regular paradigms, on the AOSP 0-255 log scale.
# Below the tú present forms (~85-105) and the common infinitives (~110-160), above
# the long tail. See the module docstring for the full rationale.
FREQ_PRESENT = 70
FREQ_IMPERATIVE = 65

# Curated list of common everyday Argentine -ar/-er/-ir verbs, as INFINITIVES. The
# regular voseo generator (present indic + affirmative imperative) runs over these.
# Verbs that are irregular in voseo (ser, ir, dar, ver) are intentionally NOT here;
# they are covered by IRREGULARS only. Kept correct over exhaustive.
INFINITIVES = [
    # -ar
    "hablar", "andar", "mirar", "pensar", "mandar", "esperar", "contar",
    "pasar", "quedar", "dejar", "tomar", "llevar", "encontrar", "llamar",
    "buscar", "entrar", "trabajar", "escuchar", "comprar", "cerrar",
    "empezar", "jugar", "ganar", "caminar", "cocinar", "cambiar", "ayudar",
    "cuidar", "usar", "necesitar", "olvidar", "recordar", "acordar",
    "mostrar", "sacar", "tocar", "cargar", "pagar", "arreglar", "manejar",
    "estudiar", "preguntar", "contestar", "explicar", "invitar", "visitar",
    "viajar", "gastar", "guardar", "juntar", "prestar", "regalar",
    "acompañar", "apurar", "avisar", "bailar", "cansar", "charlar", "cortar",
    "descansar", "disfrutar", "enseñar", "enviar", "faltar", "festejar",
    "firmar", "grabar", "gritar", "levantar", "limpiar", "llorar",
    "matar", "mejorar", "mudar", "nadar", "necesitar", "notar", "parar",
    "peinar", "pesar", "pintar", "planchar", "practicar", "preparar",
    "presentar", "probar", "quejar", "quitar", "reservar", "revisar",
    "saltar", "saludar", "sonar", "soñar", "tardar", "terminar", "tirar",
    "tratar", "usar", "votar", "acercar", "aclarar", "acostar", "actuar",
    "afeitar", "agarrar", "agregar", "alcanzar", "alquilar", "amar",
    "anotar", "apagar", "aparecer", "apoyar", "apretar", "armar",
    "arrancar", "asustar", "atar", "atacar", "aumentar", "bajar",
    "bancar", "besar", "borrar", "brillar", "callar", "calmar", "chocar",
    "colgar", "comentar", "comparar", "confiar", "conservar", "considerar",
    "controlar", "conversar", "copiar", "crear", "criticar", "cruzar",
    "curar", "dañar", "dedicar", "demostrar", "desarmar", "desatar",
    "desear", "destacar", "dibujar", "disculpar", "doblar", "dudar",
    "durar", "echar", "empujar", "encantar", "engañar", "entregar",
    "escapar", "estacionar", "estirar", "evitar", "extrañar", "fallar",
    "felicitar", "filmar", "frenar", "fumar", "funcionar", "girar",
    "golpear", "guiar", "heredar", "imaginar", "importar", "indicar",
    "instalar", "intentar", "interesar", "internar", "llegar", "lograr",
    "manchar", "marcar", "mezclar", "molestar", "necesitar", "negar",
    "nombrar", "obligar", "ocupar", "odiar", "operar", "opinar",
    "ordenar", "organizar", "pararse", "participar", "pasear", "pegar",
    "pelear", "perdonar", "pesar", "picar", "planear", "prohibir",
    "provocar", "publicar", "quemar", "rascar", "rechazar", "regresar",
    "renunciar", "reparar", "repasar", "reservar", "respetar", "respirar",
    "resultar", "retirar", "reunir", "robar", "rodear", "rogar",
    "sacudir", "secar", "sentar", "señalar", "separar", "sobrar",
    "solucionar", "soltar", "soportar", "sostener", "sujetar", "sumar",
    "tapar", "temblar", "tentar", "tocar", "traicionar", "trasladar",
    "trepar", "trotar", "vaciar", "vigilar", "volar",
    # -er
    "tener", "querer", "poder", "hacer", "comer", "creer", "correr",
    "comprender", "aprender", "entender", "responder", "romper", "meter",
    "volver", "mover", "prometer", "deber", "beber", "leer", "poner",
    "coser", "vender", "temer", "conocer", "parecer", "crecer", "ofrecer",
    "merecer", "obedecer", "reconocer", "aparecer", "recorrer", "socorrer",
    "toser", "torcer", "morder", "perder", "encender", "extender",
    "atender", "defender", "pretender", "depender", "sorprender",
    "esconder", "resolver", "devolver", "envolver", "doler", "oler",
    "valer", "caber", "traer", "proteger", "recoger", "escoger", "coger",
    "componer", "proponer", "suponer", "exponer", "oponer", "detener",
    "obtener", "mantener", "contener", "entretener", "convencer", "vencer",
    "ceder", "conceder", "suceder", "proceder", "exceder", "arder",
    "morder", "roer", "yacer", "nacer", "pertenecer", "agradecer",
    "padecer", "establecer",
    # -ir
    "venir", "vivir", "decir", "salir", "escribir", "abrir", "sentir",
    "dormir", "morir", "pedir", "conseguir", "subir", "seguir", "recibir",
    "cubrir", "descubrir", "sufrir", "partir", "repartir", "compartir",
    "discutir", "insistir", "existir", "asistir", "resistir", "consistir",
    "permitir", "admitir", "transmitir", "emitir", "omitir", "cumplir",
    "aplaudir", "reunir", "unir", "definir", "confundir", "hundir",
    "añadir", "medir", "impedir", "despedir", "elegir", "corregir",
    "dirigir", "exigir", "fingir", "mentir", "advertir", "convertir",
    "divertir", "invertir", "hervir", "servir", "vestir", "repetir",
    "competir", "sugerir", "referir", "preferir", "herir", "adquirir",
    "reír", "freír", "sonreír", "construir", "destruir", "influir",
    "incluir", "concluir", "huir", "contribuir", "distribuir", "abolir",
    "acudir", "bendecir", "predecir", "producir", "traducir", "conducir",
    "reducir", "introducir", "deducir", "seducir",
]

# KEY IRREGULARS: word -> freq. These are voseo forms that are either genuinely
# irregular (sos, vos, vas) or high-frequency Argentine forms worth hand-tuning ABOVE
# the generated defaults. They OVERRIDE / augment the generated paradigm and are merged
# with the same INSERT OR IGNORE semantics (existing AOSP rows win). See docstring.
IRREGULARS = {
    "sos": 130,    # ser, vos present ("vos sos")
    "vos": 120,    # the pronoun itself
    "vas": 110,    # ir, vos present ("vos vas")
    "andá": 95,    # andar imperative (also the go-to "ir" imperative)
    "vení": 95,    # venir imperative
    "decí": 90,    # decir imperative
    "hacé": 90,    # hacer imperative
    "tené": 90,    # tener imperative
    "poné": 88,    # poner imperative
    "salí": 85,    # salir imperative
    "dale": 110,   # ubiquitous affirmation/filler
    "mirá": 95,    # mirar imperative
    "pará": 85,    # parar imperative
    "dejá": 85,    # dejar imperative
    "esperá": 85,  # esperar imperative
    "contá": 85,   # contar imperative
    "mandá": 85,   # mandar imperative
    "fijate": 80,  # fijarse imperative ("fijate")
    "bancá": 78,   # bancar imperative (slang: to put up with / support)
}

# Infinitives that are irregular in voseo and MUST NOT be run through the regular
# generator (their two-char stem stripping would collapse the word). They are covered
# by IRREGULARS instead. Kept as a guard even though they are not in INFINITIVES.
IRREGULAR_INFINITIVES = frozenset(("ser", "ir", "dar", "ver"))

# Ending map: infinitive suffix -> (present-indicative ending, imperative ending).
_ENDINGS = {
    "ar": ("ás", "á"),
    "er": ("és", "é"),
    "ir": ("ís", "í"),
}


def generate_forms():
    """Build the deterministic set of (word, freq) voseo rows to merge.

    Runs the regular voseo generator over INFINITIVES (present indicative at
    FREQ_PRESENT, affirmative imperative at FREQ_IMPERATIVE), then layers the
    IRREGULARS dict on top. Returns a sorted list of (word, freq) tuples so the
    build is fully reproducible.

    Dedupe rule: if the same surface form is produced more than once (e.g. two
    infinitives, or a generated form colliding with an irregular), keep the MAX
    freq. IRREGULARS therefore always win over the generated defaults, and the
    generated forms never fight each other.
    """
    forms = {}

    def add(word, freq):
        if not word:
            return
        current = forms.get(word)
        if current is None or freq > current:
            forms[word] = freq

    for infinitive in INFINITIVES:
        if infinitive in IRREGULAR_INFINITIVES:
            # Irregular in voseo; handled only via IRREGULARS.
            continue
        suffix = infinitive[-2:]
        endings = _ENDINGS.get(suffix)
        if endings is None:
            # Not an -ar/-er/-ir infinitive; skip defensively.
            continue
        stem = infinitive[:-2]
        # Guard against pathological short infinitives (e.g. a 3-char verb whose
        # stem would be a single char, or shorter). We still allow single-char
        # stems (viable for real short verbs) but never an empty stem.
        if len(stem) < 1:
            continue
        present_ending, imperative_ending = endings
        add(stem + present_ending, FREQ_PRESENT)
        add(stem + imperative_ending, FREQ_IMPERATIVE)

    # Layer the hand-tuned irregulars on top (max-freq dedupe means they win).
    for word, freq in IRREGULARS.items():
        add(word, freq)

    # Deterministic ordering for reproducible builds.
    return sorted(forms.items(), key=lambda item: item[0])


def merge(db_path):
    """Open es.db read-write and INSERT OR IGNORE the voseo forms into unigrams.

    Never lowers an existing AOSP frequency (INSERT OR IGNORE leaves present rows
    untouched). Runs in a single transaction, then records meta rows and prints a
    stderr summary. Returns the number of rows actually inserted (new forms).
    """
    forms = generate_forms()

    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute("BEGIN")

        inserted = 0
        for word, freq in forms:
            cur.execute(
                "INSERT OR IGNORE INTO unigrams (word, freq, flags) "
                "VALUES (?, ?, '')",
                (word, freq),
            )
            # rowcount is 1 when a row was actually inserted, 0 when IGNOREd.
            inserted += cur.rowcount

        cur.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            ("voseo_merged", "1"),
        )
        cur.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            ("voseo_forms_added", str(inserted)),
        )

        conn.commit()
    finally:
        conn.close()

    generated = len(forms)
    skipped = generated - inserted
    print("voseo.py — Argentine voseo merge", file=sys.stderr)
    print("  db          : {}".format(db_path), file=sys.stderr)
    print("  infinitives : {}".format(len(INFINITIVES)), file=sys.stderr)
    print("  forms gen   : {} (deduped)".format(generated), file=sys.stderr)
    print("  new inserts : {}".format(inserted), file=sys.stderr)
    print("  skipped     : {} (already in AOSP data)".format(skipped),
          file=sys.stderr)
    return inserted


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Merge an Argentine voseo verb paradigm into an existing "
                    "AOSP es.db SQLite frequency database (INSERT OR IGNORE; "
                    "never lowers existing AOSP frequencies).",
    )
    parser.add_argument(
        "--db", required=True,
        help="Path to the es.db produced by convert.py (opened read-write).",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    merge(args.db)
    return 0


if __name__ == "__main__":
    sys.exit(main())
