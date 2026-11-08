# Table corpus

These cases test the strict table reader that M2 implements in both packages ([docs/spec/tables.md](../../../docs/spec/tables.md)). Each case gives a CSV input and, when the case has one, a declaration whose table block the reader applies. It expects either the columns that the reader returns, with the design and analysis samples of a formula for some cases, or the one issue that the reader reports.

| File | Cases | Covers |
|---|---|---|
| edgezoo.json | 10 | the ten edge tables of the evidence for the decisions, read as stored: default missing values, integer forms, a hexadecimal integer, NaN and the infinities, strings, CR LF, a byte-order mark, small numbers in exponent notation, a quoted line feed and a clean control |
| edge.json | 54 | the strings, numbers, byte-order marks, NaN, escapes, characters outside the BMP, surrogates and empty containers of the twelve JSON edge files, carried into CSV text |
| input.json | 10 | files that do not exist or cannot be read, the byte-order mark, invalid UTF-8, U+0000, noncharacters and unassigned code points |
| records.json | 20 | line breaks, quoted fields with line breaks and doubled quotation marks, white space, empty fields, quoting problems (E5004) and records of the wrong length (E5005) |
| header.json | 15 | invalid, too long and repeated column names (E5002) and the match with the table block in number, order and spelling (E5003) |
| values.json | 37 | missing values of the field, the table and the default, labelled sentinel codes, the lexical form of each field type (E5006), dates and times that do not exist and categories (E5007) |
| inference.json | 13 | the types inferred without a table block and the order of their issues |
| keys.json | 18 | primary keys (E5008 and E5009), unique keys (E5010), the comparison of values and the order of the checks |
| precedence.json | 9 | tables with several problems, of which the reader reports the first |
| samples.json | 6 | the rows that missing values, sentinel codes and trials of 0 remove from the design and analysis samples |

## Format

Each file is a JSON object with a `description` and a list of `cases`, read with the strict reader in the data profile, since missing values are null. The files are ASCII, with every other character written as an escape, and their strings need not be in NFC. Each case has these members:

- `id` and `description`. The ID is unique across the corpora.
- `path`: the CSV input, relative to this directory, read as bytes. The inputs keep CR LF, CR alone, byte-order marks, invalid UTF-8, U+0000 and strings in NFD on purpose, and .gitattributes keeps their bytes as stored. One input is empty.
- `file`, in place of `path`: 'missing' to read a path that does not exist, or 'directory' to read a path to a directory.
- `declaration`: a valid declaration of vocabulary 0.1, whose table block the reader applies. Without it, the reader reads the table by the rules for columns without a table block.
- `formula`: present when the case also gives the samples of the IR that the builder of ir.md makes from this formula, the declaration and the table read.
- `expected`: either `columns`, with `design_sample` and `analysis_sample` when the case has a formula, or `issue`.

`columns` lists the columns in the order of the header. Each has its `name` as the header writes it, without normalisation, its `type` and its `values`, one for each record in the order of the file. The type is the declared type of the field, 'string' for a field without a type and, without a table block, the type inferred. A value is written as a writer in the data profile writes it (conventions.md, Profiles):

- a missing value as null, which is NA in R and None in Python
- a value of an integer column as a JSON integer, which the reader returns as a double in R and an int in Python
- a value of a number column as a JSON number, or as 'NaN', 'Infinity' or '-Infinity' for the special values
- a boolean as true or false
- a string, a date or a date and time as the string read

A test compares the column names and every string code point by code point, without normalisation, and numbers by value, so that the negative zero that the reader returns for '-0' in a number column equals 0.

`design_sample` and `analysis_sample` list the rows of the design and analysis samples (ir.md, Samples), numbered from 0 in the order of the records. Numbering from 0 belongs to this file only, since the packages identify rows by their observation keys.

`issue` holds the `code`, the rendered `message` and, for a code located by offset, the byte `offset` into the input (`issue` in [defs.schema.json](../../../spec/schemas/defs.schema.json)). A test compares all three.

## Provenance

The cases were written for this project from tables.md, [conventions.md](../../../docs/spec/conventions.md), [errors.md](../../../docs/spec/errors.md) and [ir.md](../../../docs/spec/ir.md) and are MIT-licensed. They start from earlier MIT-licensed work of this project in docs/design/evidence/decisions:

- the ten tables of E-verify/edgezoo, written by its make_edgezoo.py, whose data.csv files are used byte for byte and whose design.json files give the table blocks, with `schema_version` replaced by `vocabulary`. In that evidence, R's read.csv() and pandas disagreed on five of them, and neither could serialise the special values of T4.
- the twelve JSON edge files of E/schema/edge and E-verify/edge, which the [json corpus](../json/README.md) holds as stored. Their strings, numbers, byte-order mark, NaN, keys outside the BMP, surrogate, escapes and empty containers appear here as values, column names and empty tables in CSV text, and the description of each case names the file it comes from.

[tools/make_table_corpus.py](../tools/make_table_corpus.py) writes the files. Each case states its expected code by hand, and some also state an offset, values or sample rows. The script derives the rest of each expected output with a scratch reading of tables.md that is part of neither package, stops unless the derivation agrees with what a case states, and checks it against independent oracles, as [tools/README.md](../tools/README.md) describes: Python's csv module for the records and fields of every table read, exact fractions for every number converted, the datetime module for every date and time checked and unicodedata for NFC. Messages are rendered from spec/errors.json as errors.md describes. [spec/tools/test_table_corpus.py](../../../spec/tools/test_table_corpus.py) checks the format of the corpus, the inputs and their vendoring, the edgezoo inputs against the evidence, the declarations, the columns, the samples and every issue against spec/errors.json, and that the corpus equals what the script writes.
