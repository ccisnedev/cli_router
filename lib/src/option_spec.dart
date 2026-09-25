part of 'cli_router.dart';

final RegExp _letter = RegExp(r'^[A-Za-z]$');
final RegExp _optionName = RegExp(r'^[A-Za-z][A-Za-z0-9-]*$');

/// Whether `token` has the shape of an option, per grammar G11: `-` followed
/// by a letter, `--` followed by a letter, or exactly `--`.
///
/// A negative number (`-1`, `-2.5`), a bare `-`, or anything else that is not
/// one of these three shapes is an operand, never an option, regardless of
/// whether it happens to be declared somewhere.
bool looksLikeOption(String token) {
  if (token == '--') return true;
  if (token.length < 2 || token[0] != '-') return false;
  if (token[1] == '-') {
    // '--' + letter (the rest, after that first letter, is unconstrained:
    // '--file', '--file=value', '--f1' all qualify).
    if (token.length < 3) return false; // exactly '--' already handled above
    return _letter.hasMatch(token[2]);
  }
  // '-' + letter ('-f', '-Z', '-f=value' are all option shaped here; the
  // stricter short-option grammar is enforced later, during parsing).
  return _letter.hasMatch(token[1]);
}

/// The declared shape of one option: a flag (present or not, no value) or a
/// value option (`--name value`, `--name=value`, `-n value`).
///
/// Every field that changes behavior is required and validated immediately,
/// at construction: there is no default shape to fall back on.
class OptionSpec {
  /// A flag: present or absent, never carries a value. Flags are never
  /// required (there is nothing to be "missing"; either it was read or not).
  OptionSpec.flag(this.name, {this.abbr, required this.repeatable})
    : takesValue = false,
      required = false {
    _validate();
  }

  /// A value option: `--name value`, `--name=value`, or `-n value` (never
  /// `-n=value`, which is not a valid short form).
  OptionSpec.value(
    this.name, {
    this.abbr,
    required this.required,
    required this.repeatable,
  }) : takesValue = true {
    _validate();
  }

  /// The long name, matched as `--name`.
  final String name;

  /// The single-letter short name, matched as `-x`; `null` if this option has
  /// no short form.
  final String? abbr;

  /// `true` for a value option, `false` for a flag.
  final bool takesValue;

  /// Whether the option must be present for the route to resolve. Checked
  /// only once, after every other option on the invocation has been read.
  final bool required;

  /// Whether the option may occur more than once on the same invocation.
  final bool repeatable;

  void _validate() {
    if (!_optionName.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'must start with a letter and contain only letters, digits or '
            'hyphens',
      );
    }
    final a = abbr;
    if (a != null && !_letter.hasMatch(a)) {
      throw ArgumentError.value(
        a,
        'abbr',
        'must be exactly one letter, or null',
      );
    }
  }

  @override
  String toString() =>
      'OptionSpec(${takesValue ? 'value' : 'flag'} $name'
      '${abbr != null ? ', -$abbr' : ''}'
      '${required ? ', required' : ''}'
      '${repeatable ? ', repeatable' : ''})';

  /// Two [OptionSpec]s are the same option when they have the same shape:
  /// same [name], [abbr], [takesValue], [required] and [repeatable]. This is
  /// declared-shape equality, not Dart's default reference identity, so two
  /// separately constructed `OptionSpec`s that describe the same option
  /// (e.g. one registered on a route and again, identically, on a route
  /// reachable through its own parameter chain) are recognized as one
  /// option throughout resolution, not as two unrelated ones (spec 8.2).
  @override
  bool operator ==(Object other) =>
      other is OptionSpec &&
      name == other.name &&
      abbr == other.abbr &&
      takesValue == other.takesValue &&
      required == other.required &&
      repeatable == other.repeatable;

  @override
  int get hashCode => Object.hash(name, abbr, takesValue, required, repeatable);
}

/// One occurrence of an option, exactly as it was written on the invocation.
///
/// Parsing is lossless: every occurrence of a repeatable option produces its
/// own [ParsedOption], in argv order.
class ParsedOption {
  ParsedOption({
    required this.spec,
    required this.written,
    required this.argvIndex,
    required this.value,
    required this.attached,
  });

  /// The declared option this occurrence matched.
  final OptionSpec spec;

  /// The exact token that introduced this option, as written on argv, e.g.
  /// `--file` or `-f` (never includes the value token, even when the value
  /// came from a separate argv slot).
  final String written;

  /// Index into the original argv of the token in [written].
  final int argvIndex;

  /// The value, if any: `null` for a flag, a string (possibly empty) for a
  /// value option.
  final String? value;

  /// Whether the value was attached with `=` (`--file=x`) rather than read
  /// from the next argv token (`--file x`). Always `false` for a flag.
  final bool attached;
}
