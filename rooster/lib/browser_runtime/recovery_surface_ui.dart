import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:rooster/utils/common_strings.dart';

/// Accessible recovery UI shared by every CEF-owned surface.
///
/// Covers criterion 3 of #127 across Windows embedded/standalone, native
/// Linux embedded/standalone, Flatpak both presentations, and the Windows
/// official-video adapter: reconnecting, crashed-surface, retry, close, and
/// diagnostic-reporting UI is accessible.
///
/// Contract:
/// - Recoverable failures show "Reconnecting browser" as a live region.
/// - Terminal surface failures show "This embedded page crashed. Retry" or
///   "Graphics unavailable. Retry" with Close and Report diagnostics.
/// - Terminal runtime failures show "Embedded browser unavailable. Retry
///   browser".
/// - Raw process paths, URLs, CEF statuses, profile IDs, cookies, and device
///   IDs are never shown; only the fixed strings above (translated, see
///   docs/localization.md) plus an opaque diagnostic ID (for example
///   `d-3-7`) are rendered.
/// - Every control is keyboard-focusable, exposes a semantic label, honors
///   text scaling, and works with high-contrast themes (no color-only
///   signalling; text labels always accompany state).

/// "Diagnostic" and the opaque ID, under every failure card's title.
String labelBrowserDiagnosticId(String diagnosticId) => Intl.message(
    "Diagnostic $diagnosticId",
    name: "labelBrowserDiagnosticId",
    args: [diagnosticId],
    desc: "Under the message of an embedded browser page that failed: the "
        "diagnostic's opaque ID (such as d-3-7), to quote when reporting it");

/// What a screen reader says for a failure card: its title and the
/// diagnostic.
String labelBrowserFailureSemantics(String title, String diagnosticId) =>
    Intl.message("$title. Diagnostic $diagnosticId",
        name: "labelBrowserFailureSemantics",
        args: [title, diagnosticId],
        desc: "What a screen reader announces for an embedded browser page "
            "that failed: the card's title (already translated), then the "
            "diagnostic's opaque ID");

/// Accessible reconnecting overlay shown during host restart.
///
/// The rest of Rooster remains usable while this surface reports
/// reconnecting; the overlay is a live region so screen readers announce
/// the state change.
class ReconnectingBrowserOverlay extends StatelessWidget {
  const ReconnectingBrowserOverlay({super.key});

  static String get labelBrowserReconnecting =>
      Intl.message("Reconnecting browser…",
          name: "labelBrowserReconnecting",
          desc: "Over an embedded web page (a widget, a video) while the "
              "browser behind it restarts");

  static String get labelBrowserReconnectingSemantics =>
      Intl.message("Reconnecting browser",
          name: "labelBrowserReconnectingSemantics",
          desc: "What a screen reader announces while the browser behind an "
              "embedded web page restarts");

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: labelBrowserReconnectingSemantics,
      child: Text(
        labelBrowserReconnecting,
        textDirection: TextDirection.ltr,
      ),
    );
  }
}

/// Terminal surface failure card with Retry, Close, and Report diagnostics.
///
/// [title] must be one of the fixed contract strings:
/// [labelBrowserPageCrashed] ("This embedded page crashed. Retry") or
/// [labelBrowserGraphicsUnavailable] ("Graphics unavailable. Retry").
/// [diagnosticId] is the opaque ID (for example `d-3-7`) retained locally
/// when upload is unavailable; [onCopyDiagnosticId] implements Copy
/// diagnostic ID.
class CrashedSurfaceCard extends StatelessWidget {
  const CrashedSurfaceCard({
    super.key,
    required this.title,
    required this.diagnosticId,
    required this.onRetry,
    required this.onClose,
    required this.onReport,
    required this.onCopyDiagnosticId,
  });

  static String get labelBrowserPageCrashed =>
      Intl.message("This embedded page crashed. Retry",
          name: "labelBrowserPageCrashed",
          desc: "Card in place of an embedded web page (a widget, a video) "
              "whose page crashed; asks to retry with the button below");

  static String get labelBrowserGraphicsUnavailable =>
      Intl.message("Graphics unavailable. Retry",
          name: "labelBrowserGraphicsUnavailable",
          desc: "Card in place of an embedded web page when its graphics "
              "failed; asks to retry with the button below");

  static String get promptBrowserRetry => Intl.message("Retry",
      name: "promptBrowserRetry",
      desc: "Button on the card of an embedded web page that failed: loads "
          "the page again");

  static String get promptBrowserReportDiagnostics =>
      Intl.message("Report diagnostics",
          name: "promptBrowserReportDiagnostics",
          desc: "Button on the card of an embedded web page that failed: "
              "sends the failure's diagnostics");

  static String get promptBrowserCopyDiagnosticId =>
      Intl.message("Copy diagnostic ID",
          name: "promptBrowserCopyDiagnosticId",
          desc: "Button on the card of an embedded web page that failed: "
              "copies the failure's opaque diagnostic ID");

