/// HTML entity and numeric character references (`&amp;`, `&#169;`,
/// `&#x1F600;`), decoded the CommonMark way.
///
/// Numeric references are complete. Named ones are a curated subset of the
/// HTML5 table: the whole Latin-1 range, the Greek alphabet, and the
/// punctuation, arrow and maths names that turn up in prose. A name outside
/// the subset stays literal text — which is also what CommonMark does with a
/// name that is not an entity — so the subset can only under-decode, never
/// mis-decode.
library;

const int _amp = 0x26; // '&'
const int _semicolon = 0x3B; // ';'
const int _hashUnit = 0x23; // '#'

/// The reference starting at the `&` at [i], decoded, and the index just past
/// its `;` — or null when the text there is not a reference.
({String value, int next})? entityAt(String text, int i) {
  final n = text.length;
  if (i >= n || text.codeUnitAt(i) != _amp) {
    return null;
  }
  var j = i + 1;
  if (j < n && text.codeUnitAt(j) == _hashUnit) {
    j += 1;
    final hex = j < n && (text.codeUnitAt(j) | 0x20) == 0x78; // x / X
    if (hex) {
      j += 1;
    }
    final start = j;
    final maxDigits = hex ? 6 : 7;
    while (j < n &&
        j - start < maxDigits &&
        _isDigit(text.codeUnitAt(j), hex)) {
      j += 1;
    }
    if (j == start || j >= n || text.codeUnitAt(j) != _semicolon) {
      return null;
    }
    var codePoint = int.parse(text.substring(start, j), radix: hex ? 16 : 10);
    // CommonMark: an invalid code point, and U+0000, become U+FFFD.
    if (codePoint == 0 ||
        codePoint > 0x10FFFF ||
        (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      codePoint = 0xFFFD;
    }
    return (value: String.fromCharCode(codePoint), next: j + 1);
  }
  final start = j;
  while (j < n && j - start < 32 && _isAlphanumeric(text.codeUnitAt(j))) {
    j += 1;
  }
  if (j == start || j >= n || text.codeUnitAt(j) != _semicolon) {
    return null;
  }
  final value = _named[text.substring(start, j)];
  if (value == null) {
    return null;
  }
  return (value: value, next: j + 1);
}

/// [text] with every reference in it decoded. Used for link destinations and
/// titles, where CommonMark decodes references too.
String decodeEntities(String text) {
  if (!text.contains('&')) {
    return text;
  }
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text.codeUnitAt(i) == _amp) {
      final entity = entityAt(text, i);
      if (entity != null) {
        out.write(entity.value);
        i = entity.next;
        continue;
      }
    }
    out.writeCharCode(text.codeUnitAt(i));
    i += 1;
  }
  return out.toString();
}

bool _isDigit(int c, bool hex) {
  if (c >= 0x30 && c <= 0x39) {
    return true;
  }
  if (!hex) {
    return false;
  }
  final lower = c | 0x20;
  return lower >= 0x61 && lower <= 0x66;
}

bool _isAlphanumeric(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A);

