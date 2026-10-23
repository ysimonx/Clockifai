"""docs/api/openapi.yaml décrit exactement les routes Flask : toute route ajoutée ou retirée doit l'être aussi dans la doc."""

import re
from pathlib import Path

import yaml

from app import create_app
from app.config import TestConfig

SPEC = Path(__file__).resolve().parents[2] / "docs" / "api" / "openapi.yaml"
_METHODS = {"get", "post", "put", "patch", "delete"}


def _flask_operations() -> set[tuple[str, str]]:
    app = create_app(TestConfig)
    ops = set()
    for rule in app.url_map.iter_rules():
        if rule.endpoint == "static":
            continue
        path = re.sub(r"<(?:[^:>]+:)?([^>]+)>", r"{\1}", rule.rule)
        for method in rule.methods - {"HEAD", "OPTIONS"}:
            ops.add((method.lower(), path))
    return ops


def _spec() -> dict:
    return yaml.safe_load(SPEC.read_text(encoding="utf-8"))


def _spec_operations(spec: dict) -> set[tuple[str, str]]:
    return {(method, path) for path, item in spec["paths"].items() for method in item if method in _METHODS}


def test_openapi_matches_flask_routes():
    flask_ops, spec_ops = _flask_operations(), _spec_operations(_spec())
    missing = sorted(flask_ops - spec_ops)
    extra = sorted(spec_ops - flask_ops)
    lines = [f"{SPEC.relative_to(SPEC.parents[2])} n'est plus aligné sur les routes Flask."]
    lines += [f"  à documenter : {m.upper()} {p}" for m, p in missing]
    lines += [f"  à retirer (route absente) : {m.upper()} {p}" for m, p in extra]
    assert not missing and not extra, "\n".join(lines)


def test_openapi_operations_are_complete():
    spec = _spec()
    assert str(spec["openapi"]).startswith("3.1")
    for path, item in spec["paths"].items():
        for method, op in item.items():
            if method not in _METHODS:
                continue
            assert op.get("summary"), f"{method.upper()} {path} : summary manquant"
            assert op.get("responses"), f"{method.upper()} {path} : responses manquant"
            declared = {p["name"] for p in op.get("parameters", []) if "$ref" not in p and p["in"] == "path"}
            assert declared == set(re.findall(r"{([^}]+)}", path)), f"{method.upper()} {path} : paramètres de chemin"
