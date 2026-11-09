"""The strict table reader (docs/spec/tables.md).

It works in four stages, input, text, records and keys, and reports exactly
one issue, the first that the stages find. The records are found with one
regular expression per record over the decoded text, whose quantifiers are
possessive, so that a quoted field ends at the first quotation mark that is not
doubled, as RFC 4180 and tables.md (CSV text) read it. The values are then
checked column by column, each distinct raw value once, and the first problem
is the one in the earliest record and, within it, the leftmost column.
Offsets are counted in characters while the text is scanned and converted to
byte offsets only for the issue reported.
"""

from __future__ import annotations

import math
import os
import re
from collections.abc import Callable, Mapping, Sequence
from typing import TYPE_CHECKING, Any, NoReturn

from mixedcheck._declaration import list_item_value, validate_declaration
from mixedcheck._errors import raise_issue
from mixedcheck._json_read import read_input_bytes
from mixedcheck._numbers import MAX_INTEGER
from mixedcheck._schema import calendar_day_exists, is_column_name
from mixedcheck._unicode import comparison_form, utf8_invalid_offset

if TYPE_CHECKING:
    import pandas

_BOM = b"\xef\xbb\xbf"

# A quoted field runs from '"' to the first '"' that is not doubled, and an
# unquoted field to the next ',', '"' or line break. Possessive quantifiers
# keep a quoted field that the text ends inside from matching a shorter
# field, so that the scan stops at its opening '"'.
_QUOTED = r'"[^"]*+(?:""[^"]*+)*+"'
_UNQUOTED = r'[^",\r\n]*+'
_RECORD = re.compile(rf"(?:{_QUOTED}|{_UNQUOTED})(?:,(?:{_QUOTED}|{_UNQUOTED}))*+")
_FIELD = re.compile(rf'"([^"]*+(?:""[^"]*+)*+)"|{_UNQUOTED}')

# The lexical forms of tables.md (Field types). fullmatch() matches the whole
# value, so that a final line feed is not allowed, and [0-9] is ASCII only.
_INTEGER = re.compile(r"[+-]?([0-9]+)")
_NUMBER = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
_SPECIAL_NUMBER = re.compile(r"[nN][aA][nN]|-?[iI][nN][fF]")
_MANTISSA = re.compile(r"[^eE]*")
_NON_ZERO_DIGIT = re.compile(r"[1-9]")
_DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
_DATETIME = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?"
    r"(?:Z|[+-]([0-9]{2}):([0-9]{2}))?"
)
_BOOLEANS = {
    "true": True,
    "True": True,
    "TRUE": True,
    "1": True,
    "false": False,
    "False": False,
    "FALSE": False,
    "0": False,
}
# The words that make a column without a table block a boolean column, which
# leave out '1' and '0', since such a column is a number column.
_BOOLEAN_WORDS = frozenset(("true", "True", "TRUE", "false", "False", "FALSE"))

# How E5006 names each type.
_TYPE_NAMES = {
    "integer": "an integer",
    "number": "a number",
    "boolean": "a boolean",
    "date": "a date",
    "datetime": "a date and time",
}

# Markers of the values that give E5006 and E5007 and of a raw value not yet
# converted.
_BAD_TYPE = object()
_BAD_CATEGORY = object()
_UNSEEN = object()
# The value of NaN in a key, where NaN equals NaN (tables.md, Keys).
_NAN_KEY = object()


