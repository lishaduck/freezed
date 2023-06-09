import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:collection/collection.dart';
import 'package:freezed/src/freezed_ast/freezed_ast.dart';
import 'package:freezed/src/freezed_ast/generation_backlog.dart';
import 'package:freezed/src/freezed_generator.dart' show FreezedField;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:source_gen/source_gen.dart';

typedef _AnnotatedClass = ({DartObject annotation, ClassDeclaration node});

_AnnotatedClass? _findAnnotatedClasses(
  ClassDeclaration node,
) {
  final element = node.declaredElement;
  if (element == null) return null;

  final annotation =
      const TypeChecker.fromRuntime(Freezed).firstAnnotationOfExact(element);
  if (annotation == null) return null;

  return (annotation: annotation, node: node);
}

Iterable<GeneratorBacklog> parseAst(Iterable<CompilationUnit> units) {
  final annotatedClasses = units
      .expand((e) => e.declarations)
      .whereType<ClassDeclaration>()
      .map(_findAnnotatedClasses)
      .whereNotNull()
      .toList();

  final registry = _FreezedClassRegistry.parse(annotatedClasses);

  // TODO assert that the freezed mixin is used on the class
  // TODO assert that unions are sealed classes.
  // TODO throw if "const" is used on mutable classes

  return registry._allNodesByID.values.expand((e) => e.asGeneratorBacklog());
}

class _FreezedClassRegistry {
  _FreezedClassRegistry._(this.roots);

  factory _FreezedClassRegistry.parse(List<_AnnotatedClass> annotatedClasses) {
    final roots = [
      for (final annotatedClass in annotatedClasses)
        _parseAnnotatedClass(annotatedClass),
    ];

    final result = _FreezedClassRegistry._(roots);

    for (final root in roots) {
      final rootNode = result._upsertNode(root);

      for (final child in root.children) {
        result._upsertNode(child, parent: rootNode);
      }
    }

    // TODO assert that there aren't classes with same name but different ID
    // TODO assert that generated classes names don't conflict with imported types.

    return result;
  }

  static FreezedClassDefinition _parseAnnotatedClass(
    _AnnotatedClass annotatedClass,
  ) {
    final children = annotatedClass.node.members
        .whereType<ConstructorDeclaration>()
        .map(
          (e) => switch (e) {
            ConstructorDeclaration(:final redirectedConstructor?) =>
              FreezedConstructorIdentifier(redirectedConstructor, e),
            _ => null,
          },
        )
        .whereNotNull()
        .toList();

    return FreezedClassDefinition(
      annotatedClass.node,
      annotation: _parseAnnotation(annotatedClass.annotation),
      children: children,
    );
  }

  static FreezedAnnotation _parseAnnotation(DartObject annotation) {
    // TODO
    return FreezedAnnotation();
  }

  final List<FreezedClassDefinition> roots;
  final Map<FreezedClassID, _FreezedClassTreeNode> _allNodesByID = {};

  _FreezedClassTreeNode _upsertNode(FreezedAst astNode,
      {_FreezedClassTreeNode? parent}) {
    var treeNode = _allNodesByID[astNode.id];
    if (treeNode == null) {
      treeNode = _allNodesByID[astNode.id] = _FreezedClassTreeNode(
        astNode,
        parent: parent,
      );
    } else {
      treeNode.addClass(astNode, parent: parent);
    }

    return treeNode;
  }
}

String _generatedClassNameForConstructor(
  FreezedClassID classID,
) {
  // TODO assert conflict between A.nAme and An.ame which both generate AnAme
  final typeName = classID.className;
  final constructorName = classID.constructorName?.titled ?? '';

  if (typeName.isPublic && constructorName.isPublic) {
    return '$typeName$constructorName';
  }

  return '_${typeName.public}${constructorName.public}';
}

/// An amalgamation of [FreezedClassDefinition]s with the same [FreezedClassID].
///
/// This is to represent the fact that the same Freezed class might be
/// defined/referenced multiple times in the same file.
class _FreezedClassTreeNode {
  _FreezedClassTreeNode(FreezedAst initial, {_FreezedClassTreeNode? parent})
      : id = initial.id {
    addClass(initial, parent: parent);
  }

