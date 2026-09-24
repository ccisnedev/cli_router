part of 'cli_router.dart';

// An option is `-` or `--` followed by a letter, with no whitespace in its
// name (the part before `=`). The value after `=` may contain anything, so
// `--title=two words` stays an option while `-1 2 +` is a positional.
// Includes the end-of-options marker so lookahead never consumes it as a value.
final _optionPattern = RegExp(r'^--?[A-Za-z][^=\s]*(=[\s\S]*)?$');

bool _isOptionToken(String token) =>
    token == '--' || _optionPattern.hasMatch(token);

class _FlagsParseResult {
  _FlagsParseResult(this.flags, this.trailingPositionals);
  final Map<String, String?> flags;
  final List<String> trailingPositionals;
}

_FlagsParseResult _parseFlags(List<String> args) {
  final flags = <String, String?>{};
  final trailing = <String>[];
  bool parsing = true;

  String? takeNext(int i) =>
      (i + 1 < args.length && !_isOptionToken(args[i + 1]))
      ? args[i + 1]
      : null;

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (parsing && a == '--') {
      parsing = false;
      continue;
    }
    if (!parsing) {
      trailing.add(a);
      continue;
    }
    if (!_isOptionToken(a)) {
      trailing.add(a);
      continue;
    }

    if (a.startsWith('--')) {
      final rem = a.substring(2);
      if (rem.isEmpty) continue;
      final eq = rem.indexOf('=');
      if (eq >= 0) {
        final name = rem.substring(0, eq);
        final value = rem.substring(eq + 1);
        flags[name] = value;
      } else {
        if (rem.startsWith('no-') && rem.length > 3) {
          flags[rem.substring(3)] = 'false';
        } else {
          final next = takeNext(i);
          if (next != null) {
            flags[rem] = next;
            i++;
          } else {
            flags[rem] = 'true';
          }
        }
      }
      continue;
    }

    if (a.startsWith('-') && a.length > 1) {
      final rem = a.substring(1);
      final eq = rem.indexOf('=');
      if (eq >= 0) {
        final name = rem.substring(0, eq);
        final value = rem.substring(eq + 1);
        flags[name] = value;
      } else if (rem.length == 1) {
        final name = rem;
        final next = takeNext(i);
        if (next != null) {
          flags[name] = next;
          i++;
        } else {
          flags[name] = 'true';
        }
      } else {
        for (final ch in rem.split('')) {
          flags[ch] = 'true';
        }
      }
      continue;
    }

    trailing.add(a);
  }

  return _FlagsParseResult(flags, trailing);
}
