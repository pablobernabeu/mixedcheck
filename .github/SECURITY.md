# Security policy

## Reporting a vulnerability

If you find a security problem in mixedcheck, please report it privately by
email to the maintainer, at the address given in the Authors@R field of
`r/DESCRIPTION`, rather than opening a public issue. A short description of the
problem and, where possible, a way to reproduce it is enough to get started.
You can expect an acknowledgement within a few days, and we will keep you
informed as the issue is investigated and resolved.

## Disclosure of participant data

mixedcheck is designed to write shareable results files from person-level data,
with identifying detail kept in a separate internal file (02-decisions.md, Q5
and the cross-cutting conventions). A shareable output that reveals person-level
data that the privacy filter should have withheld, or a hash or commitment from
which such data can be recovered, is a security problem. Please report it in the
same way, and never attach real participant data to a report.
