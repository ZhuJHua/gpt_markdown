/// Inline parser: turns a run of text into inline [MdNode]s (bold, italic,
/// code, links, images, LaTeX, source tags, …). Single forward pass over the
/// characters; emphasis content is parsed recursively. Ported 1:1 from the
/// Rust plusparse inline parser, using code-unit scanning and `indexOf`
/// instead of a char vector (all delimiters are ASCII, so this is safe and
/// fast on Dart's UTF-16 strings).
library;

import 'dart:typed_data';

import 'ast.dart';
import 'definitions.dart';
import 'entities.dart';
import 'scanner.dart';

const int _bang = 0x21; // '!'
const int _openBracket = 0x5B; // '['
const int _star = 0x2A; // '*'
const int _underscore = 0x5F; // '_'
const int _tilde = 0x7E; // '~'
const int _backtick = 0x60; // '`'
const int _lt = 0x3C; // '<'
const int _backslash = 0x5C; // '\'
const int _dollar = 0x24; // '$'
const int _amp = 0x26; // '&'
const int _caret = 0x5E; // '^'
const int _newline = 0x0A; // '\n'
const int _openParen = 0x28; // '('
const int _closeBracket = 0x5D; // ']'
const int _closeParen = 0x29; // ')'

/// Code units that can begin an inline construct.
///
/// Everything else is ordinary text, and the parser's only job for it is to
/// copy it through. Testing that with a table lets a run of plain prose be
/// found with one comparison per character and copied with a single
/// `substring`, instead of running the whole construct dispatch on every
/// character and appending them one at a time — which is most of the work in
/// the common case, because most of a reply is prose.
///
/// A table rather than a bitmask: Dart's web targets have no 64-bit integers,
/// and a mask over the ASCII range would need them.
final Uint8List _inlineTriggers = () {
  final table = Uint8List(128);
  for (final unit in <int>[
    _bang,
    _dollar,
    _amp,
    _star,
    _underscore,
    _lt,
    _openBracket,
    _backslash,
    _backtick,
    _tilde,
  ]) {
    table[unit] = 1;
  }
  return table;
}();

/// Whether [unit] can begin an inline construct.
///
/// Non-ASCII never can — every delimiter in the dialect is ASCII — so the
/// bounds check doubles as the answer for the whole of Unicode above 127.
bool _canStartConstruct(int unit) => unit < 128 && _inlineTriggers[unit] == 1;

/// Whether the `_` at [j] sits between two ASCII letters or digits.
///
/// Such an underscore can neither open nor close emphasis, so the plain-text
/// fast path keeps going through it. Identifiers like `snake_case_name` are
/// common in replies, and sending each of their underscores through the
/// dispatch chain is wasted work. Only ever asked about an actual `_`, so the
/// per-character cost of the fast path is unchanged.
bool _intrawordUnderscore(String text, int j) =>
    j > 0 &&
    j + 1 < text.length &&
    _isAsciiAlphanumeric(text.codeUnitAt(j - 1)) &&
    _isAsciiAlphanumeric(text.codeUnitAt(j + 1));

bool _isAsciiAlphanumeric(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A);

