/// Low-level, single-pass line helpers shared by the block parser. No regex —
/// everything is hand-written character scanning (ported 1:1 from the Rust
/// plusparse scanner).
library;

const int _space = 0x20; // ' '
const int _tab = 0x09; // '\t'
const int _hash = 0x23; // '#'
const int _zero = 0x30; // '0'
const int _nine = 0x39; // '9'

/// Number of leading-indent columns (space = 1, tab = 4).
int indentWidth(String line) {
  var w = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == _space) {
      w += 1;
    } else if (c == _tab) {
      w += 4;
    } else {
      break;
    }
  }
  return w;
}

/// Remove up to [max] columns of leading indentation, returning the remainder.
String stripIndent(String line, int max) {
  var removed = 0;
  var idx = 0;
  while (idx < line.length && removed < max) {
    final c = line.codeUnitAt(idx);
    if (c == _space) {
      removed += 1;
      idx += 1;
    } else if (c == _tab) {
      removed += 4;
      idx += 1;
    } else {
      break;
    }
  }
  return line.substring(idx);
}

bool isBlank(String line) => line.trim().isEmpty;

/// ATX heading: 1–6 `#` followed by a space. Returns (level, content), with
/// the optional closing sequence (`## Title ##`) removed.
({int level, String content})? isHeading(String trimmed) {
  var level = 0;
  while (level < trimmed.length && trimmed.codeUnitAt(level) == _hash) {
    level += 1;
  }
  if (level >= 1 &&
      level <= 6 &&
      level < trimmed.length &&
      trimmed.codeUnitAt(level) == _space) {
    return (
      level: level,
      content: stripClosingHashes(trimmed.substring(level + 1).trim()),
    );
  }
  return null;
}

/// Thematic break: 3+ of `-`, `*`, or `_` (optionally space-separated), or `⸻`.
bool isHr(String trimmed) {
  final t = trimmed.trim();
  if (t == '⸻') {
    return true;
  }
  if (t.isEmpty) {
    return false;
  }
  final first = t[0];
  if (first != '-' && first != '*' && first != '_') {
    return false;
  }
  var count = 0;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == first) {
      count += 1;
    } else if (c == ' ') {
      continue;
    } else {
      return false;
    }
  }
  return count >= 3;
}

/// `- `, `* `, or `+ ` bullet. Returns the content after the marker.
String? unorderedMarker(String trimmed) {
  if (trimmed.length >= 2 && trimmed.codeUnitAt(1) == _space) {
    final c = trimmed[0];
    if (c == '-' || c == '*' || c == '+') {
      return trimmed.substring(2);
    }
  }
  return null;
}

/// `N. ` or `N) ` ordered marker. Returns (number, content).
({int number, String content})? orderedMarker(String trimmed) {
  var idx = 0;
  while (idx < trimmed.length) {
    final c = trimmed.codeUnitAt(idx);
    if (c < _zero || c > _nine) {
      break;
    }
    idx += 1;
  }
  if (idx == 0) {
    return null;
  }
  if (idx < trimmed.length &&
      (trimmed[idx] == '.' || trimmed[idx] == ')') &&
      idx + 1 < trimmed.length &&
      trimmed.codeUnitAt(idx + 1) == _space) {
    final num = int.tryParse(trimmed.substring(0, idx)) ?? 1;
    return (number: num, content: trimmed.substring(idx + 2));
  }
  return null;
}

/// `[x] ` / `[ ] ` checkbox. Returns (checked, content).
({bool checked, String content})? checkboxMarker(String trimmed) {
  if (trimmed.startsWith('[x] ') || trimmed.startsWith('[X] ')) {
    return (checked: true, content: trimmed.substring(4));
  }
  if (trimmed.startsWith('[ ] ')) {
    return (checked: false, content: trimmed.substring(4));
  }
  return null;
}

