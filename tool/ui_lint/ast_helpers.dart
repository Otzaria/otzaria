import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// קריאה לבנאי (או למתודה סטטית בצורת `Type.name(...)`) ב-AST לא מפוענח.
///
/// `parseString` לא יודע מה הוא מחלקה: `Foo(...)` בלי `new`/`const` נקרא
/// כ-[MethodInvocation] ולא כ-[InstanceCreationExpression]. כל כלל שמחפש בנאי
/// חייב לעבור דרך [asCtorCall], אחרת הוא לא ימצא דבר.
class CtorCall {
  const CtorCall({
    required this.node,
    required this.typeName,
    required this.constructor,
    required this.importPrefix,
    required this.arguments,
  });

  final Expression node;
  final String typeName;

  /// `circular` ב-`BorderRadius.circular(...)`; null לבנאי הלא-שמי.
  final String? constructor;

  /// `pw` ב-`pw.TextStyle(...)`.
  final String? importPrefix;
  final ArgumentList arguments;

  /// הארגומנט בשם [name], אם הועבר.
  Expression? named(String name) {
    for (final argument in arguments.arguments) {
      if (argument is NamedArgument && argument.name.lexeme == name) {
        return argument.argumentExpression;
      }
    }
    return null;
  }

  Iterable<Expression> get positional =>
      arguments.arguments.whereType<Expression>();

  /// `prefix.Type.named`, בלי הארגומנטים.
  String get head => [?importPrefix, typeName, ?constructor].join('.');
}

bool _isTypeName(String name) {
  final start = name.startsWith('_') ? name.substring(1) : name;
  if (start.isEmpty) return false;
  final first = start[0];
  return first.toUpperCase() == first && first.toLowerCase() != first;
}

bool _isPrefixName(String name) => !_isTypeName(name);

/// מפרש את [node] כקריאת בנאי, או null כשאינו כזה.
///
/// prefix של ייבוא Flutter (`import 'package:flutter/material.dart' as m;`)
/// נמחק: `m.AlertDialog(...)` הוא אותו `AlertDialog(...)`, והכללים, שמדלגים על
/// קריאה עם prefix כדי לא לתפוס את `pw.*` של הייצוא, היו מפספסים אותו.
CtorCall? asCtorCall(AstNode node) {
  final call = _rawCtorCall(node);
  final prefix = call?.importPrefix;
  if (call == null ||
      prefix == null ||
      !flutterImportPrefixes(node.root).contains(prefix)) {
    return call;
  }
  return CtorCall(
    node: call.node,
    typeName: call.typeName,
    constructor: call.constructor,
    importPrefix: null,
    arguments: call.arguments,
  );
}

final _flutterPrefixes = Expando<Set<String>>();

/// ה-prefixes שהקובץ של [root] נותן לייבוא של `package:flutter/...`.
Set<String> flutterImportPrefixes(AstNode root) {
  if (root is! CompilationUnit) return const {};
  return _flutterPrefixes[root] ??= {
    for (final directive in root.directives)
      if (directive is ImportDirective &&
          (directive.uri.stringValue ?? '').startsWith('package:flutter/'))
        ?directive.prefix?.name,
  };
}

