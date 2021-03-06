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
 * @name Jump-to-definition links
 * @description Generates use-definition pairs that provide the data
 *              for jump-to-definition in the code viewer.
 * @kind definitions
 * @id js/jump-to-definition
 */

import javascript
private import Declarations.Declarations

/**
 * Gets the kind of reference that `r` represents.
 *
 * References in callee position have kind `"M"` (for "method"), all
 * others have kind `"V"` (for "variable").
 *
 * For example, in the expression `f(x)`, `f` has kind `"M"` while
 * `x` has kind `"V"`.
 */
string refKind(RefExpr r) {
  if exists(InvokeExpr invk | r = invk.getCallee().stripParens()) then
    result = "M"
  else
    result = "V"
}

/**
 * Gets a class, function or object literal `va` may refer to.
 */
ASTNode lookupDef(VarAccess va) {
  exists (AbstractValue av | av = DataFlow::valueNode(va).(AnalyzedFlowNode).getAValue() |
    result = av.(AbstractClass).getClass() or
    result = av.(AbstractFunction).getFunction() or
    result = av.(AbstractObjectLiteral).getObjectExpr()
  )
}

/**
 * Holds if `va` is of kind `kind` and `def` is the unique class,
 * function or object literal it refers to.
 */
predicate variableDefLookup(VarAccess va, ASTNode def, string kind) {
  count(lookupDef(va)) = 1 and
  def = lookupDef(va) and
  kind = refKind(va)
}

/**
 * Holds if variable access `va` is of kind `kind` and refers to the
 * variable declaration.
 *
 * For example, in the statement `var x = 42, y = x;`, the initializing
 * expression of `y` is a variable access `x` of kind `"V"` that refers to
 * the declaration `x = 42`.
 */
predicate variableDeclLookup(VarAccess va, VarDecl decl, string kind) {
  // restrict to declarations in same file to avoid accidentally picking up
  // unrelated global definitions
  decl = firstRefInTopLevel(va.getVariable(), Decl(), va.getTopLevel()) and
  kind = refKind(va)
}

/**
 * Holds if path expression `path`, which appears in a CommonJS `require`
 * call or an ES 2015 import statement, imports module `target`; `kind`
 * is always "I" (for "import").
 *
 * For example, in the statement `var a = require("./a")`, the path expression
 * `"./a"` imports a module `a` in the same folder.
 */
predicate importLookup(PathExpr path, Module target, string kind) {
  kind = "I" and
  target = any(Import i | path = i.getImportedPath()).getImportedModule()
}

/**
 * Gets a node that may write the property read by `prn`.
 */
DataFlowNode getAWrite(PropReadNode prn) {
  exists (AnalyzedFlowNode base, DefiniteAbstractValue baseVal, string propName |
    base.asExpr() = prn.getBase() and propName = prn.getPropertyName() and
    baseVal = base.getAValue().getAPrototype*() |
    // write to a property on baseVal
    DataFlow::valueNode(result).(AnalyzedPropertyWrite).writes(baseVal, propName, _)
    or
    // non-static class members aren't covered by `AnalyzedPropWrite`, so have to be handled
    // separately
    exists (ClassDefinition c, MemberDefinition m |
      m = c.getMember(propName) and
      baseVal.(AbstractInstance).getConstructor().(AbstractClass).getClass() = c and
      result = m.getNameExpr()
    )
  )
}

/**
 * Holds if `prop` is the property name expression of a property read that
 * may read the property written by `write`. Furthermore, `write` must be the
 * only such property write. Parameter `kind` is always bound to `"M"`
 * at the moment.
 */
predicate propertyLookup(Expr prop, DataFlowNode write, string kind) {
  exists (PropReadNode prn | prop = prn.getPropertyNameExpr() |
    count(getAWrite(prn)) = 1 and
    write = getAWrite(prn) and
    kind = "M"
  )
}

from ASTNode ref, ASTNode decl, string kind
where variableDefLookup(ref, decl, kind) or
      // prefer definitions over declarations
      not variableDefLookup(ref, _, _) and variableDeclLookup(ref, decl, kind) or
      importLookup(ref, decl, kind) or
      propertyLookup(ref, decl, kind)
select ref, decl, kind
