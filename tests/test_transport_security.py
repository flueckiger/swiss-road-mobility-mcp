"""Eingehende Host/Origin-Prüfung des SSE-Transports (SEC-005, eingehend).

Auslöser war kein fehlender Schutz, sondern ein zu strenger an der falschen
Adresse. mcp 2.x aktiviert automatisch eine Allow-List auf ``127.0.0.1:*``, wenn
das ``host``-Argument der App loopback-artig aussieht — und ``sse_app()``
defaultet genau darauf. Der gehärtete SSE-Pfad gab ``host`` nicht weiter, also
bekam jede Anfrage unter einem echten Hostnamen HTTP 421, auf genau dem
``MCP_HOST=0.0.0.0``-Deployment, das Dockerfile und render.yaml aufsetzen.

Dieser Server hat **zwei** SSE-Pfade, und nur einer war betroffen:

  * der gehärtete (CORS → RateLimit → BearerAuth → App) — der ausgelieferte,
  * der Fallback ``mcp.run(transport="sse", host=…)`` — dort sieht das SDK den
    echten Bind und liess den Schutz korrekt aus.

Der Fallback greift bei ``except Exception``. Das macht ihn zur zweiten Gefahr:
ein Fehler im gehärteten Aufbau verwirft still Auth, Rate-Limit *und*
Allow-List. Ein Test hält deshalb fest, dass der gehärtete Pfad wirklich
genommen wird.
"""

from __future__ import annotations

import pytest
from starlette.testclient import TestClient

from swiss_road_mobility_mcp.server import _run_sse, build_transport_security


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    """Saubere Umgebung — und ein Netz gegen den Fallback.

    ``_run_sse`` fängt ``Exception`` breit ab und ruft dann
    ``mcp.run(transport="sse", …)``, was einen echten Server startet. Ohne diese
    Absicherung würde ein Fehler im gehärteten Pfad die Suite *hängen* statt sie
    scheitern zu lassen — nachgemessen beim Mutationstest. Der Patch macht den
    Fallback beobachtbar und harmlos.
    """
    import swiss_road_mobility_mcp.server as srv

    for var in ("MCP_ALLOWED_HOSTS", "ALLOWED_ORIGINS", "MCP_AUTH_TOKEN"):
        monkeypatch.delenv(var, raising=False)
    monkeypatch.setattr(type(srv.mcp), "run", lambda self, **kw: _FELL_BACK.append(kw))
    _FELL_BACK.clear()
    yield


_FELL_BACK: list[dict] = []


def test_loopback_bind_is_protected():
    sec = build_transport_security("127.0.0.1", 8000)
    assert sec is not None
    assert sec.enable_dns_rebinding_protection is True
    assert "127.0.0.1:8000" in sec.allowed_hosts


def test_wildcard_bind_without_allowlist_stays_off():
    """Der eigentliche Fix.

    Auf 0.0.0.0 ist der erreichbare Name hier unbekannt, und der
    SDK-Loopback-Default ist genau eine Vermutung — er reproduziert das 421.
    """
    assert build_transport_security("0.0.0.0", 8000) is None


def test_wildcard_bind_with_allowlist_is_protected(monkeypatch):
    monkeypatch.setenv("MCP_ALLOWED_HOSTS", "verkehr.example.ch")
    sec = build_transport_security("0.0.0.0", 8000)
    assert sec is not None
    assert "verkehr.example.ch" in sec.allowed_hosts
    # Loopback bleibt drin, sonst brechen Container-Health-Checks.
    assert "127.0.0.1:8000" in sec.allowed_hosts


def test_a_wildcard_origin_is_not_copied(monkeypatch):
    """``*`` gehört nicht in die Transportliste: Origins werden dort literal
    verglichen, ein Eintrag namens ``*`` erlaubte also nichts und machte die
    Liste bloss unlesbar.

    Die Wildcard muss dafür **gesetzt** sein. Der Vorgänger dieses Tests hiess
    ``test_wildcard_cors_default_is_not_copied`` und berief sich auf einen
    Wildcard-Default, den es seit der Umstellung auf fail-closed nicht mehr
    gibt — die autouse-Fixture oben löscht ``ALLOWED_ORIGINS``, die Liste war
    also leer und ``"*" not in []`` trivial wahr. Eine Zusicherung, die auch
    dann hält, wenn man den Filter entfernt, prüft nichts.
    """
    monkeypatch.setenv("ALLOWED_ORIGINS", "https://claude.ai,*")
    sec = build_transport_security("127.0.0.1", 8000)
    assert "*" not in sec.allowed_origins
    # Gegenkontrolle: die echte Origin daneben kommt sehr wohl durch — sonst
    # wäre der Test auch gegen einen Filter grün, der alles wegwirft.
    assert "https://claude.ai" in sec.allowed_origins


