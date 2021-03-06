// Copyright 2018 Semmle Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

/**
 * Provides classes implementing a simple intra-procedural flow analysis for inferring abstract
 * values of nodes in the data-flow graph representation of the program.
 *
 * Properties of object literals and class/function instances are tracked to some degree, but
 * completeness should not be relied upon.
 *
 * The abstract value inference consists of a _local_ layer implemented by
 * `AnalyzedFlowNode.getALocalValue()` and a _full_ layer implemented by
 * `AnalyzedFlowNode.getAValue()`. The former only models flow through expressions, variables
 * (both local and global), IIFEs, ES6 imports that can be resolved unambiguously, and
 * flow through properties of CommonJS `module` and `exports` objects (including `require`).
 *
 * The full layer adds some modeling of flow through properties of object literals and of
 * function/class instances: any value that flows into the right-hand-side of a write to
 * property `p` of an abstract value `a` that represents an object literal or instance is
 * considered to flow out of all reads of `p` on `a`. However, in inferring which abstract
 * value `a` some property read or write refers to and what flows into the right-hand-side
 * of a property write, only local reasoning is used. In particular, the full layer does
 * not allow reasoning about nested property writes of the form `p.q.r` (except where `p.q`
 * is a module/exports object and hence handled by local flow).
 *
 * Also note that object inheritance is not modelled. Soundness is, however, preserved in
 * the sense that all expressions whole value derives (directly or indirectly) from a property
 * read are marked as indefinite.
 */

import javascript
import AbstractValues

private import InferredTypes
private import Refinements
private import AbstractValuesImpl

private AnalyzedFlowNode getAnalyzedNode(ASTNode node) {
  node = result.getAstNode()
}

/**
 * A data flow node for which analysis results are available.
 */
class AnalyzedFlowNode extends DataFlow::ValueNode {
  /**
   * Gets another data flow node whose value flows into this node in one local step
   * (that is, not involving global variables).
   */
  AnalyzedFlowNode localFlowPred() {
    result = getAPredecessor()
  }

  /**
   * Gets an abstract value that this node may evaluate to at runtime.
   *
   * This predicate tracks flow through expressions, variables (both local
   * and global), IIFEs, ES6-style imports that can be resolved uniquely, and
   * the properties of CommonJS `module` and `exports` objects. Some limited
   * tracking through the properties of object literals and function/class
   * instances is also performed.
   */
  cached
  AbstractValue getAValue() {
    result = getALocalValue()
  }

  /**
   * INTERNAL: Do not use.
   *
   * Gets an abstract value that this node may evaluate to at runtime.
   *
   * This predicate tracks flow through expressions, variables (both local
   * and global), IIFEs, ES6-style imports that can be resolved uniquely, and
   * the properties of CommonJS `module` and `exports` objects. No
   * tracking through the properties of object literals and function/class
   * instances is performed.
   */
  cached
  AbstractValue getALocalValue() {
    // model flow from other nodes; we do not currently
    // feed back the results from the (value) flow analysis into
    // the control flow analysis, so all flow predecessors are
    // considered as sources
    result = localFlowPred().getALocalValue() or
    // model flow that isn't captured by the data flow graph
    exists (DataFlow::Incompleteness cause |
      isIncomplete(cause) and result = TIndefiniteAbstractValue(cause)
    )
  }

  /** Gets a type inferred for this node. */
  pragma[nomagic] InferredType getAType() {
    result = getALocalValue().getType()
  }

  /** Gets a primitive type to which the value of this node can be coerced. */
  PrimitiveType getAPrimitiveType() {
    result = getALocalValue().toPrimitive().getType()
  }

  /** Gets a Boolean value that this node evaluates to. */
  boolean getABooleanValue() {
    result = getALocalValue().getBooleanValue()
  }

  /** Gets the unique Boolean value that this node evaluates to, if any. */
  boolean getTheBooleanValue() {
    forex (boolean bv | bv = getABooleanValue() | result = bv)
  }

  /** Gets the unique type inferred for this node, if any. */
  InferredType getTheType() {
    count(getAType()) = 1 and result = getAType()
  }

  /**
   * Gets a pretty-printed representation of all types inferred for this node
   * as a comma-separated list, with the last comma being spelled "or".
   *
   * This is useful for violation message, since some expressions (in
   * particular addition) may have more than one inferred type.
   */
  string ppTypes() {
    exists (int n | n = getNumTypes() |
      // inferred no types
      n = 0 and result = "" or
      // inferred a single type
      n = 1 and result = getAType().toString() or
      // inferred all types
      n = count(InferredType it) and result = ppAllTypeTags() or
      // the general case: more than one type, but not all types
      // first pretty-print as a comma separated list, then replace last comma by "or"
      result = (getType(1) + ", " + ppTypes(2)).regexpReplaceAll(", ([^,]++)$", " or $1")
    )
  }

  /**
   * Gets the `i`th type inferred for this node in lexicographical order.
   *
   * Only defined if the number of types inferred for this node is between two
   * and one less than the total number of types.
   */
  private string getType(int i) {
    getNumTypes() in [2..count(InferredType it)-1] and
    result = rank[i](InferredType tp | tp = getAType() | tp.toString())
  }

  /** Gets the number of types inferred for this node. */
  private int getNumTypes() {
    result = count(getAType())
  }

  /**
   * Gets a pretty-printed comma-separated list of all types inferred for this node,
   * in lexicographical order, starting with the `i`th type (1-based), where `i` ranges
   * between two and one less than the total number of types. The single-type case and
   * the all-types case are handled specially above.
   */
  private string ppTypes(int i) {
    exists (int n | n = getNumTypes() and n in [2..count(InferredType it)-1] |
      i = n and result = getType(i) or
      i in [2..n-1] and result = getType(i) + ", " + ppTypes(i+1)
    )
  }

  /** Holds if the flow analysis can infer at least one abstract value for this node. */
  predicate hasFlow() {
    exists(getALocalValue())
  }
}

/**
 * Flow analysis for literal expressions.
 */
private class LiteralSource extends AnalyzedFlowNode {

  Literal literal;

  string value;

  LiteralSource() {
    literal = astNode and
    value = literal.getValue()
  }

