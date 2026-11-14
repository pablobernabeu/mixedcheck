"""The formula grammar of docs/spec/ir.md (Formula grammar): the division into
tokens, the parser of the EBNF and the structural rules.

Each stage reports the first issue that the specification assigns to it.
Formulas hold at most 10,000 characters, so the stages work one token at a
time. A run of operands joined by operators of one level, such as
``a:b:c`` or ``a * b / c``, is held as one chain node with its operands in
order, so that walking the tree needs no recursion along the run and only
parentheses, which nest at most 64 levels deep, deepen it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, NoReturn

from mixedcheck._errors import raise_issue
from mixedcheck._unicode import comparison_form

# The reserved words of R, which a bare name cannot be (E6005).
RESERVED_WORDS = frozenset(
    (
        "if",
        "else",
        "repeat",
        "while",
        "function",
        "for",
        "next",
        "break",
        "TRUE",
        "FALSE",
        "NULL",
        "Inf",
        "NaN",
        "NA",
        "NA_integer_",
        "NA_real_",
        "NA_character_",
        "in",
    )
)

# The covariance structures of lme4 2.x and glmmTMB (E6018).
COVARIANCE_STRUCTURES = frozenset(
    ("diag", "cs", "ar1", "us", "homdiag", "homcs", "hetcs", "ou", "toep", "rr", "propto")
)

_BARE_NAME = re.compile(r"[A-Za-z][A-Za-z0-9._]*")
_WHITE = frozenset(" \t\n\r")
_OPERATORS = frozenset("~+-*/:^(),|")
_DIGITS = frozenset("0123456789")
_LETTERS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
_WORD = _LETTERS | _DIGITS | frozenset("._")


def bare_name(name: str) -> bool:
    """Whether a variable name is written bare in IR names: a bare name of the
    grammar that is not a reserved word."""
    return _BARE_NAME.fullmatch(name) is not None and name not in RESERVED_WORDS


def variable_text(name: str) -> str:
    """A variable as IR names write it: bare, or between backquotes."""
    return name if bare_name(name) else "`" + name + "`"


# --- Tokens ---------------------------------------------------------------------


@dataclass(slots=True)
class Token:
    """A token: its type ('op', 'name', 'number' or 'end'), its text as
    written, its byte offset and, for a name, its value, whether it was quoted
    and whether it names a function."""

    type: str
    text: str
    offset: int
    value: str = ""
    quoted: bool = False
    func: bool = False


def formula_offsets(formula: str) -> tuple[list[int], int]:
    """The 0-based byte offset of each code point of the formula in its UTF-8
    encoding, and the number of bytes."""
    offsets = []
    position = 0
    for char in formula:
        offsets.append(position)
        point = ord(char)
        position += 1 if point < 0x80 else 2 if point < 0x800 else 3 if point < 0x10000 else 4
    return offsets, position


def formula_tokens(formula: str) -> list[Token]:
    """Divide a formula into tokens from left to right (ir.md, Tokens).

    The list is closed by a token of type 'end' at the end of the input. The
    first lexical issue stops the scan, since it lies at the lowest offset.
    """
    at, size = formula_offsets(formula)
    n = len(formula)
    tokens: list[Token] = []

    def run_end(i: int) -> int:
        j = i + 1
        while j < n and formula[j] in _WORD:
            j += 1
        return j

    i = 0
    while i < n:
        char = formula[i]
        offset = at[i]
        if char in _WHITE:
            i += 1
        elif char == "|" and i + 1 < n and formula[i + 1] == "|":
            tokens.append(Token("op", "||", offset))
            i += 2
        elif char in _OPERATORS:
            tokens.append(Token("op", char, offset))
            i += 1
        elif char == "`":
            close = formula.find("`", i + 1)
            if close < 0:
                raise_issue("E6003", offset=offset)
            inner = formula[i + 1 : close]
            if not inner or any(
                c == "\\" or ord(c) <= 0x1F or 0x7F <= ord(c) <= 0x9F for c in inner
            ):
                raise_issue("E6004", offset=offset)
            tokens.append(Token("name", formula[i : close + 1], offset, inner, quoted=True))
            i = close + 1
        elif char in _DIGITS:
            j = run_end(i)
            text = formula[i:j]
            if not all(c in _DIGITS for c in text):
                raise_issue("E6006", {"number": text}, offset=offset)
            tokens.append(Token("number", text, offset))
            i = j
        elif char in _LETTERS:
            j = run_end(i)
            text = formula[i:j]
            if text in RESERVED_WORDS:
                raise_issue("E6005", {"name": text}, offset=offset)
            tokens.append(Token("name", text, offset, text))
            i = j
        elif char == ".":
            raise_issue("E6007", {"operator": "."}, offset=offset)
        elif char == "%":
            close = formula.find("%", i + 1)
            if close >= 0 and not any(c in _WHITE for c in formula[i + 1 : close]):
                raise_issue("E6007", {"operator": formula[i : close + 1]}, offset=offset)
            raise_issue("E6002", {"codepoint": ord(char)}, offset=offset)
        else:
            raise_issue("E6002", {"codepoint": ord(char)}, offset=offset)
    # A bare name whose next token is '(' names a function.
    for k in range(len(tokens) - 1):
        token = tokens[k]
        following = tokens[k + 1]
        if token.type == "name" and not token.quoted and following.type == "op":
            if following.text == "(":
                token.func = True
    tokens.append(Token("end", "", size))
    return tokens


# --- Syntax tree ------------------------------------------------------------------


@dataclass(slots=True)
class Name:
    start: int
    value: str
    key: str
    quoted: bool


@dataclass(slots=True)
class Number:
    start: int
    text: str


@dataclass(slots=True)
class Call:
    start: int
    name: str
    args: list[Argument]


@dataclass(slots=True)
class Paren:
    start: int
    arg: Argument


@dataclass(slots=True)
class Chain:
    """Operands joined by operators of one level, read from the left: ':' in
    an interaction, '*' and '/' in a product. ``ops`` holds the text and
    offset of the operator before each operand after the first."""

    start: int
    operands: list[Node]
    ops: list[tuple[str, int]]


@dataclass(slots=True)
class Power:
    start: int
    at: int
    base: Node
    exponent: Node


@dataclass(slots=True)
class Summand:
    sign: str | None
    sign_at: int | None
    expr: Node


@dataclass(slots=True)
class Sum:
    start: int
    summands: list[Summand] = field(default_factory=list)


@dataclass(slots=True)
class Argument:
    """An argument: a sum, with a bar and a second sum for a random term."""

    start: int
    lhs: Sum
    bar: str | None = None
    rhs: Sum | None = None


@dataclass(slots=True)
class Formula:
    lhs: Sum | None
    rhs: Sum


Node = Name | Number | Call | Paren | Chain | Power


def formula_parse(tokens: list[Token], size: int) -> Formula:
    """Parse the tokens by the grammar of ir.md (Syntax), each token by the
    first rule that can continue the formula, and return the syntax tree."""
    return _Parser(tokens, size).formula()


class _Parser:
    def __init__(self, tokens: list[Token], size: int) -> None:
        self.tokens = tokens
        self.size = size
        self.position = 0
        self.depth = 0

    def peek(self) -> Token:
        return self.tokens[self.position]

    def advance(self) -> Token:
        token = self.tokens[self.position]
        self.position += 1
        return token

    @staticmethod
    def is_op(token: Token, ops: tuple[str, ...]) -> bool:
        return token.type == "op" and token.text in ops

    def fail(self, token: Token) -> NoReturn:
        if token.type == "end":
            raise_issue("E6010", offset=self.size)
        if self.is_op(token, ("|", "||")):
            raise_issue("E6013", {"bar": token.text}, offset=token.offset)
        raise_issue("E6011", {"token": token.text}, offset=token.offset)

    def open(self) -> Token:
        token = self.advance()
        self.depth += 1
        if self.depth > 64:
            raise_issue("E6021", offset=token.offset)
        return token

    def close(self) -> None:
        if not self.is_op(self.peek(), (")",)):
            self.fail(self.peek())
        self.advance()
        self.depth -= 1

    def formula(self) -> Formula:
        lhs = None
        if not self.is_op(self.peek(), ("~",)):
            lhs = self.sum()
            if not self.is_op(self.peek(), ("~",)):
                self.fail(self.peek())
        self.advance()
        rhs = self.sum()
        if self.peek().type != "end":
            self.fail(self.peek())
        return Formula(lhs, rhs)

    def sum(self) -> Sum:
        result = Sum(self.peek().offset)
        sign: str | None = None
        sign_at: int | None = None
        if self.is_op(self.peek(), ("+", "-")):
            token = self.advance()
            sign, sign_at = token.text, token.offset
        while True:
            result.summands.append(Summand(sign, sign_at, self.product()))
            if not self.is_op(self.peek(), ("+", "-")):
                return result
            token = self.advance()
            sign, sign_at = token.text, token.offset

    def chain(self, ops: tuple[str, ...], operand: Any) -> Node:
        first: Node = operand()
        if not self.is_op(self.peek(), ops):
            return first
        node = Chain(_start(first), [first], [])
        while self.is_op(self.peek(), ops):
            token = self.advance()
            node.ops.append((token.text, token.offset))
            node.operands.append(operand())
        return node

    def product(self) -> Node:
        return self.chain(("*", "/"), self.interaction)

    def interaction(self) -> Node:
        return self.chain((":",), self.power)

    def power(self) -> Node:
        base = self.primary()
        if self.is_op(self.peek(), ("^",)):
            token = self.advance()
            exponent = self.primary()
            return Power(_start(base), token.offset, base, exponent)
        return base

    def argument(self) -> Argument:
        lhs = self.sum()
        if self.is_op(self.peek(), ("|", "||")):
            token = self.advance()
            rhs = self.sum()
            return Argument(lhs.start, lhs, token.text, rhs)
        return Argument(lhs.start, lhs)

    def primary(self) -> Node:
        token = self.peek()
        if token.type == "name" and token.func:
            self.advance()
            self.open()
            args: list[Argument] = []
            if not self.is_op(self.peek(), (")",)):
                while True:
                    args.append(self.argument())
                    if not self.is_op(self.peek(), (",",)):
                        break
                    self.advance()
            self.close()
            return Call(token.offset, token.value, args)
        if token.type == "name":
            self.advance()
            return Name(token.offset, token.value, comparison_form(token.value), token.quoted)
        if token.type == "number":
            self.advance()
            return Number(token.offset, token.text)
        if self.is_op(token, ("(",)):
            self.open()
            arg = self.argument()
            self.close()
            return Paren(token.offset, arg)
        self.fail(token)


def _start(node: Node) -> int:
    return node.start


# --- Helpers on syntax trees --------------------------------------------------------


def single_name(node: Sum) -> bool:
    """Whether a sum is a single name without a sign."""
    return (
        len(node.summands) == 1
        and node.summands[0].sign is None
        and isinstance(node.summands[0].expr, Name)
    )


def sole_call(node: Sum, name: str) -> Call | None:
    """The call that makes up a whole sum, a single summand without a sign."""
    if len(node.summands) == 1 and node.summands[0].sign is None:
        expr = node.summands[0].expr
        if isinstance(expr, Call) and expr.name == name:
            return expr
    return None


def call_of_name(call: Call) -> bool:
    """Whether a call has one argument without a bar that is a single name."""
    return len(call.args) == 1 and call.args[0].bar is None and single_name(call.args[0].lhs)


def is_random(expr: Node) -> bool:
    """Whether an expression is a random term: a parenthesised argument with a bar."""
    return isinstance(expr, Paren) and expr.arg.bar is not None


def call_name_node(argument: Sum) -> tuple[Name, str]:
    """The name of the response or of an offset, a single name or log() of a
    single name, with its transform."""
    log_call = sole_call(argument, "log")
    if log_call is None:
        expr = argument.summands[0].expr
        transform = "identity"
    else:
        expr = log_call.args[0].lhs.summands[0].expr
        transform = "log"
    assert isinstance(expr, Name)
    return expr, transform


def formula_names(node: Node | Argument | Sum) -> list[Name]:
    """The name nodes of an expression, from left to right."""
    out: list[Name] = []
    stack: list[Node | Argument | Sum] = [node]
    while stack:
        item = stack.pop()
        if isinstance(item, Name):
            out.append(item)
        elif isinstance(item, Call):
            stack.extend(reversed(item.args))
        elif isinstance(item, Paren):
            stack.append(item.arg)
        elif isinstance(item, Argument):
            if item.rhs is not None:
                stack.append(item.rhs)
            stack.append(item.lhs)
        elif isinstance(item, Chain):
            stack.extend(reversed(item.operands))
        elif isinstance(item, Power):
            stack.append(item.exponent)
            stack.append(item.base)
        elif isinstance(item, Sum):
            stack.extend(summand.expr for summand in reversed(item.summands))
    return out


# --- Structure ----------------------------------------------------------------------

# A violation: its code, its offset and the arguments of its message.
Found = tuple[str, int, dict[str, Any]]


def first_issue(found: list[Found]) -> Found | None:
    """The issue at the lowest offset and, at one offset, with the lowest code."""
    if not found:
        return None
    return min(found, key=lambda issue: (issue[1], issue[0]))


def structure_issue(tree: Formula) -> Found | None:
    """The violations of the structural rules of ir.md (Structure): the one at
    the lowest offset and, among those at one offset, with the lowest code."""
    return _Structure().run(tree)


class _Structure:
    def __init__(self) -> None:
        self.found: list[Found] = []

    def add(self, code: str, offset: int, args: dict[str, Any] | None = None) -> None:
        self.found.append((code, offset, args or {}))

    def run(self, tree: Formula) -> Found | None:
        # The response: a single name without a sign, or log() of a single name.
        if tree.lhs is not None:
            log_call = sole_call(tree.lhs, "log")
            valid = single_name(tree.lhs) or (log_call is not None and call_of_name(log_call))
            if not valid:
                self.add("E6012", tree.lhs.start)
            if log_call is not None:
                for arg in log_call.args:
                    self.walk_argument(arg, "other")
            else:
                self.walk_sum(tree.lhs, "other")
        for summand in tree.rhs.summands:
            self.walk_summand(summand, True)
        return first_issue(self.found)

    def stray_number(self, node: Number) -> None:
        """A number that is no intercept summand and no exponent."""
        if node.text in ("0", "1"):
            self.add("E6015", node.start, {"intercept": node.text})
        else:
            self.add("E6006", node.start, {"number": node.text})

    def walk_call_args(self, call: Call, offset_call: bool) -> None:
        """The arguments of a call. An argument of offset() that is log() of
        anything is in a place where log() is allowed."""
        for arg in call.args:
            log_call = sole_call(arg.lhs, "log") if offset_call and arg.bar is None else None
            if log_call is not None:
                for inner in log_call.args:
                    self.walk_argument(inner, "other")
            else:
                self.walk_argument(arg, "other")

    def walk_argument(self, arg: Argument, context: str) -> None:
        self.walk_sum(arg.lhs, context)
        if arg.bar is not None and arg.rhs is not None:
            self.walk_sum(arg.rhs, context)

    def walk_sum(self, node: Sum, context: str) -> None:
        for summand in node.summands:
            self.walk_expr(summand.expr, context)

    def walk_expr(self, node: Node, context: str) -> None:
        """An expression outside the summands that the rules treat specially.
        In a grouping, numbers fall under the rule of the grouping alone."""
        if isinstance(node, Number):
            if context != "grouping":
                self.stray_number(node)
        elif isinstance(node, Call):
            if node.name == "offset":
                self.add("E6019", node.start)
            elif node.name == "log":
                self.add("E6020", node.start)
            elif node.name in COVARIANCE_STRUCTURES:
                self.add("E6018", node.start, {"function": node.name})
            else:
                self.add("E6017", node.start, {"function": node.name})
            self.walk_call_args(node, node.name == "offset")
        elif isinstance(node, Paren):
            if is_random(node):
                self.add("E6014", node.start)
                self.walk_random(node)
            else:
                self.walk_sum(node.arg.lhs, context)
        elif isinstance(node, Chain):
            for operand in node.operands:
                self.walk_expr(operand, context)
        elif isinstance(node, Power):
            self.walk_expr(node.base, context)
            exponent = node.exponent
            if context == "grouping":
                self.walk_expr(exponent, context)
            elif isinstance(exponent, Number):
                text = exponent.text
                if text.startswith("0") or len(text) > 4 or not 2 <= int(text) <= 1000:
                    self.add("E6006", exponent.start, {"number": text})
            else:
                self.add("E6006", exponent.start, {"number": _first_token_text(exponent)})
                self.walk_expr(exponent, context)

    def walk_summand(self, summand: Summand, top: bool) -> None:
        """A summand of the sum after '~' or of the left-hand side of a random term."""
        expr = summand.expr
        if isinstance(expr, Number):
            if expr.text not in ("0", "1"):
                self.add("E6006", expr.start, {"number": expr.text})
            elif summand.sign == "-" and expr.text == "0":
                assert summand.sign_at is not None
                self.add("E6015", summand.sign_at, {"intercept": "- 0"})
        elif isinstance(expr, Paren) and is_random(expr):
            if not top or summand.sign == "-":
                self.add("E6014", expr.start)
            self.walk_random(expr)
        elif isinstance(expr, Call) and expr.name == "offset":
            arg_ok = False
            if len(expr.args) == 1 and expr.args[0].bar is None:
                lhs = expr.args[0].lhs
                log_call = sole_call(lhs, "log")
                arg_ok = single_name(lhs) or (log_call is not None and call_of_name(log_call))
            if not top or summand.sign == "-" or not arg_ok:
                self.add("E6019", expr.start)
            self.walk_call_args(expr, True)
        else:
            self.walk_expr(expr, "other")

    def walk_random(self, node: Paren) -> None:
        """The left-hand side and grouping of a random term."""
        for summand in node.arg.lhs.summands:
            self.walk_summand(summand, False)
        grouping = node.arg.rhs
        assert grouping is not None
        offsets: list[int] = []
        for summand in grouping.summands:
            if summand.sign_at is not None:
                offsets.append(summand.sign_at)
            stack: list[Node] = [summand.expr]
            while stack:
                expr = stack.pop()
                if isinstance(expr, Number | Call | Paren):
                    offsets.append(expr.start)
                elif isinstance(expr, Chain):
                    offsets.extend(at for op, at in expr.ops if op not in (":", "/"))
                    stack.extend(expr.operands)
                elif isinstance(expr, Power):
                    offsets.append(expr.at)
                    stack.extend((expr.base, expr.exponent))
        if offsets:
            self.add("E6016", min(offsets))
        self.walk_sum(grouping, "grouping")


def _first_token_text(node: Node) -> str:
    """The text of the first token of an exponent that is not a number."""
    if isinstance(node, Name):
        return "`" + node.value + "`" if node.quoted else node.value
    if isinstance(node, Call):
        return node.name
    if isinstance(node, Paren):
        return "("
    if isinstance(node, Number):
        return node.text
    return _first_token_text(node.operands[0] if isinstance(node, Chain) else node.base)