def read_table(file: str | os.PathLike[str], declaration: Any = None) -> pandas.DataFrame:
    """Read a data table with the strict reader.

    Reads a CSV file by the rules of the table specification of mixedcheck and
    returns its columns. The text must be UTF-8 without a byte-order mark,
    with fields separated by ',' and records by LF, CR LF or CR alone, and
    quoted fields as RFC 4180 writes them. Nothing is trimmed. The first
    record is the header, whose column names must be valid and distinct after
    NFC normalisation, and every later record must have as many fields.

    With a declaration that has a table block, the header must name the fields
    of the block in number and order, compared after NFC normalisation. A
    value is missing when it equals, after NFC normalisation, one of the
    field's ``missingValues``, otherwise one of the table block's, otherwise
    the empty string. Every other value must have the lexical form of its
    field's type and be one of its categories, and after the last record the
    primary key and each unique key of the block are checked. A field without
    a type is read as text. Without a table block, every column has the
    missing value '' and the type number, boolean or string, inferred from its
    values in that order.

    Args:
        file: The path of the CSV file, as a str or a path-like object.
        declaration: ``None``, the path of a declaration file in JSON or YAML,
            or a declaration in memory as a dict, as
            :func:`validate_declaration` accepts it. The declaration is
            validated first, and an invalid one gives the validator's error.
            Its table block, if it has one, applies to the table.

    Returns:
        A pandas DataFrame with one column for each column of the file, in the
        order of the header and under the names that the header writes,
        without normalisation and unchanged, and one row for each record after
        the header, in the order of the file. Every column has dtype object.
        Columns of type string, date and datetime and fields without a type
        hold str, returned as written. Columns of type integer hold int,
        columns of type number hold float and columns of type boolean hold
        bool, so that integers stay exact. A missing value is ``None``, where
        the R package returns ``NA`` of the column's type, and the values
        'NaN', 'INF' and '-INF' of a number column, in any mix of upper and
        lower case, are ``math.nan``, ``math.inf`` and ``-math.inf``, which
        stay distinct from ``None``.
        ``attrs["types"]`` is a dict of the column types, keyed by column in
        the order of the header: the declared type, 'string' for a field
        without a type or the type inferred.

    Raises:
        MixedcheckError: A problem in the table, whose ``issues`` hold one
            issue: a dict with the ``code`` of the shared error catalogue, the
            rendered ``message`` and, when the code has a location, the byte
            ``offset`` into the file at which the problem lies. Offsets count
            from 0 in both packages, whereas R numbers rows and columns from
            1. A declaration that is not valid gives the error of
            :func:`validate_declaration` instead, with every problem found.
        TypeError: A ``file`` argument that is not a path.

    Examples:
        >>> import os
        >>> import shutil
        >>> import tempfile
        >>> directory = tempfile.mkdtemp()
        >>> path = os.path.join(directory, "data.csv")
        >>> with open(path, "wb") as handle:
        ...     _ = handle.write(b"pupil,score,passed\\nP1,12.5,true\\nP2,,false\\n")
        >>> table = read_table(path)
        >>> table.attrs["types"]
        {'pupil': 'string', 'score': 'number', 'passed': 'boolean'}
        >>> table["score"].tolist()
        [12.5, None]
        >>> declaration = {
        ...     "vocabulary": "0.1.0",
        ...     "table": {
        ...         "fields": [
        ...             {"name": "pupil", "type": "string"},
        ...             {"name": "score", "type": "integer"},
        ...             {"name": "passed", "type": "boolean"},
        ...         ]
        ...     },
        ... }
        >>> try:
        ...     read_table(path, declaration)
        ... except MixedcheckError as err:
        ...     print(err.issues[0]["message"])
        The value '12.5' of the column 'score' at byte 22 cannot be read as an integer.
        >>> shutil.rmtree(directory)
    """
    if isinstance(file, os.PathLike):
        file = os.fspath(file)
    if not isinstance(file, str):
        raise TypeError("'file' must be a file path.")
    table = None
    if declaration is not None:
        table = validate_declaration(declaration).get("table")
    names, columns, types = read_table_bytes(read_input_bytes(file), table)
    return table_frame(names, columns, types)


def table_frame(
    names: Sequence[str], columns: Sequence[list[Any]], types: Sequence[str]
) -> pandas.DataFrame:
    """The DataFrame of the columns read, with dtype object, and their types in
    ``attrs["types"]``."""
    import pandas as pd

    frame = pd.DataFrame(
        {name: pd.Series(column, dtype=object) for name, column in zip(names, columns, strict=True)}
    )
    frame.attrs["types"] = dict(zip(names, types, strict=True))
    return frame