  override AbstractValue getALocalValue() {
    // flow analysis for `null` literals
    literal instanceof NullLiteral and result = TAbstractNull()
    or
    // flow analysis for Boolean literals
    literal instanceof BooleanLiteral and (
      value = "true" and result = TAbstractBoolean(true) or
      value = "false" and result = TAbstractBoolean(false)
    )
    or
    // flow analysis for number literals
    literal instanceof NumberLiteral and
    exists (float fv | fv = value.toFloat() |
      if fv = 0.0 or fv = -0.0 then
        result = TAbstractZero()
      else
        result = TAbstractNonZero()
    )
    or
    // flow analysis for string literals
    literal instanceof StringLiteral and
    (
      if value = "" then
        result = TAbstractEmpty()
      else if exists(value.toFloat()) then
        result = TAbstractNumString()
      else
        result = TAbstractOtherString()
    )
    or
    // flow analysis for regular expression literals
    literal instanceof RegExpLiteral and
    result = TAbstractOtherObject()
  }
}

/**
 * Flow analysis for template literals.
 */
private class TemplateLiteralSource extends AnalyzedFlowNode {

  TemplateLiteralSource() {
    astNode instanceof @templateliteral
  }

  override AbstractValue getALocalValue() { result = abstractValueOfType(TTString()) }
}

/**
 * Flow analysis for object expressions.
 */
private class ObjectExprSource extends AnalyzedFlowNode {

  ObjectExprSource() {
    astNode instanceof @objexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractObjectLiteral(astNode) }
}

/**
 * Flow analysis for array expressions.
 */
private class ArrayExprSource extends AnalyzedFlowNode {

  ArrayExprSource() {
    astNode instanceof @arrayexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractOtherObject() }
}

/**
 * Flow analysis for array comprehensions.
 */
private class ArrayComprehensionExprSource extends AnalyzedFlowNode {

  ArrayComprehensionExprSource() {
    astNode instanceof @arraycomprehensionexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractOtherObject() }
}

/**
 * Flow analysis for functions.
 */
private class FunctionSource extends AnalyzedFlowNode {

  FunctionSource() {
    astNode instanceof @function
  }

  override AbstractValue getALocalValue() { result = TAbstractFunction(astNode) }
}

/**
 * Flow analysis for class declarations.
 */
private class ClassExprSource extends AnalyzedFlowNode {

  ClassExprSource() {
    astNode instanceof @classdefinition
  }

  override AbstractValue getALocalValue() { result = TAbstractClass(astNode) }
}

/**
 * Flow analysis for namespace objects.
 */
private class NamespaceSource extends AnalyzedFlowNode {

  NamespaceSource() {
    astNode instanceof @namespacedeclaration
  }

  override AbstractValue getALocalValue() { result = TAbstractOtherObject() }
}

/**
 * Flow analysis for enum objects.
 */
private class EnumSource extends AnalyzedFlowNode {

  EnumSource() {
    astNode instanceof @enumdeclaration
  }

  override AbstractValue getALocalValue() { result = TAbstractOtherObject() }
}

/**
 * Flow analysis for JSX elements and fragments.
 */
private class JSXNodeSource extends AnalyzedFlowNode {

  JSXNodeSource() {
    astNode instanceof @jsxelement
  }


  override AbstractValue getALocalValue() { result = TAbstractOtherObject() }
}

/**
 * Flow analysis for qualified JSX names.
 */
private class JSXQualifiedNameSource extends AnalyzedFlowNode {

  JSXQualifiedNameSource() {
    astNode instanceof @jsxqualifiedname
  }

  override AbstractValue getALocalValue() { result = TAbstractOtherObject() }
}

/**
 * Flow analysis for empty JSX expressions.
 */
private class JSXEmptyExpressionSource extends AnalyzedFlowNode{

  JSXEmptyExpressionSource() {
    astNode instanceof @jsxemptyexpr
  }
  
  override AbstractValue getALocalValue() { result = TAbstractUndefined() }
}

/**
 * Flow analysis for `super` in super constructor calls.
 */
private class AnalyzedSuperCall extends AnalyzedFlowNode {

  AnalyzedSuperCall() {
    astNode = any(SuperCall sc).getCallee().stripParens() and
    astNode instanceof @superexpr
  }

  override AbstractValue getALocalValue() {
    exists (MethodDefinition md, AnalyzedFlowNode sup, AbstractValue supVal |
      md.getBody() = asExpr().getEnclosingFunction() and
      sup.getAstNode() = md.getDeclaringClass().getSuperClass() and
      supVal = sup.getALocalValue() |
      // `extends null` is treated specially in a way that we cannot model
      if supVal instanceof AbstractNull then
        result = TIndefiniteFunctionOrClass("heap")
      else
        result = supVal
    )
  }
}

/**
 * Flow analysis for `new`.
 *
 * This conservatively handles the case where the callee is not known
 * precisely, or where the callee might return a non-primitive value.
 */
private class NewSource extends AnalyzedFlowNode {

  NewSource() {
    astNode instanceof @newexpr
  }

  override AbstractValue getALocalValue() {
    isIndefinite() and
    (
      result = TIndefiniteFunctionOrClass("call") or
      result = TIndefiniteObject("call")
    )
  }

  /**
   * Holds if the callee is indefinite, or if the callee is the
   * constructor of a class with a superclass, or if the callee may
   * return an explicit value. In the latter two cases, the callee
   * may substitute a custom return value for the newly created
   * instance, which we cannot track.
   */
  private predicate isIndefinite() {
    exists (AnalyzedFlowNode callee, AbstractValue calleeVal |
      callee.getAstNode() = astNode.(NewExpr).getCallee() and
      calleeVal = callee.getALocalValue() |
      calleeVal.isIndefinite(_) or
      exists(calleeVal.(AbstractClass).getClass().getSuperClass()) or
      exists(calleeVal.(AbstractCallable).getFunction().getAReturnedExpr())
    )
  }
}

/**
 * Flow analysis for `new` expressions that create class/function instances.
 */
private class NewInstance extends AnalyzedFlowNode{

  NewInstance() {
    astNode instanceof @newexpr
  }

  override AbstractValue getALocalValue() {
    exists (AnalyzedFlowNode callee |
      callee.getAstNode() = astNode.(NewExpr).getCallee() and
      result = TAbstractInstance(callee.getALocalValue())
    )
  }
}

/**
 * Flow analysis for (non-short circuiting) binary expressions.
 */
private class AnalyzedBinaryExpr extends AnalyzedFlowNode {

  AnalyzedBinaryExpr() {
    not astNode instanceof LogicalBinaryExpr and
    astNode instanceof @binaryexpr
  }

  override AbstractValue getALocalValue() {
    // most binary expressions are arithmetic expressions;
    // the logical ones have overriding definitions below
    result = abstractValueOfType(TTNumber())
  }
}

