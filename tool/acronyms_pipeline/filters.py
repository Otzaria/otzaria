"""Deterministic noise filters for acronym candidates.

Pure functions, standard library only.  `check_expansion` is the entry point used by `build_candidates.py`; it returns
(reasons, flags, normalized_expansion):

  reasons - hard rejections: the candidate is dropped and the reason is counted in the report
  flags   - soft warnings: the candidate stays, but the reviewer sees the warning
"""
import re

NIKUD = re.compile("[֑-ֽֿ-ׇ]")  # without U+05BE (maqaf)
INVISIBLE = re.compile("[​-‏‪-‮⁠-⁩﻿­]")
CONTROL = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")
HEB = "א-ת"
FOLD = str.maketrans("ךםןףץ", "כמנפצ")  # final letters -> regular letters
QUOTES = str.maketrans({"״": '"', "“": '"', "”": '"', "׳": "'", "’": "'", "‘": "'"})
PREFIX_LETTERS = "ובהלמשכד"


# ---------------------------------------------------------------------------------------------------------------
# normalisation: non-destructive (invisible chars, quote variants, whitespace, nikud)
# ---------------------------------------------------------------------------------------------------------------
def clean_text(s):
    """Drop invisible/bidi/control characters, unify quote variants, collapse whitespace.  Keeps nikud and letters."""
    s = INVISIBLE.sub("", s)
    s = CONTROL.sub(" ", s)
    s = s.translate(QUOTES)
    return re.sub(r"\s+", " ", s).strip()


def key_signature(key):
    """Lookup form of a key, as the app computes it (DictionaryLookupRepository._normalizeAcronym): no nikud, no
    quotes."""
    s = NIKUD.sub("", clean_text(key))
    return s.replace('"', "").replace("'", "")


def meaning_signature(text):
    """Comparison form of a meaning: no nikud, no quotes, maqaf/hyphen = space, no edge punctuation."""
    s = NIKUD.sub("", clean_text(text))
    s = s.replace('"', "").replace("'", "").replace("-", " ").replace("־", " ")
    return re.sub(r"\s+", " ", s).strip(" .,;:")


def plene_signature(text):
    """meaning_signature without the matres lectionis (י/ו after the first letter of a word) and with final letters
    folded: איכא בינייהו = איכא בנייהו, חסר/מלא spellings of one phrase."""
    words = meaning_signature(text).translate(FOLD).split()
    return " ".join(w[:1] + re.sub("[יו]", "", w[1:]) for w in words)


def normalize_key(raw):
    """Dictionary spelling of a key: ASCII gershayim before the last letter, no nikud, no spaces."""
    s = NIKUD.sub("", clean_text(raw)).replace(" ", "")
    if '"' not in s and re.fullmatch("[" + HEB + "]{2,}", s):
        s = s[:-1] + '"' + s[-1]
    return s


def normalize_expansion(raw):
    """Light cleaning of an expansion: invisible chars, quote variants, nikud, maqaf, edge punctuation."""
    s = NIKUD.sub("", clean_text(raw)).replace("־", "-")
    return s.strip(" .,;:–—")


# ---------------------------------------------------------------------------------------------------------------
# empty values, technical values, truncation, artifacts
# ---------------------------------------------------------------------------------------------------------------
TECH = re.compile(r"(?i)\b(null|undefined|n/?a|nan|none|true|false|error|exception|traceback|timeout|http|www)\b")
HTML = re.compile(r"<[^>]*>|&[a-zA-Z#0-9]{2,8};|</?\w+")
STRUCT = re.compile(r"[{}\[\]<>|\\×Ã�=@#$%^*~`_]|\\u[0-9a-fA-F]{4}")
NAV = re.compile("(?<![א-ת])(חזרה לתפריט|לחץ כאן|דף הבית|תפריט ראשי|חיפוש באתר|עדכון אחרון)(?![א-ת])")
# a dictionary key: letters, gershayim before the last 1-3 letters
KEY_RE = re.compile("^[" + HEB + "]{1,12}\"[" + HEB + "]{1,3}$")
ALLOWED_CHARS = re.compile("^[" + HEB + r"\s'\"\-,()./]+$")


def is_blank(s):
    """Empty, whitespace, punctuation-only, nikud-only or invisible-only."""
    t = INVISIBLE.sub("", NIKUD.sub("", s or ""))
    return not re.search("[" + HEB + "]", t)


def looks_truncated(s):
    if s.endswith(("-", ",", ":", "(")) or s.startswith(("-", ")")):
        return True
    return s.count("(") != s.count(")")


