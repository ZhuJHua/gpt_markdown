/// Link reference definitions (`[label]: url "title"`) and footnote
/// definitions (`[^label]: text`), collected across a whole document.
///
/// A reference can sit pages away from its definition, and the incremental
/// view parses a document one blank-line-separated segment at a time, so a
/// segment cannot find its definitions by itself. They are collected from the
/// whole source first ([MarkdownDefinitions.collect]) and handed to every
/// segment's parse.
library;

import 'block_syntax.dart';
import 'entities.dart';
import 'scanner.dart';

/// Where a link reference definition points.
class MdLinkDefinition {
  const MdLinkDefinition({required this.url, this.title});

  final String url;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is MdLinkDefinition && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(url, title);
}

/// The link and footnote definitions of one document.
///
/// Passed to [Plusparse.parse] when a document is parsed in pieces; a whole
/// document parsed at once collects its own.
class MarkdownDefinitions {
  const MarkdownDefinitions._(this._links, this._footnotes, this._lookups);

  /// No definitions at all.
  static const MarkdownDefinitions empty = MarkdownDefinitions._(
    <String, MdLinkDefinition>{},
    <String, int>{},
    null,
  );

  final Map<String, MdLinkDefinition> _links;
  final Map<String, int> _footnotes;
  final Set<String>? _lookups;

  /// Whether there are no definitions at all.
  bool get isEmpty => _links.isEmpty && _footnotes.isEmpty;

  /// The definition for link [label], matched case-insensitively and with
  /// runs of whitespace collapsed, as CommonMark matches labels.
  MdLinkDefinition? link(String label) {
    final lookups = _lookups;
    if (lookups == null && _links.isEmpty) {
      return null;
    }
    final key = normalizeLabel(label);
    lookups?.add('l:$key');
    return _links[key];
  }

  /// The number footnote [label] displays as — its position among the
  /// document's footnote definitions, from 1 — or null when it has none.
  int? footnote(String label) {
    final lookups = _lookups;
    if (lookups == null && _footnotes.isEmpty) {
      return null;
    }
    final key = normalizeLabel(label);
    lookups?.add('f:$key');
    return _footnotes[key];
  }

  /// A view of these definitions that adds every label looked up through it to
  /// [lookups], so a cache can tell which parses a changed definition reaches.
  ///
  /// Lookups are recorded even while there are no definitions at all: a
  /// reference parsed before its definition arrives has to be found again
  /// when it does.
  MarkdownDefinitions recording(Set<String> lookups) =>
      MarkdownDefinitions._(_links, _footnotes, lookups);

  /// The lookup keys (as [recording] records them) whose answer differs
  /// between this and [other].
  Set<String> changedKeys(MarkdownDefinitions other) {
    final changed = <String>{};
    for (final key in {..._links.keys, ...other._links.keys}) {
      if (_links[key] != other._links[key]) {
        changed.add('l:$key');
      }
    }
    for (final key in {..._footnotes.keys, ...other._footnotes.keys}) {
      if (_footnotes[key] != other._footnotes[key]) {
        changed.add('f:$key');
      }
    }
    return changed;
  }

  @override
  bool operator ==(Object other) =>
      other is MarkdownDefinitions &&
      _mapEquals(other._links, _links) &&
      _mapEquals(other._footnotes, _footnotes);

  @override
  int get hashCode => Object.hash(_links.length, _footnotes.length);

  /// Every definition in [source] that starts a block at the top level.
  ///
  /// Mirrors where the block parser accepts one: at the start of the
  /// document, after a blank line, or right after another definition — a
  /// definition cannot interrupt a paragraph. Fenced code, block maths, HTML
  /// comments and custom blocks are skipped, so a `[x]: y` inside them is not
  /// a definition. The first definition of a label wins.
  static MarkdownDefinitions collect(
    String source, {
    MarkdownBlockRegistry? blockRegistry,
  }) {
    // Every definition has `]:` in it. Most replies have none, and this keeps
    // the per-token cost of asking to one scan.
    if (!_hasLabelColon(source)) {
      return empty;
    }
    final lines =
        (source.contains('\r')
                ? source.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
                : source)
            .split('\n');
    return collectLines(lines, blockRegistry: blockRegistry);
  }