const Map<String, String> _named = {
  // Markup-significant.
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  // Latin-1 supplement.
  'nbsp': ' ', 'iexcl': '¡', 'cent': '¢', 'pound': '£', 'curren': '¤',
  'yen': '¥', 'brvbar': '¦', 'sect': '§', 'uml': '¨', 'copy': '©',
  'ordf': 'ª', 'laquo': '«', 'not': '¬', 'shy': '­', 'reg': '®',
  'macr': '¯', 'deg': '°', 'plusmn': '±', 'sup2': '²', 'sup3': '³',
  'acute': '´', 'micro': 'µ', 'para': '¶', 'middot': '·', 'cedil': '¸',
  'sup1': '¹', 'ordm': 'º', 'raquo': '»', 'frac14': '¼', 'frac12': '½',
  'frac34': '¾', 'iquest': '¿', 'Agrave': 'À', 'Aacute': 'Á', 'Acirc': 'Â',
  'Atilde': 'Ã', 'Auml': 'Ä', 'Aring': 'Å', 'AElig': 'Æ', 'Ccedil': 'Ç',
  'Egrave': 'È', 'Eacute': 'É', 'Ecirc': 'Ê', 'Euml': 'Ë', 'Igrave': 'Ì',
  'Iacute': 'Í', 'Icirc': 'Î', 'Iuml': 'Ï', 'ETH': 'Ð', 'Ntilde': 'Ñ',
  'Ograve': 'Ò', 'Oacute': 'Ó', 'Ocirc': 'Ô', 'Otilde': 'Õ', 'Ouml': 'Ö',
  'times': '×', 'Oslash': 'Ø', 'Ugrave': 'Ù', 'Uacute': 'Ú', 'Ucirc': 'Û',
  'Uuml': 'Ü', 'Yacute': 'Ý', 'THORN': 'Þ', 'szlig': 'ß', 'agrave': 'à',
  'aacute': 'á', 'acirc': 'â', 'atilde': 'ã', 'auml': 'ä', 'aring': 'å',
  'aelig': 'æ', 'ccedil': 'ç', 'egrave': 'è', 'eacute': 'é', 'ecirc': 'ê',
  'euml': 'ë', 'igrave': 'ì', 'iacute': 'í', 'icirc': 'î', 'iuml': 'ï',
  'eth': 'ð', 'ntilde': 'ñ', 'ograve': 'ò', 'oacute': 'ó', 'ocirc': 'ô',
  'otilde': 'õ', 'ouml': 'ö', 'divide': '÷', 'oslash': 'ø', 'ugrave': 'ù',
  'uacute': 'ú', 'ucirc': 'û', 'uuml': 'ü', 'yacute': 'ý', 'thorn': 'þ',
  'yuml': 'ÿ',
  // Latin extended.
  'OElig': 'Œ', 'oelig': 'œ', 'Scaron': 'Š', 'scaron': 'š', 'Yuml': 'Ÿ',
  'fnof': 'ƒ', 'circ': 'ˆ', 'tilde': '˜',
  // Greek.
  'Alpha': 'Α', 'Beta': 'Β', 'Gamma': 'Γ', 'Delta': 'Δ', 'Epsilon': 'Ε',
  'Zeta': 'Ζ', 'Eta': 'Η', 'Theta': 'Θ', 'Iota': 'Ι', 'Kappa': 'Κ',
  'Lambda': 'Λ', 'Mu': 'Μ', 'Nu': 'Ν', 'Xi': 'Ξ', 'Omicron': 'Ο', 'Pi': 'Π',
  'Rho': 'Ρ', 'Sigma': 'Σ', 'Tau': 'Τ', 'Upsilon': 'Υ', 'Phi': 'Φ',
  'Chi': 'Χ', 'Psi': 'Ψ', 'Omega': 'Ω', 'alpha': 'α', 'beta': 'β',
  'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
  'theta': 'θ', 'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'mu': 'μ',
  'nu': 'ν', 'xi': 'ξ', 'omicron': 'ο', 'pi': 'π', 'rho': 'ρ',
  'sigmaf': 'ς', 'sigma': 'σ', 'tau': 'τ', 'upsilon': 'υ', 'phi': 'φ',
  'chi': 'χ', 'psi': 'ψ', 'omega': 'ω', 'thetasym': 'ϑ', 'piv': 'ϖ',
  // Spaces and joiners.
  'ensp': ' ', 'emsp': ' ', 'thinsp': ' ', 'hairsp': ' ',
  'zwnj': '‌', 'zwj': '‍', 'lrm': '‎', 'rlm': '‏',
  // Punctuation.
  'ndash': '–', 'mdash': '—', 'lsquo': '‘', 'rsquo': '’', 'sbquo': '‚',
  'ldquo': '“', 'rdquo': '”', 'bdquo': '„', 'dagger': '†', 'Dagger': '‡',
  'bull': '•', 'hellip': '…', 'permil': '‰', 'prime': '′', 'Prime': '″',
  'lsaquo': '‹', 'rsaquo': '›', 'oline': '‾', 'frasl': '⁄', 'euro': '€',
  'trade': '™', 'check': '✓', 'cross': '✗', 'star': '☆', 'starf': '★',
  // Arrows.
  'larr': '←', 'uarr': '↑', 'rarr': '→', 'darr': '↓', 'harr': '↔',
  'crarr': '↵', 'lArr': '⇐', 'uArr': '⇑', 'rArr': '⇒', 'dArr': '⇓',
  'hArr': '⇔',
  // Mathematics.
  'forall': '∀', 'part': '∂', 'exist': '∃', 'empty': '∅', 'nabla': '∇',
  'isin': '∈', 'notin': '∉', 'ni': '∋', 'prod': '∏', 'sum': '∑',
  'minus': '−', 'lowast': '∗', 'radic': '√', 'prop': '∝', 'infin': '∞',
  'ang': '∠', 'and': '∧', 'or': '∨', 'cap': '∩', 'cup': '∪', 'int': '∫',
  'there4': '∴', 'sim': '∼', 'cong': '≅', 'asymp': '≈', 'ne': '≠',
  'equiv': '≡', 'le': '≤', 'ge': '≥', 'sub': '⊂', 'sup': '⊃', 'nsub': '⊄',
  'sube': '⊆', 'supe': '⊇', 'oplus': '⊕', 'otimes': '⊗', 'perp': '⊥',
  'sdot': '⋅', 'lceil': '⌈', 'rceil': '⌉', 'lfloor': '⌊', 'rfloor': '⌋',
  'lang': '⟨', 'rang': '⟩', 'loz': '◊', 'spades': '♠', 'clubs': '♣',
  'hearts': '♥', 'diams': '♦',
};
