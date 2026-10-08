/// CommonMark syntax the parser used to miss: `_` / `__` emphasis, `*`
/// flanking, multi-backtick code spans, `~~~` and long fences, backslash
/// escapes, entity references, link titles and `<…>` destinations, reference
/// links, footnotes, HTML comments, setext headings, closing `#`s, and
/// Pandoc-style `$` maths.
///
/// Each group pins the new syntax and, next to it, the input that must keep
/// rendering the way it always has. The last group is nothing but the latter.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/plusparse/plusparse.dart';

/// The parse of [markdown], one compact line per document.
///
/// `T(text)`, `B[…]` bold, `I[…]` italic, `C(code)`, `L(tex)` inline maths,
/// `A[label](url "title")`, `SRC(1 url)`, `FN(label=n)`, `P{…}`, `H2{…}`,
/// `CODE<lang>{…}`, and so on. Newlines print as `\n`.
String dump(String markdown, {bool dollar = false}) =>
    _nodes(Plusparse.parse(markdown, useDollarSignsForLatex: dollar).children);

String _nodes(List<MdNode> nodes) => nodes.map(_node).join(' ');

String _node(MdNode n) => switch (n) {
  MdText(:final text) => 'T(${text.replaceAll('\n', r'\n')})',
  MdBold(:final children) => 'B[${_nodes(children)}]',
  MdItalic(:final children) => 'I[${_nodes(children)}]',
  MdStrike(:final children) => 'S[${_nodes(children)}]',
  MdUnderline(:final children) => 'U[${_nodes(children)}]',
  MdInlineCode(:final text) => 'C($text)',
  MdInlineLatex(:final tex) => 'L($tex)',
  MdBlockLatex(:final tex) => 'BL($tex)',
  MdLink(:final children, :final url, :final title) =>
    'A[${_nodes(children)}]($url${title == null ? '' : ' "$title"'})',
  MdImage(:final url, :final alt, :final title) =>
    'IMG[$alt]($url${title == null ? '' : ' "$title"'})',
  MdSourceTag(:final id, :final url) => 'SRC($id${url == null ? '' : ' $url'})',
  MdFootnoteReference(:final label, :final number) => 'FN($label=$number)',
  MdFootnoteDefinitions(:final footnotes) =>
    'FOOTNOTES{${footnotes.map((f) => '${f.number}:${_nodes(f.children)}').join('; ')}}',
  MdLineBreak() => 'BR',
  MdParagraph(:final children) => 'P{${_nodes(children)}}',
  MdHeading(:final level, :final children) => 'H$level{${_nodes(children)}}',
  MdCodeBlock(:final language, :final code, :final closed) =>
    'CODE<$language>{${code.replaceAll('\n', r'\n')}}${closed ? '' : '(open)'}',
  MdUnorderedList(:final items) =>
    'UL{${items.map((i) => '<${_nodes(i.children)}>').join()}}',
  MdOrderedList(:final start, :final items) =>
    'OL$start{${items.map((i) => '<${_nodes(i.children)}>').join()}}',
  MdBlockQuote(:final children) => 'Q{${_nodes(children)}}',
  MdTable(:final header, :final rows) =>
    'TABLE{${[header, ...rows].map((r) => r.cells.map((c) => _nodes(c.content)).join(' | ')).join(' / ')}}',
  MdHorizontalRule() => 'HR',
  MdCheckbox(:final checked, :final children) =>
    'CB($checked){${_nodes(children)}}',
  MdRadio(:final selected, :final children) =>
    'R($selected){${_nodes(children)}}',
  MdCustomBlock(:final type) => 'CUSTOM($type)',
};

