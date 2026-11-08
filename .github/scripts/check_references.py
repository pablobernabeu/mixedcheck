"""Checks the references in docs/ that carry a DOI against their Crossref
metadata: the title, the year, the journal, the volume, the issue, the pages
and the authors (03-execution-plan.md, M1).

Usage, from the repository root:

    python3 .github/scripts/check_references.py [DIRECTORY]

The script reads every reference in APA style that ends with a DOI in the
Markdown files under DIRECTORY (docs/ by default), and every reference in the
CSV files and JSON documents of the evidence that give a reference in a
column or member 'apa' or 'apa_reference' with its DOI in 'doi_or_url'. It
asks the Crossref REST API for each DOI and reports every field in which the
reference differs from Crossref's record. A DOI that Crossref does not hold,
such as a DataCite DOI of arXiv or Zenodo, is listed without being checked, and
so are the pages of a record that gives none. crossref-exceptions.json lists
the fields of records that are known to be wrong, with the reason for each,
and those fields are not compared.

The evidence in docs/design/evidence/ is frozen, and corrections to it are
recorded in its README, so differences found there are reported without
changing the exit status. The exit status is 0 when every other reference
agrees with Crossref, 1 when one does not or cannot be read as an APA
reference or when the arguments are wrong, and 2 when Crossref cannot be
reached. The environment variable
CROSSREF_MAILTO, when set, is sent to Crossref as the contact address that
its etiquette asks for. The script needs only the standard library.
"""

from __future__ import annotations

import csv
import html
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

API = "https://api.crossref.org/works/"
FROZEN = "docs/design/evidence/"
# Fields in which a Crossref record is known to be wrong, checked against the
# publication itself, with the reason for each.
EXCEPTIONS: dict[str, set[str]] = {}
for _entry in json.loads(
    (Path(__file__).with_name("crossref-exceptions.json")).read_text(encoding="utf-8")
)["exceptions"]:
    EXCEPTIONS.setdefault(_entry["doi"].lower(), set()).add(_entry["field"])
DOI_URL = re.compile(r"https?://(?:dx\.)?doi\.org/(10\.\d{4,9}/\S+)", re.IGNORECASE)
ANY_URL = re.compile(r"https?://\S+")
YEAR = re.compile(r"\((?P<year>\d{4})[a-z]?(?:, [A-Z][a-z]+(?: \d{1,2})?)?\)\.")
FAMILY = r"[^\W\d_](?:[^\W\d_]|['\u2019\- ])*?"
INITIALS = r"[A-Z][a-z]?\.(?:[ -][A-Z][a-z]?\.)*"
AUTHOR = rf"{FAMILY}, {INITIALS}"
AUTHORS = re.compile(
    rf"(?:^|(?<=[.:;] ))(?P<list>{AUTHOR}(?:, {AUTHOR})*(?:,? & {AUTHOR})?"
    rf"(?:, \. \. \. {AUTHOR})?)(?P<editors> \(Eds?\.\))?\.?$"
)
# The pages of a paper in proceedings, which follow the title of the
# proceedings without a volume.
PROCEEDINGS = re.compile(r", (?P<pages>[A-Za-z]?\d+[\u2013-][A-Za-z]?\d+)\.?$")
ONE_AUTHOR = re.compile(rf"(?P<family>{FAMILY}), {INITIALS}")
SOURCE = re.compile(
    r", (?P<volume>\d+)(?:\((?P<issue>[^)]+)\))?"
    r"(?:, (?P<pages>Article [A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*"
    r"|[A-Za-z]?\d+(?:[\u2013-][A-Za-z]?\d+)?))?\.?$"
)


@dataclass
class Reference:
    """A reference with a DOI, as written in a file of docs/."""

    location: str
    text: str
    doi: str
    year: str | None = None
    families: list[str] | None = None
    editors: bool = False
    organisation: str | None = None
    volume: str | None = None
    issue: str | None = None
    pages: str | None = None
    problems: list[str] = field(default_factory=list)

    @property
    def frozen(self) -> bool:
        return self.location.startswith(FROZEN)


