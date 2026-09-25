// CliRouter.run(): the I/O entry point built on the pure resolve(). onReject
// is required at the call site (no silent default), the handler receives the
// new CliRequest shape (no flags, no matchedCommand), and CliRequest exposes
// route/params/rest/options plus param()/option() helpers.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('run() dispatches to the matched handler', () {
    test(
      'a successful resolution invokes the route handler with a request',
      () async {
        CliRequest? captured;
        final router = CliRouter();
        router.cmd(
          'greet <name>',
          (req) async {
            captured = req;
            return 0;
          },
          options: [OptionSpec.flag('loud', abbr: 'l', repeatable: false)],
          globals: false,
        );

        final code = await router.run([
          'greet',
          '--loud',
          'ada',
        ], onReject: (rejection) async => 64);

        expect(code, equals(0));
        expect(captured, isNotNull);
        expect(captured!.route.pattern, equals('greet <name>'));
        expect(captured!.param('name'), equals('ada'));
        expect(captured!.option('loud'), isNotNull);
        expect(captured!.rest, isEmpty);
        expect(captured!.originalArgs, equals(['greet', '--loud', 'ada']));
      },
    );

    test('CliRequest.param returns null for an unbound name', () async {
      CliRequest? captured;
      final router = CliRouter();
      router.cmd(
        'greet <name>',
        (req) async {
          captured = req;
          return 0;
        },
        options: const [],
        globals: false,
      );
      await router.run(['greet', 'ada'], onReject: (r) async => 1);
      expect(captured!.param('missing'), isNull);
    });

    test(
      'CliRequest.option returns null when the option was not read',
      () async {
        CliRequest? captured;
        final router = CliRouter();
        router.cmd(
          'build',
          (req) async {
            captured = req;
            return 0;
          },
          options: [OptionSpec.flag('verbose', abbr: 'v', repeatable: false)],
          globals: false,
        );
        await router.run(['build'], onReject: (r) async => 1);
        expect(captured!.option('verbose'), isNull);
      },
    );

    test('a wildcard route exposes leftover operands via rest', () async {
      CliRequest? captured;
      final router = CliRouter();
      router.cmd(
        'run *',
        (req) async {
          captured = req;
          return 0;
        },
        options: const [],
        globals: false,
      );
      await router.run(['run', 'a', 'b', 'c'], onReject: (r) async => 1);
      expect(captured!.rest, equals(['a', 'b', 'c']));
    });
  });

  group('run() calls onReject for a rejection, never a silent default', () {
    test(
      'onReject receives the CliRejection and its return code is used',
      () async {
        final router = buildCalculatrixRouter();
        CliRejection? captured;
        final code = await router.run(
          ['bogus-and-unknown-but-shortcut-absorbs-it'],
          onReject: (rejection) async {
            captured = rejection;
            return 77;
          },
        );
        // The calculatrix router has a shortcut, so this actually resolves;
        // use a router without one to force a rejection instead.
        expect(code, isNot(equals(77)));

        final noShortcut = CliRouter();
        noShortcut.cmd(
          'version',
          (req) async => 0,
          options: const [],
          globals: false,
        );
        final code2 = await noShortcut.run(
          ['bogus'],
          onReject: (rejection) async {
            captured = rejection;
            return 77;
          },
        );
        expect(code2, equals(77));
        expect(captured, isNotNull);
        expect(captured!.kind, equals(CliRejectionKind.unknownCommand));
      },
    );

    test('onReject can be synchronous-returning (FutureOr<int>)', () async {
      final router = CliRouter();
      router.cmd(
        'version',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      final code = await router.run(['bogus'], onReject: (rejection) => 9);
      expect(code, equals(9));
    });
  });

  group('CliRequest has no flags map and no matchedCommand/help helpers', () {
    test(
      'the request shape exposes only route, params, rest, options',
      () async {
        CliRequest? captured;
        final router = CliRouter();
        router.cmd(
          'ping',
          (req) async {
            captured = req;
            return 0;
          },
          options: const [],
          globals: false,
        );
        await router.run(['ping'], onReject: (r) async => 1);

        // dynamic-free structural check: these members must exist and behave
        // as documented; the old `flags`/`matchedCommand`/`isHelpRequested`
        // members from 0.1.1 are gone entirely, so this file would fail to
        // compile if they were referenced. We only assert the new surface.
        expect(captured!.route.pattern, equals('ping'));
        expect(captured!.params, isEmpty);
        expect(captured!.rest, isEmpty);
        expect(captured!.options, isEmpty);
      },
    );
  });
}