def artifact_reasons(raw):
    """Reasons that need the raw string (normalisation removes the evidence)."""
    out = []
    if CONTROL.search(raw):
        out.append("control_chars")
    if HTML.search(raw):
        out.append("html")
    if STRUCT.search(raw):
        out.append("structure_chars")
    if NAV.search(raw):
        out.append("navigation_text")
    return out


# ---------------------------------------------------------------------------------------------------------------
# letter names (צמיער = צדיק מם יוד עין ריש)
# ---------------------------------------------------------------------------------------------------------------
# Spelled without quotes/nikud and with final letters folded (the form `meaning_signature` + FOLD gives).  Everyday
# words that double as letter names ("בת", "יד", "פה", "מים") are deliberately not listed.
_NAMES = {
    "א": "אלף",
    "ב": "בית",
    "ג": "גימל",
    "ד": "דלת דלית",
    "ה": "הא הי הה",
    "ו": "ואו וו ויו",
    "ז": "זין זיין",
    "ח": "חית",
    "ט": "טית",
    "י": "יוד",
    "כ": "כף",
    "ל": "למד",
    "מ": "מם",
    "נ": "נון",
    "ס": "סמך",
    "ע": "עין עיין",
    "פ": "פא",
    "צ": "צדי צדיק",
    "ק": "קוף",
    "ר": "ריש",
    "ש": "שין",
    "ת": "תיו תו",
}
LETTER_NAMES = {name.translate(FOLD): letter for letter, names in _NAMES.items() for name in names.split()}


def letter_name_letters(expansion):
    """If the whole expansion is a run of >=2 letter names, return the letters they spell; otherwise None."""
    words = meaning_signature(expansion).split()
    if len(words) < 2:
        return None
    letters = []
    for w in words:
        letter = LETTER_NAMES.get(w.translate(FOLD))
        if letter is None:
            return None
        letters.append(letter)
    return "".join(letters)


# ---------------------------------------------------------------------------------------------------------------
# gematria and numbers
# ---------------------------------------------------------------------------------------------------------------
GEMATRIA = {c: i + 1 for i, c in enumerate("אבגדהוזחט")}
GEMATRIA.update({c: (i + 1) * 10 for i, c in enumerate("יכלמנסעפצ")})
GEMATRIA.update({c: (i + 1) * 100 for i, c in enumerate("קרשת")})


def gematria_value(letters):
    """Value of `letters` read as a Hebrew numeral (letters in descending order; 15/16 as ט״ו/ט״ז), else None."""
    letters = key_signature(letters).translate(FOLD)
    if not letters or not re.fullmatch("[" + HEB + "]+", letters):
        return None
    vals = [GEMATRIA[c] for c in letters]
    for a, b in zip(vals, vals[1:]):
        if b > a and not (a == 9 and b in (6, 7)):
            return None
        if b == a and a < 400:
            return None
    return sum(vals)


_UNITS = {
    "אחד": 1, "אחת": 1, "שני": 2, "שתי": 2, "שנים": 2, "שתים": 2, "שניים": 2, "שתיים": 2,
    "שלוש": 3, "שלש": 3, "שלושה": 3, "שלשה": 3, "ארבע": 4, "ארבעה": 4,
    "חמש": 5, "חמשה": 5, "חמישה": 5, "שש": 6, "שישה": 6, "ששה": 6,
    "שבע": 7, "שבעה": 7, "שמונה": 8, "שמנה": 8, "תשע": 9, "תשעה": 9,
}
_TENS = {
    "עשר": 10, "עשרה": 10, "עשרים": 20, "שלושים": 30, "שלשים": 30, "ארבעים": 40, "חמישים": 50, "חמשים": 50,
    "שישים": 60, "ששים": 60, "שבעים": 70, "שמונים": 80, "שמנים": 80, "תשעים": 90,
}
NUMBER_PREFIX_WORDS = ("פרק", "סימן", "סעיף", "דף", "עמוד", "מספר", "שנת", "פסוק", "מצוה", "מצווה", "בפרק", "לפרק")