# Finding references.


def clean_doi(doi: str) -> str:
    """A DOI without the punctuation that follows it in the text."""
    while doi and (doi[-1] in ".,;:" or (doi[-1] == ")" and doi.count("(") < doi.count(")"))):
        doi = doi[:-1]
    return doi


def plain(text: str) -> str:
    """Text without Markdown emphasis or code marks."""
    return text.replace("*", "").replace("`", "").strip()


def parse(location: str, text: str, doi: str) -> Reference:
    """Read the year, the authors, the volume, the issue and the pages of an
    APA reference that ends before its DOI."""
    reference = Reference(location, text, clean_doi(doi))
    years = list(YEAR.finditer(text))
    if not years:
        reference.problems.append("no year in parentheses followed by a full stop")
        return reference
    year = years[-1]
    reference.year = year.group("year")
    before = text[: year.start()].rstrip()
    if re.search(r"\bet al\b", before):
        reference.problems.append("the authors are shortened with 'et al.'")
        return reference
    authors = AUTHORS.search(before)
    if authors:
        listed = authors.group("list")
        reference.families = [match.group("family") for match in ONE_AUTHOR.finditer(listed)]
        reference.editors = authors.group("editors") is not None
        reference.text = text[authors.start() :]
    else:
        start = max(before.rfind(". ", 0, len(before) - 1), before.rfind(": "))
        reference.organisation = before[start + 2 if start >= 0 else 0 :].rstrip(".")
        reference.text = text[start + 2 if start >= 0 else 0 :]
    tail = text[year.end() :].strip()
    source = SOURCE.search(tail)
    if source:
        reference.volume = source.group("volume")
        reference.issue = source.group("issue")
        reference.pages = source.group("pages")
    elif proceedings := PROCEEDINGS.search(tail):
        reference.pages = proceedings.group("pages")
    return reference


def markdown_references(path: Path, location: str) -> Iterator[Reference]:
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = plain(line)
        start = 0
        for match in ANY_URL.finditer(line):
            segment = line[start : match.start()].strip()
            start = match.end()
            doi = DOI_URL.match(match.group(0))
            if doi:
                yield parse(f"{location}:{number}", segment, doi.group(1))


def table_references(path: Path, location: str) -> Iterator[Reference]:
    with path.open(encoding="utf-8", newline="") as handle:
        for number, row in enumerate(csv.DictReader(handle), start=2):
            yield from row_reference(row, f"{location}:{number}")


def json_references(path: Path, location: str) -> Iterator[Reference]:
    def walk(value: Any, pointer: str) -> Iterator[Reference]:
        if isinstance(value, dict):
            yield from row_reference(value, f"{location}#{pointer}")
            for key, item in value.items():
                yield from walk(item, f"{pointer}/{key}")
        elif isinstance(value, list):
            for index, item in enumerate(value):
                yield from walk(item, f"{pointer}/{index}")

    yield from walk(json.loads(path.read_text(encoding="utf-8")), "")


def row_reference(row: dict[str, Any], location: str) -> Iterator[Reference]:
    text = row.get("apa") or row.get("apa_reference")
    link = row.get("doi_or_url")
    if isinstance(text, str) and isinstance(link, str):
        doi = DOI_URL.match(link.strip())
        if doi:
            text = ANY_URL.sub("", plain(text)).strip()
            yield parse(location, text, doi.group(1))


def find_references(directory: Path, root: Path) -> list[Reference]:
    """Every reference with a DOI in the Markdown, CSV and JSON files of a directory."""
    references = []
    readers: dict[str, Callable[[Path, str], Iterator[Reference]]] = {
        ".md": markdown_references,
        ".csv": table_references,
        ".json": json_references,
    }
    for path in sorted(directory.rglob("*")):
        reader = readers.get(path.suffix.lower())
        if not reader or not path.is_file():
            continue
        # The evidence holds deliberately broken JSON and CSV files, which
        # list no references.
        if reader is not markdown_references and b"doi_or_url" not in path.read_bytes():
            continue
        references.extend(reader(path, path.relative_to(root).as_posix()))
    return references


