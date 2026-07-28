"""Swiss Road & Mobility MCP Server.

Shared mobility, EV charging, traffic alerts, Park & Rail, multimodal trip
planning and geo.admin.ch geocoding for Swiss road infrastructure.
"""

from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as _distribution_version

try:
    # Read the version from the installed distribution metadata, which is built
    # from pyproject.toml. Hand-maintaining the literal here caused a silent
    # drift: it sat at 0.5.0 while the package had moved on to 0.5.3, so every
    # outbound request advertised a version three patch releases old. A value
    # nobody has to remember to bump cannot go stale.
    __version__ = _distribution_version("swiss-road-mobility-mcp")
except PackageNotFoundError:
    # Running from the source tree without an install (e.g. a bare checkout).
    # Deliberately not a plausible-looking number: an obviously non-release
    # marker is better than a wrong version in the User-Agent.
    __version__ = "0.0.0+source"

# Single source of truth for the outbound User-Agent (used by every HTTP client).
USER_AGENT = f"swiss-road-mobility-mcp/{__version__}"
