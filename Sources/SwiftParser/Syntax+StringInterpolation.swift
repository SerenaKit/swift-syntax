@_spi(RawSyntax)
import SwiftSyntax

fileprivate class Indenter: SyntaxRewriter {
  let indentation: Trivia

  init(indentation: Trivia) {
    self.indentation = indentation
  }

  /// Adds `indentation` after all newlines in the syntax tree.
  public static func indent<SyntaxType: SyntaxProtocol>(
    _ node: SyntaxType,
    indentation: Trivia
  ) -> SyntaxType {
    return Indenter(indentation: indentation).visit(Syntax(node)).as(SyntaxType.self)!
  }

  public override func visit(_ token: TokenSyntax) -> Syntax {
    return Syntax(TokenSyntax(
      token.tokenKind,
      leadingTrivia: indent(trivia: token.leadingTrivia),
      trailingTrivia: indent(trivia: token.trailingTrivia),
      presence: token.presence
    ))
  }

  private func indent(trivia: Trivia) -> Trivia {
    let mappedPieces = trivia.flatMap { (piece) -> [TriviaPiece] in
      if piece.isNewline {
        return [piece] + indentation.pieces
      } else {
        return [piece]
      }
    }
    return Trivia(pieces: mappedPieces)
  }
}


/// An individual interpolated syntax node.
struct InterpolatedSyntaxNode {
  let node: Syntax
  let startIndex: Int
  let endIndex: Int
}

/// The string interpolation type used for creating syntax nodes.
public struct SyntaxStringInterpolation {
  /// The source text in UTF-8.
  ///
  /// We use an array of UTF-8 for the representation of the source text
  /// because that's what the parser uses, and we need the stable indices
  /// that arrays provide when appending new nodes to this array.
  var sourceText: [UInt8] = []

  /// If we appended a string literal last and the last line only consisted of
  /// whitespace, that trivia. This allows us to apply this indentation to all
  /// lines of an interpolated syntax node.
  var lastIndentation: Trivia?

  /// Tracks of all of the syntax nodes that were interpolated into the
  /// syntax.
  ///
  /// For each node, we record the syntax node, its start position within the
  /// source text, and its UTF-8 length.
  var interpolatedSyntaxNodes: [InterpolatedSyntaxNode] = []
}

extension SyntaxStringInterpolation: StringInterpolationProtocol {
  public init(literalCapacity: Int, interpolationCount: Int) {
    interpolatedSyntaxNodes.reserveCapacity(interpolationCount)
  }

  /// Append source text to the interpolation.
  public mutating func appendLiteral(_ text: String) {
    sourceText.append(contentsOf: text.utf8)
    let lines = text.split(whereSeparator: \.isNewline)
    if let lastLine = lines.last, lastLine.allSatisfy({ $0 == " " }) {
      self.lastIndentation = .spaces(lastLine.count)
    } else if let lastLine = lines.last, lastLine.allSatisfy({ $0 == "\t" }) {
      self.lastIndentation = .tabs(lastLine.count)
    } else {
      self.lastIndentation = nil
    }
  }

  /// Append a syntax node to the interpolation.
  public mutating func appendInterpolation<Node: SyntaxProtocol>(
    _ node: Node
  ) {
    let startIndex = sourceText.count
    let indentedNode: Node
    if let lastIndentation = lastIndentation {
      indentedNode = Indenter.indent(node, indentation: lastIndentation)
    } else {
      indentedNode = node
    }
    sourceText.append(contentsOf: indentedNode.syntaxTextBytes)
    interpolatedSyntaxNodes.append(
      .init(
        node: Syntax(indentedNode), startIndex: startIndex, endIndex: sourceText.count
      )
    )
    self.lastIndentation = nil
  }

  // Append a value of any CustomStringConvertible type as source text.
  public mutating func appendInterpolation<T: CustomStringConvertible>(
    _ value: T
  ) {
    sourceText.append(contentsOf: value.description.utf8)
    self.lastIndentation = nil
  }
}

