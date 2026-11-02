import 'package:flutter/widgets.dart';

/// Hors du web, la page de connexion garde ses champs Flutter : le vrai formulaire HTML est dans
/// web_login_form_web.dart.
class WebLoginForm extends StatelessWidget {
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
  Widget build(BuildContext context) => throw UnsupportedError('WebLoginForm : version web seulement');
}