  FreezedClassDefinition? userDefinedClass;

  final FreezedClassID id;

  final parents = <_FreezedClassTreeNode>[];
  final children = <_FreezedClassTreeNode>[];

  @protected
  final _classes = <FreezedConstructorIdentifier>[];

  late final fields = _computeFields();

  List<FreezedField> _computeFields() {
    if (userDefinedClass == null) {
      return _computeGeneratedFields().toList();
    }

    return _computeCommonUserDefinedFields().toList();
  }

  Iterable<FreezedField> _computeCommonUserDefinedFields() sync* {
    final allFields = children.expand((e) => e.fields);

    // TODO handle field downcast
    final uniqueFields = <String, FreezedField>{
      for (final field in allFields) field.name: field,
    };

    yield* uniqueFields.values;
  }

  Iterable<FreezedField> _computeGeneratedFields() sync* {
    final positionalParameters = <FreezedField>[];
    final namedParameters = <String, FreezedField>{};
    for (final clazz in _classes) {
      var positionalOffset = 0;
      for (final parameter in clazz.constructor.parameters.parameters) {
        final field = FreezedField.parse(parameter);

        if (parameter.isPositional) {
          if (positionalOffset < positionalParameters.length) {
            positionalParameters[positionalOffset] = field;
          } else {
            positionalParameters.add(field);
          }
          positionalOffset++;
        } else {
          // "name" has to be present because constructor parameters must have a name.
          namedParameters[parameter.name!.lexeme] = field;
        }

        // TODO assert if there are two parameters with the same keyy but incompatible types
        // TODO assert if there are both optional positionals and named parameters
        // TODO assert if a field is required on one constructor but absent in another
        // TODO allow a parameter to be required in one constructor but optional in another if types match
        // TODO have the field dartdoc list all the constructors it's used in along with the types – to explain why a field may be downcasted.
        // TODO assert that all optional parameters use the same defautl value
      }
    }

    yield* positionalParameters;
    yield* namedParameters.values;
  }

  @internal
  void addClass(FreezedAst node, {_FreezedClassTreeNode? parent}) {
    if (node.id != id) {
      throw StateError('Expected ${node.id} to be $id');
    }

    // TODO assert that [node] is compatible with all [classes]
    // TODO handle redirecting two constructor to the same generated type with different constructor names.

    switch (node) {
      case FreezedClassDefinition():
        // There cannot be an ID conflict between two annotated classes, as they
        // would cause a compile-time error.
        // As such, a node can only be associated with a single annotated class at most.
        userDefinedClass = node;

      case FreezedConstructorIdentifier():
        _classes.add(node);
    }

    if (parent != null) {
      // TODO A generated type is associated with two classes, yet at least
      // one of those classes defined a ._() constructor. Meaning that class
      // should be extended. But that's not doable due to classes being able
      // to extend only one class.

      parents.add(parent);
      parent.children.add(this);
    }
  }

  Iterable<GeneratorBacklog> asGeneratorBacklog() sync* {
    final userDefinedClass = this.userDefinedClass;

    if (userDefinedClass == null) {
      // No associated annotated class, so this is a generated class.

      // Search for all the siblings of this node, filtering duplicates.

      final mixins = <String>[];

      final implementList = <String>[
        for (final parent in parents) parent.id.className,
      ];
      String? extendClause;

      // final siblings = parents //
      //     .expand((e) => e.children)
      //     .where((e) => e != this)
      //     .toSet();

      final generatedName = _generatedClassNameForConstructor(id);

      yield GeneratedFreezedClass(
        name: generatedName,
        mixins: mixins,
        implementList: implementList,
        extendClause: extendClause,
        fields: fields,
      );
    } else {
      // One annotated class is associated, so this is a user-defined class.
      // Let's generate a mixin for it.

      yield UserDefinedClassMixin(
        annotatedClassName: userDefinedClass.declaration.name.lexeme,
        mixinName: userDefinedClass.declaration.name.lexeme.generated,
        fields: fields,
      );
    }
  }
}