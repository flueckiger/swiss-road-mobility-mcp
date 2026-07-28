"""Guards against the version drift that made the User-Agent lie.

`__version__` used to be a hand-maintained literal in `__init__.py`. Nothing
forced it to be bumped alongside `pyproject.toml`, so it silently fell three
patch releases behind (0.5.0 vs 0.5.3) and every outbound request advertised
the wrong version to GBFS operators, the EV charging feeds and DATEX II.

These tests fail if anyone reintroduces a literal.
"""

import tomllib
from pathlib import Path

import swiss_road_mobility_mcp as pkg

PYPROJECT = Path(__file__).resolve().parent.parent / "pyproject.toml"


def _pyproject_version() -> str:
    return tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))["project"]["version"]


def test_version_matches_pyproject():
    """The single source of truth is pyproject.toml, via distribution metadata."""
    assert pkg.__version__ == _pyproject_version()


def test_user_agent_carries_the_real_version():
    assert pkg.USER_AGENT == f"swiss-road-mobility-mcp/{_pyproject_version()}"


def test_user_agent_is_not_a_source_checkout_marker():
    """In CI the package is installed, so the fallback must not be in play.

    If this fails, `importlib.metadata` did not find the distribution — the
    User-Agent would then go out as `0.0.0+source` instead of a real version.
    """
    assert "+source" not in pkg.USER_AGENT