  /// [collect] over a document already split into lines.
  static MarkdownDefinitions collectLines(
    List<String> lines, {
    MarkdownBlockRegistry? blockRegistry,
  }) {
    // A definition opens its line with `[`. Checking each line's first
    // character is far cheaper than reading every character of the document,
    // and most documents have no such line.
    if (!lines.any((line) => startsAfterIndent(line, _openBracket))) {
      return empty;
    }
    final links = <String, MdLinkDefinition>{};
    final footnotes = <String, int>{};
    var mayStart = true;
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final first = firstNonSpace(line);
      if (first == -1) {
        mayStart = true;
        i += 1;
        continue;
      }
      final custom = blockRegistry?.match(lines, i);
      if (custom != null) {
        i = custom.endLine;
        mayStart = false;
        continue;
      }
      final unit = line.codeUnitAt(first);
      if (unit == 0x60 /* ` */ || unit == 0x7E /* ~ */ ) {
        final fence = fenceOpen(line.substring(first));
        if (fence != null) {
          i += 1;
          while (i < lines.length && !isFenceClose(lines[i], fence)) {
            i += 1;
          }
          i += 1;
          mayStart = false;
          continue;
        }
      }
      if (unit == 0x5C /* \ */ && line.startsWith(r'\[', first)) {
        var rest = line.substring(first);
        while (rest.startsWith(r'\[')) {
          rest = rest.substring(2);
        }
        if (!rest.contains(r'\]')) {
          i += 1;
          while (i < lines.length && !lines[i].contains(r'\]')) {
            i += 1;
          }
        }
        i += 1;
        mayStart = false;
        continue;
      }
      if (unit == 0x3C /* < */ && line.startsWith('<!--', first)) {
        final end = htmlCommentEnd(lines, i);
        i = end.next;
        mayStart = end.trailing.trim().isEmpty;
        continue;
      }
      if (mayStart && unit == _openBracket && first <= 3) {
        final footnote = footnoteDefinitionAt(lines, i);
        if (footnote != null) {
          footnotes.putIfAbsent(
            normalizeLabel(footnote.label),
            () => footnotes.length + 1,
          );
          i = footnote.next;
          continue;
        }
        final link = linkDefinitionAt(line);
        if (link != null) {
          links.putIfAbsent(normalizeLabel(link.label), () => link.definition);
          i += 1;
          continue;
        }
      }
      mayStart = false;
      i += 1;
    }
    if (links.isEmpty && footnotes.isEmpty) {
      return empty;
    }
    return MarkdownDefinitions._(links, footnotes, null);
  }
}

const int _openBracket = 0x5B; // '['

