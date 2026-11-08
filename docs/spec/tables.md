# Data tables

This document specifies how both packages read a data table: the CSV text they accept, how its header matches the table block of a declaration, which values are missing, the lexical form of each field type and the error codes of the table area. It turns the Frictionless lexical defaults that 02-decisions.md (Q4) requires into explicit rules, so that the table conformance corpus can state the expected outcome of every case and the two readers of M2 return the same values. The table block itself is specified in [declarations.md](declarations.md), the conventions on UTF-8, NFC and numbers in [conventions.md](conventions.md) and the codes in [spec/errors.json](../../spec/errors.json), described in [errors.md](errors.md). The conformance corpus in [fixtures/conformance/tables/](../../fixtures/conformance/tables/README.md) holds tables with their expected values and samples or the issue that the reader reports.

M1 specifies the reader. The reader, the canonical analysis table and the handling of data frames passed in memory are implemented in M2 (03-execution-plan.md), and M2 applies the rules below on column names and on missing values given as strings to a data frame passed in memory.

## Stages

The reader works in four stages and reports exactly one issue, the first that it finds.

1. Input. A file that does not exist gives E1001 and one that cannot be read E1002. If the input starts with EF BB BF, the reader reports E1003, as every reader does, although some spreadsheet programs write that mark.
2. Text. The whole input is validated as UTF-8 (E1201, conventions.md, UTF-8). Only then does the first U+0000 give E1202 at its offset, so that invalid UTF-8 anywhere is reported before a U+0000 earlier in the input.
3. Records. The text is divided into records and fields from left to right, and each record is checked as it is read: the header first, then each further record. In the header, quoting problems (E5004) come first, as the scan meets them, then the column names in order (E5002) and then their match with the table block (E5003). In every further record, quoting problems (E5004) come first, as the scan meets them, then the number of fields (E5005), then each value in order (E5006 and E5007). Without a table block, the types of the columns depend on all their values, so every record is read and checked for quoting and length first, and the values are checked afterwards (Columns without a table block).
4. Keys. After the last record, the primary key and then each unique key of the table block are checked (Keys).

Offsets are byte offsets into the input, counted from 0 (conventions.md). A record is located at its first byte, and a field or value at the first byte of its field, which is the opening quotation mark of a quoted field. An empty record or field is located where it starts: an empty record at its line break, and an empty field at the ',' or line break that ends it or, at the end of the text, at the length of the input.

## CSV text

The text follows RFC 4180, with these choices, which are the defaults of the Frictionless Table Dialect except where stated.

- Fields are separated by ',' and records by a line break: LF, CR LF or CR alone. A line break at the end of the text ends the last record and starts no new one.
- A field that starts with '"' is quoted. It ends at the next '"' that is not followed by another '"', and a doubled '"' stands for one. A quoted field may hold ',', '"' and line breaks, which are kept as written, so that a quoted CR LF stays CR LF. The closing '"' must be followed by ',', a line break or the end of the text (E5004 at the character found instead), and a quoted field that the text ends inside gives E5004 at its opening '"'.
- A field that does not start with '"' runs to the next ',' or line break and must not contain '"' (E5004 at that character).
- Nothing is trimmed: spaces and tabs belong to the field, inside or outside quotation marks.
- An empty line is a record with one empty field.
- The text of a field, after the quotation marks are removed and doubled '"' made single, is its raw value. A quoted empty field and an empty field have the same raw value, the empty string.

## Header

The first record is the header, and its raw values are the column names. An empty input has no record and gives E5001, whereas a text that holds only a line break has one empty record, whose one column name is empty (E5002). Each column name must be a column name of defs.schema.json, 1 to 128 characters without control characters or characters outside the Basic Multilingual Plane, and must differ from every earlier column name after NFC (conventions.md, NFC). The first that does not gives E5002 at its field. Every later record must have as many fields as the header (E5005 at the record). The reader returns each column under its name as the header writes it, without normalisation.

With a table block, the column names must match the fields of the block, in number and order, as the default `fieldsMatch` 'exact' of Frictionless requires (declarations.md, table). They are matched only when every column name has passed the checks above, so that a header with an invalid column name gives E5002 even where it also differs from the block. Each column name is compared with the name of the field at the same position after NFC, and the first that differs gives E5003 at its field. When the header has fewer columns than the block has fields, E5003 is reported at the line break that ends the header, or at the end of the text, and when it has more, at the first column without a field. A field of the block applies to the column at its position.

## Missing values

A value is missing when its raw value, compared after NFC, equals one of the missing values that apply to its column: the field's `missingValues` when the field has them, otherwise the table block's `missingValues` and otherwise the Frictionless default `[""]`, which the reader applies explicitly (02-decisions.md, Q4). A missing value given as an object, such as a labelled sentinel code '-99', matches through its `value`. An empty list of missing values declares that no value is missing, so that the empty string is then a value. Missing values are matched before any conversion and never checked against the type or the categories, and the reader returns a missing value as NA in R and None in Python.

## Field types

Each value that is not missing must have the lexical form of its field's type, or the reader reports E5006 at its field, naming the type as 'an integer', 'a number', 'a boolean', 'a date' or 'a date and time'. These forms are the Frictionless defaults: no group character, '.' as the decimal character and bare numbers without currency signs or units.