List<MdNode> parseInline(
  String text,
  bool useDollar, [
  MarkdownDefinitions defs = MarkdownDefinitions.empty,
]) {
  final n = text.length;

  // Most runs of an assistant's prose contain no markup at all. Finding that
  // out costs one scan, and skips the buffer, the delimiter tables and the
  // dispatch loop entirely.
  var plainUntil = 0;
  while (plainUntil < n) {
    final unit = text.codeUnitAt(plainUntil);
    if (_canStartConstruct(unit) &&
        (unit != _underscore || !_intrawordUnderscore(text, plainUntil))) {
      break;
    }
    plainUntil += 1;
  }
  if (plainUntil == n) {
    return n == 0 ? <MdNode>[] : <MdNode>[MdText(text: text)];
  }

  final delims = _Delims(text);
  final closers = _Closers(text);
  final dollars = useDollar ? DollarMathCloser(text) : null;
  final urls = _BareUrls(text);
  final nodes = <MdNode>[];
  final buf = StringBuffer();
  var i = 0;

  void flush() {
    if (buf.isNotEmpty) {
      nodes.add(MdText(text: buf.toString()));
      buf.clear();
    }
  }

  while (i < n) {
    final c = text.codeUnitAt(i);

    // Fast path: a run of characters that cannot begin a construct is copied
    // through in one piece. This is the bulk of ordinary prose, and skipping
    // the dispatch chain for it is what keeps the parser's cost close to a
    // scan.
    if (!_canStartConstruct(c) ||
        (c == _underscore && _intrawordUnderscore(text, i))) {
      var j = i + 1;
      while (j < n) {
        final unit = text.codeUnitAt(j);
        if (_canStartConstruct(unit) &&
            (unit != _underscore || !_intrawordUnderscore(text, j))) {
          break;
        }
        j += 1;
      }
      buf.write(text.substring(i, j));
      i = j;
      continue;
    }

    var matched = false;

    // ![alt](url)  or  ![alt][label]
    if (c == _bang &&
        i + 1 < n &&
        text.codeUnitAt(i + 1) == _openBracket &&
        delims.bracket.containsKey(i + 1)) {
      final r =
          _tryImage(text, i, delims) ??
          _tryReferenceImage(text, i, delims, defs);
      if (r != null) {
        flush();
        nodes.add(r.node);
        i = r.next;
        matched = true;
      }
    }

    // [text](url), [text][label], [label], [^note]  or  [123] source tag
    if (!matched && c == _openBracket) {
      final link =
          _tryLink(text, i, useDollar, delims, defs) ??
          _tryReferenceLink(text, i, useDollar, delims, defs) ??
          _tryFootnoteReference(text, i, delims, defs) ??
          _trySourceTag(text, i, defs);
      if (link != null) {
        flush();
        nodes.add(link.node);
        i = link.next;
        matched = true;
      }
    }

    // **bold**, *italic*, __bold__, _italic_
    if (!matched && (c == _star || c == _underscore)) {
      // Emphasis is decided by the length of the *run* of delimiters, not by
      // the first one. Reading `***both***` as `**` starting at the second
      // asterisk left a stray `*` inside the bold, and closing a single `*`
      // with `indexOf('*')` landed on the opening half of a nested `**`, which
      // dropped the bold and cut the italic into pieces.
      var run = 1;
      while (i + run < n && text.codeUnitAt(i + run) == c) {
        run += 1;
      }

      if (_canOpen(text, i, run, c, urls)) {
        // `***x***` is both.
        if (run >= 3) {
          final close = closers.find(i + run, c, 3);
          if (close != -1) {
            final inner = text.substring(i + 3, close);
            if (inner.trim().isNotEmpty) {
              flush();
              nodes.add(
                MdBold(
                  children: [
                    MdItalic(children: parseInline(inner, useDollar, defs)),
                  ],
                ),
              );
              i = close + 3;
              matched = true;
            }
          }
        }
        if (!matched && run == 2) {
          final close = closers.find(i + 2, c, 2);
          if (close != -1) {
            final inner = text.substring(i + 2, close);
            if (inner.trim().isNotEmpty) {
              flush();
              nodes.add(MdBold(children: parseInline(inner, useDollar, defs)));
              i = close + 2;
              matched = true;
            }
          }
        }
        if (!matched && run == 1) {
          // Only a lone delimiter closes an italic; a `**` inside it opens a
          // bold, which the recursive parse below then claims.
          final close = closers.find(i + 1, c, 1, exact: true);
          if (close != -1) {
            final inner = text.substring(i + 1, close);
            if (inner.trim().isNotEmpty) {
              flush();
              nodes.add(
                MdItalic(children: parseInline(inner, useDollar, defs)),
              );
              i = close + 1;
              matched = true;
            }
          }
        }
      }
    }

    // ~~strike~~
    if (!matched &&
        c == _tilde &&
        i + 1 < n &&
        text.codeUnitAt(i + 1) == _tilde) {
      final end = text.indexOf('~~', i + 2);
      if (end != -1) {
        flush();
        nodes.add(
          MdStrike(
            children: parseInline(text.substring(i + 2, end), useDollar, defs),
          ),
        );
        i = end + 2;
        matched = true;
      }
    }

    // `code`, ``co`de`` — a run of N backticks closes at the next run of
    // exactly N. An opening run with no closer is literal, all of it.
    if (!matched && c == _backtick) {
      final span = codeSpanAt(text, i);
      if (span != null) {
        flush();
        nodes.add(
          MdInlineCode(
            text: codeSpanContent(text.substring(i + span.run, span.close)),
          ),
        );
        i = span.close + span.run;
      } else {
        final run = backtickRunAt(text, i);
        buf.write(text.substring(i, i + run));
        i += run;
      }
      matched = true;
    }

    // <u>underline</u>
    if (!matched && c == _lt && text.startsWith('<u>', i)) {
      final end = text.indexOf('</u>', i + 3);
      if (end != -1) {
        flush();
        nodes.add(
          MdUnderline(
            children: parseInline(text.substring(i + 3, end), useDollar, defs),
          ),
        );
        i = end + 4;
        matched = true;
      }
    }

    // <!-- comment --> — dropped, as an HTML renderer would hide it.
    if (!matched && c == _lt && text.startsWith('<!--', i)) {
      final end = text.indexOf('-->', i + 4);
      if (end != -1) {
        i = end + 3;
        matched = true;
      }
    }

    // \[ block latex \] in an inline position.
    //
    // The block parser claims `\[` only when it opens a line, so block maths
    // written mid-sentence — or after a list marker, `1. Result: \[ x^2 \]` —
    // used to survive as literal text. The syntax is recognised wherever it
    // appears; it still renders as a block, because that is what it is.
    if (!matched &&
        c == _backslash &&
        i + 1 < n &&
        text.codeUnitAt(i + 1) == _openBracket) {
      final end = text.indexOf('\\]', i + 2);
      if (end != -1) {
        flush();
        nodes.add(MdBlockLatex(tex: text.substring(i + 2, end).trim()));
        i = end + 2;
        matched = true;
      }
    }

    // \( inline latex \)
    if (!matched &&
        c == _backslash &&
        i + 1 < n &&
        text.codeUnitAt(i + 1) == _openParen) {
      final end = text.indexOf('\\)', i + 2);
      if (end != -1) {
        flush();
        nodes.add(MdInlineLatex(tex: text.substring(i + 2, end).trim()));
        i = end + 2;
        matched = true;
      }
    }

    // Backslash escapes. Any ASCII punctuation after a backslash is literal —
    // `\*`, `\_`, `\#`, `\$`, and `\|`, the GFM escape a table cell uses for a
    // pipe (cells are split before this runs; see _splitPipes in
    // block_parser.dart). A backslash before a line break is a hard break.
    //
    // Not `\(`, `\)`, `\[` or `\]`: in this dialect those are maths
    // delimiters, matched above when they pair up. An unpaired one stays
    // exactly as written, which is also what the streaming reveal expects of
    // a formula still arriving.
    if (!matched && c == _backslash && i + 1 < n) {
      final next = text.codeUnitAt(i + 1);
      if (next == _newline) {
        buf.writeCharCode(_newline);
        i += 2;
        matched = true;
      } else if (isAsciiPunctuation(next) &&
          next != _openParen &&
          next != _closeParen &&
          next != _openBracket &&
          next != _closeBracket) {
        buf.writeCharCode(next);
        i += 2;
        matched = true;
      }
    }

    // $$ … $$  /  $ … $  (only when enabled)
    if (!matched && useDollar && c == _dollar) {
      if (i + 1 < n && text.codeUnitAt(i + 1) == _dollar) {
        final end = text.indexOf(r'$$', i + 2);
        if (end != -1) {
          flush();
          nodes.add(MdInlineLatex(tex: text.substring(i + 2, end).trim()));
          i = end + 2;
          matched = true;
        }
      }
      if (!matched) {
        final end = dollars!.find(i);
        if (end != -1) {
          flush();
          nodes.add(MdInlineLatex(tex: text.substring(i + 1, end).trim()));
          i = end + 1;
          matched = true;
        }
      }
    }

    // &amp;  &#169;  &#x1F600; — but not inside a bare URL. The autolinker
    // reads the raw text there, and GFM has it leave a trailing `&amp;` out
    // of the link, which it can only do if the reference is still written.
    if (!matched && c == _amp && !urls.contains(i)) {
      final entity = entityAt(text, i);
      if (entity != null) {
        buf.write(entity.value);
        i = entity.next;
        matched = true;
      }
    }

    if (!matched) {
      buf.writeCharCode(c);
      i += 1;
    }
  }

  flush();
  return nodes;
}