/**
 * Holds if `e` is a `+` or `+=` expression that could be interpreted as a string append
 * (as opposed to a numeric addition) at runtime.
 */
private predicate isStringAppend(Expr e) {
  (e instanceof AddExpr or e instanceof AssignAddExpr) and
  getAnalyzedNode(e.getAChild()).getAPrimitiveType() = TTString()
}

/**
 * Holds if `e` is a `+` or `+=` expression that could be interpreted as a numeric addition
 * (as opposed to a string append) at runtime.
 */
private predicate isAddition(Expr e) {
  (e instanceof AddExpr or e instanceof AssignAddExpr) and
  getAnalyzedNode(e.getChild(0)).getAPrimitiveType() != TTString() and
  getAnalyzedNode(e.getChild(1)).getAPrimitiveType() != TTString()
}

/**
 * Flow analysis for addition.
 */
private class AnalyzedAddExpr extends AnalyzedBinaryExpr {

  AnalyzedAddExpr() {
    astNode instanceof @addexpr
  }

  override AbstractValue getALocalValue() {
    isStringAppend(astNode) and result = abstractValueOfType(TTString()) or
    isAddition(astNode) and result = abstractValueOfType(TTNumber())
  }
}

/**
 * Flow analysis for comparison expressions.
 */
private class ComparisonSource extends AnalyzedBinaryExpr {

  ComparisonSource() {
    astNode instanceof @comparison
  }

  override AbstractValue getALocalValue() { result = TAbstractBoolean(_) }
}

/**
 * Flow analysis for `in` expressions.
 */
private class InSource extends AnalyzedBinaryExpr  {

  InSource() {
    astNode instanceof @inexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractBoolean(_) }
}

/**
 * Flow analysis for `instanceof` expressions.
 */
private class InstanceofSource extends AnalyzedBinaryExpr {

  InstanceofSource() {
    astNode instanceof @instanceofexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractBoolean(_) }
}


/**
 * Flow analysis for unary expressions (except for spread, which is not
 * semantically a unary expression).
 */
private class AnalyzedUnaryExpr extends AnalyzedFlowNode {
  AnalyzedUnaryExpr() {
    not astNode instanceof SpreadElement and
    astNode instanceof @unaryexpr
  }

  override AbstractValue getALocalValue() {
    // many unary expressions are arithmetic expressions;
    // the others have overriding definitions below
    result = abstractValueOfType(TTNumber())
  }
}

/**
 * Flow analysis for `void` expressions.
 */
private class VoidSource extends AnalyzedUnaryExpr {

  VoidSource() {
    astNode instanceof @voidexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractUndefined() }
}

/**
 * Flow analysis for `typeof` expressions.
 */
private class TypeofSource extends AnalyzedUnaryExpr {

  TypeofSource() {
    astNode instanceof @typeofexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractOtherString() }
}

/**
 * Flow analysis for logical negation.
 */
private class AnalyzedLogNotExpr extends AnalyzedUnaryExpr {

  AnalyzedLogNotExpr() {
    astNode instanceof @lognotexpr
  }

  override AbstractValue getALocalValue() {
    exists (AbstractValue op | op = getAnalyzedNode(astNode.(UnaryExpr).getOperand()).getALocalValue() |
      exists (boolean bv | bv = op.getBooleanValue() |
        bv = true and result = TAbstractBoolean(false) or
        bv = false and result = TAbstractBoolean(true)
      )
    )
  }
}

/**
 * Flow analysis for `delete` expressions.
 */
private class DeleteSource extends AnalyzedUnaryExpr {

  DeleteSource() {
    astNode instanceof @deleteexpr
  }

  override AbstractValue getALocalValue() { result = TAbstractBoolean(_) }
}


/**
 * Flow analysis for increment and decrement expressions.
 */
private class UpdateSource extends AnalyzedFlowNode {

  UpdateSource() {
    astNode instanceof @updateexpr
  }

  override AbstractValue getALocalValue() { result = abstractValueOfType(TTNumber()) }
}


/**
 * Flow analysis for compound assignments.
 */
private class AnalyzedCompoundAssignExpr extends AnalyzedFlowNode {
  AnalyzedCompoundAssignExpr() {
    astNode instanceof CompoundAssignExpr
  }

  override AbstractValue getALocalValue() { result = abstractValueOfType(TTNumber()) }
}

/**
 * Flow analysis for add-assign.
 */
private class AnalyzedAddAssignExpr extends AnalyzedCompoundAssignExpr {

  AnalyzedAddAssignExpr() {
    astNode instanceof @assignaddexpr
  }

  override AbstractValue getALocalValue() {
    isStringAppend(astNode) and result = abstractValueOfType(TTString()) or
    isAddition(astNode) and result = abstractValueOfType(TTNumber())
  }
}


/**
 * Flow analysis for captured variables.
 */
private class AnalyzedCapturedVariable extends @variable {
  AnalyzedCapturedVariable() {
    this.(Variable).isCaptured()
  }

  /**
   * Gets an abstract value that may be assigned to this variable.
   */
  pragma[nomagic]
  AbstractValue getALocalValue() {
    result = getADef().getAnAssignedValue()
  }

  /**
   * Gets a definition of this variable.
   */
  AnalyzedVarDef getADef() {
    this = result.getAVariable()
  }

  /** Gets a textual representation of this element. */
  string toString() {
    result = this.(Variable).toString()
  }
}

/**
 * Flow analysis for accesses to SSA variables.
 */
private class SsaVarAccessAnalysis extends AnalyzedFlowNode {
  AnalyzedSsaDefinition def;

  SsaVarAccessAnalysis() {
    astNode = def.getVariable().getAUse()
  }

  override AbstractValue getALocalValue() {
    result = def.getAnRhsValue()
  }
}

/**
 * Flow analysis for `VarDef`s.
 */
private class AnalyzedVarDef extends VarDef {
  /**
   * Gets an abstract value that this variable definition may assign
   * to its target, including indefinite values if this definition
   * cannot be analyzed completely.
   */
  AbstractValue getAnAssignedValue() {
    result = getAnRhsValue() or
    exists (DataFlow::Incompleteness cause |
      isIncomplete(cause) and result = TIndefiniteAbstractValue(cause)
    )
  }

