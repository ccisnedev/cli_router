// reservedWords (the router's literal children at the root) and mount
// grafting semantics: a mount's prefix must be literal, nested mounts
// flatten, and build-time checks re-fire against the parent's existing trie.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('reservedWords', () {
    test('lists the root literal children', () {
      final router = buildCalculatrixRouter();
      expect(
        router.reservedWords,
        containsAll([
          'version',
          'doctor',
          'upgrade',
          'help',
          'eval',
          'commands',
        ]),
      );
    });

    test('does not include a root parameter (the shortcut)', () {
      final router = buildCalculatrixRouter();
      expect(router.reservedWords, isNot(contains('<program>')));
    });

    test('a fresh router has an empty reservedWords', () {
      final router = CliRouter(globalOptions: const []);
      expect(router.reservedWords, isEmpty);
    });

    test('mounting adds the mount prefix as a reserved word', () {
      final router = CliRouter(globalOptions: const []);
      final sub = CliRouter(globalOptions: const []);
      sub.cmd('list', (req) async => 0, options: const [], globals: false);
      router.mount('things', sub);
      expect(router.reservedWords, contains('things'));
    });
  });

  group('mount grafting', () {
    test('a mounted route resolves under its prefix', () {
      final router = CliRouter(globalOptions: const []);
      final sub = CliRouter(globalOptions: const []);
      sub.cmd('list', (req) async => 0, options: const [], globals: false);
      router.mount('things', sub);

      final outcome = router.resolve(['things', 'list']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).route.pattern, equals('things list'));
    });

    test('nested mounts flatten transitively', () {
      final innermost = CliRouter(globalOptions: const []);
      innermost.cmd(
        'show',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final middle = CliRouter(globalOptions: const []);
      middle.mount('b', innermost);

      final router = CliRouter(globalOptions: const []);
      router.mount('a', middle);

      final outcome = router.resolve(['a', 'b', 'show']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).route.pattern, equals('a b show'));
    });

    test('a mount prefix must be a plain literal word, not a pattern', () {
      final router = CliRouter(globalOptions: const []);
      final sub = CliRouter(globalOptions: const []);
      sub.cmd('list', (req) async => 0, options: const [], globals: false);
      expect(() => router.mount('<name>', sub), throwsArgumentError);
      expect(() => router.mount('a b', sub), throwsArgumentError);
      expect(() => router.mount('*', sub), throwsArgumentError);
    });

    test('build-time checks re-fire after grafting: option scope collision '
        'against the parent globals', () {
      final router = CliRouter(
        globalOptions: [OptionSpec.flag('json', abbr: null, repeatable: false)],
      );
      final sub = CliRouter(globalOptions: const []);
      sub.cmd(
        'list',
        (req) async => 0,
        options: [OptionSpec.flag('json', abbr: null, repeatable: false)],
        globals: true,
      );
      expect(() => router.mount('things', sub), throwsArgumentError);
    });

    test('build-time checks re-fire after grafting: duplicate pattern', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'things list',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      final sub = CliRouter(globalOptions: const []);
      sub.cmd('list', (req) async => 0, options: const [], globals: false);
      expect(() => router.mount('things', sub), throwsA(isA<StateError>()));
    });

    test('mounting an empty router (no routes) is a no-op that still '
        'reserves the prefix word', () {
      final router = CliRouter(globalOptions: const []);
      final sub = CliRouter(globalOptions: const []);
      router.mount('things', sub);
      expect(router.reservedWords, contains('things'));
      final outcome = router.resolve(['things']);
      expect(outcome, isA<CliRejection>());
    });
  });
}