/// Whether the run of [run] [delimiter]s at [i] can open emphasis.
///
/// `*` follows CommonMark's whitespace rule: it cannot open when whitespace
/// follows it, so `2 * 3 * 4` stays arithmetic. CommonMark's further
/// punctuation rule is deliberately not applied to `*`: it would stop
/// `**Note:**text` and CJK text such as `**粗体：**中文` from being bold,
/// which models write constantly.
///
/// `_` follows CommonMark exactly, which adds that it cannot open inside a
/// word: `snake_case_name` stays an identifier. It also cannot open inside a
/// bare URL, so `https://x.com/_a_` reaches the autolinker whole.
bool _canOpen(String text, int i, int run, int delimiter, _BareUrls urls) {
  final after = codePointAt(text, i + run);
  if (isUnicodeWhitespace(after)) {
    return false;
  }
  if (delimiter == _star) {
    return true;
  }
  final before = codePointBefore(text, i);
  if (!isUnicodeWhitespace(before) && !isUnicodePunctuation(before)) {
    return false;
  }
  return !urls.contains(i);
}

/// Whether the run of [run] [delimiter]s at [i] can close emphasis — the
/// mirror image of [_canOpen].
bool _canClose(String text, int i, int run, int delimiter) {
  final before = codePointBefore(text, i);
  if (isUnicodeWhitespace(before)) {
    return false;
  }
  if (delimiter == _star) {
    return true;
  }
  final after = codePointAt(text, i + run);
  return isUnicodeWhitespace(after) || isUnicodePunctuation(after);
}