/// Whether [source] contains `]:`.
///
/// Not `contains(']:')`: a two-character pattern search measured three times
/// slower than finding each `]` — rare in prose — and looking at the next
/// character, and this runs on the whole reply for every streamed token.
bool _hasLabelColon(String source) {
  var k = source.indexOf(']');
  while (k != -1) {
    if (k + 1 < source.length && source.codeUnitAt(k + 1) == 0x3A /* : */ ) {
      return true;
    }
    k = source.indexOf(']', k + 1);
  }
  return false;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// A label as CommonMark compares it: trimmed, inner whitespace collapsed to
/// one space, and case-folded.
String normalizeLabel(String label) {
  final trimmed = label.trim();
  final collapsed = trimmed.contains(_whitespaceToCollapse)
      ? trimmed.replaceAll(_whitespaceRun, ' ')
      : trimmed;
  return collapsed.toLowerCase();
}

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Two whitespace characters in a row, or one that is not a plain space —
/// the labels [normalizeLabel] has to rewrite at all.
final RegExp _whitespaceToCollapse = RegExp(r'\s\s|[^\S ]');

/// Where an HTML comment that opens at line [start] ends: the line after the
/// one holding `-->` (or the end of [lines] when it never closes), and the
/// text after `-->` on that line.
({int next, String trailing}) htmlCommentEnd(List<String> lines, int start) {
  final first = lines[start];
  final open = first.indexOf('<!--');
  var from = open + 4;
  for (var k = start; k < lines.length; k++) {
    final line = lines[k];
    final close = line.indexOf('-->', k == start ? from : 0);
    if (close != -1) {
      return (next: k + 1, trailing: line.substring(close + 3));
    }
    from = 0;
  }
  return (next: lines.length, trailing: '');
}

/// A link reference definition occupying the whole of [line], or null.
///
/// `[label]: destination "optional title"` — up to three spaces of indent, a
/// label that is not blank and holds no unescaped bracket, and nothing after
/// the title. A label starting with `^` is a footnote, not a link.
({String label, MdLinkDefinition definition})? linkDefinitionAt(String line) {
  if (!startsAfterIndent(line, 0x5B /* [ */)) {
    return null;
  }
  final t = line.trim();
  if (t.length < 4 || t.codeUnitAt(0) != 0x5B /* [ */ ) {
    return null;
  }
  final close = _labelEnd(t, 1);
  if (close == -1 || close + 1 >= t.length || t[close + 1] != ':') {
    return null;
  }
  final label = t.substring(1, close);
  if (label.trim().isEmpty || label.startsWith('^') || label.length > 999) {
    return null;
  }
  final target = parseLinkTarget(t.substring(close + 2), strict: true);
  if (target == null || target.url.isEmpty) {
    return null;
  }
  return (
    label: label,
    definition: MdLinkDefinition(url: target.url, title: target.title),
  );
}

/// A footnote definition starting at line [start], or null.
///
/// `[^label]: text`, then its continuation: following lines up to a blank
/// line, unless they start another definition or a block of their own; and
/// after a blank line, further paragraphs indented by four or more spaces.
/// [lines] is its body with the marker and the continuation indent removed.
({String label, List<String> lines, int next})? footnoteDefinitionAt(
  List<String> lines,
  int start,
) {
  final line = lines[start];
  if (!startsAfterIndent(line, 0x5B /* [ */)) {
    return null;
  }
  final t = line.trimLeft();
  if (!t.startsWith('[^')) {
    return null;
  }
  final close = t.indexOf(']');
  if (close < 3 || close + 1 >= t.length || t[close + 1] != ':') {
    return null;
  }
  final label = t.substring(2, close);
  if (label.contains(RegExp(r'[\s\[]'))) {
    return null;
  }
  var first = t.substring(close + 2);
  if (first.startsWith(' ') || first.startsWith('\t')) {
    first = first.substring(1);
  }
  final body = <String>[first];
  var k = start + 1;
  while (k < lines.length) {
    final next = lines[k];
    if (isBlank(next)) {
      var j = k + 1;
      while (j < lines.length && isBlank(lines[j])) {
        j += 1;
      }
      if (j < lines.length && indentWidth(lines[j]) >= 4) {
        for (var b = k; b < j; b++) {
          body.add('');
        }
        k = j;
        continue;
      }
      break;
    }
    if (indentWidth(next) < 4 &&
        (startsDefinition(next) || _interruptsParagraph(next.trimLeft()))) {
      break;
    }
    body.add(stripIndent(next, 4));
    k += 1;
  }
  while (body.isNotEmpty && body.last.trim().isEmpty) {
    body.removeLast();
  }
  return (label: label, lines: body, next: k);
}

/// Whether [line] looks like the start of a link or footnote definition.
bool startsDefinition(String line) {
  if (!startsAfterIndent(line, 0x5B /* [ */)) {
    return false;
  }
  final t = line.trimLeft();
  if (!t.startsWith('[')) {
    return false;
  }
  final close = _labelEnd(t, 1);
  return close != -1 && close + 1 < t.length && t[close + 1] == ':';
}

bool _interruptsParagraph(String t) =>
    fenceOpen(t) != null ||
    t.startsWith(r'\[') ||
    isHeading(t) != null ||
    isHr(t) ||
    t.startsWith('>') ||
    unorderedMarker(t) != null ||
    orderedMarker(t) != null;

/// Index of the `]` closing a label that opened just before [from], or -1.
/// Escaped brackets do not count; an unescaped `[` ends the search.
int _labelEnd(String t, int from) {
  var i = from;
  while (i < t.length) {
    final c = t.codeUnitAt(i);
    if (c == 0x5C /* \ */ ) {
      i += 2;
      continue;
    }
    if (c == 0x5B /* [ */ ) {
      return -1;
    }
    if (c == 0x5D /* ] */ ) {
      return i;
    }
    i += 1;
  }
  return -1;
}

/// The destination and optional title inside a link's parentheses (or after
/// a definition's colon).
///
/// `<url with spaces>` is taken whole; otherwise the URL runs to the first
/// whitespace. A title follows in `"…"`, `'…'` or `(…)`. Backslash escapes and
/// entity references are decoded in both.
///
/// With [strict] (definitions) anything else after the URL means there is no
/// definition. Without it (inline links) the whole text is the URL, exactly as
/// before titles were understood — `[doc](My File.pdf)` keeps working.
({String url, String? title})? parseLinkTarget(
  String raw, {
  bool strict = false,
}) {
  final s = raw.trim();
  String url;
  String rest;
  if (s.startsWith('<')) {
    final end = s.indexOf('>');
    if (end == -1 || s.substring(1, end).contains('<')) {
      if (strict) {
        return null;
      }
      return (url: _decode(s), title: null);
    }
    url = s.substring(1, end);
    rest = s.substring(end + 1);
  } else {
    var end = 0;
    while (end < s.length && !isUnicodeWhitespace(s.codeUnitAt(end))) {
      end += 1;
    }
    url = s.substring(0, end);
    rest = s.substring(end);
  }
  final trimmedRest = rest.trim();
  if (trimmedRest.isEmpty) {
    return (url: _decode(url), title: null);
  }
  // A title must be separated from the URL by whitespace.
  final separated = rest.isNotEmpty && isUnicodeWhitespace(rest.codeUnitAt(0));
  final title = separated ? _title(trimmedRest) : null;
  if (title == null) {
    if (strict) {
      return null;
    }
    return (url: _decode(s), title: null);
  }
  return (url: _decode(url), title: _decode(title));
}

String? _title(String s) {
  if (s.length < 2) {
    return null;
  }
  final open = s.codeUnitAt(0);
  final close = s.codeUnitAt(s.length - 1);
  final matches =
      (open == 0x22 && close == 0x22) || // "
      (open == 0x27 && close == 0x27) || // '
      (open == 0x28 && close == 0x29); // ( )
  if (!matches) {
    return null;
  }
  final inner = s.substring(1, s.length - 1);
  // The closing quote must be the only unescaped one.
  for (var i = 0; i < inner.length; i++) {
    final c = inner.codeUnitAt(i);
    if (c == 0x5C /* \ */ ) {
      i += 1;
      continue;
    }
    if (c == close || (open == 0x28 && c == 0x28)) {
      return null;
    }
  }
  return inner;
}

String _decode(String s) => decodeEntities(unescapeBackslashes(s));

/// [s] with every backslash escape of ASCII punctuation replaced by the
/// character it escapes.
String unescapeBackslashes(String s) {
  if (!s.contains(r'\')) {
    return s;
  }
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x5C &&
        i + 1 < s.length &&
        isAsciiPunctuation(s.codeUnitAt(i + 1))) {
      out.writeCharCode(s.codeUnitAt(i + 1));
      i += 2;
      continue;
    }
    out.writeCharCode(c);
    i += 1;
  }
  return out.toString();
}
