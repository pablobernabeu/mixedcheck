"""The error catalogue and the rendering of messages (docs/spec/errors.md)."""

from __future__ import annotations

import pytest

from mixedcheck import MixedcheckError, MixedcheckWarning
from mixedcheck._errors import display_text, error_catalogue, finish_issues, new_issue, raw_issue


def test_every_code_of_the_catalogue_renders_with_arguments_of_each_kind():
    catalogue = error_catalogue()
    assert len(catalogue) > 100
    samples = {
        "text": "x",
        "integer": 3,
        "number": 0.5,
        "codepoint": 0x1F,
        "values": ["a", 1, True, None],
        "words": ["a", "b"],
    }
    for code, entry in catalogue.items():
        args = {name: samples[kind] for name, kind in entry["args"].items()}
        location = {
            "none": {},
            "offset": {"offset": 0},
            "pointer": {"pointer": "/a"},
            "offset_or_pointer": {"pointer": ""},
        }[entry["location"]]
        issue = new_issue(code, args, **location)
        assert "{" not in issue["message"], code
        assert issue["code"] == code


def test_messages_are_rendered_as_errors_md_describes():
    assert (
        new_issue("E1029", {"key": "go\tal"}, offset=45)["message"]
        == "Duplicate key 'go\\u0009al' at byte 45."
    )
    allowed = ["occasion", "timestamp", "trial_index", "duration_since_start"]
    assert new_issue("E1405", {"allowed": allowed}, pointer="/observation/time/kind")[
        "message"
    ] == (
        "The value at /observation/time/kind must be 'occasion', 'timestamp', 'trial_index' "
        "or 'duration_since_start'."
    )
    assert (
        new_issue("E1101", pointer="")["message"]
        == "A null at (root) is not allowed in the hashable profile."
    )
    assert (
        new_issue("E1024", {"codepoint": 9}, offset=2)["message"]
        == "Unescaped control character U+0009 in a string at byte 2."
    )
    assert new_issue("E1409", {"limit": 1e-307}, pointer="/n")["message"] == (
        "The number at /n is less than 1e-307."
    )
    assert new_issue("E1441", {"version": "0.2.0", "supported": "0.1.x"}, pointer="/v")[
        "message"
    ] == ("Version '0.2.0' at /v is not supported. This release reads version 0.1.x.")
    assert new_issue("E2015", {"value": [False]}, pointer="/a")["message"] == (
        "The value false at /a repeats an earlier value in the list."
    )
    with pytest.raises(RuntimeError, match="wrong location"):
        new_issue("E1029", {"key": "a"})
    with pytest.raises(RuntimeError, match="unknown error code"):
        new_issue("E0000")


def test_issues_have_the_json_form_of_defs_schema():
    assert new_issue("E1001") == {"code": "E1001", "message": "The file does not exist."}
    assert list(new_issue("E1021", offset=3)) == ["code", "message", "offset"]
    assert list(new_issue("E1101", pointer="/a")) == ["code", "message", "pointer"]


def test_text_is_escaped_for_display_and_truncated_to_60_code_points():
    assert display_text("\x00\x7f\x9f\xa0  ") == "\\u0000\\u007F\\u009F\xa0\\u2028\\u2029"
    assert display_text("a" * 60) == "a" * 60
    assert display_text("a" * 61) == "a" * 57 + "..."
    # An escape counts as six code points and can be cut.
    assert display_text("a" * 55 + "\x01bbbb") == "a" * 55 + "\\u..."
    assert display_text("\xe9" * 70) == "\xe9" * 57 + "..."
    assert display_text("/a/b", limit=None) == "/a/b"


def test_errors_join_the_messages_of_several_issues():
    issues = [new_issue("E1001"), new_issue("E1002")]
    error = MixedcheckError(issues)
    assert isinstance(error, ValueError)
    assert str(error) == "The file does not exist.\nThe file cannot be read."
    assert error.issues == issues
    warning = MixedcheckWarning(issues[:1])
    assert isinstance(warning, UserWarning)
    assert str(warning) == "The file does not exist."
    assert warning.issues == issues[:1]


def test_finish_issues_reports_each_issue_once_and_caps_the_list_at_100():
    raw = [raw_issue("E1403", f"/units/{i}", {"key": "x"}) for i in range(105)]
    raw.append(raw_issue("E1403", "/units/3", {"key": "x"}))
    issues = finish_issues(raw)
    assert len(issues) == 101
    assert issues[0]["pointer"] == "/units/0"
    assert issues[2]["pointer"] == "/units/10"
    assert issues[100] == {
        "code": "W1490",
        "message": "5 further problems were found but not listed.",
    }
    assert finish_issues([]) == []
    assert finish_issues([raw_issue("E2030", ""), raw_issue("E2028", "", {"key": "units"})]) == [
        new_issue("E2028", {"key": "units"}, pointer=""),
        new_issue("E2030", pointer=""),
    ]


def test_issues_are_sorted_by_code_point_with_a_prefix_first():
    raw = [
        raw_issue("E1403", "/variables/\xe9", {"key": "x"}),
        raw_issue("E1403", "/variables/b", {"key": "x"}),
        raw_issue("E1403", "/variables/B", {"key": "x"}),
        raw_issue("E1403", "/variables", {"key": "x"}),
    ]
    pointers = [issue["pointer"] for issue in finish_issues(raw)]
    assert pointers == ["/variables", "/variables/B", "/variables/b", "/variables/\xe9"]


def test_errors_and_warnings_can_be_pickled_and_copied():
    import copy
    import pickle

    issues = [new_issue("E1022", {"character": "]"}, offset=3)]
    for cls in (MixedcheckError, MixedcheckWarning):
        err = cls(issues)
        for clone in (pickle.loads(pickle.dumps(err)), copy.copy(err), copy.deepcopy(err)):
            assert type(clone) is cls
            assert clone.issues == err.issues
            assert str(clone) == str(err)


def test_the_catalogue_and_the_assigned_ranges_load_once_across_threads():
    # A fresh interpreter, so that the caches are empty when the threads start.
    import subprocess
    import sys

    script = """
import sys
import threading

import mixedcheck

barrier = threading.Barrier(16)
results = []
data = '{"t": "caf\\u00e9 \\U0001F600 \\u4e2d"}'.encode()


def work():
    barrier.wait()
    try:
        mixedcheck.read_json_strict(b"[1,]")
    except mixedcheck.MixedcheckError as err:
        results.append(err.issues[0]["code"])
    except Exception as err:
        results.append(repr(err))
    try:
        mixedcheck.read_json_strict(data, "hashable")
        results.append("ok")
    except Exception as err:
        results.append(repr(err))


sys.setswitchinterval(1e-6)
threads = [threading.Thread(target=work) for _ in range(16)]
for thread in threads:
    thread.start()
for thread in threads:
    thread.join()
print(sorted(set(results)))
"""
    done = subprocess.run(
        [sys.executable, "-c", script], capture_output=True, text=True, check=True
    )
    assert done.stdout.strip() == "['E1022', 'ok']"