# Comparing with Crossref.


def folded(text: str) -> str:
    """Text for comparison: without accents, tags or punctuation, in lower case."""
    text = re.sub(r"<[^>]+>", "", html.unescape(text))
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.casefold().replace("&", " and ")
    return " ".join(re.findall(r"[^\W_]+", text))


def dashes(text: str) -> str:
    return re.sub(r"[\u2010-\u2015\u2212]", "-", text)


def years(record: dict[str, Any]) -> list[str]:
    found = []
    for key in ("published-print", "published-online", "issued", "published"):
        parts = (record.get(key) or {}).get("date-parts") or [[None]]
        if parts[0] and parts[0][0] is not None:
            found.append(str(parts[0][0]))
    return sorted(set(found))


def contributors(record: dict[str, Any], editors: bool) -> list[dict[str, Any]]:
    people = record.get("author") or []
    if editors or not people:
        people = record.get("editor") or people
    return people


def compare(reference: Reference, record: dict[str, Any]) -> list[str]:
    """The fields in which a reference differs from a Crossref record."""
    problems = []
    text = folded(reference.text)
    title = " ".join((record.get("title") or [""])[:1])
    if title and folded(title) not in text:
        problems.append(f"title: Crossref gives '{title}'")
    for subtitle in record.get("subtitle") or []:
        if folded(subtitle) not in text:
            problems.append(f"title: the subtitle '{subtitle}' that Crossref gives is missing")
    found_years = years(record)
    if reference.year and found_years and reference.year not in found_years:
        problems.append(
            f"year: the reference gives {reference.year}, Crossref {', '.join(found_years)}"
        )
    journal = record.get("type") == "journal-article"
    containers = (record.get("container-title") or []) + (record.get("short-container-title") or [])
    if journal and containers and not any(folded(name) in text for name in containers):
        problems.append(f"journal: Crossref gives '{containers[0]}'")
    for name, ours in (("volume", reference.volume), ("issue", reference.issue)):
        theirs = record.get(name)
        # Some publishers record an issue 'C' for journals without issues.
        if not ours and not re.search(r"\d", theirs or ""):
            theirs = None
        if (ours or journal) and (ours or "") != (theirs or ""):
            problems.append(
                f"{name}: the reference gives '{ours or ''}', Crossref '{theirs or ''}'"
            )
    # Pages are compared only where Crossref records them. Some publishers
    # record only the first page, which then has to match.
    pages = dashes(reference.pages or "").removeprefix("Article ")
    theirs = dashes(record.get("page") or record.get("article-number") or "")
    if "-" not in theirs and pages.split("-")[0] == theirs:
        theirs = pages
    if theirs and pages != theirs:
        problems.append(
            f"pages: the reference gives '{reference.pages or ''}', Crossref '{theirs}'"
        )
    problems.extend(compare_authors(reference, contributors(record, reference.editors)))
    return problems


def compare_authors(reference: Reference, people: list[dict[str, Any]]) -> list[str]:
    persons = [person.get("family") or person.get("name") or "" for person in people]
    if reference.families is None:
        # Crossref may add a country to an organisation, as in 'National
        # Institute of Standards and Technology (US)'.
        named = [
            re.sub(r"\s*\([^)]*\)$", "", person["name"])
            for person in people
            if "name" in person and "family" not in person
        ]
        if len(named) != len(people) or not all(
            folded(name) in folded(reference.organisation or "") for name in named
        ):
            listed = ", ".join(persons) or "none"
            return [f"authors: the reference names '{reference.organisation}', Crossref {listed}"]
        return []
    ours = [folded(name) for name in reference.families]
    theirs = [folded(name) for name in persons]
    if ". . ." in reference.text.split("(")[0] and len(theirs) > len(ours):
        theirs = theirs[: len(ours) - 1] + theirs[-1:]
    if ours != theirs:
        return [
            f"authors: the reference gives {', '.join(reference.families)}, "
            f"Crossref {', '.join(persons) or 'none'}"
        ]
    return []