  /**
   * Gets an abstract value that the right hand side of this `VarDef`
   * may evaluate to.
   */
  AbstractValue getAnRhsValue() {
    result = getRhs().getALocalValue() or
    this = any(ForInStmt fis).getIteratorExpr() and result = abstractValueOfType(TTString()) or
    this = any(EnumMember member | not exists(member.getInitializer())).getIdentifier() and result = abstractValueOfType(TTNumber())
  }

  /**
   * Gets a node representing the value of the right hand side of
   * this `VarDef`.
   */
  AnalyzedFlowNode getRhs() {
    result.getAstNode() = getSource() and getTarget() instanceof VarRef or
    result.asExpr() = (CompoundAssignExpr)this or
    result.asExpr() = (UpdateExpr)this
  }

  /**
   * Holds if flow analysis results for this node may be incomplete
   * due to the given `cause`.
   */
  predicate isIncomplete(DataFlow::Incompleteness cause) {
    this instanceof Parameter and cause = "call" or
    this instanceof ImportSpecifier and cause = "import" or
    exists (EnhancedForLoop efl | efl instanceof ForOfStmt or efl instanceof ForEachStmt |
      this = efl.getIteratorExpr()
    ) and cause = "heap" or
    exists (ComprehensionBlock cb | this = cb.getIterator()) and cause = "yield" or
    getTarget() instanceof DestructuringPattern and cause = "heap"
  }

  /**
   * Gets the toplevel syntactic unit to which this definition belongs.
   */
  TopLevel getTopLevel() {
    result = this.(ASTNode).getTopLevel()
  }
}

/**
 * Flow analysis for simple IIFE parameters.
 */
private class AnalyzedIIFEParameter extends AnalyzedVarDef, @vardecl {
  AnalyzedIIFEParameter() {
    exists (ImmediatelyInvokedFunctionExpr iife, int parmIdx |
      this = iife.getParameter(parmIdx) |
      // we cannot track flow into rest parameters...
      not this.(Parameter).isRestParameter() and
      // ...nor flow out of spread arguments
      exists (int argIdx | argIdx = parmIdx + iife.getArgumentOffset() |
        not iife.isSpreadArgument([0..argIdx])
      )
    )
  }

  /** Gets the IIFE this is a parameter of. */
  ImmediatelyInvokedFunctionExpr getIIFE() {
    this = result.getAParameter()
  }

  override AnalyzedFlowNode getRhs() {
    getIIFE().argumentPassing(this, result.getAstNode()) or
    result.getAstNode() = this.(Parameter).getDefault()
  }

  override AbstractValue getAnRhsValue() {
    result = AnalyzedVarDef.super.getAnRhsValue() or
    not getIIFE().argumentPassing(this, _) and result = TAbstractUndefined()
  }

  override predicate isIncomplete(DataFlow::Incompleteness cause) {
    exists (ImmediatelyInvokedFunctionExpr iife | iife = getIIFE() |
      // if the IIFE has a name and that name is referenced, we conservatively
      // assume that there may be other calls than the direct one
      exists (iife.getVariable().getAnAccess()) and cause = "call" or
      // if the IIFE is non-strict and its `arguments` object is accessed, we
      // also assume that there may be other calls (through `arguments.callee`)
      not iife.isStrict() and
      exists (iife.getArgumentsVariable().getAnAccess()) and cause = "call"
    )
  }
}

/**
 * Flow analysis for simple rest parameters.
 */
private class AnalyzedRestParameter extends AnalyzedVarDef, @vardecl {
  AnalyzedRestParameter() {
    this.(Parameter).isRestParameter()
  }

  override AbstractValue getAnRhsValue() {
    result = TAbstractOtherObject()
  }

  override predicate isIncomplete(DataFlow::Incompleteness cause) {
    none()
  }
}

/**
 * Flow analysis for ECMAScript 2015 imports.
 */
private class AnalyzedImport extends AnalyzedVarDef, @importspecifier {
  AnalyzedImport() {
    resolveImport(_, this, _, _)
  }

  override predicate isIncomplete(DataFlow::Incompleteness cause) {
    // mark as incomplete if the import could rely on the lookup path
    exists (ImportDeclaration id, string path |
      resolveImport(id, this, _, _) and path = id.getImportedPath().getValue() |
      // imports starting with `.` or `/` do not rely on the lookup path
      not path.regexpMatch("[./].*") and
      cause = "import"
    )
  }
}

/**
 * Holds if the specifier `s` in import `i` imports symbol `name` from module `m`.
 */
private predicate resolveImport(ImportDeclaration i, ImportSpecifier s,
                                string name, ES2015Module m) {
  s = i.getASpecifier() and
  m = i.resolveImportedPath() and
  name = s.getImportedName() and
  exists(m.getAnExport().getSourceNode(name))
}

/**
 * Flow analysis for ECMAScript 2015 imports that import a value.
 */
private class AnalyzedDefaultImport extends AnalyzedImport {
  override AbstractValue getAnRhsValue() {
    exists (ES2015Module m, string name | resolveImport(_, this, name, m) |
      // if we are importing a value, we only see that value
      exists (AnalyzedFlowNode remoteSrc |
        remoteSrc.getAstNode() = m.getAnExport().getSourceNode(name) and
        result = remoteSrc.getALocalValue()
      )
    )
  }
}

/**
 * Flow analysis for ECMAScript 2015 imports that import a variable.
 *
 * In this case, we are importing a binding (namely, the variable being exported),
 * so we need to consider all assignments to that variable.
 */
private class AnalyzedVariableImport extends AnalyzedImport {
  override AbstractValue getAnRhsValue() {
    exists (ES2015Module m, string name | resolveImport(_, this, name, m) |
      // if we are importing a variable, we see every assignment to it
      exists (AnalyzedVarDef remoteDef | m.exportsAs(remoteDef.getAVariable(), name) |
        result = remoteDef.getAnAssignedValue()
      )
    )
  }
}

/**
 * Flow analysis for `module` and `exports` parameters of AMD modules.
 */
private class AnalyzedAmdParameter extends AnalyzedVarDef {
  AbstractValue implicitInitVal;

  AnalyzedAmdParameter() {
    exists (AMDModule m, AMDModuleDefinition mdef | mdef = m.getDefine() |
      this = mdef.getModuleParameter() and
      implicitInitVal = TAbstractModuleObject(m)
      or
      this = mdef.getExportsParameter() and
      implicitInitVal = TAbstractExportsObject(m)
    )
  }

  override AbstractValue getAnAssignedValue() {
    result = super.getAnAssignedValue() or
    result = implicitInitVal
  }
}

/**
 * Flow analysis for SSA definitions.
 */