def read_table_bytes(
    data: bytes, table: Mapping[str, Any] | None
) -> tuple[list[str], list[list[Any]], list[str]]:
    """Stages 1 to 4 for the bytes of an input: the column names, the columns
    of values and the column types, or a MixedcheckError with one issue."""
    if data.startswith(_BOM):
        raise_issue("E1003")
    invalid = utf8_invalid_offset(data)
    if invalid is not None:
        raise_issue("E1201", offset=invalid)
    nul = data.find(b"\x00")
    if nul >= 0:
        raise_issue("E1202", offset=nul)
    return _Reader(data, table).read()


class _Field:
    """How the values of one column are read: its type, its categories and
    its missing values, both in the form in which they are compared."""

    def __init__(self, field: Mapping[str, Any] | None, table: Mapping[str, Any] | None) -> None:
        field = field or {}
        self.type: str | None = field.get("type")
        if "missingValues" in field:
            missing = field["missingValues"]
        elif table is not None and "missingValues" in table:
            missing = table["missingValues"]
        else:
            missing = [""]
        self.missing = frozenset(comparison_form(list_item_value(item)) for item in missing)
        self.categories: frozenset[Any] | None = None
        if "categories" in field:
            values = [list_item_value(item) for item in field["categories"]]
            if self.type == "integer":
                self.categories = frozenset(int(value) for value in values)
            else:
                self.categories = frozenset(comparison_form(value) for value in values)

    def is_missing(self, raw: str) -> bool:
        """Whether a raw value is missing, compared after NFC."""
        if raw in self.missing:
            return True
        return not raw.isascii() and comparison_form(raw) in self.missing

    def convert(self, raw: str) -> Any:
        """The value of a raw value that is not missing, or a marker of E5006
        or E5007."""
        kind = self.type
        if kind is None or kind == "string":
            if self.categories is not None and comparison_form(raw) not in self.categories:
                return _BAD_CATEGORY
            return raw
        value = _CONVERTERS[kind](raw)
        if value is not _BAD_TYPE and self.categories is not None:
            if value not in self.categories:
                return _BAD_CATEGORY
        return value

    def read(self, raw: str) -> Any:
        """None for a missing value, otherwise the converted value or a marker."""
        if self.is_missing(raw):
            return None
        return self.convert(raw)


def _integer(raw: str) -> Any:
    match = _INTEGER.fullmatch(raw)
    if match is None:
        return _BAD_TYPE
    # The digits without leading zeros: more than 16 lie outside the range,
    # and int() refuses strings beyond its limit on digits.
    digits = match.group(1).lstrip("0")
    if len(digits) > 16:
        return _BAD_TYPE
    value = int(digits) if digits else 0
    if value > MAX_INTEGER:
        return _BAD_TYPE
    return -value if raw.startswith("-") else value


def _number(raw: str) -> Any:
    if _NUMBER.fullmatch(raw) is not None:
        # float() rounds correctly, ties to even.
        value = float(raw)
        if math.isinf(value):
            return _BAD_TYPE
        if value == 0 and _NON_ZERO_DIGIT.search(_matched(_MANTISSA, raw)) is not None:
            return _BAD_TYPE
        return value
    if _SPECIAL_NUMBER.fullmatch(raw) is not None:
        return float(raw)
    return _BAD_TYPE


def _boolean(raw: str) -> Any:
    return _BOOLEANS.get(raw, _BAD_TYPE)


def _date(raw: str) -> Any:
    if _DATE.fullmatch(raw) is None or not _date_exists(raw):
        return _BAD_TYPE
    return raw


def _datetime(raw: str) -> Any:
    match = _DATETIME.fullmatch(raw)
    if match is None or not _date_exists(raw):
        return _BAD_TYPE
    hour, minute, second, offset_hour, offset_minute = match.groups()
    if int(hour) > 23 or int(minute) > 59 or int(second) > 59:
        return _BAD_TYPE
    if offset_hour is not None and (int(offset_hour) > 23 or int(offset_minute) > 59):
        return _BAD_TYPE
    return raw


