import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('example CLI', () {
    test('system version', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/example.dart',
        'system',
        'version',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('system.version = 1.0.0'));
    });

    test('root help', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/example.dart',
        'help',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Available commands:'));
      expect(result.stdout, contains('Shows general help'));
    });

    test('user list', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/example.dart',
        'user',
        'list',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Users.list(limit=10, activeOnly=false)'));
      expect(result.stdout, contains('- u#1  Alice'));
      expect(result.stdout, contains('- u#2  Bob'));
    });

    test('user show 42', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/example.dart',
        'user',
        'show',
        '42',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Users.show(id=42)'));
    });

    test('order process with options before the operand', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/example.dart',
        'order',
        'process',
        '--dry-run',
        '--threads',
        '4',
        '900',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, equals(0));
      expect(
        result.stdout,
        contains('Orders.process(id=900, dryRun=true, threads=4)'),
      );
    });

    test('an option after the operand is rejected', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/example.dart',
        'order',
        'process',
        '900',
        '--dry-run',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, equals(64));
      expect(result.stderr, contains('error:'));
    });
  });
}
