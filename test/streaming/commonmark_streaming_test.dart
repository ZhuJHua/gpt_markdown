/// The streaming helpers agree with the parser about the CommonMark syntax
/// it gained: `_` emphasis, N-backtick code spans, `~~~` and long fences,
/// setext underlines, reference definitions, HTML comments and Pandoc-style
/// `$` maths.
///
/// Each helper makes a guess about text that has not finished arriving. A
/// guess that disagrees with the parser shows text in one form and restyles
/// it a moment later, which is the artefact the helpers exist to prevent.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:gpt_markdown/streaming/math_stream.dart';

void main() {
  group('inlineSafeLength', () {
    test('holds an open _ or __ emphasis', () {
      expect(inlineSafeLength('say _hello'), 'say '.length);
      expect(inlineSafeLength('say __hello'), 'say '.length);
      expect(inlineSafeLength('say _hello_ there'), 'say _hello_ there'.length);
    });

    test('never holds an underscore inside a word', () {
      const source = 'call snake_case_name now';
      expect(inlineSafeLength(source), source.length);
    });

    test('a double-backtick span closes only on a double backtick', () {
      expect(inlineSafeLength('run `` a`b'), 'run '.length);
      const closed = 'run `` a`b `` done';
      expect(inlineSafeLength(closed), closed.length);
    });

    test('holds a possible setext underline still arriving', () {
      expect(inlineSafeLength('Title\n-'), 'Title\n'.length);
      expect(inlineSafeLength('Title\n=='), 'Title\n'.length);
      const settled = 'Title\n---\n';
      expect(inlineSafeLength(settled), settled.length);
    });

    test('holds a reference definition line until it ends', () {
      expect(inlineSafeLength('text\n\n[1]: https://exa'), 'text\n\n'.length);
      const done = 'text\n\n[1]: https://example.com\n';
      expect(inlineSafeLength(done), done.length);
    });

    test('a lone table pipe after a leading newline does not throw', () {
      expect(inlineSafeLength('\n|'), greaterThanOrEqualTo(0));
    });

    test('holds a line that is only a list marker so far', () {
      expect(inlineSafeLength('1. one\n2'), '1. one\n'.length);
      expect(inlineSafeLength('1. one\n2.'), '1. one\n'.length);
      expect(inlineSafeLength('- one\n*'), '- one\n'.length);
    });

    test('never shows a list marker whose content is held', () {
      // The open code span holds `curr`; the `2. ` before it waits too.
      expect(inlineSafeLength('1. one\n2. `curr'), '1. one\n'.length);
      expect(inlineSafeLength('- a\n- [ ] `x'), '- a\n'.length);
    });

    test('holds a bare [label] line that may become a definition', () {
      expect(inlineSafeLength('text\n\n[1]'), 'text\n\n'.length);
      const citation = 'text\n\n[1] the source';
      expect(inlineSafeLength(citation), citation.length);
    });

    test('a hold at the very start does not throw', () {
      expect(inlineSafeLength('`open'), 0);
    });

    test('holds an HTML comment until it closes', () {
      expect(inlineSafeLength('a <!-- b'), 'a '.length);
      expect(inlineSafeLength('a <!'), 'a '.length);
      const done = 'a <!-- b --> c';
      expect(inlineSafeLength(done), done.length);
    });

    test(r'a $ before a space or digit is not held', () {
      const prices = r'from $5 to $ 10 each';
      expect(inlineSafeLength(prices, holdMathDollars: true), prices.length);
    });

    test(r'an open $x is held, a closed $x$ is not', () {
      expect(inlineSafeLength(r'so $x', holdMathDollars: true), 'so '.length);
      const closed = r'so $x$ and more';
      expect(inlineSafeLength(closed, holdMathDollars: true), closed.length);
    });

    test(r'a $ does not pair across a line break', () {
      const source = 'cost \$x\nand \$y\$ here';
      // `$x` never closed on its line, so it is prose; `$y$` is closed.
      expect(inlineSafeLength(source, holdMathDollars: true), source.length);
    });
  });

  group('completeOpenMath', () {
    test(r'a $ before whitespace or a digit opens nothing', () {
      expect(completeOpenMath(r'pay $ 5', dollarsAreMath: true), isNull);
      expect(completeOpenMath(r'pay $5', dollarsAreMath: true), isNull);
    });

    test(r'an open $x on the last line completes', () {
      final open = completeOpenMath(r'so $x^2', dollarsAreMath: true);
      expect(open, isNotNull);
      expect(open!.start, 3);
      expect(open.completed, r'\(x^2 \)');
    });

    test(r'an unclosed $ on an earlier line is prose', () {
      expect(completeOpenMath('so \$x\nnext', dollarsAreMath: true), isNull);
    });

    test(r'a closed $x$ is not reopened', () {
      expect(completeOpenMath(r'$x$ and', dollarsAreMath: true), isNull);
    });

    test('a double-backtick span hides its maths', () {
      expect(completeOpenMath(r'`` \(x `` and', dollarsAreMath: false), isNull);
      expect(completeOpenMath(r'`` open \(x', dollarsAreMath: false), isNull);
    });
  });

  group('settledSplitOffset', () {
    test('a tilde fence with blank lines is not split inside', () {
      const source = 'Intro.\n\n~~~\na\n\nb\n~~~\n\nTail.';
      final offset = settledSplitOffset(source);
      expect(offset, 'Intro.\n\n'.length);
    });

    test('a long fence is not closed by a shorter one', () {
      const source = 'Intro.\n\n````\n```\n\nx\n';
      expect(settledSplitOffset(source), 0);
    });

    test('a comment with blank lines is not split inside', () {
      const source = 'Intro.\n\n<!--\na\n\nb\n';
      expect(settledSplitOffset(source), 0);
    });
  });
}
