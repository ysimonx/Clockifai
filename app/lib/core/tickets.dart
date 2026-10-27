/// Tickets des clients (plans/19-tickets-clients.md) : une tâche porte l'URL d'un ticket Jira, Linear ou GitHub, et
/// sa clé (« ENG-123 »), qui la retrouve. Le serveur fait la même analyse pour les sessions de Claude (lot 2).
library;

/// Clé et URL d'un ticket ; l'une des deux au moins.
class TicketRef {
  const TicketRef({this.key, this.url});
  final String? key;
  final String? url;

  /// Ce qu'on montre : la clé, sinon l'URL.
  String get label => key ?? url!;
}

final _key = RegExp(r'^[A-Za-z][A-Za-z0-9_]*-\d+$');

/// Longueur maximale d'une URL de ticket (colonne `tasks.ticket_url`).
const ticketUrlMax = 500;

/// Ticket désigné par [input] : une URL http(s) (Jira `…/browse/ENG-123` ou `?selectedIssue=ENG-123`, Linear
/// `…/issue/ENG-123/…`, GitHub `…/<org>/<dépôt>/issues/45` → `dépôt#45`, autre URL sans clé) ou une clé seule.
TicketRef? parseTicket(String input) {
  final text = input.trim();
  if (text.isEmpty || text.length > ticketUrlMax) return null;
  if (_key.hasMatch(text)) return TicketRef(key: text.toUpperCase());
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) return null;
  return TicketRef(key: _keyOf(uri), url: text);
}

String? _keyOf(Uri uri) {
  final segs = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
  String? after(String marker) {
    final i = segs.indexOf(marker);
    return i >= 0 && i + 1 < segs.length && _key.hasMatch(segs[i + 1]) ? segs[i + 1].toUpperCase() : null;
  }

  final selected = uri.queryParameters['selectedIssue'];
  if (selected != null && _key.hasMatch(selected)) return selected.toUpperCase();
  if (uri.host == 'github.com') {
    final ok = segs.length >= 4 && (segs[2] == 'issues' || segs[2] == 'pull') && int.tryParse(segs[3]) != null;
    return ok ? '${segs[1]}#${segs[3]}' : null;
  }
  return after('issue') ?? after('browse');
}

/// Vrai si la tâche de clé [key] et d'URL [url] est celle de [ticket] : même clé (sans tenir compte de la casse),
/// sinon même URL.
bool isTicket(TicketRef ticket, {String? key, String? url}) =>
    ticket.key != null ? key?.toUpperCase() == ticket.key!.toUpperCase() : url != null && url == ticket.url;

/// Nom d'une tâche de ticket : « ENG-123 · Titre », la clé seule, ou le titre.
String ticketTaskName(TicketRef ticket, String? title) {
  final t = title?.trim() ?? '';
  if (ticket.key == null) return t.isEmpty ? ticket.url! : t;
  return t.isEmpty ? ticket.key! : '${ticket.key} · $t';
}
