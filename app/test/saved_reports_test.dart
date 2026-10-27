import 'package:clockifai/features/reports/saved_reports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('destinataires : virgules, points-virgules, espaces ou retours à la ligne', () {
    expect(splitRecipients(' compta@acme.fr, lea@studio.fr;\nzoe@x.fr  '), ['compta@acme.fr', 'lea@studio.fr', 'zoe@x.fr']);
    expect(splitRecipients(' , '), isEmpty);
  });
}
