/// A small LaTeX maths parser for `data-mx-maths` (Matrix v1.11, MSC2191).
///
/// It covers the common subset: fractions, super- and subscripts, roots,
/// Greek letters, operators and relations, function names, `\left`/`\right`
/// groups, `\text` and spacing. Anything else throws [LatexParseException],
/// so the caller can show the source instead.
library;

class LatexParseException implements Exception {
  final String message;
  const LatexParseException(this.message);

  @override
  String toString() => 'LatexParseException: $message';
}

enum MathSymbolKind { variable, number, operator, relation, punctuation, text }

sealed class MathNode {
  const MathNode();
}

class MathSymbol extends MathNode {
  final String text;
  final MathSymbolKind kind;
  const MathSymbol(this.text, this.kind);
}

class MathRow extends MathNode {
  final List<MathNode> children;
  const MathRow(this.children);
}

class MathFraction extends MathNode {
  final MathNode numerator;
  final MathNode denominator;
  const MathFraction(this.numerator, this.denominator);
}

class MathRoot extends MathNode {
  final MathNode body;
  final MathNode? index;
  const MathRoot(this.body, this.index);
}

class MathScripts extends MathNode {
  final MathNode base;
  final MathNode? superscript;
  final MathNode? subscript;
  const MathScripts(this.base, this.superscript, this.subscript);
}

class MathDelimited extends MathNode {
  final String left;
  final MathNode body;
  final String right;
  const MathDelimited(this.left, this.body, this.right);
}

class MathSpace extends MathNode {
  /// Width in em.
  final double width;
  const MathSpace(this.width);
}

class MathStyled extends MathNode {
  final MathNode child;
  final bool bold;
  final bool upright;
  const MathStyled(this.child, {this.bold = false, this.upright = false});
}

class LatexParser {
  static const int maxLength = 1000;
  static const int maxDepth = 24;

  static const greek = {
    'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', //
    'epsilon': 'ϵ', 'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
    'theta': 'θ', 'vartheta': 'ϑ', 'iota': 'ι', 'kappa': 'κ',
    'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π',
    'varpi': 'ϖ', 'rho': 'ρ', 'varrho': 'ϱ', 'sigma': 'σ',
    'varsigma': 'ς', 'tau': 'τ', 'upsilon': 'υ', 'phi': 'ϕ',
    'varphi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
    'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ',
    'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ', 'Phi': 'Φ', 'Psi': 'Ψ',
    'Omega': 'Ω',
  };

  static const operators = {
    'times': '×', 'cdot': '⋅', 'div': '÷', 'pm': '±', 'mp': '∓', //
    'ast': '∗', 'star': '⋆', 'circ': '∘', 'bullet': '∙', 'cup': '∪',
    'cap': '∩', 'setminus': '∖', 'wedge': '∧', 'vee': '∨', 'oplus': '⊕',
    'otimes': '⊗', 'land': '∧', 'lor': '∨',
  };

  static const relations = {
    'leq': '≤', 'le': '≤', 'geq': '≥', 'ge': '≥', 'neq': '≠', 'ne': '≠', //
    'approx': '≈', 'equiv': '≡', 'sim': '∼', 'simeq': '≃', 'cong': '≅',
    'propto': '∝', 'll': '≪', 'gg': '≫', 'in': '∈', 'notin': '∉',
    'ni': '∋', 'subset': '⊂', 'supset': '⊃', 'subseteq': '⊆',
    'supseteq': '⊇', 'to': '→', 'rightarrow': '→', 'leftarrow': '←',
    'gets': '←', 'leftrightarrow': '↔', 'Rightarrow': '⇒',
    'Leftarrow': '⇐', 'Leftrightarrow': '⇔', 'implies': '⟹',
    'iff': '⟺', 'mapsto': '↦', 'mid': '∣', 'parallel': '∥',
    'perp': '⊥',
  };

  static const symbols = {
    'infty': '∞', 'partial': '∂', 'nabla': '∇', 'forall': '∀', //
    'exists': '∃', 'emptyset': '∅', 'varnothing': '∅', 'hbar': 'ℏ',
    'ell': 'ℓ', 'Re': 'ℜ', 'Im': 'ℑ', 'aleph': 'ℵ', 'angle': '∠',
    'degree': '°', 'prime': '′', 'neg': '¬', 'lnot': '¬',
    'ldots': '…', 'dots': '…', 'cdots': '⋯', 'vdots': '⋮',
    'ddots': '⋱', 'sum': '∑', 'prod': '∏', 'coprod': '∐', 'int': '∫',
    'iint': '∬', 'iiint': '∭', 'oint': '∮', 'bigcup': '⋃',
    'bigcap': '⋂', 'langle': '⟨', 'rangle': '⟩', 'lfloor': '⌊',
    'rfloor': '⌋', 'lceil': '⌈', 'rceil': '⌉', 'vert': '|', 'Vert': '‖',
    'lbrace': '{', 'rbrace': '}',
  };

