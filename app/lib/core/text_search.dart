/// Recherche tolérante (plans/13-ux-moderne.md) : sans accents ni majuscules, par début de mot. Sert à la saisie
/// express et à la palette ⌘K.
library;

/// [s] en minuscules sans accents, de même longueur (les positions restent valables dans l'original).
String fold(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    b.write(i < 0 ? c : to[i]);
  }
  return b.toString();
}

/// Rang de [text] pour la recherche [query], ou null s'il ne correspond pas ; plus petit = meilleur. Chaque mot de la
/// requête doit commencer un mot du texte : « rap » trouve « Rapports », « sombre » trouve « Apparence : sombre ».
int? searchRank(String query, String text) {
  final words = fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return 0;
  final parts = fold(text).split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty).toList();
  var rank = 0;
  for (final w in words) {
    final i = parts.indexWhere((p) => p.startsWith(w));
    if (i < 0) return null;
    rank += i;
  }
  return rank;
}