  static String get labelBrowserRetryPageHint =>
      Intl.message("Retry loading this page",
          name: "labelBrowserRetryPageHint",
          desc: "What a screen reader says the Retry button does, on the card "
              "of an embedded web page that failed");

  static String get labelBrowserClosePageHint => Intl.message("Close this page",
      name: "labelBrowserClosePageHint",
      desc: "What a screen reader says the Close button does, on the card of "
          "an embedded web page that failed");

  static String get labelBrowserReportDiagnosticsHint =>
      Intl.message("Report diagnostics for this failure",
          name: "labelBrowserReportDiagnosticsHint",
          desc: "What a screen reader says the Report diagnostics button "
              "does, on the card of an embedded web page that failed");

  static String labelBrowserCopyDiagnosticIdHint(String diagnosticId) =>
      Intl.message("Copy diagnostic ID $diagnosticId",
          name: "labelBrowserCopyDiagnosticIdHint",
          args: [diagnosticId],
          desc: "What a screen reader says the Copy diagnostic ID button "
              "does; diagnosticId is the opaque ID, such as d-3-7");

  final String title;
  final String diagnosticId;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback onReport;
  final VoidCallback onCopyDiagnosticId;

  @override
  Widget build(BuildContext context) {
    assert(
      title == labelBrowserPageCrashed ||
          title == labelBrowserGraphicsUnavailable,
      'crashed-surface title must use the fixed contract string',
    );
    return Semantics(
      liveRegion: true,
      label: labelBrowserFailureSemantics(title, diagnosticId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, textDirection: TextDirection.ltr),
          Text(
            labelBrowserDiagnosticId(diagnosticId),
            textDirection: TextDirection.ltr,
          ),
          Wrap(
            spacing: 8,
            children: [
              _Action(
                label: promptBrowserRetry,
                semanticHint: labelBrowserRetryPageHint,
                onPressed: onRetry,
              ),
              _Action(
                label: CommonStrings.promptClose,
                semanticHint: labelBrowserClosePageHint,
                onPressed: onClose,
              ),
              _Action(
                label: promptBrowserReportDiagnostics,
                semanticHint: labelBrowserReportDiagnosticsHint,
                onPressed: onReport,
              ),
              _Action(
                label: promptBrowserCopyDiagnosticId,
                semanticHint: labelBrowserCopyDiagnosticIdHint(diagnosticId),
                onPressed: onCopyDiagnosticId,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Terminal runtime failure card with a single Retry browser action.
class RuntimeUnavailableCard extends StatelessWidget {
  const RuntimeUnavailableCard({
    super.key,
    required this.diagnosticId,
    required this.onRetryBrowser,
  });

  static String get labelBrowserRuntimeUnavailable =>
      Intl.message("Embedded browser unavailable. Retry browser",
          name: "labelBrowserRuntimeUnavailable",
          desc: "Card in place of an embedded web page when the browser that "
              "draws it could not run; asks to start it again with the button "
              "below");

  static String get promptBrowserRetryBrowser => Intl.message("Retry browser",
      name: "promptBrowserRetryBrowser",
      desc: "Button on the card shown when the embedded browser could not "
          "run: starts it again");

  static String get labelBrowserRetryBrowserHint =>
      Intl.message("Retry starting the embedded browser",
          name: "labelBrowserRetryBrowserHint",
          desc: "What a screen reader says the Retry browser button does");

  final String diagnosticId;
  final VoidCallback onRetryBrowser;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: labelBrowserFailureSemantics(
          labelBrowserRuntimeUnavailable, diagnosticId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            labelBrowserRuntimeUnavailable,
            textDirection: TextDirection.ltr,
          ),
          Text(
            labelBrowserDiagnosticId(diagnosticId),
            textDirection: TextDirection.ltr,
          ),
          _Action(
            label: promptBrowserRetryBrowser,
            semanticHint: labelBrowserRetryBrowserHint,
            onPressed: onRetryBrowser,
          ),
        ],
      ),
    );
  }
}

/// Keyboard-focusable semantic button used by all recovery cards.
///
/// Built on widgets-only primitives so the cards work in every presentation
/// (embedded texture, owned window placeholder, dialog chrome) and remain
/// testable without a Material ancestor.
class _Action extends StatefulWidget {
  const _Action({
    required this.label,
    required this.semanticHint,
    required this.onPressed,
  });

  final String label;
  final String semanticHint;
  final VoidCallback onPressed;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!mounted) return;
      setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      hint: widget.semanticHint,
      focused: _focused,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Focus(
          focusNode: _focus,
          onKeyEvent: (node, event) {
            // Enter/Space activation is handled by the embedder's shortcut
            // layer; focus traversal itself must work for keyboard users.
            return KeyEventResult.ignored;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF000000),
                width: _focused ? 3 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.label,
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  }
}