| Type | Lexical form | Value returned |
|---|---|---|
| string | any text | the raw value, unchanged and not normalised |
| integer | `^[+-]?[0-9]+$`, with a value from -9007199254740991 to 9007199254740991 | the integer, as a double in R and an int in Python |
| number | `^[+-]?([0-9]+(\.[0-9]*)?\|\.[0-9]+)([eE][+-]?[0-9]+)?$`, or 'NaN', 'INF' or '-INF' in any mix of upper and lower case | the nearest double, rounded correctly with ties to even, or NaN, +∞ or −∞ for the special values |
| boolean | 'true', 'True', 'TRUE' or '1', and 'false', 'False', 'FALSE' or '0' | true or false |
| date | `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` | the raw value |
| datetime | `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z\|[+-][0-9]{2}:[0-9]{2})?$` | the raw value |

Each pattern must match the whole raw value, and `[0-9]` stands for the ASCII digits only, so that a quoted value that ends in a line break, such as '1' followed by LF, or a value written with other digits, such as '١' (U+0661), has none of these forms. In Python, a final '$' is therefore matched as '\Z' (conventions.md, Schemas). So '007' and '+5' are the integers 7 and 5, whereas ' 12', '1_000' and '0x1A' are not integers. '-0' is the integer 0 and, as a number, negative zero, which equals zero and is written as 0 (conventions.md, Serialisation). A number in the form of the table that converts to an infinity, such as '1e400', or to zero from a non-zero value, such as '1e-400', gives E5006, as the data profile refuses such numbers (conventions.md, Numbers). The special values are values, not missing values, so that a computed NaN and a missing value stay apart. A date or a date and time must also name a real time: a year from 0001 to 9999, a month from 01 to 12, a day that exists in its month by the rule of conventions.md (Shared definitions), hours from 00 to 23, minutes and seconds from 00 to 59 and, for an offset, hours from 00 to 23 and minutes from 00 to 59. Dates and times are returned as written, since vocabulary 0.1 defers time zones (declarations.md, observation).

A field without a type has the Frictionless type 'any' and is read as a string (declarations.md, table).

## Categories

A value of a field with `categories` that is not missing and has the field's type must be one of the categories (E5007 at its field), compared after NFC for a field of type 'string' and by value, as an integer, for a field of type 'integer'. A category given as an object matches through its `value`. A value outside the categories is never read as missing or recoded.

## Columns without a table block

Without a table block, every column has the default missing values `[""]` and a type inferred from its values that are not missing, in this order: number when every such value has the lexical form of a number, boolean when every such value is 'true', 'True', 'TRUE', 'false', 'False' or 'FALSE', and string otherwise, also when the column has no value that is not missing. So a column of '1' and '0' is a number column, and a column that holds 'NA' for missing values is a string column unless the declaration lists 'NA' among its missing values.

The values of a number column are converted as those of a field of type 'number'. A value such as '1e400', which has the lexical form of a number but converts to an infinity, therefore gives E5006 rather than making the column a string column, so that the type of a column never depends on the range of its values. The values are checked only after every record has been read and has passed the checks of quoting and length, record by record and each record from left to right. A table with an invalid record later in the file thus gives E5004 or E5005 there, even when an earlier value would give E5006.

## Keys

After the last record, the reader checks the `primaryKey` of the table block and then each list of `uniqueKeys` in its order, each over the records in the order of the file (declarations.md, table). Values are compared as the reader returns them. Strings, dates and dates and times are compared after NFC, and integers, numbers and booleans by value, with NaN equal to NaN and negative zero equal to zero. So '007' and '7' are one value of an integer field and two values of a string field. Two records have the same values in a key when their values are equal in every column of the key.

- Primary key. Every column of the primary key must have a value in every record, since a record whose key is incomplete cannot be identified. The records are taken in order. In each, the columns of the primary key are taken in the order of `primaryKey`, and the first missing value gives E5008 at its field. Otherwise, a record with the same values in the primary key as an earlier record gives E5009 at the record, naming the first earlier record that has them.
- Unique keys. A record with a missing value in a column of a unique key is not compared on that key, so that a unique key constrains only the records that have a value in each of its columns. A record with the same values in a unique key as an earlier record gives E5010 at the record, naming the key by its position in `uniqueKeys`, counted from 1, and the first earlier record that has them.

The declared observation key need not be a key of the table block. Its duplicates are a finding of the check keys.duplicates, never an error of the reader (registry.md).

## Errors

| Code | Name | Raised when |
|---|---|---|
| E5001 | table_no_header | the table has no header row |
| E5002 | table_column_name | a column name is empty, is not a valid column name or equals an earlier one after NFC |
| E5003 | table_fields_mismatch | the column names do not match the fields of the table block in number and order |
| E5004 | table_csv_quote | a quotation mark does not open or close a quoted field |
| E5005 | table_record_length | a record has a different number of values from the header |
| E5006 | table_value_type | a value does not have the lexical form of its field's type |
| E5007 | table_value_category | a value is not one of the declared categories of its field |
| E5008 | table_key_missing | a column of the primary key has a missing value |
| E5009 | table_primary_key_duplicate | a record has the same values in the primary key as an earlier record |
| E5010 | table_unique_key_duplicate | a record has the same values in a unique key as an earlier record |

The argument {value} of E5006 and E5007 is the raw value and {column} of E5006 to E5008 the column name as the header writes it, each after display escaping and truncation (errors.md, Rendering messages). {earlier} of E5009 and E5010 is the byte offset of the first earlier record with the same values, and {index} of E5010 the position of the unique key in `uniqueKeys`, counted from 1.

## References

Frictionless Data. (2024). Table Schema (version 2.0). https://datapackage.org/standard/table-schema/

Frictionless Data. (2024). Table Dialect (version 2.0). https://datapackage.org/standard/table-dialect/

Shafranovich, Y. (2005). Common format and MIME type for comma-separated values (CSV) files (RFC 4180). Internet Engineering Task Force. https://doi.org/10.17487/RFC4180