class Unreachable(Exception):
    """Crossref cannot be reached."""


def fetch(doi: str) -> dict[str, Any] | None:
    """The Crossref record of a DOI, or None when Crossref does not hold it."""
    agent = "mixedcheck-reference-check (https://github.com/pablobernabeu/lmecheck)"
    mailto = os.environ.get("CROSSREF_MAILTO")
    if mailto:
        agent += f"; mailto:{mailto}"
    url = API + urllib.parse.quote(doi, safe="/()")
    request = urllib.request.Request(url, headers={"User-Agent": agent})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)["message"]
        except urllib.error.HTTPError as err:
            if err.code == 404:
                return None
            if err.code not in (429, 500, 502, 503, 504) or attempt == 3:
                raise Unreachable(f"Crossref answered {err.code} for {doi}.") from err
        except (urllib.error.URLError, TimeoutError) as err:
            if attempt == 3:
                raise Unreachable(f"Crossref cannot be reached: {err}.") from err
        time.sleep(2 ** (attempt + 1))
    return None


def check(
    references: list[Reference], lookup: Callable[[str], dict[str, Any] | None]
) -> dict[str, list[Reference]]:
    """Sort references into those that agree with Crossref, those that differ,
    those that cannot be read and those whose DOI Crossref does not hold."""
    records: dict[str, dict[str, Any] | None] = {}
    sorted_references: dict[str, list[Reference]] = {
        "differ": [],
        "unread": [],
        "absent": [],
        "agree": [],
    }
    for reference in references:
        if reference.problems:
            sorted_references["unread"].append(reference)
            continue
        key = reference.doi.lower()
        if key not in records:
            records[key] = lookup(reference.doi)
            time.sleep(0.2 if lookup is fetch else 0)
        record = records[key]
        if record is None:
            sorted_references["absent"].append(reference)
            continue
        excepted = EXCEPTIONS.get(key, set())
        reference.problems = [
            problem
            for problem in compare(reference, record)
            if problem.split(":")[0] not in excepted
        ]
        sorted_references["differ" if reference.problems else "agree"].append(reference)
    return sorted_references


def report(results: dict[str, list[Reference]]) -> int:
    """Print the results and return the exit status."""
    headings = {
        "differ": "References that differ from Crossref",
        "unread": "References that cannot be read as APA references",
        "absent": "DOIs that Crossref does not hold, not checked",
    }
    lines = []
    for kind, heading in headings.items():
        for frozen in (False, True):
            group = [reference for reference in results[kind] if reference.frozen == frozen]
            if not group:
                continue
            lines.append(f"\n## {heading}{' (frozen evidence)' if frozen else ''}\n")
            for reference in group:
                lines.append(f"- {reference.location}: https://doi.org/{reference.doi}")
                lines += [f"  - {problem}" for problem in reference.problems]
    total = sum(len(group) for group in results.values())
    failing = [
        reference
        for kind in ("differ", "unread")
        for reference in results[kind]
        if not reference.frozen
    ]
    lines.append(
        f"\n{total} references checked: {len(results['agree'])} agree with Crossref, "
        f"{len(results['differ'])} differ, {len(results['unread'])} cannot be read and "
        f"{len(results['absent'])} have a DOI that Crossref does not hold. "
        f"{len(failing)} outside the frozen evidence need attention."
    )
    text = "\n".join(lines)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("# Reference check\n" + text + "\n")
    return 1 if failing else 0


def main(argv: list[str]) -> int:
    if len(argv) > 2 or (len(argv) == 2 and argv[1].startswith("-")):
        print(__doc__, file=sys.stderr)
        return 1
    root = Path.cwd()
    directory = Path(argv[1]) if len(argv) > 1 else root / "docs"
    if not directory.is_dir():
        print(f"{directory} is not a directory.", file=sys.stderr)
        return 1
    references = find_references(directory.resolve(), root.resolve())
    try:
        results = check(references, fetch)
    except Unreachable as err:
        print(err, file=sys.stderr)
        return 2
    return report(results)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
