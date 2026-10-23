import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'l10n.dart';
import 'team_rights.dart';
import 'widgets/common.dart';

/// Page du guide d'utilisation (docs/guide/, noms de fichiers à garder alignés) qui correspond au rôle.
String guidePage(TeamRights rights) {
  if (rights.isAdmin) return 'proprietaire.html';
  if (rights.isManager) return 'manager.html';
  if (rights.isTeamManager) return 'chef-equipe.html';
  return 'membre.html';
}

/// Adresse d'une page du guide : [guideUrl] s'il est fourni, sinon `/guide/` du service Flask
/// ([servicesUrl], ou [webOrigin] quand l'app web et le service partagent l'origine).
Uri guideUri(
  String page, {
  String guideUrl = AppConfig.guideUrl,
  String servicesUrl = AppConfig.servicesUrl,
  String webOrigin = '',
}) {
  var base = guideUrl.isNotEmpty ? guideUrl : '${servicesUrl.isEmpty ? webOrigin : servicesUrl}/guide/';
  if (!base.endsWith('/')) base = '$base/';
  return Uri.parse(base).resolve(page);
}

/// Ouvre la page du guide de l'utilisateur dans le navigateur (nouvel onglet sur le web).
Future<void> openGuide(BuildContext context) async {
  final uri = guideUri(guidePage(TeamRights.read(context)), webOrigin: kIsWeb ? Uri.base.origin : '');
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  } catch (_) {
    // Pas de navigateur disponible : signalé ci-dessous.
  }
  if (!opened && context.mounted) showSnack(context, context.l10n.cannotOpenLink(uri.toString()));
}