def test_explicit_cors_origins_pass_the_transport_check(monkeypatch):
    monkeypatch.setenv("ALLOWED_ORIGINS", "https://claude.ai")
    sec = build_transport_security("127.0.0.1", 8000)
    assert "https://claude.ai" in sec.allowed_origins


@pytest.mark.parametrize("host", ["127.0.0.1", "localhost", "::1"])
def test_all_loopback_forms_count_as_local(host):
    assert build_transport_security(host, 8000) is not None


def _served_app(monkeypatch, host: str, port: int = 8000):
    """Baut die App über den echten `_run_sse`, ohne uvicorn zu starten."""
    import uvicorn

    captured: dict = {}
    monkeypatch.setattr(uvicorn, "run", lambda app, **kw: captured.update(app=app, **kw))
    _run_sse(host, port)
    return captured


def test_the_hardened_path_is_taken_not_the_fallback(monkeypatch):
    """Der Fallback fängt `Exception` breit ab.

    Ein Fehler im gehärteten Aufbau würde damit still auf `mcp.run()`
    umschalten — ohne Auth, ohne Rate-Limit, ohne Allow-List, und ohne dass ein
    Test es merkt. Dieser hält fest, dass der gehärtete Pfad wirklich läuft.
    """
    captured = _served_app(monkeypatch, "127.0.0.1")
    assert not _FELL_BACK, "fiel auf plain SSE zurück — Middleware-Stack wäre weg"
    assert "app" in captured


def test_the_bind_reaches_uvicorn_too(monkeypatch):
    """App und Listener müssen dieselbe Adresse sehen, sonst schützt die
    Allow-List eine andere als die gebundene."""
    captured = _served_app(monkeypatch, "0.0.0.0", 9100)
    assert captured["host"] == "0.0.0.0"
    assert captured["port"] == 9100


def _get_sse(app, host_header: str) -> int:
    """Status eines GET auf den SSE-Endpunkt.

    Nur für **abgewiesene** Hosts benutzbar: die Host-Prüfung entscheidet vor
    dem ersten Byte und liefert dann sofort 421. Ein *erlaubter* Host öffnet
    dagegen einen Event-Stream, der nie endet — der TestClient wartet beim
    Verlassen auf den ASGI-Task, auch mit ``client.stream``. Der Positivfall
    wird deshalb an der Verdrahtung geprüft
    (``test_a_public_bind_gets_no_loopback_allowlist``), nicht end-to-end.

    ``raise_server_exceptions=False`` ist nötig: der SSE-Transport meldet die
    abgelehnte Anfrage als ``ValueError: Request validation failed``, und der
    TestClient würde die per Default nach oben durchreichen statt die
    421-Antwort zu liefern. Ein echter Client sieht den Status, nicht die
    Ausnahme — also wird der Status geprüft.
    """
    with TestClient(app, raise_server_exceptions=False) as client:
        return client.get("/sse", headers={"Host": host_header}).status_code


def test_a_public_bind_gets_no_loopback_allowlist(monkeypatch):
    """Die Regression selbst, an der Stelle, an der sie entsteht.

    Der Positivfall lässt sich nicht end-to-end prüfen (ein erlaubter Host
    öffnet einen endlosen Stream), aber die Ursache schon: ohne den
    ``host``-Kwarg sähe ``sse_app()`` den Default ``127.0.0.1`` und schaltete
    eine Loopback-Allow-List scharf — das ist das 421. Also wird genau
    festgehalten, dass der echte Bind ankommt und ``transport_security`` bewusst
    ``None`` ist, damit das SDK auf einem 0.0.0.0-Bind gar nichts erzwingt.
    """
    import swiss_road_mobility_mcp.server as srv

    captured: dict = {}
    real = type(srv.mcp).sse_app

    def _spy(self, **kwargs):
        captured.update(kwargs)
        return real(self, **kwargs)

    monkeypatch.setattr(type(srv.mcp), "sse_app", _spy)
    _served_app(monkeypatch, "0.0.0.0")
    assert captured["host"] == "0.0.0.0"
    assert captured["transport_security"] is None


def test_foreign_host_is_rejected(monkeypatch):
    monkeypatch.setenv("MCP_ALLOWED_HOSTS", "verkehr.example.ch")
    app = _served_app(monkeypatch, "0.0.0.0")["app"]
    assert _get_sse(app, "evil.example.com") == 421


def test_right_host_wrong_port_is_rejected(monkeypatch):
    """Der tragende Fall.

    ``evil.example.com`` allein beweist wenig: ein zurückfallender
    Loopback-Default würde ihn ebenfalls abweisen. Nur „richtiger Hostname,
    falscher Port" unterscheidet eine portgenaue Allow-List von einer, die alles
    durchlässt.
    """
    monkeypatch.setenv("MCP_ALLOWED_HOSTS", "verkehr.example.ch:8000")
    app = _served_app(monkeypatch, "0.0.0.0")["app"]
    assert _get_sse(app, "verkehr.example.ch:9999") == 421