abstract class AnalyzedSsaDefinition extends SsaDefinition {
  /**
   * Gets an abstract value that the right hand side of this definition
   * may evaluate to at runtime.
   */
  abstract AbstractValue getAnRhsValue();
}

/**
 * Flow analysis for SSA definitions corresponding to `VarDef`s.
 */
private class AnalyzedExplicitDefinition extends AnalyzedSsaDefinition, SsaExplicitDefinition {
  override AbstractValue getAnRhsValue() {
    result = getDef().(AnalyzedVarDef).getAnAssignedValue()
  }
}

/**
 * Flow analysis for SSA definitions corresponding to implicit variable initialization.
 */
private class AnalyzedImplicitInit extends AnalyzedSsaDefinition, SsaImplicitInit {
  override AbstractValue getAnRhsValue() {
    result = getImplicitInitValue(getSourceVariable())
  }
}

/**
 * Flow analysis for SSA definitions corresponding to implicit variable capture.
 */
private class AnalyzedVariableCapture extends AnalyzedSsaDefinition, SsaVariableCapture {
  override AbstractValue getAnRhsValue() {
    exists (LocalVariable v | v = getSourceVariable() |
      result = v.(AnalyzedCapturedVariable).getALocalValue() or
      not guaranteedToBeInitialized(v) and result = getImplicitInitValue(v)
    )
  }
}

/**
 * Flow analysis for SSA phi nodes.
 */
private class AnalyzedPhiNode extends AnalyzedSsaDefinition, SsaPhiNode {
  override AbstractValue getAnRhsValue() {
    result = getAnInput().(AnalyzedSsaDefinition).getAnRhsValue()
  }
}

/**
 * Flow analysis for refinement nodes.
 */
class AnalyzedRefinement extends AnalyzedSsaDefinition, SsaRefinementNode {
  override AbstractValue getAnRhsValue() {
    // default implementation: don't refine
    result = getAnInputRhsValue()
  }

  /**
   * Gets an abstract value that one of the inputs of this refinement may evaluate to.
   */
  AbstractValue getAnInputRhsValue() {
    result = getAnInput().(AnalyzedSsaDefinition).getAnRhsValue()
  }
}

/**
 * Flow analysis for refinement nodes where the guard is a condition.
 *
 * For such nodes, we want to split any indefinite abstract values flowing into the node
 * into sets of more precise abstract values to enable them to be refined.
 */
class AnalyzedConditionGuard extends AnalyzedRefinement {
  AnalyzedConditionGuard() {
    getGuard() instanceof ConditionGuardNode
  }

  override AbstractValue getAnInputRhsValue() {
    exists (AbstractValue input | input = super.getAnInputRhsValue() |
      result = input.(IndefiniteAbstractValue).split()
      or
      not input instanceof IndefiniteAbstractValue and result = input
    )
  }
}

/**
 * Flow analysis for condition guards with an outcome of `true`.
 *
 * For example, in `if(x) s; else t;`, this will restrict the possible values of `x` at
 * the beginning of `s` to those that are truthy.
 */
class AnalyzedPositiveConditionGuard extends AnalyzedRefinement {
  AnalyzedPositiveConditionGuard() {
    getGuard().(ConditionGuardNode).getOutcome() = true
  }

  override AbstractValue getAnRhsValue() {
    result = getAnInputRhsValue() and
    exists (RefinementContext ctxt |
      ctxt = TVarRefinementContext(this, getSourceVariable(), result) and
      getRefinement().eval(ctxt).getABooleanValue() = true
    )
  }
}

/**
 * Flow analysis for condition guards with an outcome of `false`.
 *
 * For example, in `if(x) s; else t;`, this will restrict the possible values of `x` at
 * the beginning of `t` to those that are falsy.
 */
class AnalyzedNegativeConditionGuard extends AnalyzedRefinement {
  AnalyzedNegativeConditionGuard() {
    getGuard().(ConditionGuardNode).getOutcome() = false
  }

  override AbstractValue getAnRhsValue() {
    result = getAnInputRhsValue() and
    exists (RefinementContext ctxt |
      ctxt = TVarRefinementContext(this, getSourceVariable(), result) and
      getRefinement().eval(ctxt).getABooleanValue() = false
    )
  }
}

/**
 * Gets the abstract value representing the initial value of variable `v`.
 *
 * Most variables are implicitly initialized to `undefined`, except
 * for `arguments` (which is initialized to the arguments object),
 * and special Node.js variables such as `module` and `exports`.
 */
private AbstractValue getImplicitInitValue(LocalVariable v) {
  if v instanceof ArgumentsVariable then
    exists (Function f | v = f.getArgumentsVariable() |
      result = TAbstractArguments(f)
    )
  else if nodeBuiltins(v, _) then
    nodeBuiltins(v, result)
  else
    result = TAbstractUndefined()
}

/**
 * Holds if `v` is a local variable that can never be observed in its uninitialized state.
 */
private predicate guaranteedToBeInitialized(LocalVariable v) {
  // function declarations can never be uninitialized due to hoisting
  exists (FunctionDeclStmt fd | v = fd.getVariable()) or
  // parameters also can never be uninitialized
  exists (Parameter p | v = p.getAVariable())
}

/**
 * Holds if `av` represents an initial value of CommonJS variable `var`.
 */
private predicate nodeBuiltins(Variable var, AbstractValue av) {
  exists (Module m, string name | var = m.getScope().getVariable(name) |
    name = "require" and av = TIndefiniteAbstractValue("heap")
    or
    name = "module" and av = TAbstractModuleObject(m)
    or
    name = "exports" and av = TAbstractExportsObject(m)
    or
    name = "arguments" and av = TAbstractOtherObject()
    or
    (name = "__filename" or name = "__dirname") and
    (av = TAbstractNumString() or av = TAbstractOtherString())
  )
}

/**
 * Flow analysis for global variables.
 */
private class AnalyzedGlobalVarUse extends AnalyzedFlowNode {
  GlobalVariable gv;
  TopLevel tl;

  AnalyzedGlobalVarUse() {
    useIn(gv, astNode, tl)
  }

  /** Gets the name of this global variable. */
  string getVariableName() { result = gv.getName() }

  /**
   * Gets a property write that may assign to this global variable as a property
   * of the global object.
   */
  private PropWriteNode getAnAssigningPropWrite() {
    result.getPropertyName() = getVariableName() and
    getAnalyzedNode(result.getBase()).getALocalValue() instanceof AbstractGlobalObject
  }