CtorCall? _rawCtorCall(AstNode node) {
  if (node is InstanceCreationExpression) {
    final type = node.constructorName.type;
    final prefix = type.importPrefix?.name.lexeme;
    // `const Foo.named()`: בלי פענוח המפרש קורא את `Foo` כ־prefix ואת `named`
    // כשם הטיפוס.
    if (prefix != null &&
        node.constructorName.name == null &&
        _isTypeName(prefix) &&
        !_isTypeName(type.name.lexeme)) {
      return CtorCall(
        node: node,
        typeName: prefix,
        constructor: type.name.lexeme,
        importPrefix: null,
        arguments: node.argumentList,
      );
    }
    return CtorCall(
      node: node,
      typeName: type.name.lexeme,
      constructor: node.constructorName.name?.name,
      importPrefix: type.importPrefix?.name.lexeme,
      arguments: node.argumentList,
    );
  }
  if (node is! MethodInvocation || node.isCascaded) return null;
  final method = node.methodName.name;
  final target = node.target;
  // Foo(...)
  if (target == null) {
    if (!_isTypeName(method)) return null;
    return CtorCall(
      node: node,
      typeName: method,
      constructor: null,
      importPrefix: null,
      arguments: node.argumentList,
    );
  }
  if (target is SimpleIdentifier) {
    final name = target.name;
    // Foo.named(...)
    if (_isTypeName(name)) {
      return CtorCall(
        node: node,
        typeName: name,
        constructor: method,
        importPrefix: null,
        arguments: node.argumentList,
      );
    }
    // prefix.Foo(...)
    if (_isTypeName(method)) {
      return CtorCall(
        node: node,
        typeName: method,
        constructor: null,
        importPrefix: name,
        arguments: node.argumentList,
      );
    }
    return null;
  }
  // prefix.Foo.named(...)
  if (target is PrefixedIdentifier &&
      _isPrefixName(target.prefix.name) &&
      _isTypeName(target.identifier.name)) {
    return CtorCall(
      node: node,
      typeName: target.identifier.name,
      constructor: method,
      importPrefix: target.prefix.name,
      arguments: node.argumentList,
    );
  }
  return null;
}

/// כל קריאות הבנאי של הטיפוסים [typeNames] בתוך [root], בכל הצורות.
List<CtorCall> ctorCallsNamed(AstNode root, Set<String> typeNames) {
  final collector = _CtorCollector(typeNames);
  root.accept(collector);
  return collector.calls;
}

class _CtorCollector extends RecursiveAstVisitor<void> {
  _CtorCollector(this.typeNames);

  final Set<String> typeNames;
  final calls = <CtorCall>[];

  void _check(Expression node) {
    final call = asCtorCall(node);
    if (call != null && typeNames.contains(call.typeName)) calls.add(call);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
    super.visitMethodInvocation(node);
  }
}

/// הקריאה לבנאי הקרובה ביותר שמקבלת את [node] כארגומנט (ישיר או עמוק).
CtorCall? enclosingCtorCall(AstNode node, bool Function(CtorCall) test) {
  for (AstNode? n = node.parent; n != null; n = n.parent) {
    if (n is ArgumentList) {
      final call = n.parent == null ? null : asCtorCall(n.parent!);
      if (call != null && test(call)) return call;
    }
    if (n is FunctionBody || n is ClassMember) return null;
  }
  return null;
}

/// האם [node] נמצא בתוך מחלקה שיורשת מ-[superclasses].
bool isInsideClassExtending(AstNode node, Set<String> superclasses) {
  final declaration = node.thisOrAncestorOfType<ClassDeclaration>();
  final superclass = declaration?.extendsClause?.superclass.name.lexeme;
  return superclass != null && superclasses.contains(superclass);
}

/// ליטרל מספרי, כולל שלילי.
bool isNumericLiteral(Expression expression) {
  final e = expression.unParenthesized;
  if (e is IntegerLiteral || e is DoubleLiteral) return true;
  return e is PrefixExpression &&
      e.operator.lexeme == '-' &&
      isNumericLiteral(e.operand);
}

/// `Class.member` של הצומת, לזיהוי יציב של חריגה בלי מספרי שורות.
String scopeOf(AstNode node) {
  String? member;
  String? type;
  for (AstNode? n = node.parent; n != null; n = n.parent) {
    switch (n) {
      case MethodDeclaration():
        member = n.name.lexeme;
      case FunctionDeclaration():
        member = n.name.lexeme;
      case ConstructorDeclaration():
        member = n.name?.lexeme ?? 'new';
      case VariableDeclaration()
          when n.parent?.parent is FieldDeclaration ||
              n.parent?.parent is TopLevelVariableDeclaration:
        member = n.name.lexeme;
      case ClassDeclaration():
        type = n.namePart.typeName.lexeme;
      case MixinDeclaration():
        type = n.name.lexeme;
      case ExtensionDeclaration():
        type = n.name?.lexeme ?? 'extension';
      case EnumDeclaration():
        type = n.namePart.typeName.lexeme;
      case ExtensionTypeDeclaration():
        type = n.namePart.typeName.lexeme;
      default:
        break;
    }
    if (type != null) break;
  }
  final scope = [?type, ?member].join('.');
  return scope.isEmpty ? '<top>' : scope;
}