def number_phrase_value(words):
    """Value of a list of Hebrew number words (שמונים ואחד = 81), or None if any word is not a number word."""
    total = pending = 0
    for raw in words:
        w = raw
        if w.startswith("ו") and len(w) > 2:
            w = w[1:]
        if w in _UNITS:
            pending += _UNITS[w]
        elif w in ("עשר", "עשרה") and pending:
            total += pending + 10
            pending = 0
        elif w in _TENS:
            total += _TENS[w] + pending
            pending = 0
        elif w == "מאה":
            total += 100
        elif w == "מאות":
            total += (pending or 1) * 100
            pending = 0
        elif w in ("מאתיים", "מאתים"):
            total += 200
        elif w == "אלף":
            total = (total + pending or 1) * 1000
            pending = 0
        elif w == "אלפיים":
            total += 2000
        elif w == "אלפים":
            total += (pending or 1) * 1000
            pending = 0
        else:
            return None
    return total + pending if words else None


def is_gematria_numeral(key, expansion):
    """True when the expansion is just the key's letters read as a number: קכ״ג = "מאה עשרים ושלוש", or the same
    after פרק/סימן/דף...  Real abbreviations such as פ״א = "פרק א" stay, because "א" is not a number word."""
    kv = gematria_value(key)
    if kv is None:
        return False
    words = meaning_signature(expansion).split()
    while words and words[0] in NUMBER_PREFIX_WORDS:
        words = words[1:]
    return bool(words) and number_phrase_value(words) == kv


# ---------------------------------------------------------------------------------------------------------------
# model-guess heuristics: do the key's letters actually fit the words?
# ---------------------------------------------------------------------------------------------------------------
def _consumed(word, letters, i):
    """How many of letters[i:] can `word` account for: its first letter (after an optional prefix letter), and
    optionally one more letter from its first three positions (ה-ג-און in הגר"א)."""
    res = []
    w = word.replace("-", "").translate(FOLD)
    starts = [0]
    if len(w) > 2 and w[0] in PREFIX_LETTERS:
        starts.append(1)
    for s in starts:
        if s >= len(w) or w[s] != letters[i]:
            continue
        res.append(1)
        if i + 1 < len(letters) and any(off < len(w) and w[off] == letters[i + 1] for off in (s + 1, s + 2)):
            res.append(2)
    return res


def aligns(key_letters, words):
    """Do the key letters fit the words, in order, each word accounting for one or two letters?"""
    letters = key_signature(key_letters).translate(FOLD)
    words = [w for w in words if w]
    m, n = len(letters), len(words)
    memo = {}

    def go(i, j):
        if j == n:
            return i == m
        if i >= m:
            return False
        if (i, j) not in memo:
            memo[(i, j)] = any(go(i + c, j + 1) for c in set(_consumed(words[j], letters, i)))
        return memo[(i, j)]

    return go(0, 0)


def aligns_with_prefix(key, expansion):
    """`aligns`, also after dropping up to 3 leading prefix letters of the key (ובהגר"א -> הגר"א)."""
    words = meaning_signature(expansion).split()
    letters = key_signature(key).translate(FOLD)
    for cut in range(4):
        if cut and (len(letters) - cut < 2 or letters[cut - 1] not in PREFIX_LETTERS):
            break
        if aligns(letters[cut:], words):
            return True
    return False


# ---------------------------------------------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------------------------------------------
MAX_CHARS = 100
SUSPECT_WORDS = 7


def check_expansion(key, raw_expansion):
    """Returns (reasons, flags, normalized_expansion) for one (key, expansion) candidate."""
    if not isinstance(raw_expansion, str):
        return ["not_a_string"], [], ""
    reasons, flags = artifact_reasons(raw_expansion), []
    exp = normalize_expansion(raw_expansion)
    if is_blank(exp):
        return reasons + ["empty"], flags, exp
    if TECH.search(exp):
        reasons.append("technical_value")
    if not ALLOWED_CHARS.match(exp):
        reasons.append("unexpected_characters")
    if meaning_signature(exp) == key_signature(key):
        reasons.append("same_as_key")
    if looks_truncated(exp):
        reasons.append("truncated")
    if len(exp) > MAX_CHARS:
        reasons.append("too_long")
    if re.fullmatch("[" + HEB + "]+\"[" + HEB + "]+", exp):
        reasons.append("expansion_is_acronym")  # an acronym "explained" by another acronym (איב"א = אב"א)
    spelled = letter_name_letters(exp)
    if spelled is not None:
        reasons.append("letter_names")
    if is_gematria_numeral(key, exp):
        reasons.append("gematria_number")
    if len(meaning_signature(exp).split()) > SUSPECT_WORDS:
        flags.append("many_words")
    if not aligns_with_prefix(key, exp):
        flags.append("letters_do_not_align")
    return reasons, flags, exp