/// Answers "is this position inside a bare URL?" for one parse: whether
/// the whitespace-delimited word around it starts with `www.` or holds `://`
/// before it.
///
/// Positions must be asked about left to right. The scan state carries over
/// between questions, so the whole parse reads each character once — walking
/// back to the start of the word on every `&` or `_` made a long run of them
/// quadratic.
class _BareUrls {
  _BareUrls(this.text);

  final String text;
  int _scanned = 0;
  int _wordStart = 0;
  bool _hasScheme = false;

  bool contains(int i) {
    for (var j = _scanned; j < i; j++) {
      final c = text.codeUnitAt(j);
      if (isUnicodeWhitespace(c)) {
        _wordStart = j + 1;
        _hasScheme = false;
      } else if (!_hasScheme &&
          c == 0x2F /* / */ &&
          j - 2 >= _wordStart &&
          text.codeUnitAt(j - 1) == 0x2F &&
          text.codeUnitAt(j - 2) == 0x3A /* : */ ) {
        _hasScheme = true;
      }
    }
    if (i > _scanned) {
      _scanned = i;
    }
    if (_hasScheme) {
      return true;
    }
    return i - _wordStart >= 4 &&
        text.substring(_wordStart, _wordStart + 4).toLowerCase() == 'www.';
  }
}

/// Finds emphasis closers for one parse.
///
/// The search steps over what binds tighter than emphasis — backslash
/// escapes, code spans and `\(…\)` / `\[…\]` maths — so `*a `*` b*` is one
/// italic around a code span, not an italic that ends inside it.
///
/// A search that fails is remembered: every later search for the same closer
/// starts further right and would fail too. Without that, a line of openers
/// that never close — `*a *b *c …` — costs a full scan per opener.
class _Closers {
  _Closers(this.text);

  final String text;

  /// Built on first failure: most parses find every closer they look for.
  Map<int, int>? _failedFrom;

  int find(int from, int delimiter, int length, {bool exact = false}) {
    final key = delimiter * 8 + length * 2 + (exact ? 1 : 0);
    final failed = _failedFrom?[key];
    if (failed != null && from >= failed) {
      return -1;
    }
    final n = text.length;
    var i = from;
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (c == _backslash && i + 1 < n) {
        final next = text.codeUnitAt(i + 1);
        if (next == _openParen || next == _openBracket) {
          final end = text.indexOf(next == _openParen ? r'\)' : r'\]', i + 2);
          if (end != -1) {
            i = end + 2;
            continue;
          }
        }
        i += 2;
        continue;
      }
      if (c == _backtick) {
        final span = codeSpanAt(text, i);
        i = span != null ? span.close + span.run : i + backtickRunAt(text, i);
        continue;
      }
      if (c != delimiter) {
        i += 1;
        continue;
      }
      var run = 1;
      while (i + run < n && text.codeUnitAt(i + run) == delimiter) {
        run += 1;
      }
      if ((exact ? run == length : run >= length) &&
          _canClose(text, i, run, delimiter)) {
        return i;
      }
      i += run;
    }
    (_failedFrom ??= <int, int>{})[key] = from;
    return -1;
  }
}