  static const functions = {
    'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'arcsin', 'arccos', //
    'arctan', 'sinh', 'cosh', 'tanh', 'log', 'ln', 'lg', 'exp', 'lim',
    'liminf', 'limsup', 'max', 'min', 'sup', 'inf', 'det', 'dim', 'ker',
    'gcd', 'deg', 'arg', 'mod', 'Pr',
  };

  static const spaces = {
    ',': 0.17,
    ':': 0.22,
    '>': 0.22,
    ';': 0.28,
    ' ': 0.33,
    '!': -0.17,
    'quad': 1.0,
    'qquad': 2.0,
    'enspace': 0.5,
    'thinspace': 0.17,
  };

  static const _escapedCharacters = {'{', '}', '%', '#', '&', '_', r'$', '|'};

  final String _source;
  int _position = 0;
  int _depth = 0;

  LatexParser._(this._source);

  static MathNode parse(String source) {
    if (source.length > maxLength) {
      throw const LatexParseException('formula too long');
    }
    if (source.trim().isEmpty) {
      throw const LatexParseException('empty formula');
    }
    final parser = LatexParser._(source);
    final row = parser._parseRow();
    if (!parser._atEnd) {
      throw LatexParseException('unexpected "${parser._peek}"');
    }
    return row;
  }

  bool get _atEnd => _position >= _source.length;
  String get _peek => _source[_position];

  void _skipSpaces() {
    while (!_atEnd && _peek.trim().isEmpty) {
      _position++;
    }
  }

  /// Parses atoms until the end, a closing `}`, `]` (when [untilBracket]) or
  /// `\right`.
  MathRow _parseRow({bool untilBracket = false}) {
    if (++_depth > maxDepth) {
      throw const LatexParseException('formula nested too deeply');
    }
    final children = <MathNode>[];
    while (true) {
      _skipSpaces();
      if (_atEnd || _peek == '}' || (untilBracket && _peek == ']')) break;
      if (_source.startsWith(r'\right', _position)) break;
      children.add(_parseScripts(_parseAtom()));
    }
    _depth--;
    return MathRow(children);
  }

  MathNode _parseScripts(MathNode base) {
    MathNode? superscript;
    MathNode? subscript;
    while (true) {
      _skipSpaces();
      if (_atEnd || (_peek != '^' && _peek != '_')) break;
      final isSuper = _peek == '^';
      _position++;
      if ((isSuper ? superscript : subscript) != null) {
        throw LatexParseException('double ${isSuper ? '^' : '_'}');
      }
      final argument = _parseArgument();
      if (isSuper) {
        superscript = argument;
      } else {
        subscript = argument;
      }
    }
    if (superscript == null && subscript == null) return base;
    return MathScripts(base, superscript, subscript);
  }

  /// One argument: a `{...}` group or a single atom.
  MathNode _parseArgument() {
    _skipSpaces();
    if (_atEnd) throw const LatexParseException('missing argument');
    if (_peek == '}' || _peek == '^' || _peek == '_') {
      throw LatexParseException('unexpected "$_peek"');
    }
    return _parseAtom(single: true);
  }

  MathNode _parseGroup() {
    _position++; // {
    final row = _parseRow();
    _expect('}');
    return row;
  }

  void _expect(String character) {
    if (_atEnd || _peek != character) {
      throw LatexParseException('expected "$character"');
    }
    _position++;
  }

  /// With [single], a number is one digit: `\frac12` is 1 over 2.
  MathNode _parseAtom({bool single = false}) {
    final character = _peek;
    if (character == '{') return _parseGroup();
    if (character == '\\') return _parseCommand();
    if (character == '^' || character == '_') {
      return const MathRow([]); // A script with no base, as LaTeX allows.
    }
    _position++;
    if (RegExp(r'[0-9.]').hasMatch(character)) {
      final buffer = StringBuffer(character);
      while (!single && !_atEnd && RegExp(r'[0-9.]').hasMatch(_peek)) {
        buffer.write(_source[_position++]);
      }
      return MathSymbol(buffer.toString(), MathSymbolKind.number);
    }
    if (RegExp(r'[A-Za-z]').hasMatch(character)) {
      return MathSymbol(character, MathSymbolKind.variable);
    }
    switch (character) {
      case '+' || '/':
        return MathSymbol(character, MathSymbolKind.operator);
      case '-':
        return const MathSymbol('−', MathSymbolKind.operator);
      case '*':
        return const MathSymbol('∗', MathSymbolKind.operator);
      case '=' || '<' || '>':
        return MathSymbol(character, MathSymbolKind.relation);
      case ',' || ';':
        return MathSymbol(character, MathSymbolKind.punctuation);
      case "'":
        return const MathSymbol('′', MathSymbolKind.text);
      case '~':
        return const MathSpace(0.33);
      case '&' || '#' || '%' || '}' || r'$':
        throw LatexParseException('unexpected "$character"');
    }
    return MathSymbol(character, MathSymbolKind.text);
  }

