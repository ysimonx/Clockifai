import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Connexion sur le web : un vrai <form> HTML à la place des champs Flutter, pour les gestionnaires de mots de passe.
/// Flutter ne met dans le DOM que le champ qui a le focus ; le mot de passe y reste un champ de 0 × 0 px que
/// Bitwarden juge invisible et ne remplit pas. Ici, les champs sont visibles, dans un même formulaire, avec leur
/// `autocomplete`, et habillés comme ceux du thème (InputDecorationTheme).
class WebLoginForm extends StatefulWidget {
  const WebLoginForm({
    super.key,
    required this.name,
    required this.email,
    required this.password,
    required this.signUp,
    required this.labels,
    required this.onSubmit,
  });
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController password;
  final bool signUp;
  final ({String name, String email, String password}) labels;
  final VoidCallback onSubmit;

  @override
  State<WebLoginForm> createState() => _WebLoginFormState();
}

class _WebLoginFormState extends State<WebLoginForm> {
  static const _fieldHeight = 40.0;
  static const _gap = 12.0;
  static var _styled = false;

  web.HTMLFormElement? _form;
  final _inputs = <String, web.HTMLInputElement>{};

  /// Le focus de Flutter suit celui des champs HTML : sans lui, Tab et Entrée iraient à un bouton de la page.
  final _focus = FocusNode(debugLabel: 'WebLoginForm');

  /// Feuille de style commune, une fois par page : Geist (la police de l'app, servie avec ses assets) et l'aspect des
  /// champs, dont les couleurs viennent du thème par des variables CSS.
  static void _addStyle() {
    if (_styled) return;
    _styled = true;
    final font = ui_web.assetManager.getAssetUrl('assets/fonts/Geist-Regular.ttf');
    final style = web.document.createElement('style') as web.HTMLStyleElement;
    style.textContent = '''
@font-face { font-family: ClockifaiGeist; src: url("$font"); }
.clockifai-login { display: flex; flex-direction: column; gap: ${_gap}px; margin: 0; width: 100%; height: 100%; }
.clockifai-login input { box-sizing: border-box; height: ${_fieldHeight}px; margin: 0; padding: 0 12px; outline: none;
  border: 1px solid var(--border); border-radius: 10px; background: var(--fill); color: var(--text);
  font: 16px ClockifaiGeist, system-ui, sans-serif; }
.clockifai-login input:focus { border: 2px solid var(--focus); padding: 0 11px; }
.clockifai-login input::placeholder { color: var(--hint); }
''';
    web.document.head!.append(style);
  }

  void _created(Object element) {
    _addStyle();
    final form = (element as web.HTMLFormElement)
      ..className = 'clockifai-login'
      ..method = 'post'
      ..action = '#'
      ..noValidate = true;
    form.addEventListener('focusin', (web.Event _) {
      if (!_focus.hasFocus) _focus.requestFocus();
    }.toJS);
    form.addEventListener('submit', (web.Event e) {
      e.preventDefault();
      widget.onSubmit();
    }.toJS);
    for (final (key, type, controller) in [
      ('name', 'text', widget.name),
      ('email', 'email', widget.email),
      ('password', 'password', widget.password),
    ]) {
      final input = (web.document.createElement('input') as web.HTMLInputElement)
        ..type = type
        ..name = key
        ..value = controller.text;
      // Saisie, et remplissage par le navigateur ou un gestionnaire (événements input ou change) : dans le contrôleur.
      void sync(web.Event _) => controller.text = input.value;
      input.addEventListener('input', sync.toJS);
      input.addEventListener('change', sync.toJS);
      // Entrée : champ suivant, puis envoi depuis le mot de passe (un formulaire sans bouton ne s'envoie pas seul).
      input.addEventListener('keydown', (web.KeyboardEvent e) {
        if (e.key != 'Enter') return;
        e.preventDefault();
        if (key == 'password') {
          form.requestSubmit();
        } else {
          _inputs[key == 'name' ? 'email' : 'password']!.focus();
        }
      }.toJS);
      form.append(input);
      _inputs[key] = input;
    }
    _form = form;
    _update();
  }

  /// Ce qui change avec l'inscription et le thème : champ du nom, `autocomplete` du mot de passe, libellés, couleurs.
  void _update() {
    final form = _form;
    if (form == null) return;
    final theme = Theme.of(context);
    final decoration = theme.inputDecorationTheme;
    String css(Color? c) => c == null
        ? 'transparent'
        : 'rgba(${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()}, ${c.a.toStringAsFixed(3)})';
    for (final (name, color) in [
      ('--border', decoration.enabledBorder?.borderSide.color ?? theme.colorScheme.outline),
      ('--focus', decoration.focusedBorder?.borderSide.color ?? theme.colorScheme.primary),
      ('--fill', decoration.fillColor ?? theme.colorScheme.surface),
      ('--text', theme.colorScheme.onSurface),
      ('--hint', theme.colorScheme.onSurfaceVariant),
    ]) {
      form.style.setProperty(name, css(color));
    }
    final signUp = widget.signUp;
    for (final (key, label, autocomplete) in [
      ('name', widget.labels.name, 'name'),
      ('email', widget.labels.email, 'username'),
      ('password', widget.labels.password, signUp ? 'new-password' : 'current-password'),
    ]) {
      _inputs[key]!
        ..placeholder = label
        ..autocomplete = autocomplete
        ..setAttribute('aria-label', label);
    }
    _inputs['name']!.style.display = signUp ? '' : 'none';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(WebLoginForm old) {
    super.didUpdateWidget(old);
    _update();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
        // Tab, ⇧Tab et Entrée restent au navigateur (champ suivant, envoi), pas à la navigation de Flutter.
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.tab): DoNothingAndStopPropagationIntent(),
          SingleActivator(LogicalKeyboardKey.tab, shift: true): DoNothingAndStopPropagationIntent(),
          SingleActivator(LogicalKeyboardKey.enter): DoNothingAndStopPropagationIntent(),
        },
        child: Focus(
          focusNode: _focus,
          child: SizedBox(
            height: widget.signUp ? 3 * _fieldHeight + 2 * _gap : 2 * _fieldHeight + _gap,
            child: HtmlElementView.fromTagName(tagName: 'form', onElementCreated: _created),
          ),
        ),
      );
}
