"""Alertes de budget (plans/18-rapports-presence-alertes-partage.md, lot 2) : texte des emails."""

from __future__ import annotations

from app.services.budget_alerts import Alert, compose, describe


def _alert(metric: str, used: int, budget: int, name: str = "Chantier", project: str | None = None) -> Alert:
    return Alert(workspace_id="w", target_id="t", metric=metric, name=name, project_name=project, used=used,
                 budget=budget, threshold=100)


def test_describe_in_french_and_english():
    hours = _alert("hours", 204 * 3600, 200 * 3600)
    assert describe(hours, "EUR", "fr") == "102 % du budget en heures (204 h sur 200 h)"
    assert describe(hours, "EUR", "en") == "102% of the hours budget (204 h of 200 h)"
    amount = _alert("amount", 1_245_000, 1_200_000)
    assert describe(amount, "EUR", "fr") == "103 % du budget en montant (12 450 € sur 12 000 €)"
    assert describe(amount, "USD", "en") == "103% of the amount budget ($12,450 of $12,000)"
    estimate = _alert("estimate", int(3.5 * 3600), 4 * 3600, name="Montage", project="Chantier")
    assert describe(estimate, "EUR", "fr") == "87 % de l'estimation (3,5 h sur 4 h)"


def test_one_alert_in_the_subject_several_in_a_list():
    one = compose([_alert("hours", 9 * 3600, 10 * 3600)], "Échafaudages du Nord", "EUR", "fr", "https://c.example.fr/")
    assert one[0] == "Clockifai · Chantier : 90 % du budget en heures (9 h sur 10 h)"
    assert "Dans « Échafaudages du Nord » :" in one[1] and one[1].endswith("https://c.example.fr/projects\n")
    many = compose([_alert("hours", 9 * 3600, 10 * 3600),
                    _alert("estimate", 5 * 3600, 4 * 3600, name="Montage", project="Chantier")],
                   "Studio", "EUR", "en", "https://c.example.fr")
    assert many[0] == "Clockifai · 2 budget alerts"
    lines = [line for line in many[1].splitlines() if line.startswith("- ")]
    assert lines == ["- Chantier › Montage: 125% of the estimate (5 h of 4 h)",
                     "- Chantier: 90% of the hours budget (9 h of 10 h)"], "les plus avancés d'abord"
