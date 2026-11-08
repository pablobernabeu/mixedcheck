"""Tests of check_references.py without network access: the reading of APA
references and the comparison with Crossref records written by hand.

Run from the repository root:

    python3 -m unittest discover -s .github/scripts -v
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_references as cr  # noqa: E402

ALBERT = (
    "Albert, A., & Anderson, J. A. (1984). On the existence of maximum likelihood estimates "
    "in logistic regression models. *Biometrika, 71*(1), 1\u201310. "
    "https://doi.org/10.1093/biomet/71.1.1"
)
ALBERT_RECORD = {
    "type": "journal-article",
    "title": ["On the existence of maximum likelihood estimates in logistic regression models"],
    "container-title": ["Biometrika"],
    "volume": "71",
    "issue": "1",
    "page": "1-10",
    "author": [{"given": "A.", "family": "ALBERT"}, {"given": "J. A.", "family": "ANDERSON"}],
    "issued": {"date-parts": [[1984]]},
}
PROVENANCE = (
    "- Sources: Wilkinson, G. N., & Rogers, C. E. (1973). Symbolic description of factorial "
    "models for analysis of variance. Journal of the Royal Statistical Society: Series C "
    "(Applied Statistics), 22(3), 392\u2013399. https://doi.org/10.2307/2346786. Bates, D., "
    "M\u00e4chler, M., Bolker, B., & Walker, S. (2015). Fitting linear mixed-effects models "
    "using lme4. Journal of Statistical Software, 67(1), 1\u201348. "
    "https://doi.org/10.18637/jss.v067.i01, for the bar notation. The R 4.3.3 documentation "
    "of formula, terms.object and model.matrix. Shewchuk, J. R. (1997). Adaptive precision "
    "floating-point arithmetic. Discrete & Computational Geometry, 18(3), 305\u2013363. "
    "https://doi.org/10.1007/PL00009321, and the Python documentation."
)


def references_in(text: str, name: str = "docs/spec/example.md") -> list[cr.Reference]:
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        path = root / name
        path.parent.mkdir(parents=True)
        path.write_text(text, encoding="utf-8")
        return cr.find_references(root / "docs", root)


class ReadingTests(unittest.TestCase):
    def test_a_markdown_reference_with_emphasis(self):
        (reference,) = references_in(ALBERT + "\n")
        self.assertEqual(reference.location, "docs/spec/example.md:1")
        self.assertEqual(reference.doi, "10.1093/biomet/71.1.1")
        self.assertEqual(reference.year, "1984")
        self.assertEqual(reference.families, ["Albert", "Anderson"])
        self.assertEqual(
            (reference.volume, reference.issue, reference.pages), ("71", "1", "1\u201310")
        )
        self.assertEqual(reference.problems, [])

    def test_several_references_in_one_line(self):
        references = references_in(PROVENANCE)
        self.assertEqual(
            [reference.doi for reference in references],
            ["10.2307/2346786", "10.18637/jss.v067.i01", "10.1007/PL00009321"],
        )
        self.assertEqual(
            [reference.families for reference in references],
            [["Wilkinson", "Rogers"], ["Bates", "M\u00e4chler", "Bolker", "Walker"], ["Shewchuk"]],
        )
        self.assertTrue(references[2].text.startswith("Shewchuk, J. R. (1997)."))

    def test_editors_particles_and_hyphens(self):
        text = (
            "Bryan, P., Zyp, K., & Nottingham, M. (Eds.). (2013). JavaScript Object Notation "
            "(JSON) Pointer (RFC 6901). Internet Engineering Task Force. "
            "https://doi.org/10.17487/RFC6901\n\n"
            "Terwee, C. B., de Boer, M. R., van der Windt, D. A. W. M., & Mayo-Wilson, E. (2007). "
            "A title. *Journal, 60*(1), 34\u201342. https://doi.org/10.1016/j.jclinepi.2006.03.012\n\n"
            "Boulesteix, A.-L., & White, J.-S. S. (2013). A plea. *PLoS ONE, 8*(4), Article "
            "e61562. https://doi.org/10.1371/journal.pone.0061562\n"
        )
        rfc, terwee, plea = references_in(text)
        self.assertTrue(rfc.editors)
        self.assertEqual(rfc.families, ["Bryan", "Zyp", "Nottingham"])
        self.assertIsNone(rfc.volume)
        self.assertEqual(terwee.families, ["Terwee", "de Boer", "van der Windt", "Mayo-Wilson"])
        self.assertEqual(plea.families, ["Boulesteix", "White"])
        self.assertEqual(plea.pages, "Article e61562")

    def test_an_organisation_as_author(self):
        (reference,) = references_in(
            "National Institute of Standards and Technology. (2015). Secure hash standard (SHS) "
            "(FIPS PUB 180-4). https://doi.org/10.6028/NIST.FIPS.180-4\n"
        )
        self.assertIsNone(reference.families)
        self.assertEqual(reference.organisation, "National Institute of Standards and Technology")

    def test_prose_and_et_al_cannot_be_read(self):
        prose, short = references_in(
            "Halekoh and H\u00f8jsgaard (2014), in the Journal of Statistical Software, 59(9), "
            "https://doi.org/10.18637/jss.v059.i09, runs to pages 1\u201332.\n"
            "Smith, S., et al. (2025). A statement. BMJ, 389, e081123. "
            "https://doi.org/10.1136/bmj-2024-081123\n"
        )
        self.assertEqual(prose.problems, ["no year in parentheses followed by a full stop"])
        self.assertEqual(short.problems, ["the authors are shortened with 'et al.'"])

    def test_tables_and_json_of_the_evidence(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            evidence = root / "docs" / "design" / "evidence"
            evidence.mkdir(parents=True)
            (evidence / "references.csv").write_text(
                "apa,doi_or_url,status\n"
                f'"{ALBERT.replace("*", "")}",https://doi.org/10.1093/biomet/71.1.1,verified\n',
                encoding="utf-8",
            )
            (evidence / "reports.json").write_text(
                json.dumps(
                    {
                        "r": {
                            "references": [
                                {
                                    "apa": ALBERT.split(" https://")[0],
                                    "doi_or_url": "https://doi.org/10.1093/biomet/71.1.1",
                                }
                            ]
                        }
                    }
                ),
                encoding="utf-8",
            )
            (evidence / "broken.json").write_bytes(b"\xef\xbb\xbf{}")
            table, document = cr.find_references(root / "docs", root)
        self.assertEqual(table.location, "docs/design/evidence/references.csv:2")
        self.assertEqual(document.location, "docs/design/evidence/reports.json#/r/references/0")
        for reference in (table, document):
            self.assertTrue(reference.frozen)
            self.assertNotIn("https://", reference.text)
            self.assertEqual(cr.compare(reference, ALBERT_RECORD), [])


class ComparisonTests(unittest.TestCase):
    def reference(self) -> cr.Reference:
        (reference,) = references_in(ALBERT + "\n")
        return reference

    def test_a_reference_that_agrees(self):
        self.assertEqual(cr.compare(self.reference(), ALBERT_RECORD), [])

    def test_every_field_that_differs(self):
        record = dict(
            ALBERT_RECORD,
            title=["On the existence of estimates"],
            subtitle=["A second look"],
            **{"container-title": ["Biometrics"], "published-print": {"date-parts": [[1985]]}},
            issued={"date-parts": [[1985]]},
            volume="72",
            issue="2",
            page="1-11",
            author=[{"family": "Albert"}, {"family": "Andersen"}],
        )
        problems = cr.compare(self.reference(), record)
        self.assertEqual(
            [problem.split(":")[0] for problem in problems],
            ["title", "title", "year", "journal", "volume", "issue", "pages", "authors"],
        )
        self.assertIn("the subtitle 'A second look'", problems[1])
        self.assertEqual(problems[2], "year: the reference gives 1984, Crossref 1985")

    def test_a_missing_volume_and_a_pseudo_issue(self):
        (reference,) = references_in(
            "Matuschek, H., & Bates, D. (2017). Balancing Type I error. *Journal of Memory "
            "and Language, 94*, 305\u2013315. https://doi.org/10.1016/j.jml.2017.01.001\n"
        )
        record = {
            "type": "journal-article",
            "title": ["Balancing Type I error"],
            "container-title": ["Journal of Memory and Language"],
            "volume": "94",
            "issue": "C",
            "page": "305-315",
            "author": [{"family": "Matuschek"}, {"family": "Bates"}],
            "issued": {"date-parts": [[2017, 6]]},
        }
        self.assertEqual(cr.compare(reference, record), [])
        (online,) = references_in(
            "Siepe, B. S., & Pawel, S. (2024). Simulation studies. *Psychological Methods*. "
            "Advance online publication. https://doi.org/10.1037/met0000695\n"
        )
        record = {
            "type": "journal-article",
            "title": ["Simulation studies"],
            "container-title": ["Psychological Methods"],
            "volume": "29",
            "issue": "6",
            "page": "1-20",
            "author": [{"family": "Siepe"}, {"family": "Pawel"}],
            "published-online": {"date-parts": [[2024, 7]]},
            "published-print": {"date-parts": [[2025]]},
        }
        self.assertEqual(
            [problem.split(":")[0] for problem in cr.compare(online, record)],
            ["volume", "issue", "pages"],
        )

    def test_books_editors_and_organisations(self):
        book, rfc, nist = references_in(
            "James, G., & Witten, D. (2013). *An introduction to statistical learning: With "
            "applications in R*. Springer. https://doi.org/10.1007/978-1-4614-7138-7\n"
            "Bray, T. (Ed.). (2017). The JavaScript Object Notation (JSON) data interchange "
            "format (RFC 8259). Internet Engineering Task Force. "
            "https://doi.org/10.17487/RFC8259\n"
            "National Institute of Standards and Technology. (2015). Secure hash standard "
            "(SHS) (FIPS PUB 180-4). https://doi.org/10.6028/NIST.FIPS.180-4\n"
        )
        self.assertEqual(
            cr.compare(
                book,
                {
                    "type": "book",
                    "title": ["An Introduction to Statistical Learning"],
                    "subtitle": ["with Applications in R"],
                    "author": [{"family": "James"}, {"family": "Witten"}],
                    "issued": {"date-parts": [[2013]]},
                },
            ),
            [],
        )
        self.assertEqual(
            cr.compare(
                rfc,
                {
                    "type": "report",
                    "title": ["The JavaScript Object Notation (JSON) Data Interchange Format"],
                    "author": [{"given": "T.", "family": "Bray"}],
                    "published": {"date-parts": [[2017, 12]]},
                },
            ),
            [],
        )
        record = {"type": "report", "title": ["Secure Hash Standard (SHS)"]}
        self.assertEqual(cr.compare(nist, record), [])
        record["author"] = [{"name": "National Institute of Standards and Technology (US)"}]
        self.assertEqual(cr.compare(nist, record), [])
        record["author"] = [{"family": "Dang"}]
        self.assertEqual(
            cr.compare(nist, record),
            [
                "authors: the reference names 'National Institute of Standards and "
                "Technology', Crossref Dang"
            ],
        )

    def test_pages_that_crossref_records_only_in_part(self):
        first_page = dict(ALBERT_RECORD, page="1")
        self.assertEqual(cr.compare(self.reference(), first_page), [])
        no_pages = {key: value for key, value in ALBERT_RECORD.items() if key != "page"}
        self.assertEqual(cr.compare(self.reference(), no_pages), [])
        other_page = dict(ALBERT_RECORD, page="2")
        self.assertEqual(
            cr.compare(self.reference(), other_page),
            ["pages: the reference gives '1\u201310', Crossref '2'"],
        )


class CheckTests(unittest.TestCase):
    def test_known_errors_of_crossref_are_not_compared(self):
        (rfc,) = references_in(
            "Bryan, P., Zyp, K., & Nottingham, M. (Eds.). (2013). JavaScript Object Notation "
            "(JSON) Pointer (RFC 6901). Internet Engineering Task Force. "
            "https://doi.org/10.17487/RFC6901\n"
        )
        record = {
            "type": "report",
            "title": ["JavaScript Object Notation (JSON) Pointer"],
            "editor": [{"family": "Bryan"}, {"family": "Nottingham"}],
            "published": {"date-parts": [[2013, 4]]},
        }
        self.assertEqual([p.split(":")[0] for p in cr.compare(rfc, record)], ["authors"])
        results = cr.check([rfc], lambda doi: record)
        self.assertEqual(results["agree"], [rfc])
        record["published"] = {"date-parts": [[2014]]}
        self.assertEqual(cr.check([rfc], lambda doi: record)["differ"], [rfc])

    def test_the_exit_status_ignores_the_frozen_evidence(self):
        wrong = dict(ALBERT_RECORD, volume="99")
        (current,) = references_in(ALBERT + "\n")
        (frozen,) = references_in(ALBERT + "\n", "docs/design/evidence/notes.md")
        (absent,) = references_in(
            "Bates, D., & Kliegl, R. (2015). *Parsimonious mixed models* (arXiv:1506.04967). "
            "arXiv. https://doi.org/10.48550/arXiv.1506.04967\n"
        )
        lookups = []

        def lookup(doi: str) -> dict | None:
            lookups.append(doi)
            return None if doi.startswith("10.48550/") else wrong

        output = io.StringIO()
        with redirect_stdout(output):
            results = cr.check([current, frozen, absent], lookup)
            status = cr.report(results)
        self.assertEqual(lookups, ["10.1093/biomet/71.1.1", "10.48550/arXiv.1506.04967"])
        self.assertEqual(status, 1)
        self.assertEqual(len(results["differ"]), 2)
        self.assertEqual(results["absent"], [absent])
        self.assertIn("(frozen evidence)", output.getvalue())
        with redirect_stdout(io.StringIO()):
            self.assertEqual(cr.report(cr.check([frozen, absent], lookup)), 0)

    def test_dois_lose_the_punctuation_after_them(self):
        self.assertEqual(cr.clean_doi("10.1002/sim.8086."), "10.1002/sim.8086")
        self.assertEqual(cr.clean_doi("10.1016/S0003(05)80093-3),"), "10.1016/S0003(05)80093-3")

    def test_wrong_arguments_stop_before_any_lookup(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = str(Path(tmp) / "missing")
            for argv in (["x", missing], ["x", "--help"], ["x", tmp, tmp]):
                with redirect_stderr(io.StringIO()) as err:
                    self.assertEqual(cr.main(argv), 1)
                self.assertTrue(err.getvalue())


if __name__ == "__main__":
    unittest.main()
