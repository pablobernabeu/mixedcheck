"""The privacy filter of shareable mode (docs/spec/privacy.md), which step 12
of :func:`audit` applies. The second part of M2b-3 ports it from the R
package. Until then, a shareable run stops at step 12 with an internal error."""

from __future__ import annotations

from typing import Any

from mixedcheck._checks import Finding, Run
from mixedcheck._errors import internal_error


def privacy_filter(
    run: Run, findings: list[Finding], key: str
) -> tuple[list[Finding], list[dict[str, Any]]]:
    """The findings after the privacy filter, with the pseudonyms of the
    sidecar."""
    internal_error(
        "shareable mode arrives with the privacy filter, which the Python package does not "
        "have yet. Run audit() with privacy='internal' for an internal document."
    )