/// Syntax nodes that can be formed by a string interpolation involve source
/// code and interpolated syntax nodes.
public protocol SyntaxExpressibleByStringInterpolation:
    ExpressibleByStringInterpolation, SyntaxProtocol
    where Self.StringInterpolation == SyntaxStringInterpolation {
  /// Create an instance of this syntax node by parsing it from the given
  /// parser.
  static func parse(from parser: inout Parser) -> Self
}

extension SyntaxExpressibleByStringInterpolation {
  /// Initialize a syntax node by parsing the contents of the interpolation.
  public init(stringInterpolation: SyntaxStringInterpolation) {
    self = stringInterpolation.sourceText.withUnsafeBufferPointer { buffer in
      var parser = Parser(buffer)
      // FIXME: When the parser supports incremental parsing, put the
      // interpolatedSyntaxNodes in so we don't have to parse them again.
      return Self.parse(from: &parser)
    }
  }

  /// Initialize a syntax node from a string literal.
  public init(stringLiteral value: String) {
    var interpolation = SyntaxStringInterpolation()
    interpolation.appendLiteral(value)
    self.init(stringInterpolation: interpolation)
  }
}

private func castRawToSyntaxNode<OutputType: SyntaxProtocol, RawType: RawSyntaxNodeProtocol>(_ raw: RawType) -> OutputType {
  let syntax = Syntax(raw: raw.raw)
  guard let result = syntax.as(OutputType.self) else {
    fatalError("Parsing was expected to produce a \(OutputType.self) but produced \(type(of: syntax.asProtocol(SyntaxProtocol.self)))")
  }
  return result
}

// Parsing support for the main kinds of syntax nodes.
extension DeclSyntaxProtocol {
  public static func parse(from parser: inout Parser) -> Self {
    return castRawToSyntaxNode(parser.parseDeclaration())
  }
}

extension ExprSyntaxProtocol {
  public static func parse(from parser: inout Parser) -> Self {
    return castRawToSyntaxNode(parser.parseExpression())
  }
}

extension StmtSyntaxProtocol {
  public static func parse(from parser: inout Parser) -> Self {
    return castRawToSyntaxNode(parser.parseStatement())
  }
}

extension TypeSyntaxProtocol {
  public static func parse(from parser: inout Parser) -> Self {
    return castRawToSyntaxNode(parser.parseType())
  }
}

extension PatternSyntaxProtocol {
  public static func parse(from parser: inout Parser) -> Self {
    return castRawToSyntaxNode(parser.parsePattern())
  }
}

// String interpolation support for the primary node kinds.
extension SourceFileSyntax: SyntaxExpressibleByStringInterpolation {
  public static func parse(from parser: inout Parser) -> Self {
    return castRawToSyntaxNode(parser.parseSourceFile())
  }
}

extension DeclSyntax: SyntaxExpressibleByStringInterpolation { }
extension ExprSyntax: SyntaxExpressibleByStringInterpolation { }
extension StmtSyntax: SyntaxExpressibleByStringInterpolation { }
extension TypeSyntax: SyntaxExpressibleByStringInterpolation { }
extension PatternSyntax: SyntaxExpressibleByStringInterpolation { }
extension FunctionDeclSyntax: SyntaxExpressibleByStringInterpolation { }
extension ReturnStmtSyntax: SyntaxExpressibleByStringInterpolation { }
extension SwitchStmtSyntax: SyntaxExpressibleByStringInterpolation { }
extension FunctionSignatureSyntax: SyntaxExpressibleByStringInterpolation {
  public static func parse(from parser: inout Parser) -> SwiftSyntax.FunctionSignatureSyntax {
    return castRawToSyntaxNode(parser.parseFunctionSignature())
  }
}
extension SwitchCaseSyntax: SyntaxExpressibleByStringInterpolation {
  public static func parse(from parser: inout Parser) -> SwiftSyntax.SwitchCaseSyntax {
    return castRawToSyntaxNode(parser.parseSwitchCase())
  }
}