def _date_exists(text: str) -> bool:
    """Whether the date YYYY-MM-DD at the start of a value names a real day: a
    year from 0001 to 9999, a month from 01 to 12 and a day that exists in its
    month (conventions.md, Shared definitions)."""
    month = int(text[5:7])
    return (
        int(text[0:4]) >= 1
        and 1 <= month <= 12
        and int(text[8:10]) >= 1
        and calendar_day_exists(text)
    )


def _matched(pattern: re.Pattern[str], text: str) -> str:
    """The text that a pattern which always matches matches at the start."""
    match = pattern.match(text)
    assert match is not None
    return match.group(0)


_CONVERTERS: dict[str, Callable[[str], Any]] = {
    "integer": _integer,
    "number": _number,
    "boolean": _boolean,
    "date": _date,
    "datetime": _datetime,
}


def _read_column(raw: Sequence[str], read: Callable[[str], Any]) -> tuple[list[Any], int]:
    """The values of a column, each distinct raw value read once, and the row
    of its first marker, or -1."""
    cache: dict[str, Any] = {}
    out: list[Any] = []
    append = out.append
    for row, text in enumerate(raw):
        value = cache.get(text, _UNSEEN)
        if value is _UNSEEN:
            value = read(text)
            cache[text] = value
        if value is _BAD_TYPE or value is _BAD_CATEGORY:
            out.append(value)
            return out, row
        append(value)
    return out, -1