/// `(x) ` / `( ) ` radio. Returns (selected, content).
({bool selected, String content})? radioMarker(String trimmed) {
  if (trimmed.startsWith('(x) ') || trimmed.startsWith('(X) ')) {
    return (selected: true, content: trimmed.substring(4));
  }
  if (trimmed.startsWith('( ) ')) {
    return (selected: false, content: trimmed.substring(4));
  }
  return null;
}

// ---------------------------------------------------------------------------
// Fenced code blocks
// ---------------------------------------------------------------------------

const int _backtickUnit = 0x60; // '`'
const int _tildeUnit = 0x7E; // '~'

/// The opening line of a fenced code block: a run of at least three backticks
/// or tildes.
///
/// [fenceChar] and [length] are what a closing line has to match — see
/// [isFenceClose]. [info] is the rest of the line, trimmed (the language).
typedef FenceOpen = ({int fenceChar, int length, String info});

/// The fence [trimmed] (an already left-trimmed line) opens, or null.
///
/// CommonMark: a backtick fence's info string may not contain a backtick.
/// That is what keeps a one-line ```` ```code``` ```` an inline code span
/// instead of a fence that swallows the rest of the document.
FenceOpen? fenceOpen(String trimmed) {
  if (trimmed.length < 3) {
    return null;
  }
  final c = trimmed.codeUnitAt(0);
  if (c != _backtickUnit && c != _tildeUnit) {
    return null;
  }
  var run = 1;
  while (run < trimmed.length && trimmed.codeUnitAt(run) == c) {
    run += 1;
  }
  if (run < 3) {
    return null;
  }
  final info = trimmed.substring(run).trim();
  if (c == _backtickUnit && info.contains('`')) {
    return null;
  }
  return (fenceChar: c, length: run, info: info);
}

/// Whether [line] closes [open]: the same character, at least as many of
/// them, and nothing after but whitespace.
bool isFenceClose(String line, FenceOpen open) {
  final t = line.trim();
  if (t.length < open.length) {
    return false;
  }
  for (var i = 0; i < t.length; i++) {
    if (t.codeUnitAt(i) != open.fenceChar) {
      return false;
    }
  }
  return true;
}

/// Whether a fence opened in [lines] is still open after the last line.
///
/// The one fence-tracking loop shared by the parser's neighbours (segment
/// splitting, the streaming reveal), so they agree with the parser about
/// where a fence ends.
///
/// Fences inside a block quote count: ```` > ```bash ```` opens one, and it
/// closes with its closing line or when the quote ends.
FenceOpen? openFenceAfter(Iterable<String> lines) {
  FenceOpen? open;
  var depth = 0;
  for (final line in lines) {
    final current = open;
    final lineDepth = quoteDepth(line);
    if (current != null && lineDepth >= depth) {
      if (isFenceClose(unquoted(line), current)) {
        open = null;
      }
      continue;
    }
    open = fenceOpen(unquoted(line));
    depth = lineDepth;
  }
  return open;
}

// ---------------------------------------------------------------------------
// Code spans
// ---------------------------------------------------------------------------

/// The code span whose opening backtick run starts at [i], if it closes.
///
/// CommonMark: a span opens with a run of N backticks and closes at the next
/// run of exactly N. Returns the index of the closing run and N, or null when
/// no run of the same length follows — the opening run is then literal text.
///
/// [end] bounds the search, for callers scanning more than one paragraph: a
/// code span never crosses a blank line.
({int close, int run})? codeSpanAt(String text, int i, {int? end}) {
  final n = end ?? text.length;
  var run = 0;
  while (i + run < n && text.codeUnitAt(i + run) == _backtickUnit) {
    run += 1;
  }
  if (run == 0) {
    return null;
  }
  var j = i + run;
  while (j < n) {
    if (text.codeUnitAt(j) != _backtickUnit) {
      j += 1;
      continue;
    }
    var close = 0;
    while (j + close < n && text.codeUnitAt(j + close) == _backtickUnit) {
      close += 1;
    }
    if (close == run) {
      return (close: j, run: run);
    }
    j += close;
  }
  return null;
}

