import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictée (plans/13-ux-moderne.md, lot 9) : « 2 h chantier Dupuis » dit au téléphone devient le texte de la saisie
/// express. Reconnaissance du système (iOS, Android, macOS, navigateur) ; rien ne passe par le serveur de Clockifai.
class Dictation {
  Dictation._();
  static final instance = Dictation._();

  final _speech = SpeechToText();
  bool? _ready;

  /// Vrai pendant l'écoute.
  final listening = ValueNotifier(false);

  /// Plateformes où la reconnaissance du système existe (pas Windows ni Linux).
  static bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Écoute en [localeTag] (« fr », « en ») et rend le texte reconnu au fil de la parole ; faux si la dictée est
  /// indisponible (micro refusé, pas de reconnaissance sur l'appareil).
  Future<bool> start(String localeTag, void Function(String text, bool done) onText) async {
    try {
      _ready ??= await _speech.initialize(
        onStatus: (s) => listening.value = s == SpeechToText.listeningStatus,
        onError: (_) => listening.value = false,
      );
      if (_ready != true) return false;
      await _speech.listen(
        onResult: (r) => onText(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: localeTag.startsWith('en') ? 'en_US' : 'fr_FR',
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
        ),
      );
      listening.value = true;
      return true;
    } catch (_) {
      _ready = false; // plugin absent (tests) ou refus : le bouton dira « indisponible »
      listening.value = false;
      return false;
    }
  }

  Future<void> stop() async {
    listening.value = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }
}