  String _readCommandName() {
    _position++; // backslash
    if (_atEnd) throw const LatexParseException('lone backslash');
    final start = _position;
    while (!_atEnd && RegExp(r'[A-Za-z]').hasMatch(_peek)) {
      _position++;
    }
    if (_position == start) _position++; // A one character command: \, \{
    return _source.substring(start, _position);
  }

  MathNode _parseCommand() {
    final name = _readCommandName();

    if (spaces.containsKey(name)) return MathSpace(spaces[name]!);
    if (_escapedCharacters.contains(name)) {
      return MathSymbol(name, MathSymbolKind.text);
    }
    if (greek.containsKey(name)) {
      final letter = greek[name]!;
      final upper = letter.toUpperCase() == letter;
      return MathSymbol(
          letter, upper ? MathSymbolKind.text : MathSymbolKind.variable);
    }
    if (operators.containsKey(name)) {
      return MathSymbol(operators[name]!, MathSymbolKind.operator);
    }
    if (relations.containsKey(name)) {
      return MathSymbol(relations[name]!, MathSymbolKind.relation);
    }
    if (symbols.containsKey(name)) {
      return MathSymbol(symbols[name]!, MathSymbolKind.text);
    }
    if (functions.contains(name)) {
      return MathSymbol(name, MathSymbolKind.text);
    }

    switch (name) {
      case 'frac' || 'dfrac' || 'tfrac' || 'cfrac':
        final numerator = _parseArgument();
        return MathFraction(numerator, _parseArgument());
      case 'sqrt':
        MathNode? index;
        _skipSpaces();
        if (!_atEnd && _peek == '[') {
          _position++;
          index = _parseRow(untilBracket: true);
          _expect(']');
        }
        return MathRoot(_parseArgument(), index);
      case 'left':
        final left = _parseDelimiter();
        final body = _parseRow();
        if (!_source.startsWith(r'\right', _position)) {
          throw const LatexParseException(r'\left without \right');
        }
        _readCommandName();
        return MathDelimited(left, body, _parseDelimiter());
      case 'text' || 'textrm' || 'mathrm' || 'operatorname' || 'mbox':
        return MathSymbol(_parseRawText(), MathSymbolKind.text);
      case 'textbf':
        return MathStyled(MathSymbol(_parseRawText(), MathSymbolKind.text),
            bold: true);
      case 'mathbf' || 'boldsymbol':
        return MathStyled(_parseArgument(), bold: true, upright: true);
      case 'mathit':
        return _parseArgument();
    }
    throw LatexParseException('unknown command \\$name');
  }

  String _parseDelimiter() {
    _skipSpaces();
    if (_atEnd) throw const LatexParseException('missing delimiter');
    if (_peek == '\\') {
      final name = _readCommandName();
      if (name == '{' || name == '}' || name == '|') return name;
      final symbol = symbols[name];
      if (symbol == null) {
        throw LatexParseException('unknown delimiter \\$name');
      }
      return symbol;
    }
    final character = _source[_position++];
    if (!'()[]|./<>'.contains(character)) {
      throw LatexParseException('unknown delimiter "$character"');
    }
    return character == '.' ? '' : character;
  }

  /// The text of a `{...}` argument, braces balanced, without parsing.
  String _parseRawText() {
    _skipSpaces();
    _expect('{');
    final start = _position;
    var level = 1;
    while (!_atEnd) {
      final character = _source[_position];
      if (character == '\\') {
        _position += 2;
        continue;
      }
      if (character == '{') level++;
      if (character == '}' && --level == 0) {
        final text = _source.substring(start, _position);
        _position++;
        return text.replaceAllMapped(
            RegExp(r'\\([{}%#&_$])'), (match) => match.group(1)!);
      }
      _position++;
    }
    throw const LatexParseException('unclosed text');
  }
}
