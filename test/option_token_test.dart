import 'dart:convert';
import 'dart:io';

import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

Future<CliRequest> _requestOf(
  List<String> args, {
  String route = 'calc add',
}) async {
  late CliRequest seen;
  final router = CliRouter();
  router.cmd(route, (req) async {
    seen = req;
    return 0;
  });
  final exitCode = await router.run(
    args,
    stdout: _TestSink(),
    stderr: _TestSink(),
  );
  expect(exitCode, equals(0));
  return seen;
}

void main() {
  group('option tokens', () {
    const positionalTokens = [
      '-3',
      '-2.5',
      '-.5',
      '-1e3',
      '-',
      '-1 2 +',
      '--3',
      '-?',
      '--?',
      '---name',
      '-a b',
      '--name\tvalue',
      '-a\nb',
      '--name\rvalue',
      '-a\fb',
      '--name\u000bvalue',
      '--name\u00a0value',
      '-a\u2003b',
      '-v ',
      ' --name',
      'plain text',
      '',
    ];

    for (final token in positionalTokens) {
      final label = jsonEncode(token);

      test('keeps $label positional before options', () async {
        final req = await _requestOf([
          'calc',
          'add',
          token,
          '5',
          '--json',
        ]);

        expect(req.positionals, equals([token, '5']));
        expect(req.flags, equals({'json': 'true'}));
      });

      test('keeps $label positional after options', () async {
        final req = await _requestOf([
          'calc',
          'add',
          '--json=true',
          token,
          '5',
        ]);

        expect(req.positionals, equals([token, '5']));
        expect(req.flags, equals({'json': 'true'}));
      });

      test('matches $label as a route parameter', () async {
        final req = await _requestOf(
          ['show', token, 'details'],
          route: 'show <value> details',
        );

        expect(req.matchedCommand, equals(['show', token, 'details']));
        expect(req.params, equals({'value': token}));
        expect(req.positionals, isEmpty);
        expect(req.flags, isEmpty);
      });

      for (final option in ['--offset', '-o']) {
        test('accepts $label as a value for $option', () async {
          final req = await _requestOf([
            'calc',
            'add',
            option,
            token,
            '--json',
          ]);
          final name = option == '--offset' ? 'offset' : 'o';

          expect(req.flags, equals({name: token, 'json': 'true'}));
          expect(req.positionals, isEmpty);
        });
      }
    }

    test('keeps negative operands without flags', () async {
      final req = await _requestOf(['calc', 'add', '-3', '5']);

      expect(req.positionals, equals(['-3', '5']));
      expect(req.flags, isEmpty);
    });

    test('keeps an expression after a matched route prefix', () async {
      final req = await _requestOf(
        ['rpn', 'eval', '-1 2 +'],
        route: 'rpn eval',
      );

      expect(req.matchedCommand, equals(['rpn', 'eval']));
      expect(req.positionals, equals(['-1 2 +']));
      expect(req.flags, isEmpty);
    });

    test('ends options at --', () async {
      const trailing = [
        '-v',
        '--name=value',
        '--no-color',
        '--',
        '-3',
        '-',
        '-1 2 +',
      ];
      const prefixes = [
        <String>[],
        ['--flag'],
        ['-o'],
      ];

      for (final prefix in prefixes) {
        final req = await _requestOf([
          'calc',
          'add',
          ...prefix,
          '--',
          ...trailing,
        ]);
        final expectedFlags = <String, String?>{};
        if (prefix.isNotEmpty) {
          expectedFlags[prefix.single == '--flag' ? 'flag' : 'o'] = 'true';
        }

        expect(req.positionals, equals(trailing));
        expect(req.flags, equals(expectedFlags));
      }
    });

    const regressions = [
      (args: ['-v'], flags: {'v': 'true'}),
      (args: ['-abc'], flags: {'a': 'true', 'b': 'true', 'c': 'true'}),
      (args: ['--name=value'], flags: {'name': 'value'}),
      (args: ['--no-color'], flags: {'color': 'false'}),
      (args: ['--flag', 'value'], flags: {'flag': 'value'}),
      (args: ['-o', 'value'], flags: {'o': 'value'}),
      (args: ['-V', '--Name=value'], flags: {'V': 'true', 'Name': 'value'}),
      (args: ['--x1.y=z'], flags: {'x1.y': 'z'}),
      (args: ['-a1?'], flags: {'a': 'true', '1': 'true', '?': 'true'}),
      (args: ['-o=value'], flags: {'o': 'value'}),
      (
        args: ['--title=value with spaces'],
        flags: {'title': 'value with spaces'},
      ),
      (args: ['-o=a b'], flags: {'o': 'a b'}),
    ];

    for (final regression in regressions) {
      test('preserves ${regression.args.join(' ')}', () async {
        final req = await _requestOf([
          'calc',
          'add',
          ...regression.args,
        ]);

        expect(req.flags, equals(regression.flags));
        expect(req.positionals, isEmpty);
      });
    }
  });
}

class _TestSink implements IOSink {
  final _buffer = StringBuffer();

  @override
  void write(Object? object) => _buffer.write(object);
  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) => Future.value();
  @override
  Future flush() => Future.value();
  @override
  Future close() => Future.value();
  @override
  Future get done => Future.value();
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding value) {}

  @override
  String toString() => _buffer.toString();
}