/// Length of the backtick run starting at [i].
int backtickRunAt(String text, int i) {
  var run = 0;
  while (i + run < text.length && text.codeUnitAt(i + run) == _backtickUnit) {
    run += 1;
  }
  return run;
}

/// The content of a code span, normalised the CommonMark way: line endings
/// become spaces, and one space is stripped from each end when both ends have
/// one and the content is not all spaces — which is what lets
/// ``` `` `a` `` ``` hold a backtick at its edge.
String codeSpanContent(String raw) {
  var s = raw.contains('\n') ? raw.replaceAll('\n', ' ') : raw;
  if (s.length >= 2 &&
      s.codeUnitAt(0) == _space &&
      s.codeUnitAt(s.length - 1) == _space &&
      s.trim().isNotEmpty) {
    s = s.substring(1, s.length - 1);
  }
  return s;
}

// ---------------------------------------------------------------------------
// Character classes
// ---------------------------------------------------------------------------

/// Whether [unit] is ASCII punctuation — the set a backslash can escape.
bool isAsciiPunctuation(int unit) =>
    (unit >= 0x21 && unit <= 0x2F) ||
    (unit >= 0x3A && unit <= 0x40) ||
    (unit >= 0x5B && unit <= 0x60) ||
    (unit >= 0x7B && unit <= 0x7E);

/// Unicode whitespace in CommonMark's sense: the `Zs` category plus tab, line
/// feed, form feed and carriage return. -1 (outside the text) counts as
/// whitespace, so the start and end of a run behave like a space.
bool isUnicodeWhitespace(int codePoint) {
  if (codePoint < 0) {
    return true;
  }
  if (codePoint < 0x80) {
    return codePoint == _space ||
        codePoint == _tab ||
        codePoint == 0x0A ||
        codePoint == 0x0C ||
        codePoint == 0x0D;
  }
  return codePoint == 0xA0 ||
      codePoint == 0x1680 ||
      (codePoint >= 0x2000 && codePoint <= 0x200A) ||
      codePoint == 0x202F ||
      codePoint == 0x205F ||
      codePoint == 0x3000;
}

final RegExp _unicodePunctuation = RegExp(r'^[\p{P}\p{S}]$', unicode: true);

/// Unicode punctuation in CommonMark's sense: the `P` and `S` categories.
bool isUnicodePunctuation(int codePoint) {
  if (codePoint < 0) {
    return false;
  }
  if (codePoint < 0x80) {
    return isAsciiPunctuation(codePoint);
  }
  return _unicodePunctuation.hasMatch(String.fromCharCode(codePoint));
}

/// The code point that ends just before [i], or -1 at the start.
int codePointBefore(String text, int i) {
  if (i <= 0) {
    return -1;
  }
  final low = text.codeUnitAt(i - 1);
  if (low >= 0xDC00 && low <= 0xDFFF && i >= 2) {
    final high = text.codeUnitAt(i - 2);
    if (high >= 0xD800 && high <= 0xDBFF) {
      return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
    }
  }
  return low;
}

/// The code point that starts at [i], or -1 at the end.
int codePointAt(String text, int i) {
  if (i >= text.length) {
    return -1;
  }
  final high = text.codeUnitAt(i);
  if (high >= 0xD800 && high <= 0xDBFF && i + 1 < text.length) {
    final low = text.codeUnitAt(i + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
    }
  }
  return high;
}

// ---------------------------------------------------------------------------
// Headings
// ---------------------------------------------------------------------------