  override predicate isIncomplete(DataFlow::Incompleteness reason) {
    AnalyzedFlowNode.super.isIncomplete(reason)
    or
    clobberedProp(gv, reason)
  }

  override AbstractValue getALocalValue() {
    result = AnalyzedFlowNode.super.getALocalValue()
    or
    result = getAnalyzedNode(getAnAssigningPropWrite().getRhs()).getALocalValue()
    or
    // prefer definitions within the same toplevel
    exists (AnalyzedVarDef def | defIn(gv, def, tl) |
      result = def.getAnAssignedValue()
    )
    or
    // if there aren't any, consider all definitions as sources
    not defIn(gv, _, tl) and
    result = gv.(AnalyzedCapturedVariable).getALocalValue()
  }
}

/**
 * Holds if `gva` is a use of `gv` in `tl`.
 */
private predicate useIn(GlobalVariable gv, GlobalVarAccess gva, TopLevel tl) {
  gva = gv.getAnAccess() and
  gva instanceof RValue and
  gva.getTopLevel() = tl
}

/**
 * Holds if `def` is a definition of `gv` in `tl`.
 */
private predicate defIn(GlobalVariable gv, AnalyzedVarDef def, TopLevel tl) {
  def.getTarget().(VarRef).getVariable() = gv and
  def.getTopLevel() = tl
}

/**
 * Holds if there is a write to a property with the same name as `gv` on an object
 * for which the analysis is incomplete due to the given `reason`.
 */

private predicate clobberedProp(GlobalVariable gv, DataFlow::Incompleteness reason) {
  exists (PropWriteNode pwn, AbstractValue baseVal |
    pwn.getPropertyName() = gv.getName() and
    baseVal = getAnalyzedNode(pwn.getBase()).getALocalValue() and
    baseVal.isIndefinite(reason) and
    baseVal.getType() = TTObject()
  )
}

/**
 * Flow analysis for `undefined`.
 */
private class UndefinedSource extends AnalyzedGlobalVarUse {
  UndefinedSource() { getVariableName() = "undefined" }

  override AbstractValue getALocalValue() { result = TAbstractUndefined() }
}

/**
 * Holds if there might be indirect assignments to `v` through an `arguments` object.
 *
 * This predicate is conservative (that is, it may hold even for variables that cannot,
 * in fact, be assigned in this way): it checks if `v` is a parameter of a function
 * with a mapped `arguments` variable, and either there is a property write on `arguments`,
 * or we lose track of `arguments` (for example, because it is passed to another function).
 *
 * Here is an example with a property write on `arguments`:
 *
 * ```
 * function f1(x) {
 *   for (var i=0; i<arguments.length; ++i)
 *     arguments[i]++;
 * }
 * ```
 *
 * And here is an example where `arguments` escapes:
 *
 * ```
 * function f2(x) {
 *   [].forEach.call(arguments, function(_, i, args) {
 *     args[i]++;
 *   });
 * }
 * ```
 *
 * In both cases `x` is assigned through the `arguments` object.
 */
private predicate maybeModifiedThroughArguments(LocalVariable v) {
  exists (Function f, ArgumentsVariable args |
    v = f.getAParameter().(SimpleParameter).getVariable() and
    f.hasMappedArgumentsVariable() and args = f.getArgumentsVariable() |
    exists (VarAccess acc | acc = args.getAnAccess() |
      // `acc` is a use of `arguments` that isn't a property access
      // (like `arguments[0]` or `arguments.length`), so we conservatively
      // consider `arguments` to have escaped
      not exists (PropAccess pacc | acc = pacc.getBase())
      or
      // acc is a write to a property of `arguments` other than `length`,
      // so we conservatively consider it a possible write to `v`
      exists (PropAccess pacc | acc = pacc.getBase() |
        not pacc.getPropertyName() = "length" and
        pacc instanceof LValue
      )
    )
  )
}

/**
 * Flow analysis for variables that may be mutated reflectively through `eval`
 * or via the `arguments` array, and for variables that may refer to properties
 * of a `with` scope object.
 *
 * Note that this class overlaps with the other classes for handling variable
 * accesses, notably `VarAccessAnalysis`: its implementation of `getALocalValue`
 * does not replace the implementations in other classes, but complements
 * them by injecting additional values into the analysis.
 */
private class ReflectiveVarFlow extends AnalyzedFlowNode {
  ReflectiveVarFlow() {
    exists (Variable v | v = astNode.(VarAccess).getVariable() |
      any(DirectEval de).mayAffect(v)
      or
      maybeModifiedThroughArguments(v)
      or
      any(WithStmt with).mayAffect(astNode)
    )
  }

  override AbstractValue getALocalValue() { result = TIndefiniteAbstractValue("eval") }
}

/**
 * Flow analysis for variables exported from a TypeScript namespace.
 *
 * These are translated to property accesses by the TypeScript compiler and
 * can thus be mutated indirectly through the heap.
 */
private class NamespaceExportVarFlow extends AnalyzedFlowNode {
  NamespaceExportVarFlow() {
    astNode.(VarAccess).getVariable().isNamespaceExport()
  }

  override AbstractValue getALocalValue() { result = TIndefiniteAbstractValue("namespace") }
}

/**
 * Flow analysis for property reads, either explicitly (`x.p` or `x[e]`) or
 * implicitly.
 */
private abstract class AnalyzedPropertyRead extends AnalyzedFlowNode {
  /**
   * Holds if this property read may read property `propName` of a concrete value represented
   * by `base`.
   */
  pragma[nomagic]
  abstract predicate reads(AbstractValue base, string propName);

  override AbstractValue getAValue() {
    result = getASourceProperty().getAValue() or
    result = AnalyzedFlowNode.super.getAValue()
  }

  override AbstractValue getALocalValue() {
    result = getASourceProperty().getALocalValue() or
    result = AnalyzedFlowNode.super.getALocalValue()
  }

  /**
   * Gets an abstract property representing one of the concrete properties that
   * this read may refer to.
   */
  pragma[noinline]
  private AbstractProperty getASourceProperty() {
    exists (AbstractValue base, string prop | reads(base, prop) |
      result = MkAbstractProperty(base, prop)
    )
  }
}

/**
 * Flow analysis for `require` calls, interpreted as an implicit read of
 * the `module.exports` property of the imported module.
 */
class AnalyzedRequireCall extends AnalyzedPropertyRead {
  Module required;

  AnalyzedRequireCall() {
    required = astNode.(Require).getImportedModule()
  }