class _Reader:
    """Stages 3 and 4 on a decoded input."""

    def __init__(self, data: bytes, table: Mapping[str, Any] | None) -> None:
        self.data = data
        self.text = data.decode("utf-8")
        self.n = len(self.text)
        self.ascii = self.n == len(data)
        self.table = table

    # Locations -----------------------------------------------------------------

    def offset(self, index: int) -> int:
        """The byte offset of a character index."""
        if self.ascii:
            return index
        return len(self.text[:index].encode("utf-8"))

    def fail(self, code: str, index: int, args: Mapping[str, Any] | None = None) -> NoReturn:
        raise_issue(code, args, offset=self.offset(index))

    # Records --------------------------------------------------------------------

    def scan(self, start: int) -> tuple[int, int, int]:
        """Scan the record that starts at a character index.

        Returns three character indices: where its last field ends, where the
        next record starts, which is the length of the text after the last
        record, and where a quoting problem lies, or -1 when there is none.
        """
        text = self.text
        match = _RECORD.match(text, start)
        assert match is not None
        end = match.end()
        if end == self.n:
            return end, end, -1
        char = text[end]
        if char == "\n":
            return end, end + 1, -1
        if char == "\r":
            return end, end + 2 if text.startswith("\n", end + 1) else end + 1, -1
        return end, end, end

    def fields(self, start: int, end: int) -> tuple[list[str], list[int]]:
        """The raw values of a well-formed record and the character indices at
        which its fields start."""
        record = self.text[start:end]
        if '"' not in record:
            values = record.split(",")
            starts = []
            position = start
            for value in values:
                starts.append(position)
                position += len(value) + 1
            return values, starts
        values = []
        starts = []
        position = 0
        size = len(record)
        while True:
            match = _FIELD.match(record, position)
            assert match is not None
            starts.append(start + position)
            inner = match.group(1)
            values.append(inner.replace('""', '"') if inner is not None else match.group(0))
            position = match.end()
            if position >= size:
                return values, starts
            position += 1

    def field_start(self, record_start: int, column: int) -> int:
        """The character index of a field of a well-formed record."""
        end = self.scan(record_start)[0]
        return self.fields(record_start, end)[1][column]

    # The stages -------------------------------------------------------------------

    def read(self) -> tuple[list[str], list[list[Any]], list[str]]:
        if self.n == 0:
            raise_issue("E5001")
        end, position, problem = self.scan(0)
        if problem >= 0:
            self.fail("E5004", problem)
        names, name_starts = self.fields(0, end)
        self.check_names(names, name_starts)
        table = self.table
        specs: list[_Field] | None = None
        if table is not None:
            self.check_match(names, name_starts, table["fields"], end)
            specs = [_Field(field, table) for field in table["fields"]]
        rows, starts, structure = self.records(position, len(names))
        if specs is None:
            if structure is not None:
                self.fail(*structure)
            columns, types = self.inferred_columns(names, rows, starts)
            return names, columns, types
        columns = self.declared_columns(names, specs, rows, starts)
        if structure is not None:
            self.fail(*structure)
        assert table is not None
        self.check_keys(names, specs, table, columns, starts)
        types = [spec.type or "string" for spec in specs]
        return names, columns, types

    def check_names(self, names: list[str], starts: list[int]) -> None:
        """E5002 for the first column name that is not a column name of
        defs.schema.json or equals an earlier name after NFC."""
        seen: set[str] = set()
        for name, start in zip(names, starts, strict=True):
            form = comparison_form(name)
            if not is_column_name(name) or form in seen:
                self.fail("E5002", start)
            seen.add(form)

    def check_match(
        self,
        names: list[str],
        starts: list[int],
        fields: Sequence[Mapping[str, Any]],
        header_end: int,
    ) -> None:
        """E5003 for the first column name that differs from the field at its
        position after NFC, then for a header with fewer or more columns than
        the block has fields."""
        for name, start, field in zip(names, starts, fields, strict=False):
            if comparison_form(name) != comparison_form(field["name"]):
                self.fail("E5003", start)
        if len(names) < len(fields):
            self.fail("E5003", header_end)
        if len(names) > len(fields):
            self.fail("E5003", starts[len(fields)])

    def records(
        self, position: int, width: int
    ) -> tuple[list[list[str]], list[int], tuple[str, int, dict[str, Any]] | None]:
        """The raw values of the records after the header and the character
        index of each, up to the first record with a quoting problem or a
        different number of fields from the header, which is returned as the
        code, the index and the arguments of its issue."""
        text = self.text
        n = self.n
        match = _RECORD.match
        rows: list[list[str]] = []
        starts: list[int] = []
        while position < n:
            found = match(text, position)
            assert found is not None
            end = found.end()
            if end == n:
                following = n
            else:
                char = text[end]
                if char == "\n":
                    following = end + 1
                elif char == "\r":
                    following = end + 2 if text.startswith("\n", end + 1) else end + 1
                else:
                    return rows, starts, ("E5004", end, {})
            record = text[position:end]
            values = record.split(",") if '"' not in record else self.fields(position, end)[0]
            if len(values) != width:
                arguments = {"found": len(values), "expected": width}
                return rows, starts, ("E5005", position, arguments)
            rows.append(values)
            starts.append(position)
            position = following
        return rows, starts, None

    def declared_columns(
        self,
        names: list[str],
        specs: list[_Field],
        rows: list[list[str]],
        starts: list[int],
    ) -> list[list[Any]]:
        """The values of each column read by its field, or E5006 or E5007 for
        the first value, by record and then by column, that lacks the form of
        its field's type or is not one of its categories."""
        raw_columns = _transpose(rows, len(names))
        columns: list[list[Any]] = []
        first: tuple[int, int] | None = None
        for column, (raw, spec) in enumerate(zip(raw_columns, specs, strict=True)):
            limit = len(raw) if first is None else first[0] + 1
            values, row = _read_column(raw[:limit] if limit < len(raw) else raw, spec.read)
            columns.append(values)
            if row >= 0 and (first is None or row < first[0]):
                first = (row, column)
        if first is not None:
            row, column = first
            text = raw_columns[column][row]
            index = self.field_start(starts[row], column)
            if columns[column][row] is _BAD_TYPE:
                kind = specs[column].type
                assert kind is not None
                arguments = {"value": text, "column": names[column], "type": _TYPE_NAMES[kind]}
                self.fail("E5006", index, arguments)
            self.fail("E5007", index, {"value": text, "column": names[column]})
        return columns

    def inferred_columns(
        self, names: list[str], rows: list[list[str]], starts: list[int]
    ) -> tuple[list[list[Any]], list[str]]:
        """The values and types of the columns of a table without a table
        block, or E5006 for the first value of a number column, by record and
        then by column, that converts to an infinity or to zero from a value
        that is not zero."""
        raw_columns = _transpose(rows, len(names))
        columns: list[list[Any]] = []
        types: list[str] = []
        first: tuple[int, int] | None = None
        for column, raw in enumerate(raw_columns):
            distinct = set(raw)
            distinct.discard("")
            if distinct and all(_number_form(value) for value in distinct):
                kind = "number"
                values, row = _read_column(raw, _read_inferred_number)
                if row >= 0 and (first is None or row < first[0]):
                    first = (row, column)
            elif distinct and distinct <= _BOOLEAN_WORDS:
                kind = "boolean"
                values = [None if value == "" else _BOOLEANS[value] for value in raw]
            else:
                kind = "string"
                values = [None if value == "" else value for value in raw]
            columns.append(values)
            types.append(kind)
        if first is not None:
            row, column = first
            arguments = {
                "value": raw_columns[column][row],
                "column": names[column],
                "type": _TYPE_NAMES["number"],
            }
            self.fail("E5006", self.field_start(starts[row], column), arguments)
        return columns, types

    def check_keys(
        self,
        names: list[str],
        specs: list[_Field],
        table: Mapping[str, Any],
        columns: list[list[Any]],
        starts: list[int],
    ) -> None:
        """Stage 4: the primary key, then each unique key in its order."""
        position = {field["name"]: i for i, field in enumerate(table["fields"])}
        if "primaryKey" in table:
            indices = [position[name] for name in table["primaryKey"]]
            # The first record with a missing value in the primary key, and in
            # it the first column of the key in its order.
            missing: tuple[int, int] | None = None
            for index in indices:
                try:
                    row = columns[index].index(None)
                except ValueError:
                    continue
                if missing is None or row < missing[0]:
                    missing = (row, index)
            stop = len(starts) if missing is None else missing[0]
            keys = _key_rows(columns, specs, indices)
            first: dict[tuple[Any, ...], int] = {}
            for row in range(stop):
                key = keys[row]
                if key in first:
                    self.fail("E5009", starts[row], {"earlier": self.offset(starts[first[key]])})
                first[key] = row
            if missing is not None:
                row, index = missing
                self.fail("E5008", self.field_start(starts[row], index), {"column": names[index]})
        for number, unique in enumerate(table.get("uniqueKeys", []), start=1):
            indices = [position[name] for name in unique]
            keys = _key_rows(columns, specs, indices)
            first = {}
            for row, key in enumerate(keys):
                if any(columns[index][row] is None for index in indices):
                    continue
                if key in first:
                    arguments = {"index": number, "earlier": self.offset(starts[first[key]])}
                    self.fail("E5010", starts[row], arguments)
                first[key] = row