/// The level of a setext underline — `1` for `===`, `2` for `---` — or null.
///
/// Up to three spaces of indent, then one run of a single character, then
/// only whitespace. Internal spaces (`- - -`) make it a thematic break, not an
/// underline.
int? setextUnderlineLevel(String line) {
  final indent = firstNonSpace(line);
  if (indent == -1 || indent > 3) {
    return null;
  }
  final first = line.codeUnitAt(indent);
  if (first != 0x3D /* = */ && first != 0x2D /* - */ ) {
    return null;
  }
  final t = line.trim();
  if (t.isEmpty) {
    return null;
  }
  final c = t.codeUnitAt(0);
  if (c != 0x3D /* = */ && c != 0x2D /* - */ ) {
    return null;
  }
  for (var i = 1; i < t.length; i++) {
    if (t.codeUnitAt(i) != c) {
      return null;
    }
  }
  return c == 0x3D ? 1 : 2;
}

/// [content] without an ATX heading's optional closing sequence.
///
/// `# Title ##` is `Title`. The `#`s only close the heading when a space comes
/// before them, so `# C#` keeps its `#`, and so does an escaped `\#`.
String stripClosingHashes(String content) {
  var end = content.length;
  while (end > 0 && content.codeUnitAt(end - 1) == _hash) {
    end -= 1;
  }
  if (end == content.length) {
    return content;
  }
  if (end == 0) {
    return '';
  }
  final before = content.codeUnitAt(end - 1);
  if (before != _space && before != _tab) {
    return content;
  }
  return content.substring(0, end).trimRight();
}

// ---------------------------------------------------------------------------
// HTML comments
// ---------------------------------------------------------------------------

/// Index of the first character that is not a space or tab, or -1.
int firstNonSpace(String line) {
  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c != _space && c != _tab) {
      return i;
    }
  }
  return -1;
}

/// Whether [line] starts, after up to three spaces, with [unit] — the cheap
/// test that lets a line-level check skip copying a line that cannot match.
bool startsAfterIndent(String line, int unit) {
  final i = firstNonSpace(line);
  return i != -1 && i <= 3 && line.codeUnitAt(i) == unit;
}

/// Whether [trimmed] opens an HTML comment.
bool startsHtmlComment(String trimmed) => trimmed.startsWith('<!--');

// ---------------------------------------------------------------------------
// Dollar maths
// ---------------------------------------------------------------------------

/// Finds the closing `$` of single-dollar maths, for one text.
///
/// Pandoc's rule, which is what keeps prices out of maths: the opening `$`
/// must have a non-space right after it, and the closing one a non-space right
/// before it and no digit right after. `$x$` and `$\frac{a}{b}$` are maths;
/// `$5 and $10` has no closer, so both dollars stay prose. An escaped `\$` and
/// either half of a `$$` never close. With [sameLine] the closer must be on
/// the opener's line.
///
/// One addition: an opener followed by a digit closes only before the next
/// whitespace. `$2^{10}$` is maths, but `cost $5 and $x^2$` is the price `$5`
/// followed by the formula `x^2` — Pandoc alone reads `5 and $x^2` as one
/// formula. The streaming reveal never opens at a digit, so the two agree on
/// every price.
///
/// The one rule the parser, the `$` rewrite and the streaming reveal share.
/// Openers must be asked about left to right: a search that fails is
/// remembered, because every later opener (on the same line, with
/// [sameLine]) would fail too. Without that a line of `$a ` repeated costs a
/// full scan per dollar.
class DollarMathCloser {
  DollarMathCloser(this.text, {this.sameLine = false});

  final String text;
  final bool sameLine;

  int _failedFrom = -1;
  int _failedUntil = -1;

