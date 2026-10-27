"""Tickets des clients (plans/19-tickets-clients.md) : mêmes cas que app/test/tickets_test.dart."""

from __future__ import annotations

import pytest

from app.services.tickets import Ticket, branch_key, parse_ticket, ticket_task_name, ticket_title


@pytest.mark.parametrize(("text", "key"), [
    ("https://acme.atlassian.net/browse/ENG-123", "ENG-123"),
    ("https://jira.acme.fr/browse/abc_1-7?focusedId=3", "ABC_1-7"),
    ("https://acme.atlassian.net/jira/software/projects/ENG/boards/1?selectedIssue=ENG-42", "ENG-42"),
    ("https://linear.app/acme/issue/ENG-123/formulaire-de-commande", "ENG-123"),
    ("https://github.com/acme/site/issues/45", "site#45"),
    ("https://github.com/acme/site/pull/46", "site#46"),
    ("  eng-123 ", "ENG-123"),
])
def test_keys_of_jira_linear_github_and_bare_keys(text, key):
    assert parse_ticket(text).key == key


def test_other_urls_have_no_key():
    t = parse_ticket(" https://trello.com/c/AbCd/12-formulaire ")
    assert t == Ticket(None, "https://trello.com/c/AbCd/12-formulaire") and t.label == t.url
    assert parse_ticket("https://github.com/acme/site").key is None
    assert parse_ticket("ENG-123") == Ticket("ENG-123", None)


@pytest.mark.parametrize("text", ["", "Formulaire de commande", "ftp://acme.fr/ENG-1", "ENG-", "123-ENG",
                                  "https://" + "a" * 500 + ".fr", None, 42])
def test_neither_an_http_url_nor_a_key(text):
    assert parse_ticket(text) is None


def test_task_name_and_title():
    linear = Ticket("ENG-123", "https://linear.app/acme/issue/ENG-123/x")
    assert ticket_task_name(linear, " Formulaire de commande ") == "ENG-123 · Formulaire de commande"
    assert ticket_task_name(linear, "") == ticket_task_name(linear, None) == "ENG-123"
    assert ticket_task_name(Ticket(None, "https://trello.com/c/x"), None) == "https://trello.com/c/x"
    assert ticket_title("  Formulaire   de  commande ") == "Formulaire de commande"
    assert ticket_title("   ") is None and len(ticket_title("x" * 200)) == 80


@pytest.mark.parametrize(("branch", "key"), [
    ("yannick/eng-123-formulaire-de-commande", "ENG-123"),
    ("feature/ENG-42", "ENG-42"),
    ("ENG-7-correctif", "ENG-7"),
    ("plan-10-lot-1", "PLAN-10"),  # crue seulement pour un projet facturé par ticket ou un ticket connu
    ("main", None),
    ("v2", None),
    (None, None),
])
def test_branch_key(branch, key):
    assert branch_key(branch) == key
