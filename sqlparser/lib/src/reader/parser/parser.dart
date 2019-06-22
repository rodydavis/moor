import 'package:meta/meta.dart';
import 'package:sqlparser/src/ast/ast.dart';
import 'package:sqlparser/src/reader/tokenizer/token.dart';

part 'num_parser.dart';

const _comparisonOperators = [
  TokenType.less,
  TokenType.lessEqual,
  TokenType.more,
  TokenType.moreEqual,
];
const _binaryOperators = const [
  TokenType.shiftLeft,
  TokenType.shiftRight,
  TokenType.ampersand,
  TokenType.pipe,
];

class ParsingError implements Exception {
  final Token token;
  final String message;

  ParsingError(this.token, this.message);

  @override
  String toString() {
    return token.span.message('Error: $message}');
  }
}

// todo better error handling and synchronisation, like it's done here:
// https://craftinginterpreters.com/parsing-expressions.html#synchronizing-a-recursive-descent-parser

class Parser {
  final List<Token> tokens;
  final List<ParsingError> errors = [];
  int _current = 0;

  Parser(this.tokens);

  bool get _isAtEnd => _peek.type == TokenType.eof;
  Token get _peek => tokens[_current];
  Token get _previous => tokens[_current - 1];

  bool _match(List<TokenType> types) {
    for (var type in types) {
      if (_check(type)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  bool _check(TokenType type) {
    if (_isAtEnd) return false;
    return _peek.type == type;
  }

  Token _advance() {
    if (!_isAtEnd) {
      _current++;
    }
    return _previous;
  }

  @alwaysThrows
  void _error(String message) {
    final error = ParsingError(_peek, message);
    errors.add(error);
    throw error;
  }

  Token _consume(TokenType type, String message) {
    if (_check(type)) return _advance();
    _error(message);
  }

  /// Parses a [SelectStatement], or returns null if there is no select token
  /// after the current position.
  ///
  /// See also:
  /// https://www.sqlite.org/lang_select.html
  SelectStatement select() {
    if (!_match(const [TokenType.select])) return null;

    // todo parse result column
    final resultColumns = <ResultColumn>[];
    do {
      resultColumns.add(_resultColumn());
    } while (_match(const [TokenType.comma]));

    final where = _where();
    final orderBy = _orderBy();
    final limit = _limit();

    return SelectStatement(
        where: where, columns: resultColumns, orderBy: orderBy, limit: limit);
  }

  /// Parses a [ResultColumn] or throws if none is found.
  /// https://www.sqlite.org/syntax/result-column.html
  ResultColumn _resultColumn() {
    if (_match(const [TokenType.star])) {
      return StarResultColumn(null);
    }

    final positionBefore = _current;

    if (_match(const [TokenType.identifier])) {
      // two options. the identifier could be followed by ".*", in which case
      // we have a star result column. If it's followed by anything else, it can
      // still refer to a column in a table as part of a expression result column
      final identifier = _previous;

      if (_match(const [TokenType.dot]) && _match(const [TokenType.star])) {
        return StarResultColumn((identifier as IdentifierToken).identifier);
      }

      // not a star result column. go back and parse the expression.
      // todo this is a bit unorthodox. is there a better way to parse the
      // expression from before?
      _current = positionBefore;
    }

    final expr = expression();
    // todo in sqlite, the as is optional
    if (_match(const [TokenType.as])) {
      if (_match(const [TokenType.identifier])) {
        final identifier = (_previous as IdentifierToken).identifier;
        return ExpressionResultColumn(expression: expr, as: identifier);
      } else {
        throw ParsingError(_peek, 'Expected an identifier as the column name');
      }
    }

    return ExpressionResultColumn(expression: expr);
  }

  /// Parses a where clause if there is one at the current position
  Expression _where() {
    if (_match(const [TokenType.where])) {
      return expression();
    }
    return null;
  }

  OrderBy _orderBy() {
    if (_match(const [TokenType.order])) {
      _consume(TokenType.by, 'Expected "BY" after "ORDER" token');
      final terms = <OrderingTerm>[];
      do {
        terms.add(_orderingTerm());
      } while (_match(const [TokenType.comma]));
    }
    return null;
  }

  OrderingTerm _orderingTerm() {
    final expr = expression();

    if (_match(const [TokenType.asc, TokenType.desc])) {
      final mode = _previous.type == TokenType.asc
          ? OrderingMode.ascending
          : OrderingMode.descending;
      return OrderingTerm(expression: expr, orderingMode: mode);
    }

    return OrderingTerm(expression: expr);
  }

  /// Parses a [Limit] clause, or returns null if there is no limit token after
  /// the current position.
  Limit _limit() {
    if (!_match(const [TokenType.limit])) return null;

    final count = expression();
    Token offsetSep;
    Expression offset;

    if (_match(const [TokenType.comma, TokenType.offset])) {
      offsetSep = _previous;
      offset = expression();
    }

    return Limit(count: count, offsetSeparator: offsetSep, offset: offset);
  }

  /* We parse expressions here.
  * Operators have the following precedence:
  *  - + ~ NOT (unary)
  *  || (concatenation)
  *  * / %
  *  + -
  *  << >> & |
  *  < <= > >=
  *  = == != <> IS IS NOT  IN LIKE GLOB MATCH REGEXP
  *  AND
  *  OR
  *  We also treat expressions in parentheses and literals with the highest
  *  priority. Parsing methods are written in ascending precedence, and each
  *  parsing method calls the next higher precedence if unsuccessful.
  *  https://www.sqlite.org/lang_expr.html
  * */

  Expression expression() {
    return _or();
  }

  /// Parses an expression of the form a <T> b, where <T> is in [types] and
  /// both a and b are expressions with a higher precedence parsed from
  /// [higherPrecedence].
  Expression _parseSimpleBinary(
      List<TokenType> types, Expression Function() higherPrecedence) {
    var expression = higherPrecedence();

    while (_match(types)) {
      final operator = _previous;
      final right = higherPrecedence();
      expression = BinaryExpression(expression, operator, right);
    }
    return expression;
  }

  Expression _or() => _parseSimpleBinary(const [TokenType.or], _and);
  Expression _and() => _parseSimpleBinary(const [TokenType.and], _equals);

  Expression _equals() {
    var expression = _comparison();
    final ops = const [
      TokenType.equal,
      TokenType.doubleEqual,
      TokenType.exclamationEqual,
      TokenType.lessMore,
      TokenType.$is,
      TokenType.$in,
      TokenType.like,
      TokenType.glob,
      TokenType.match,
      TokenType.regexp,
    ];

    while (_match(ops)) {
      final operator = _previous;
      if (operator.type == TokenType.$is) {
        final not = _match(const [TokenType.not]);
        // special case: is not expression
        expression = IsExpression(not, expression, _comparison());
      } else {
        expression = BinaryExpression(expression, operator, _comparison());
      }
    }
    return expression;
  }

  Expression _comparison() {
    return _parseSimpleBinary(_comparisonOperators, _binaryOperation);
  }

  Expression _binaryOperation() {
    return _parseSimpleBinary(_binaryOperators, _addition);
  }

  Expression _addition() {
    return _parseSimpleBinary(const [
      TokenType.plus,
      TokenType.minus,
    ], _multiplication);
  }

  Expression _multiplication() {
    return _parseSimpleBinary(const [
      TokenType.star,
      TokenType.slash,
      TokenType.percent,
    ], _concatenation);
  }

  Expression _concatenation() {
    return _parseSimpleBinary(const [TokenType.doublePipe], _unary);
  }

  Expression _unary() {
    if (_match(const [
      TokenType.minus,
      TokenType.plus,
      TokenType.tilde,
      TokenType.not
    ])) {
      final operator = _previous;
      final expression = _unary();
      return UnaryExpression(operator, expression);
    }

    return _primary();
  }

  Expression _primary() {
    final token = _advance();
    final type = token.type;
    switch (type) {
      case TokenType.numberLiteral:
        return NumericLiteral(_parseNumber(token.lexeme), _peek);
      case TokenType.stringLiteral:
        final token = _peek as StringLiteralToken;
        return StringLiteral(token);
      case TokenType.$null:
        return NullLiteral(_peek);
      case TokenType.$true:
        return BooleanLiteral.withTrue(_peek);
      case TokenType.$false:
        return BooleanLiteral.withFalse(_peek);
      // todo CURRENT_TIME, CURRENT_DATE, CURRENT_TIMESTAMP
      case TokenType.leftParen:
        final left = _previous;
        final expr = expression();
        _consume(TokenType.rightParen, 'Expected a closing bracket');
        return Parentheses(left, expr, _previous);
      case TokenType.identifier:
        final first = _previous as IdentifierToken;
        if (_match(const [TokenType.dot])) {
          final second =
              _consume(TokenType.identifier, 'Expected a column name here')
                  as IdentifierToken;
          return Reference(
              tableName: first.identifier, columnName: second.identifier);
        } else {
          return Reference(columnName: first.identifier);
        }
        break;
      default:
        break;
    }

    // nothing found -> issue error
    _error('Could not parse this expression');
  }
}