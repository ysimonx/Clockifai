import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Raccourcis clavier (plans/13-ux-moderne.md, lot 1). Écoutés sur [HardwareKeyboard], donc quel que soit le widget
/// qui a le focus ; ignorés quand une boîte de dialogue couvre l'écran. Une touche seule ne vaut que hors saisie
/// ([plainKey]) : taper « n » dans un champ écrit un « n ».
typedef KeyHandler = bool Function(KeyEvent event);

/// Vrai si le focus est dans un champ de texte.
bool isTyping() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText || context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// ⌘ sur Mac, Ctrl ailleurs (les deux sont acceptés).
bool get commandPressed => HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;

/// Nom affiché de la touche de commande : « ⌘ » sur Mac et iPhone, « Ctrl » ailleurs.
String get commandKeyLabel =>
    defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS ? '⌘' : 'Ctrl';

/// Une touche seule (sans ⌘, Ctrl ni Alt), hors saisie.
bool plainKey(KeyEvent event) =>
    !isTyping() && !commandPressed && !HardwareKeyboard.instance.isAltPressed && event is! KeyUpEvent;

/// Racine des raccourcis : ceux des pages ([PageShortcuts]) d'abord, puis [onKey], ceux de toute l'app.
class AppShortcuts extends StatefulWidget {
  const AppShortcuts({super.key, required this.onKey, required this.child});
  final KeyHandler onKey;
  final Widget child;

  @override
  State<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends State<AppShortcuts> {
  final _pages = <KeyHandler>[];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  bool _handle(KeyEvent event) {
    if (event is KeyUpEvent || !mounted) return false;
    // Une boîte de dialogue (route au-dessus de la coquille) garde ses touches.
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    for (final page in _pages.reversed) {
      if (page(event)) return true;
    }
    return widget.onKey(event);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Raccourcis propres à une page, actifs tant qu'elle est affichée.
class PageShortcuts extends StatefulWidget {
  const PageShortcuts({super.key, required this.onKey, required this.child});
  final KeyHandler onKey;
  final Widget child;

  @override
  State<PageShortcuts> createState() => _PageShortcutsState();
}

class _PageShortcutsState extends State<PageShortcuts> {
  _AppShortcutsState? _root;

  bool _handle(KeyEvent event) => widget.onKey(event);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _root?._pages.remove(_handle);
    _root = context.findAncestorStateOfType<_AppShortcutsState>();
    _root?._pages.add(_handle);
  }

  @override
  void dispose() {
    _root?._pages.remove(_handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