  /// The closer for the `$` at [i], or -1.
  int find(int i) {
    final n = text.length;
    if (i + 1 >= n || isUnicodeWhitespace(text.codeUnitAt(i + 1))) {
      return -1;
    }
    if (_failedFrom != -1 && i >= _failedFrom && i < _failedUntil) {
      return -1;
    }
    var limit = n;
    if (sameLine) {
      final lineEnd = text.indexOf('\n', i);
      if (lineEnd != -1) {
        limit = lineEnd;
      }
    }
    final next = text.codeUnitAt(i + 1);
    final digitLed = next >= 0x30 && next <= 0x39;
    var searchLimit = limit;
    if (digitLed) {
      var w = i + 1;
      while (w < limit && !isUnicodeWhitespace(text.codeUnitAt(w))) {
        w += 1;
      }
      searchLimit = w;
    }
    var k = text.indexOf(r'$', i + 1);
    while (k != -1 && k < searchLimit) {
      final before = text.codeUnitAt(k - 1);
      final after = k + 1 < n ? text.codeUnitAt(k + 1) : -1;
      if (k > i + 1 &&
          before != 0x5C /* \ */ &&
          before != 0x24 /* $ */ &&
          after != 0x24 &&
          !isUnicodeWhitespace(before) &&
          !(after >= 0x30 && after <= 0x39)) {
        return k;
      }
      k = text.indexOf(r'$', k + 1);
    }
    if (!digitLed) {
      _failedFrom = i;
      _failedUntil = limit;
    }
    return -1;
  }
}

/// Index of the end of the paragraph containing [i]: the next line break that
/// is followed by a blank line, or the end of [text].
int paragraphEnd(String text, int i) {
  var k = text.indexOf('\n', i);
  while (k != -1) {
    var j = k + 1;
    while (j < text.length &&
        (text.codeUnitAt(j) == _space || text.codeUnitAt(j) == _tab)) {
      j += 1;
    }
    if (j >= text.length || text.codeUnitAt(j) == 0x0A) {
      return k;
    }
    k = text.indexOf('\n', j);
  }
  return text.length;
}

// ---------------------------------------------------------------------------
// Blank lines inside a block
// ---------------------------------------------------------------------------

/// Whether a blank line followed by [next] continues the block that [before]
/// ends with, rather than separating two blocks.
///
/// It does when [next] is indented under a list item — a second paragraph
/// or a fenced code block that belongs to the item, the shape of almost every
/// step-by-step answer — or under a footnote definition. The owner is the
/// nearest earlier line indented less than [next]; it continues the item
/// exactly when the parser would nest [next] under it.
///
/// For the code that cuts a document into independently parsed pieces at
/// blank lines: cutting here moved the item's code block out of the list,
/// and parsed alone, every line of it kept the item's indentation.
bool continuesAfterBlank(List<String> before, String next) {
  final indent = indentWidth(next);
  if (indent == 0) {
    return false;
  }
  for (var k = before.length - 1; k >= 0; k--) {
    final line = before[k];
    if (isBlank(line)) {
      continue;
    }
    if (indentWidth(line) >= indent) {
      continue;
    }
    final t = line.trimLeft();
    if (unorderedMarker(t) != null || orderedMarker(t) != null) {
      return true;
    }
    return indent >= 4 && t.startsWith('[^');
  }
  return false;
}

// ---------------------------------------------------------------------------
// Block quote markers
// ---------------------------------------------------------------------------

/// How many `>` quote markers open [line].
int quoteDepth(String line) {
  var depth = 0;
  var i = 0;
  while (i < line.length) {
    final c = line.codeUnitAt(i);
    if (c == _space || c == _tab) {
      i += 1;
    } else if (c == 0x3E /* > */ ) {
      depth += 1;
      i += 1;
    } else {
      break;
    }
  }
  return depth;
}

/// [line] without its leading `>` quote markers and indentation — what a
/// fence check has to look at, so ```` > ```bash ```` is seen as the fence
/// it is.
String unquoted(String line) {
  var i = 0;
  while (i < line.length) {
    final c = line.codeUnitAt(i);
    if (c == _space || c == _tab || c == 0x3E /* > */ ) {
      i += 1;
    } else {
      break;
    }
  }
  return i == 0 ? line : line.substring(i);
}
