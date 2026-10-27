import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/widgets/common.dart';
import 'presence.dart';

/// Paramètres › Présence chantier (plans/13-ux-moderne.md, lot 13) : réglage personnel, sur ce téléphone.
class PresenceTile extends StatelessWidget {
  const PresenceTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tracker = PresenceTracker.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: tracker.enabled,
      builder: (context, on, _) => ListTile(
        leading: const Icon(Icons.share_location_outlined),
        title: Text(l.presenceTitle),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.presenceHelp),
          if (on)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await tracker.forget();
                  if (context.mounted) showSnack(context, l.presenceForgotten);
                },
                child: Text(l.presenceForget),
              ),
            ),
        ]),
        isThreeLine: true,
        trailing: Switch(
          value: on,
          onChanged: (v) async {
            if (!v) return tracker.disable();
            final r = await tracker.enable();
            if (!context.mounted) return;
            switch (r) {
              case PresenceStart.ok:
                showSnack(context, l.presenceOn);
              case PresenceStart.denied:
                showSnack(context, l.presenceDenied);
              case PresenceStart.serviceOff:
                showSnack(context, l.presenceServiceOff);
              case PresenceStart.unsupported:
                break;
            }
          },
        ),
      ),
    );
  }
}

/// « 48.8566, 2.3522 » (copié d'une carte) → (48.8566, 2.3522) ; null si vide ou hors limites.
(double, double)? parseSite(String text) {
  final m = RegExp(r'^\s*(-?\d+(?:[.,]\d+)?)\s*[;,\s]\s*(-?\d+(?:[.,]\d+)?)\s*$').firstMatch(text);
  if (m == null) return null;
  final lat = double.parse(m.group(1)!.replaceAll(',', '.')), lng = double.parse(m.group(2)!.replaceAll(',', '.'));
  return lat.abs() <= 90 && lng.abs() <= 180 ? (lat, lng) : null;
}

String formatSite(double lat, double lng) => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

/// Fiche projet : position et rayon du chantier (managers). La position se colle depuis une carte, ou se prend sur
/// place avec « Ici » (téléphone, navigateur) ; « Voir sur la carte » l'ouvre dans OpenStreetMap.
class SiteFields extends StatefulWidget {
  const SiteFields({super.key, required this.position, required this.radius});
  final TextEditingController position;
  final TextEditingController radius;

  @override
  State<SiteFields> createState() => _SiteFieldsState();
}

class _SiteFieldsState extends State<SiteFields> {
  bool _locating = false;

  static bool get _canLocate =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;

  Future<void> _here() async {
    final l = context.l10n;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, l.presenceDenied);
        return;
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      widget.position.text = formatSite(p.latitude, p.longitude);
    } catch (_) {
      if (mounted) showSnack(context, l.presenceServiceOff);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = widget.position.text;
    final site = parseSite(text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: widget.position,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(
              labelText: l.sitePosition,
              hintText: '48.856600, 2.352200',
              helperText: l.sitePositionHelp,
              helperMaxLines: 3,
              errorText: text.trim().isNotEmpty && site == null ? l.sitePositionInvalid : null,
              suffixIcon: site == null
                  ? null
                  : IconButton(
                      tooltip: l.siteOnMap,
                      icon: const Icon(Icons.map_outlined),
                      onPressed: () => launchUrl(Uri.parse(
                          'https://www.openstreetmap.org/?mlat=${site.$1}&mlon=${site.$2}#map=17/${site.$1}/${site.$2}')),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: TextField(
            controller: widget.radius,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.siteRadius, suffixText: 'm'),
          ),
        ),
      ]),
      if (_canLocate)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label: Text(l.siteHere),
            onPressed: _locating ? null : _here,
          ),
        ),
    ]);
  }
}
