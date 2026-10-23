import 'package:clockifai/core/guide.dart';
import 'package:clockifai/core/team_rights.dart';
import 'package:flutter_test/flutter_test.dart';

TeamRights _rights(String role, {Set<String> managed = const {}}) =>
    TeamRights(me: 'moi', role: role, timeForOthers: null, members: const [], managed: managed);

void main() {
  test('page du guide selon le rôle', () {
    expect(guidePage(_rights('owner')), 'proprietaire.html');
    expect(guidePage(_rights('admin')), 'proprietaire.html');
    expect(guidePage(_rights('manager', managed: {'karim'})), 'manager.html');
    expect(guidePage(_rights('member', managed: {'camille'})), 'chef-equipe.html');
    expect(guidePage(_rights('member')), 'membre.html');
  });

  test('adresse du guide', () {
    // Apps natives : le service Flask de la prod, dont le Caddy sert aussi /guide/.
    expect(guideUri('membre.html', guideUrl: '', servicesUrl: 'https://clockifai.kysoe.com').toString(),
        'https://clockifai.kysoe.com/guide/membre.html');
    // App web de prod : SERVICES_URL vide, même origine que l'app.
    expect(guideUri('manager.html', guideUrl: '', servicesUrl: '', webOrigin: 'https://clockifai.kysoe.com').toString(),
        'https://clockifai.kysoe.com/guide/manager.html');
    // Développement : GUIDE_URL de config/local.json (make docs-serve), avec ou sans « / » final.
    for (final base in ['http://localhost:3200/guide/', 'http://localhost:3200/guide']) {
      expect(guideUri('membre.html', guideUrl: base, servicesUrl: 'http://localhost:5050').toString(),
          'http://localhost:3200/guide/membre.html');
    }
  });
}