def _transpose(rows: list[list[str]], width: int) -> list[list[str]]:
    """The columns of a list of records of one width."""
    if not rows:
        return [[] for _ in range(width)]
    return [list(column) for column in zip(*rows, strict=True)]


def _number_form(raw: str) -> bool:
    """Whether a raw value has the lexical form of a number."""
    return _NUMBER.fullmatch(raw) is not None or _SPECIAL_NUMBER.fullmatch(raw) is not None


def _read_inferred_number(raw: str) -> Any:
    """A value of a number column without a table block: None for the empty
    string, otherwise the number or the marker of E5006."""
    if raw == "":
        return None
    return _number(raw)


def _key_rows(
    columns: list[list[Any]], specs: list[_Field], indices: list[int]
) -> list[tuple[Any, ...]]:
    """The values of the columns of a key in each record, in the form in which
    they are compared.

    Strings, dates and dates and times are compared after NFC, and integers,
    numbers and booleans by value. NaN equals NaN, and negative zero equals
    zero, as it does in Python.
    """
    parts = []
    for index in indices:
        kind = specs[index].type
        values = columns[index]
        if kind == "number":
            parts.append([_NAN_KEY if v is not None and math.isnan(v) else v for v in values])
        elif kind in ("integer", "boolean"):
            parts.append(values)
        else:
            parts.append([None if v is None else comparison_form(v) for v in values])
    return list(zip(*parts, strict=True))