  override predicate reads(AbstractValue base, string propName) {
    base = TAbstractModuleObject(required) and
    propName = "exports"
  }
}

/**
 * Flow analysis for (non-numeric) property read accesses.
 */
class AnalyzedPropertyAccess extends AnalyzedPropertyRead {
  AnalyzedFlowNode baseNode;
  string propName;

  AnalyzedPropertyAccess() {
    astNode.(PropAccess).accesses(baseNode.getAstNode(), propName) and
    not exists(propName.toInt()) and
    astNode instanceof RValue
  }

  override predicate reads(AbstractValue base, string prop) {
    base = baseNode.getALocalValue() and
    prop = propName
  }
}

/**
 * Holds if properties named `prop` should be tracked.
 */
pragma[noinline]
private predicate isTrackedPropertyName(string prop) {
  exists (MkAbstractProperty(_, prop))
}

/**
 * Flow analysis for property writes.
 */
class AnalyzedPropertyWrite extends DataFlow::ValueNode {
  AnalyzedFlowNode baseNode;
  string prop;
  AnalyzedFlowNode rhs;

  AnalyzedPropertyWrite() {
    exists (PropWriteNode pwn | astNode = pwn |
      baseNode.getAstNode() = pwn.getBase() and
      prop = pwn.getPropertyName() and
      rhs.getAstNode() = pwn.getRhs()
    ) and
    isTrackedPropertyName(prop)
  }

  /**
   * Holds if this property write assigns `source` to property `propName` of one of the
   * concrete objects represented by `baseVal`.
   */
  predicate writes(AbstractValue baseVal, string propName, AnalyzedFlowNode source) {
    baseVal = baseNode.getALocalValue() and
    propName = prop and
    source = rhs and
    shouldTrackProperties(baseVal)
  }
}

/**
 * Holds if the result is known to be an initial value of property `propertyName` of one
 * of the concrete objects represented by `baseVal`.
 */
private AbstractValue getAnInitialPropertyValue(DefiniteAbstractValue baseVal, string propertyName) {
  // initially, `module.exports === exports`
  exists (Module m |
    baseVal = TAbstractModuleObject(m) and
    propertyName = "exports" and
    result = TAbstractExportsObject(m)
  )
  or
  // class members
  exists (ClassDefinition c, AnalyzedFlowNode init, MemberDefinition m |
    m = c.getMember(propertyName) and
    init.getAstNode() = m.getInit() and
    result = init.getALocalValue() |
    if m.isStatic() then
      baseVal = TAbstractClass(c)
    else
      baseVal = TAbstractInstance(TAbstractClass(c))
  )
  or
  // object properties
  exists (ValueProperty p |
    baseVal.(AbstractObjectLiteral).getObjectExpr() = p.getObjectExpr() and
    propertyName = p.getName() and
    result = getAnalyzedNode(p.getInit()).getALocalValue()
  )
  or
  // `f.prototype` for functions `f` that are instantiated
  propertyName = "prototype" and
  baseVal = getAnalyzedNode(any(NewExpr ne).getCallee()).getALocalValue() and
  result = TAbstractInstance(baseVal)
}

/**
 * Holds if `baseVal` is an abstract value whose properties we track for the purposes
 * of `getALocalValue`.
 */
private predicate shouldAlwaysTrackProperties(AbstractValue baseVal) {
  baseVal instanceof AbstractModuleObject or
  baseVal instanceof AbstractExportsObject or
  baseVal instanceof AbstractCallable
}

/** Holds if `baseVal` is an abstract value whose properties we track. */
private predicate shouldTrackProperties(AbstractValue baseVal) {
  shouldAlwaysTrackProperties(baseVal) or
  baseVal instanceof AbstractObjectLiteral or
  baseVal instanceof AbstractInstance
}

/**
 * An abstract representation of a set of concrete properties, characterized
 * by a base object (which is an abstract value for which properties are tracked)
 * and a property name.
 */
private newtype TAbstractProperty =
  MkAbstractProperty(AbstractValue base, string prop) {
    any(AnalyzedPropertyRead apr).reads(base, prop) and shouldTrackProperties(base)
    or
    any(AnalyzedPropertyWrite apw).writes(base, prop, _)
    or
    exists(getAnInitialPropertyValue(base, prop))
    or
    // make sure `__proto__` properties exist for all instance values
    base instanceof AbstractInstance and
    prop = "__proto__"
  }

/**
 * An abstract representation of a set of concrete properties, characterized
 * by a base object (which is an abstract value for which properties are tracked)
 * and a property name.
 */
class AbstractProperty extends TAbstractProperty {
  AbstractValue base;
  string prop;

  AbstractProperty() {
    this = MkAbstractProperty(base, prop)
  }

  /** Gets the base object of this abstract property. */
  AbstractValue getBase() {
    result = base
  }

  /** Gets the property name of this abstract property. */
  string getPropertyName() {
    result = prop
  }

  /**
   * Gets an initial value that is implicitly assigned to this property.
   */
  AbstractValue getAnInitialValue() {
    result = getAnInitialPropertyValue(base, prop)
  }

  /**
   * Gets a value that is explicitly assigned to this property.
   */
  private DefiniteAbstractValue getAnAssignedValue() {
    result = getAnAssignedValue(base, prop)
  }

  /**
   * Gets a value of this property for the purposes of `AnalyzedFlowNode.getALocalValue`.
   */
  AbstractValue getALocalValue() {
    result = getAnInitialValue()
    or
    shouldAlwaysTrackProperties(base) and result = getAnAssignedValue()
  }

  /**
   * Gets a value of this property for the purposes of `AnalyzedFlowNode.getAValue`.
   */
  AbstractValue getAValue() {
    result = getALocalValue() or
    result = getAnAssignedValue()
  }

  /**
   * Gets a textual representation of this element.
   */
  string toString() {
    result = "property " + prop + " of " + base
  }
}

/**
 * Gets a value that is explicitly assigned to property `p` of abstract value `b`.
 *
 * This auxiliary predicate is necessary to enforce a better join order, and it
 * has to be toplevel predicate to avoid a spurious type join with `AbstractProperty`,
 * which in turn introduces a materialization.
 */
pragma[noopt]
private DefiniteAbstractValue getAnAssignedValue(AbstractValue b, string p) {
  exists (AnalyzedPropertyWrite apw, AnalyzedFlowNode afn |
    apw.writes(b, p, afn) and
    result = afn.getALocalValue() and
    result instanceof DefiniteAbstractValue
  )
}