typedef _InlineMatch = ({MdNode node, int next});

/// Delimiter positions, resolved once per parse.
///
/// A `_try*` that scans forward for its closer is O(n) per opener, so text
/// made of unmatched or nested openers — `[[[[[[`, `[a](` repeated — costs
/// O(n²). Both tables below are built in one pass with a stack, which makes
/// every lookup O(1) and the whole parse linear.
class _Delims {
  _Delims(this.text);

  final String text;

  Map<int, int>? _bracket;
  Map<int, int>? _paren;

  /// Index of `[` to index of its matching `]`.
  ///
  /// Built on first use: most runs of text contain no brackets at all, and
  /// paying for the table there costs more than it saves.
  Map<int, int> get bracket {
    _ensurePairs();
    return _bracket!;
  }

  /// Index of `(` to index of its matching `)`.
  Map<int, int> get paren {
    _ensurePairs();
    return _paren!;
  }

  /// Fills both tables in one pass.
  ///
  /// Separately they are two scans of the same string, and the constructs
  /// that consult one — links, images — almost always go on to consult the
  /// other, so the second scan was rarely avoided anyway.
  void _ensurePairs() {
    if (_bracket != null) {
      return;
    }
    final brackets = <int, int>{};
    final parens = <int, int>{};
    final bracketStack = <int>[];
    final parenStack = <int>[];
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == _backslash) {
        i += 1;
        continue;
      }
      switch (c) {
        case _openBracket:
          bracketStack.add(i);
        case _closeBracket:
          if (bracketStack.isNotEmpty) {
            brackets[bracketStack.removeLast()] = i;
          }
        case _openParen:
          parenStack.add(i);
        case _closeParen:
          if (parenStack.isNotEmpty) {
            parens[parenStack.removeLast()] = i;
          }
      }
    }
    _bracket = brackets;
    _paren = parens;
  }
}

_InlineMatch? _tryImage(String text, int i, _Delims delims) {
  final n = text.length;
  final j0 = delims.bracket[i + 1]; // past '!'
  if (j0 == null) {
    return null;
  }
  var j = j0 + 1; // past ']'
  if (j >= n || text.codeUnitAt(j) != _openParen) {
    return null;
  }
  final close = delims.paren[j];
  if (close == null) {
    return null;
  }
  // Sliced only now that the whole shape has matched. Slicing before the
  // check copies the label of every unmatched `[` in the document.
  final alt = text.substring(i + 2, j0);
  final target = parseLinkTarget(text.substring(j + 1, close))!;
  final size = _parseImageSize(alt);
  return (
    node: MdImage(
      url: target.url,
      alt: alt,
      width: size.width,
      height: size.height,
      title: target.title,
    ),
    next: close + 1,
  );
}

/// `![alt][label]`, `![alt][]` or `![alt]` against a reference definition.
_InlineMatch? _tryReferenceImage(
  String text,
  int i,
  _Delims delims,
  MarkdownDefinitions defs,
) {
  final ref = _resolveReference(text, i + 1, delims, defs);
  if (ref == null) {
    return null;
  }
  final alt = text.substring(i + 2, ref.labelEnd);
  final size = _parseImageSize(alt);
  return (
    node: MdImage(
      url: ref.definition.url,
      alt: alt,
      width: size.width,
      height: size.height,
      title: ref.definition.title,
    ),
    next: ref.next,
  );
}

/// Parse an alt text of the form `WxH` (e.g. `100x200`, `100x`, `x200`).
({double? width, double? height}) _parseImageSize(String alt) {
  final t = alt.trim();
  final x = t.indexOf('x');
  if (x != -1) {
    final a = t.substring(0, x);
    final b = t.substring(x + 1);
    final aOk = a.isNotEmpty && _allAsciiDigits(a);
    final bOk = b.isNotEmpty && _allAsciiDigits(b);
    if ((aOk || a.isEmpty) && (bOk || b.isEmpty) && (aOk || bOk)) {
      return (
        width: aOk ? double.tryParse(a) : null,
        height: bOk ? double.tryParse(b) : null,
      );
    }
  }
  return (width: null, height: null);
}

