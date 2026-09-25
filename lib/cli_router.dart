/// Public library for cli_router.
///
/// Import `package:cli_router/cli_router.dart` to use:
/// - CliRouter, CliRequest, CliHandler, CliMiddleware
/// - OptionSpec, ParsedOption, looksLikeOption
/// - CliRoute, CliOutcome, CliResolution, CliRejection, CliRejectionKind,
///   CliRejectionHandler
/// - ListedCommand
/// - handler(...) helper
library;

export 'src/cli_router.dart'
    show
        CliRouter,
        CliRequest,
        CliHandler,
        CliMiddleware,
        OptionSpec,
        ParsedOption,
        looksLikeOption,
        CliRoute,
        CliOutcome,
        CliResolution,
        CliRejection,
        CliRejectionKind,
        CliRejectionHandler,
        ListedCommand,
        handler;
