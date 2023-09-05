import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct WithViewStoreMacro: MemberMacro {
  public static func expansion<D: DeclGroupSyntax, C: MacroExpansionContext>(
    of node: AttributeSyntax,
    providingMembersOf declaration: D,
    in context: C
  ) throws -> [SwiftSyntax.DeclSyntax] {
    guard declaration.hasStoreVariable
    else {
      throw DiagnosticsError(diagnostics: [
        WithViewStoreDiagnostic.noStoreVariable(declaration).diagnose(at: Syntax(node))
      ])
    }

    declaration.diagnoseDirectStoreDotSend(
      declaration: declaration,
      context: context
    )

    guard
      case let .argumentList(arguments) = node.arguments,
      arguments.count == 1
    else { return [] }
    guard
      let memberAccessExpr = arguments.first?.expression.as(MemberAccessExprSyntax.self)
    else { return [] }
    let rawType = String("\(memberAccessExpr)".dropLast(5))

    return [
      """
      func send(_ action: \(raw: rawType).Action.View) {
      self.store.send(.view(action))
      }
      """
    ]
  }
}

struct SimpleDiagnosticMessage: DiagnosticMessage, Error {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity
}

extension SimpleDiagnosticMessage: FixItMessage {
  var fixItID: MessageID { diagnosticID }
}

extension SyntaxProtocol {
  func diagnoseDirectStoreDotSend<D: SyntaxProtocol>(
    declaration: D,
    context: some MacroExpansionContext
  ) {
    for decl in declaration.children(viewMode: .fixedUp) {
      if
        let memberAccess = decl.as(MemberAccessExprSyntax.self),
        let identifierSyntax = memberAccess.base?.as(DeclReferenceExprSyntax.self),
        identifierSyntax.baseName.text == "store",
        memberAccess.declName.baseName.text == "send"
      {
        context.diagnose(
          Diagnostic(
            node: Syntax(decl),
            message: WithViewStoreDiagnostic.hasDirectStoreDotSend
          )
        )
      }
      if
        let memberAccess = decl.as(MemberAccessExprSyntax.self),
        let selfMemberAccess = memberAccess.base?.as(MemberAccessExprSyntax.self),
        selfMemberAccess.declName.baseName.text == "store",
        memberAccess.declName.baseName.text == "send"
      {
        context.diagnose(
          Diagnostic(
            node: Syntax(decl),
            message: WithViewStoreDiagnostic.hasDirectStoreDotSend
          )
        )
      }
      decl.diagnoseDirectStoreDotSend(declaration: decl, context: context)
    }
  }
}

extension DeclGroupSyntax {
  fileprivate var hasStoreVariable: Bool {
    self.memberBlock.members.contains(where: { member in
      if
        let variableDecl = member.decl.as(VariableDeclSyntax.self),
        let firstBinding = variableDecl.bindings.first,
        let identifierPattern = firstBinding.pattern.as(IdentifierPatternSyntax.self),
        identifierPattern.identifier.text == "store"
      {
        return true
      } else {
        return false
      }
    })
  }
}

enum WithViewStoreDiagnostic {
  case hasDirectStoreDotSend
  case noStoreVariable(DeclGroupSyntax)
}

extension WithViewStoreDiagnostic: DiagnosticMessage {
  var message: String {
    switch self {
    case .hasDirectStoreDotSend:
      return """
      Do not use 'store.send' directly when using @WithViewStore. Instead, use 'send'.
      """
    case let .noStoreVariable(decl):
      return """
        @WithViewStore macro requires \(decl.identifierDescription.map { "'\($0)' " } ?? "")\
        to have a 'store' property of type 'Store'.
        """
    }
  }

  var diagnosticID: MessageID {
    switch self {
    case .hasDirectStoreDotSend:
      return MessageID(domain: "WithViewStoreDiagnostic", id: "hasDirectStoreDotSend")
    case .noStoreVariable:
      return MessageID(domain: "WithViewStoreDiagnostic", id: "noStoreVariable")
    }
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .hasDirectStoreDotSend:
      return .warning
    case .noStoreVariable:
      return .error
    }
  }

  func diagnose(at node: Syntax) -> Diagnostic {
    Diagnostic(node: node, message: self)
  }
}

extension DeclGroupSyntax {
  var identifierDescription: String? {
    switch self {
    case let syntax as ActorDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as ClassDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as ExtensionDeclSyntax:
      return syntax.extendedType.trimmedDescription
    case let syntax as ProtocolDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as StructDeclSyntax:
      return syntax.name.trimmedDescription
    case let syntax as EnumDeclSyntax:
      return syntax.name.trimmedDescription
    default:
      return nil
    }
  }
}