/**
 * An abstract representation of the `__proto__` property of a function or
 * class instance.
 */
class AbstractProtoProperty extends AbstractProperty {
  AbstractProtoProperty() {
    prop = "__proto__"
  }

  override AbstractValue getAValue() {
    result = super.getAValue() and
    (
     not result instanceof PrimitiveAbstractValue or
     result instanceof AbstractNull
    )
    or
    exists (AbstractCallable ctor | base = TAbstractInstance(ctor) |
      // the value of `ctor.prototype`
      exists (AbstractProperty prototype |
        prototype = MkAbstractProperty((AbstractFunction)ctor, "prototype") and
        result = prototype.getALocalValue()
      )
      or
      // instance of super class
      exists (ClassDefinition cd, AbstractCallable superCtor |
        cd = ctor.(AbstractClass).getClass() and
        superCtor = getAnalyzedNode(cd.getSuperClass()).getALocalValue() and
        result = TAbstractInstance(superCtor)
      )
    )
  }
}


/**
 * Flow analysis for `arguments.callee`. We assume it is never redefined,
 * which is unsound in practice, but pragmatically useful.
 */
private class AnalyzedArgumentsCallee extends AnalyzedPropertyAccess {
  AnalyzedArgumentsCallee() {
    propName = "callee"
  }

  override AbstractValue getALocalValue() {
    exists (AbstractArguments baseVal | reads(baseVal, _) |
      result = TAbstractFunction(baseVal.getFunction())
    )
    or
    hasNonArgumentsBase(astNode) and result = super.getALocalValue()
  }
}

/**
 * Holds if `pacc` is of the form `e.callee` where `e` could evaluate to some
 * value that is not an arguments object.
 */
private predicate hasNonArgumentsBase(PropAccess pacc) {
  pacc.getPropertyName() = "callee" and
  exists (AbstractValue baseVal |
    baseVal = getAnalyzedNode(pacc.getBase()).getALocalValue() and
    not baseVal instanceof AbstractArguments
  )
}

/**
 * Flow analysis for immediately-invoked function expressions (IIFEs).
 */
private class IifeReturnFlow extends AnalyzedFlowNode {
  ImmediatelyInvokedFunctionExpr iife;

  IifeReturnFlow() {
    astNode = iife.getInvocation() and
    astNode instanceof @callexpr
  }

  override AbstractValue getALocalValue() {
    result = getAReturnValue(iife)
  }
}

/**
 * Gets a return value for the immediately-invoked function expression `f`.
 */
private AbstractValue getAReturnValue(ImmediatelyInvokedFunctionExpr f) {
  // explicit return value
  result = getAnalyzedNode(f.getAReturnedExpr()).getALocalValue()
  or
  // implicit return value
  (
    // either because execution of the function may terminate normally
    mayReturnImplicitly(f)
    or
    // or because there is a bare `return;` statement
    exists (ReturnStmt ret | ret = f.getAReturnStmt() | not exists(ret.getExpr()))
  ) and
  result = getDefaultReturnValue(f)
}


/**
 * Holds if the execution of function `f` may complete normally without
 * encountering a `return` or `throw` statement.
 *
 * Note that this is an overapproximation, that is, the predicate may hold
 * of functions that cannot actually complete normally, since it does not
 * account for `finally` blocks and does not check reachability.
 */
private predicate mayReturnImplicitly(Function f) {
  exists (ConcreteControlFlowNode final |
    final.getContainer() = f and
    final.isAFinalNode() and
    not final instanceof ReturnStmt and
    not final instanceof ThrowStmt
  )
}

/**
 * Gets the default return value for immediately-invoked function expression `f`,
 * that is, the value that `f` returns if its execution terminates without
 * encountering an explicit `return` statement.
 */
private AbstractValue getDefaultReturnValue(ImmediatelyInvokedFunctionExpr f) {
  if f.isGenerator() or f.isAsync() then
    result = TAbstractOtherObject()
  else
    result = TAbstractUndefined()
}

/**
 * Flow analysis for `this` expressions inside functions.
 */
private abstract class AnalyzedThisExpr extends AnalyzedFlowNode {
  Function binder;

  AnalyzedThisExpr() {
    binder = astNode.(ThisExpr).getBinder()
  }
}

/**
 * Flow analysis for `this` expressions inside a function that is instantiated.
 *
 * These expressions are assumed to refer to an instance of that function. Since
 * this is only a heuristic, however, we additionally still infer an indefinite
 * abstract value.
 */
private class AnalyzedThisInConstructorFunction extends AnalyzedThisExpr {
  AbstractValue value;

  AnalyzedThisInConstructorFunction() {
    value = TAbstractInstance(TAbstractFunction(binder))
  }

  override AbstractValue getALocalValue() {
    result = value or
    result = AnalyzedThisExpr.super.getALocalValue()
  }
}

/**
 * Flow analysis for `this` expressions inside an instance member of a class.
 *
 * These expressions are assumed to refer to an instance of that class. This
 * is a safe assumption in practice, but to guard against corner cases we still
 * additionally infer an indefinite abstract value.
 */
private class AnalyzedThisInInstanceMember extends AnalyzedThisExpr {
  ClassDefinition c;

  AnalyzedThisInInstanceMember() {
    exists (MemberDefinition m |
      m = c.getAMember() and
      not m.isStatic() and
      binder = c.getAMember().getInit()
    )
  }

  override AbstractValue getALocalValue() {
    result = TAbstractInstance(TAbstractClass(c)) or
    result = AnalyzedThisExpr.super.getALocalValue()
  }
}

/**
 * Flow analysis for `this` expressions inside a function that is assigned to a property.
 *
 * These expressions are assumed to refer to the object to whose property the function
 * is assigned. Since this is only a heuristic, however, we additionally still infer an
 * indefinite abstract value.
 *
 * The following code snippet shows an example:
 *
 * ```
 * var o = {
 *   p: function() {
 *     this;  // assumed to refer to object literal `o`
 *   }
 * };
 * ```
 */
private class AnalyzedThisInPropertyFunction extends AnalyzedThisExpr {
  AnalyzedFlowNode base;

  AnalyzedThisInPropertyFunction() {
    exists (PropWriteNode pwn |
      pwn.getRhs() = binder and
      base.getAstNode() = pwn.getBase()
    )
  }

  override AbstractValue getALocalValue() {
    result = base.getALocalValue() or
    result = AnalyzedThisExpr.super.getALocalValue()
  }
}