bool _allAsciiDigits(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) {
      return false;
    }
  }
  return true;
}

_InlineMatch? _tryLink(
  String text,
  int i,
  bool useDollar,
  _Delims delims,
  MarkdownDefinitions defs,
) {
  final n = text.length;
  final j0 = delims.bracket[i];
  if (j0 == null) {
    return null;
  }
  var j = j0 + 1; // past ']'
  if (j >= n || text.codeUnitAt(j) != _openParen) {
    return null;
  }
  final close = delims.paren[j];
  if (close == null) {
    return null;
  }
  // Sliced only now that the whole shape has matched. Slicing before the
  // check copies the label of every unmatched `[` in the document.
  final linkText = text.substring(i + 1, j0);
  final target = parseLinkTarget(text.substring(j + 1, close))!;
  return (
    node: MdLink(
      children: parseInline(linkText, useDollar, defs),
      url: target.url,
      title: target.title,
    ),
    next: close + 1,
  );
}

/// `[text][label]`, `[text][]` or `[text]` against a reference definition.
///
/// An all-digit shortcut such as `[1]` is left to [_trySourceTag]: it is a
/// citation, and stays one even when the document defines its URL.
_InlineMatch? _tryReferenceLink(
  String text,
  int i,
  bool useDollar,
  _Delims delims,
  MarkdownDefinitions defs,
) {
  final ref = _resolveReference(text, i, delims, defs);
  if (ref == null) {
    return null;
  }
  return (
    node: MdLink(
      children: parseInline(
        text.substring(i + 1, ref.labelEnd),
        useDollar,
        defs,
      ),
      url: ref.definition.url,
      title: ref.definition.title,
    ),
    next: ref.next,
  );
}

/// Resolves the reference whose first bracket is at [i].
///
/// [labelEnd] is the `]` closing the link text; [next] is the index after the
/// whole reference.
({MdLinkDefinition definition, int labelEnd, int next})? _resolveReference(
  String text,
  int i,
  _Delims delims,
  MarkdownDefinitions defs,
) {
  final j0 = delims.bracket[i];
  if (j0 == null) {
    return null;
  }
  final linkText = text.substring(i + 1, j0);
  final after = j0 + 1;
  if (after < text.length && text.codeUnitAt(after) == _openBracket) {
    final k = delims.bracket[after];
    if (k != null) {
      // Full `[text][label]`, or collapsed `[text][]` (the text is the label).
      final label = text.substring(after + 1, k);
      final definition = defs.link(label.trim().isEmpty ? linkText : label);
      if (definition == null) {
        return null;
      }
      return (definition: definition, labelEnd: j0, next: k + 1);
    }
  }
  // Shortcut `[label]`.
  if (linkText.trim().isEmpty ||
      linkText.startsWith('^') ||
      _allAsciiDigits(linkText)) {
    return null;
  }
  final definition = defs.link(linkText);
  if (definition == null) {
    return null;
  }
  return (definition: definition, labelEnd: j0, next: j0 + 1);
}

/// `[^label]`, when the document defines that footnote.
_InlineMatch? _tryFootnoteReference(
  String text,
  int i,
  _Delims delims,
  MarkdownDefinitions defs,
) {
  if (i + 1 >= text.length || text.codeUnitAt(i + 1) != _caret) {
    return null;
  }
  final j0 = delims.bracket[i];
  if (j0 == null || j0 < i + 3) {
    return null;
  }
  final label = text.substring(i + 2, j0);
  for (var k = 0; k < label.length; k++) {
    if (isUnicodeWhitespace(label.codeUnitAt(k))) {
      return null;
    }
  }
  final number = defs.footnote(label);
  if (number == null) {
    return null;
  }
  return (
    node: MdFootnoteReference(label: label, number: number),
    next: j0 + 1,
  );
}

_InlineMatch? _trySourceTag(String text, int i, MarkdownDefinitions defs) {
  final n = text.length;
  var j = i + 1; // past '['
  final start = j;
  while (j < n) {
    final c = text.codeUnitAt(j);
    if (c < 0x30 || c > 0x39) {
      break;
    }
    j += 1;
  }
  if (j == start || j >= n || text[j] != ']') {
    return null;
  }
  final id = text.substring(start, j);
  return (node: MdSourceTag(id: id, url: defs.link(id)?.url), next: j + 1);
}
