//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SyntaxSupport
import Utils

let tokenFile = SourceFile {
  ImportDecl(
    leadingTrivia: .docLineComment(copyrightHeader),
    path: [AccessPathComponent(name: "SwiftSyntax")]
  )

  ExtensionDecl(modifiers: [DeclModifier(name: .public)], extendedType: Type("TokenSyntax")) {
    for token in SYNTAX_TOKENS {
      if token.isKeyword {
        VariableDecl("""
          /// The `\(token.text!)` keyword
          static var \(token.name.withFirstCharacterLowercased.backticked): Token {
            return .\(token.swiftKind)()
          }
          """
        )
      } else if let text = token.text {
        VariableDecl("""
          /// The `\(text)` token
          static var \(token.name.withFirstCharacterLowercased.backticked): TokenSyntax {
            return .\(token.swiftKind)Token()
          }
          """
        )
      }
    }
    VariableDecl("""
      /// The `eof` token
      static var eof: TokenSyntax {
        return .eof()
      }
      """
    )

    VariableDecl("""
      /// The `open` contextual token
      static var open: TokenSyntax {
        return .contextualKeyword("open").withTrailingTrivia(.space)
      }
      """
    )
  }
}
