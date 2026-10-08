// Regression test for: Link with title attribute
//
// FIXED: `[text](url "title")` used to keep the title inside the URL, so
// `[Link Text](/path/to/page "Link Title")` linked to
// `/path/to/page "Link Title"`. The parser now splits a quoted, single-quoted
// or parenthesised title off the destination (CommonMark "Links").

import 'package:flutter_test/flutter_test.dart';
import '../utils/test_helpers.dart';

void main() {
  group('Link with title attribute', () {
    testWidgets('link with quoted title links to the URL alone', (
      tester,
    ) async {
      await pumpMarkdown(tester, '[Link Text](/path/to/page "Link Title")');
      expect(
        getSerializedOutput(tester),
        contains('LINK("Link Text", url="/path/to/page")'),
      );
    });

    testWidgets('link with title in sentence context', (tester) async {
      await pumpMarkdown(
        tester,
        'Check out [Projects](/page/projects "Project Overview") for more info.',
      );
      final output = getSerializedOutput(tester);
      expect(output, contains('LINK("Projects", url="/page/projects")'));
      expect(output, contains('Check out'));
      expect(output, contains('for more info'));
    });

    testWidgets('link with title containing special characters', (
      tester,
    ) async {
      await pumpMarkdown(
        tester,
        '[Features](/features "App Features: Overview")',
      );
      expect(
        getSerializedOutput(tester),
        contains('LINK("Features", url="/features")'),
      );
    });

    testWidgets('single-quoted and parenthesised titles', (tester) async {
      await pumpMarkdown(tester, "[A](/a 'Title A') and [B](/b (Title B))");
      final output = getSerializedOutput(tester);
      expect(output, contains('LINK("A", url="/a")'));
      expect(output, contains('LINK("B", url="/b")'));
    });

    testWidgets('multiple links with titles', (tester) async {
      await pumpMarkdown(
        tester,
        '[First](/a "Title A") and [Second](/b "Title B")',
      );
      final output = getSerializedOutput(tester);
      expect(output, contains('LINK("First", url="/a")'));
      expect(output, contains('LINK("Second", url="/b")'));
      expect(output, contains('and'));
    });
  });
}