void main() {
  group('underscore emphasis', () {
    test('_x_ is italic, __x__ bold, ___x___ both', () {
      expect(dump('_x_'), 'P{I[T(x)]}');
      expect(dump('__x__'), 'P{B[T(x)]}');
      expect(dump('___x___'), 'P{B[I[T(x)]]}');
    });

    test('works mid-sentence and next to punctuation', () {
      expect(dump('a _b_ c'), 'P{T(a ) I[T(b)] T( c)}');
      expect(dump('(_b_)'), 'P{T(() I[T(b)] T())}');
      expect(
        dump('__bold__, then _it_.'),
        'P{B[T(bold)] T(, then ) I[T(it)] T(.)}',
      );
    });

    test('an underscore inside a word never opens or closes', () {
      expect(dump('snake_case_name'), 'P{T(snake_case_name)}');
      expect(dump('call my_func_here() now'), 'P{T(call my_func_here() now)}');
      expect(dump('a_b_ c'), 'P{T(a_b_ c)}');
      expect(dump('MAX__SIZE__X'), 'P{T(MAX__SIZE__X)}');
    });

    test('dunder names follow CommonMark (bold when not in code)', () {
      // `__init__.py`: the closing `__` is followed by punctuation, so by the
      // spec this is bold "init". In backticks it is code, as models write it.
      expect(dump('__init__.py'), 'P{B[T(init)] T(.py)}');
      expect(dump('`__init__.py`'), 'P{C(__init__.py)}');
    });

    test('a bare URL keeps its underscores', () {
      expect(
        dump('see https://x.com/_a_ now'),
        'P{T(see https://x.com/_a_ now)}',
      );
      expect(dump('www.x.com/_a_'), 'P{T(www.x.com/_a_)}');
    });

    test('whitespace after the opener or before the closer stops it', () {
      expect(dump('_ x_'), 'P{T(_ x_)}');
      expect(dump('_x _'), 'P{T(_x _)}');
    });

    test('mixes with asterisk emphasis', () {
      expect(dump('_a **b** c_'), 'P{I[T(a ) B[T(b)] T( c)]}');
      expect(dump('**a _b_ c**'), 'P{B[T(a ) I[T(b)] T( c)]}');
    });

    test('inside headings, list items and table cells', () {
      expect(dump('# _x_'), 'H1{I[T(x)]}');
      expect(dump('- __x__'), 'UL{<B[T(x)]>}');
      expect(
        dump('| _a_ | b |\n|---|---|\n| 1 | __2__ |'),
        'TABLE{I[T(a)] | T(b) / T(1) | B[T(2)]}',
      );
    });

    test('a line of underscores is still a thematic break', () {
      expect(dump('___'), 'HR');
      expect(dump('_ _ _'), 'HR');
    });

    test('never touches maths or code', () {
      expect(dump(r'\(a_1 + b_2\)'), r'P{L(a_1 + b_2)}');
      expect(dump(r'$a_1 + b_2$', dollar: true), r'P{L(a_1 + b_2)}');
      expect(dump('`_x_`'), 'P{C(_x_)}');
    });
  });

  group('asterisk flanking', () {
    test('a * followed by whitespace cannot open', () {
      expect(dump('2 * 3 * 4'), 'P{T(2 * 3 * 4)}');
      expect(dump('a * b * c'), 'P{T(a * b * c)}');
      expect(dump('** not bold**'), 'P{T(** not bold**)}');
    });

    test('a * preceded by whitespace cannot close', () {
      expect(dump('*a *'), 'P{T(*a *)}');
      expect(dump('**a **'), 'P{T(**a **)}');
    });

    test('intraword * still works, as CommonMark allows', () {
      expect(dump('x*y*z'), 'P{T(x) I[T(y)] T(z)}');
    });

    test('punctuation before the closer still closes (lenient on purpose)', () {
      // Strict CommonMark leaves these literal; models write them constantly.
      expect(dump('**Note:**text'), 'P{B[T(Note:)] T(text)}');
      expect(dump('**粗体：**中文'), 'P{B[T(粗体：)] T(中文)}');
    });

    test('the closer search skips code spans and escapes', () {
      expect(dump('*a `*` b*'), 'P{I[T(a ) C(*) T( b)]}');
      expect(dump(r'*a \* b*'), 'P{I[T(a * b)]}');
    });

    test('many openers that never close stay literal', () {
      final input = List.filled(500, '*a ').join();
      expect(
        dump(input),
        'P{T(${input.trimRight()}${input.endsWith(' ') ? ' ' : ''})}',
      );
    });
  });

  group('code spans', () {
    test('double backticks hold a single backtick', () {
      expect(dump('`` a`b ``'), 'P{C(a`b)}');
      expect(dump('``a`b``'), 'P{C(a`b)}');
    });

    test('a run closes only at a run of the same length', () {
      expect(dump('`a``b`'), 'P{C(a``b)}');
      expect(dump('```x```'), 'P{C(x)}');
    });

    test('one space is stripped from each end when both have one', () {
      expect(dump('` x `'), 'P{C(x)}');
      expect(dump('`` `x` ``'), 'P{C(`x`)}');
      expect(dump('`  `'), 'P{C(  )}');
      expect(dump('` x`'), 'P{C( x)}');
    });

    test('an unclosed run is literal, and later code still parses', () {
      expect(dump('`` a ` b'), 'P{T(`` a ` b)}');
      expect(dump('it`s `x`'), 'P{T(it) C(s ) T(x`)}');
    });

    test('content is not parsed', () {
      expect(dump('`**b** _i_ &amp; \\*`'), r'P{C(**b** _i_ &amp; \*)}');
    });

    test('a line break inside becomes a space', () {
      expect(dump('`a\nb`'), 'P{C(a b)}');
    });

    test('a pipe in a double-backtick span stays in its table cell', () {
      expect(
        dump('| ``a|b`` | c |\n|---|---|\n| 1 | 2 |'),
        'TABLE{C(a|b) | T(c) / T(1) | T(2)}',
      );
    });
  });

  group('fenced code', () {
    test('a tilde fence is a code block', () {
      expect(dump('~~~python\nx = 1\n~~~'), 'CODE<python>{x = 1}');
    });

    test('a fence closes only on the same character', () {
      expect(dump('~~~\n```\nx\n~~~'), r'CODE<>{```\nx}');
      expect(dump('```\n~~~\nx\n```'), r'CODE<>{~~~\nx}');
    });

    test('a longer fence holds a shorter one', () {
      expect(dump('````md\n```js\nx\n```\n````'), r'CODE<md>{```js\nx\n```}');
    });

    test('the closer may be longer, but not shorter, than the opener', () {
      expect(dump('```\nx\n`````'), 'CODE<>{x}');
      expect(dump('````\nx\n```\ny\n````'), r'CODE<>{x\n```\ny}');
    });

    test('a line with text after the backticks does not close', () {
      expect(dump('```\nx\n```js\ny\n```'), r'CODE<>{x\n```js\ny}');
    });

    test('a backtick info string with a backtick is not a fence', () {
      expect(dump('```one-line```'), 'P{C(one-line)}');
      expect(dump('```a`b\nc'), r'P{T(```a`b\nc)}');
    });

    test('an unclosed fence runs to the end, marked open', () {
      expect(dump('~~~js\ncode'), 'CODE<js>{code}(open)');
    });

    test('a fence interrupts a paragraph', () {
      expect(dump('text\n~~~\ncode\n~~~'), 'P{T(text)} CODE<>{code}');
    });

    test('inside a list item', () {
      expect(
        dump('- item\n  ~~~\n  code\n  ~~~'),
        'UL{<T(item) CODE<>{code}>}',
      );
    });
  });

  group('backslash escapes', () {
    test('escaped punctuation is literal', () {
      expect(dump(r'\*not italic\*'), 'P{T(*not italic*)}');
      expect(dump(r'\_x\_'), 'P{T(_x_)}');
      expect(dump(r'\`x\`'), 'P{T(`x`)}');
      expect(dump(r'\~\~x\~\~'), 'P{T(~~x~~)}');
      expect(dump(r'\<u>x\</u>'), 'P{T(<u>x</u>)}');
      expect(dump(r'\&amp;'), 'P{T(&amp;)}');
      expect(dump(r'\\'), r'P{T(\)}');
    });

    test('escaped block markers do not start blocks', () {
      expect(dump(r'\# not heading'), 'P{T(# not heading)}');
      expect(dump(r'\- not a list'), 'P{T(- not a list)}');
      expect(dump(r'1\. not a list'), 'P{T(1. not a list)}');
      expect(dump(r'\> not a quote'), 'P{T(> not a quote)}');
    });

    test('a backslash before a non-punctuation character stays', () {
      expect(dump(r'C:\Users\me'), r'P{T(C:\Users\me)}');
      expect(dump(r'\d+'), r'P{T(\d+)}');
    });

    test('a dollar can be escaped with or without dollar maths', () {
      expect(dump(r'price \$5'), r'P{T(price $5)}');
      expect(dump(r'\$x\$', dollar: true), r'P{T($x$)}');
    });

    test('maths delimiters are never escapes', () {
      expect(dump(r'\(x\)'), 'P{L(x)}');
      expect(dump(r'a \( b'), r'P{T(a \( b)}');
      expect(dump(r'a \] b'), r'P{T(a \] b)}');
    });

    test('a backslash at the end of a line is a hard break', () {
      expect(dump('one\\\ntwo'), r'P{T(one\ntwo)}');
      expect(dump('trailing\\'), r'P{T(trailing\)}');
    });

    test(r'\| is still a literal pipe in a table cell', () {
      expect(
        dump('| a \\| b | c |\n|---|---|\n| 1 | 2 |'),
        'TABLE{T(a | b) | T(c) / T(1) | T(2)}',
      );
    });
  });

  group('entity references', () {
    test('named, decimal and hex references decode', () {
      expect(dump('a &amp; b'), 'P{T(a & b)}');
      expect(dump('&lt;tag&gt;'), 'P{T(<tag>)}');
      expect(dump('&copy; &#169; &#xA9; &#XA9;'), 'P{T(© © © ©)}');
      expect(dump('&#x1F600;'), 'P{T(😀)}');
      expect(dump('a&nbsp;b'), 'P{T(a\u00A0b)}');
    });

    test('invalid code points become U+FFFD', () {
      expect(dump('&#0;'), 'P{T(\uFFFD)}');
      expect(dump('&#xD800;'), 'P{T(\uFFFD)}');
    });

    test('anything else stays literal', () {
      expect(dump('AT&T and R&D'), 'P{T(AT&T and R&D)}');
      expect(dump('&bogus; &amp &#; &#x;'), 'P{T(&bogus; &amp &#; &#x;)}');
    });

    test('a decoded character is text, not markup', () {
      expect(dump('&#42;not italic&#42;'), 'P{T(*not italic*)}');
    });

    test('not decoded in code or in a bare URL', () {
      expect(dump('`&amp;`'), 'P{C(&amp;)}');
      expect(
        dump('https://x.com/?a=1&amp;b=2'),
        'P{T(https://x.com/?a=1&amp;b=2)}',
      );
    });

    test('decoded in link destinations', () {
      expect(dump('[a](/x?a=1&amp;b=2)'), 'P{A[T(a)](/x?a=1&b=2)}');
    });
  });

  group('link destinations and titles', () {
    test('a quoted title is split from the URL', () {
      expect(dump('[a](https://a.com "T")'), 'P{A[T(a)](https://a.com "T")}');
      expect(dump("[a](/x 'T')"), 'P{A[T(a)](/x "T")}');
      expect(dump('[a](/x (T))'), 'P{A[T(a)](/x "T")}');
    });

    test('an angle-bracket destination may hold spaces', () {
      expect(dump('[a](<my file.pdf>)'), 'P{A[T(a)](my file.pdf)}');
      expect(dump('[a](<my file.pdf> "T")'), 'P{A[T(a)](my file.pdf "T")}');
    });

    test('images take titles too', () {
      expect(dump('![alt](/i.png "T")'), 'P{IMG[alt](/i.png "T")}');
    });

    test('escapes in the destination and title decode', () {
      expect(dump(r'[a](/x\_y "a \"q\"")'), r'P{A[T(a)](/x_y "a "q"")}');
    });

    test('a URL with an unbracketed space still links, as before', () {
      expect(dump('[doc](My File.pdf)'), 'P{A[T(doc)](My File.pdf)}');
      expect(dump('[a](/x "unclosed)'), 'P{A[T(a)](/x "unclosed)}');
    });
  });

  group('reference links', () {
    test('full, collapsed and shortcut forms', () {
      const defs = '\n\n[docs]: https://d.dev "D"';
      expect(
        dump('[the docs][docs]$defs'),
        'P{A[T(the docs)](https://d.dev "D")}',
      );
      expect(dump('[docs][]$defs'), 'P{A[T(docs)](https://d.dev "D")}');
      expect(dump('[docs]$defs'), 'P{A[T(docs)](https://d.dev "D")}');
    });

    test('labels match case-insensitively with whitespace collapsed', () {
      expect(dump('[The  Docs]\n\n[the docs]: /d'), 'P{A[T(The  Docs)](/d)}');
    });

    test('the definition line is hidden', () {
      expect(dump('[a]: /x'), '');
      expect(dump('text\n\n[a]: /x\n[b]: <my file> "T"'), 'P{T(text)}');
    });

    test('the first definition of a label wins', () {
      expect(dump('[a]\n\n[a]: /one\n[a]: /two'), 'P{A[T(a)](/one)}');
    });

    test('a reference image', () {
      expect(dump('![logo][l]\n\n[l]: /l.png'), 'P{IMG[logo](/l.png)}');
    });

    test('an undefined label stays text', () {
      expect(dump('[nope] and [x][nope]'), 'P{T([nope] and [x][nope])}');
    });

    test('a definition cannot interrupt a paragraph', () {
      expect(dump('text\n[a]: /x\n\n[a]'), r'P{T(text\n[a]: /x)} P{T([a])}');
    });

    test('a line that only looks like a definition is text', () {
      expect(
        dump('[Note]: this is important'),
        'P{T([Note]: this is important)}',
      );
      expect(dump('[a]:'), 'P{T([a]:)}');
    });

    test('a definition inside a fence is code', () {
      expect(dump('```\n[a]: /x\n```\n\n[a]'), 'CODE<>{[a]: /x} P{T([a])}');
    });

    test('reaches into lists, quotes, headings and tables', () {
      const defs = '\n\n[a]: /x';
      expect(dump('- [a]$defs'), 'UL{<A[T(a)](/x)>}');
      expect(dump('> [a]$defs'), 'Q{P{A[T(a)](/x)}}');
      expect(dump('# [a]$defs'), 'H1{A[T(a)](/x)}');
    });
  });

  group('source tags with definitions', () {
    test('[1] stays a citation, and carries the defined URL', () {
      expect(
        dump('cite [1] here\n\n[1]: https://a.com'),
        'P{T(cite ) SRC(1 https://a.com) T( here)}',
      );
    });

    test('[1] without a definition is unchanged', () {
      expect(dump('cite [1] here'), 'P{T(cite ) SRC(1) T( here)}');
    });

    test('[text][1] is a link', () {
      expect(
        dump('[ref][1]\n\n[1]: https://a.com'),
        'P{A[T(ref)](https://a.com)}',
      );
    });
  });

  group('footnotes', () {
    test('references number by definition order', () {
      expect(
        dump('A[^x] and B[^1].\n\n[^1]: one\n[^x]: ex'),
        'P{T(A) FN(x=2) T( and B) FN(1=1) T(.)} FOOTNOTES{1:P{T(one)}; 2:P{T(ex)}}',
      );
    });

    test('definitions separated by blank lines form one list', () {
      expect(
        dump('a[^1]\n\n[^1]: one\n\n[^2]: two'),
        'P{T(a) FN(1=1)} FOOTNOTES{1:P{T(one)}; 2:P{T(two)}}',
      );
    });

    test('a definition continues on following lines', () {
      expect(
        dump('[^1]: first\nsecond line\n\n    next para\n\nafter'),
        r'FOOTNOTES{1:P{T(first\nsecond line)} P{T(next para)}} P{T(after)}',
      );
    });

    test('a definition body is parsed as Markdown', () {
      expect(
        dump('[^1]: **b** [l](/x)'),
        'FOOTNOTES{1:P{B[T(b)] T( ) A[T(l)](/x)}}',
      );
    });

    test('an undefined reference stays text', () {
      expect(dump('no def [^9]'), 'P{T(no def [^9])}');
      expect(dump('[^]'), 'P{T([^])}');
    });

    test('a reference with a URL is still a link', () {
      expect(
        dump('[^1](/x)\n\n[^1]: n'),
        'P{A[T(^1)](/x)} FOOTNOTES{1:P{T(n)}}',
      );
    });
  });

  group('HTML comments', () {
    test('a comment on its own lines is hidden', () {
      expect(dump('<!-- note -->'), '');
      expect(dump('<!--\nmulti\n\nline\n-->\nafter'), 'P{T(after)}');
    });

    test('a comment inside a paragraph is dropped', () {
      expect(dump('before <!-- x --> after'), 'P{T(before  after)}');
    });

    test('an unclosed comment at line start hides the rest', () {
      expect(dump('<!-- streaming'), '');
    });

    test('an unclosed comment inside a paragraph is text', () {
      expect(dump('a <!-- b'), 'P{T(a <!-- b)}');
    });

    test('text after a comment on the same line is kept', () {
      expect(dump('<!-- x --> after'), 'P{T( after)}');
    });

    test('a comment in code is code', () {
      expect(dump('`<!-- x -->`'), 'P{C(<!-- x -->)}');
    });
  });

  group('setext headings', () {
    test('=== makes an h1 and --- an h2', () {
      expect(dump('Title\n====='), 'H1{T(Title)}');
      expect(dump('Sub\n---'), 'H2{T(Sub)}');
      expect(dump('Sub\n-'), 'H2{T(Sub)}');
    });

    test('a multi-line paragraph becomes one heading', () {
      expect(dump('a\nb\n==='), r'H1{T(a\nb)}');
    });

    test('--- after a blank line is still a thematic break', () {
      expect(dump('text\n\n---'), 'P{T(text)} HR');
      expect(dump('---'), 'HR');
    });

    test('spaced dashes are a thematic break, not an underline', () {
      expect(dump('text\n- - -'), 'P{T(text)} HR');
    });

    test('*** is never an underline', () {
      expect(dump('text\n***'), 'P{T(text)} HR');
    });

    test('=== with nothing above is text', () {
      expect(dump('==='), 'P{T(===)}');
    });

    test('a list item is not an underline', () {
      expect(dump('text\n- item'), 'P{T(text)} UL{<T(item)>}');
    });

    test('--- after a quote ends the quote', () {
      expect(dump('> quote\n---'), 'Q{P{T(quote)}} HR');
    });
  });

  group('closing hashes', () {
    test('a closing sequence is removed', () {
      expect(dump('# Title #'), 'H1{T(Title)}');
      expect(dump('## Title ######'), 'H2{T(Title)}');
      expect(dump('### ###'), 'H3{}');
    });

    test('hashes not preceded by a space stay', () {
      expect(dump('# C#'), 'H1{T(C#)}');
      expect(dump('# a#b'), 'H1{T(a#b)}');
      expect(dump(r'# Title \#'), 'H1{T(Title #)}');
    });
  });

  group('dollar maths', () {
    test('prices are not maths', () {
      expect(dump(r'$5 and $10', dollar: true), r'P{T($5 and $10)}');
      expect(dump(r'from $5 to $10.', dollar: true), r'P{T(from $5 to $10.)}');
    });

    test('a space inside either delimiter stops it', () {
      expect(dump(r'$ x$', dollar: true), r'P{T($ x$)}');
      expect(dump(r'$x $', dollar: true), r'P{T($x $)}');
    });

    test('a closer followed by a digit does not close', () {
      expect(dump(r'$x$5 and $y$', dollar: true), r'P{L(x$5 and $y)}');
    });

    test('maths still works', () {
      expect(dump(r'$x$ and $y$', dollar: true), 'P{L(x) T( and ) L(y)}');
      expect(dump(r'$\frac{a}{b}$', dollar: true), r'P{L(\frac{a}{b})}');
      expect(dump(r'$$x^2$$', dollar: true), 'P{L(x^2)}');
    });

    test('ignored without the option', () {
      expect(dump(r'$x$'), r'P{T($x$)}');
    });

    test('a digit-led opener closes only before whitespace', () {
      expect(dump(r'$2^{10}$', dollar: true), r'P{L(2^{10})}');
      expect(
        dump(r'cost $5 and $x^2$', dollar: true),
        r'P{T(cost $5 and ) L(x^2)}',
      );
    });
  });

  group('adversarial input stays fast', () {
    // Each of these was quadratic at some point during development. The
    // budget is generous for a debug VM; the quadratic versions took a second
    // or more.
    void fast(String name, String input, {bool dollar = false}) {
      test(name, () {
        final watch = Stopwatch()..start();
        Plusparse.parse(input, useDollarSignsForLatex: dollar);
        expect(watch.elapsedMilliseconds, lessThan(300));
      });
    }

    fast(r'dollars that never close, one line', r'$a ' * 20000, dollar: true);
    fast(
      r'dollars that never close, many lines',
      '\$a\n' * 20000,
      dollar: true,
    );
    fast('a run of ampersands', '&' * 40000);
    fast('underscores after punctuation', '._' * 20000);
    fast('asterisks that never close', '*a ' * 20000);
    fast('unclosed backtick runs', '` `` ``` ' * 5000);
    fast('comment openers with a far closer', '${'<!-- x\n\n' * 3000}--> y');
  });

  group('definition collection', () {
    test('a document without definitions collects nothing', () {
      expect(MarkdownDefinitions.collect('plain [1] text').isEmpty, isTrue);
      expect(MarkdownDefinitions.collect('a]: b').isEmpty, isTrue);
    });

    test('collected definitions resolve a separately parsed piece', () {
      const whole = 'See [docs][d] and[^n].\n\n[d]: /docs\n\n[^n]: note';
      final definitions = MarkdownDefinitions.collect(whole);
      final piece = Plusparse.parse(
        'See [docs][d] and[^n].',
        definitions: definitions,
      );
      expect(
        _nodes(piece.children),
        'P{T(See ) A[T(docs)](/docs) T( and) FN(n=1) T(.)}',
      );
    });

    test('equal sources collect equal definitions', () {
      const source = '[a]: /x\n[^b]: y';
      expect(
        MarkdownDefinitions.collect(source),
        MarkdownDefinitions.collect(source),
      );
      expect(
        MarkdownDefinitions.collect(source) ==
            MarkdownDefinitions.collect('[a]: /z\n[^b]: y'),
        isFalse,
      );
    });

    test('CRLF line endings', () {
      expect(dump('[a]\r\n\r\n[a]: /x\r\n'), 'P{A[T(a)](/x)}');
    });
  });

  group('segment splitting agrees with the parser', () {
    test('a tilde fence with a blank line stays one segment', () {
      expect(splitStreamSegments('~~~\na\n\nb\n~~~\n\nafter'), [
        '~~~\na\n\nb\n~~~',
        'after',
      ]);
    });

    test('a long fence holding a short one stays one segment', () {
      expect(splitStreamSegments('````\n```\n\nx\n```\n````\n\nafter'), [
        '````\n```\n\nx\n```\n````',
        'after',
      ]);
    });

    test('a comment with a blank line stays one segment', () {
      expect(splitStreamSegments('<!--\na\n\nb\n-->\n\nafter'), [
        '<!--\na\n\nb\n-->',
        'after',
      ]);
    });
  });

  group('unchanged behaviour', () {
    test('asterisk emphasis', () {
      expect(
        dump('**bold** *it* ***both***'),
        'P{B[T(bold)] T( ) I[T(it)] T( ) B[I[T(both)]]}',
      );
      expect(dump('*a **b** c*'), 'P{I[T(a ) B[T(b)] T( c)]}');
      expect(dump('**`code`**'), 'P{B[C(code)]}');
    });

    test('single-backtick code', () {
      expect(dump('`npm install`'), 'P{C(npm install)}');
      expect(dump('`**not bold**`'), 'P{C(**not bold**)}');
    });

    test('backtick fences', () {
      expect(
        dump('```dart\nvoid main() {}\n```'),
        'CODE<dart>{void main() {}}',
      );
    });

    test('links, images and source tags', () {
      expect(dump('[a](https://a.com)'), 'P{A[T(a)](https://a.com)}');
      expect(dump('![100x50](/i.png)'), 'P{IMG[100x50](/i.png)}');
      expect(dump('see [1][2]'), 'P{T(see ) SRC(1) SRC(2)}');
    });

    test('task lists and radios', () {
      expect(dump('- [ ] a\n- [x] b'), 'UL{<CB(false){T(a)}><CB(true){T(b)}>}');
      expect(dump('(x) a'), 'R(true){T(a)}');
    });

    test('maths delimiters', () {
      expect(dump(r'\[x\]'), 'BL(x)');
      expect(dump(r'a \(x\) b'), 'P{T(a ) L(x) T( b)}');
    });

    test('underline, strike and line breaks', () {
      expect(dump('<u>u</u> ~~s~~'), 'P{U[T(u)] T( ) S[T(s)]}');
      expect(dump('a\nb'), r'P{T(a\nb)}');
    });

    test('ATX headings and thematic breaks', () {
      expect(dump('## H2'), 'H2{T(H2)}');
      expect(dump('#NoSpace'), 'P{T(#NoSpace)}');
      expect(dump('* * *'), 'HR');
    });
  });
}
