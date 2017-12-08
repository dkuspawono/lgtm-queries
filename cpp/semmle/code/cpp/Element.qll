// Copyright 2017 Semmle Ltd.
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

import semmle.code.cpp.Location

/**
 * A C/C++ element. This class is the base class for all C/C++
 * elements, such as functions, classes, expressions, and so on.
 */
class Element extends @element {

  /** Gets a textual representation of this element. */
  string toString() { none() }

  /** Gets the primary file where this element occurs. */
  File getFile() { result = this.getLocation().getFile() }

  /**
   * Holds if this element may be from source.
   *
   * Note: this predicate is provided for consistency with the libraries
   * for other languages, such as Java and Python. In C++, all files are
   * classified as source files, so this predicate is always true.
   */
  predicate fromSource() { this.getFile().fromSource() }

  /**
   * Holds if this element may be from a library.
   *
   * DEPRECATED: always true.
   */
  deprecated
  predicate fromLibrary() { this.getFile().fromLibrary() }

  /** Gets the primary location of this element. */
  Location getLocation() {
    none()
  }

  /**
   * Gets the source of this element: either itself or a macro that expanded
   * to this element.
   *
   * If the element is not in a macro expansion, then the "root" is just
   * the element itself. Otherwise, it is the definition of the innermost
   * macro whose expansion the element is in.
   *
   * This method is useful for filtering macro results in checks: simply
   * blame `e.findRootCause` rather than `e`. This will report only bugs
   * that are not in macros, and in addition report macros that (somewhere)
   * expand to a bug.
   */
  Element findRootCause() {
    if (exists(MacroInvocation mi | this = mi.getAGeneratedElement())) then
      exists(MacroInvocation mi |
        this = mi.getAGeneratedElement() and
        not exists(MacroInvocation closer |
          this = closer.getAGeneratedElement() and
          mi = closer.getParentInvocation+()
        ) and
        result = mi.getMacro()
      )
    else
      result = this
  }

  /**
   * Gets the parent scope of this `Element`, if any.
   * A scope is a `Type` (`Class` / `Enum`), a `Namespace`, a `Block`, a `Function`,
   * or certain kinds of `Statement`.
   */
  Element getParentScope() {
    // result instanceof class
    exists (Declaration m
    | m = this and
      result = m.getDeclaringType() and
      not this instanceof EnumConstant)
    or
    exists (TemplateClass tc
    | this = tc.getATemplateArgument() and result = tc)

    // result instanceof namespace
    or
    exists (Namespace n
    | result = n and n.getADeclaration() = this)
    or
    exists (FriendDecl d, Namespace n
    | this = d and n.getADeclaration() = d and result = n)
    or
    exists (Namespace n
    | this = n and result = n.getParentNamespace())

    // result instanceof stmt
    or
    exists (LocalVariable v
    | this = v and
      exists (DeclStmt ds
      | ds.getADeclaration() = v and result = ds.getParent()))
    or
    exists (Parameter p
    | this = p and result = p.getFunction())
    or
    exists (GlobalVariable g, Namespace n
    | this = g and n.getADeclaration() = g and result = n)
    or
    exists (EnumConstant e
    | this = e and result = e.getDeclaringEnum())

    // result instanceof block|function
    or
    exists (Block b
    | this = b and blockscope(b, result))
    or
    exists (TemplateFunction tf
    | this = tf.getATemplateArgument() and result = tf)

    // result instanceof stmt
    or
    exists (ControlStructure s
    | this = s and result = s.getParent())

    // result instanceof namespace|class|function
    or
    usings(this,_,result,_)
  }

  /**
   * Holds if this element comes from a macro expansion. Only elements that
   * are entirely generated by a macro are included - for elements that
   * partially come from a macro, see `isAffectedByMacro`.
   */
  predicate isInMacroExpansion() {
    inMacroExpansion(this)
  }

  /**
   * Holds if this element is affected in any way by a macro. All elements
   * that are totally or partially generated by a macro are included, so
   * this is a super-set of `isInMacroExpansion`.
   */
  predicate isAffectedByMacro() {
    affectedByMacro(this)
  }

  private Element getEnclosingElementPref() {
    enclosingfunction(this, result) or
    stmtfunction(this, result) or
    this.(LocalScopeVariable).getFunction() = result or
    enumconstants(this, result, _, _, _, _) or
    derivations(this, result, _, _, _) or
    stmtparents(this, _, result) or
    exprparents(this, _, result) or
    namequalifiers(this, result, _, _) or
    initialisers(this, result, _, _) or
    exprconv(result, this) or
    this = result.(MacroAccess).getParentInvocation() or
    result = this.(MacroInvocation).getExpr() or // macroinvocation -> outer Expr
    param_decl_bind(this,_,result)
  }

  /** Gets the closest `Element` enclosing this one. */
  cached Element getEnclosingElement() {
    result = getEnclosingElementPref() or
    (
      not exists(getEnclosingElementPref()) and
      (
        // macroinvocation -> all enclosed elements
        inmacroexpansion(result, this)
        or
        macrolocationbind(
          this.(MacroInvocation),
          result.(VariableDeclarationEntry).getLocation())
        or
        macrolocationbind(
          this.(MacroInvocation),
          result.(FunctionDeclarationEntry).getLocation())
        or
        member(result, _, this)
        or
        exprcontainers(this, result)
        or
        var_decls(this, result, _, _, _)
      )
    )
  }

  /**
   * Holds if this `Element` is a part of a template instantiation (but not
   * the template itself).
   */
  predicate isFromTemplateInstantiation(Element instantiation) {
    (
      // instantiation is an enclosing Element
      instantiation = getEnclosingElement*() or
      exists(Declaration d |
        this.(DeclarationEntry).getDeclaration() = d and
        instantiation = d.getEnclosingElement*()
      )
    ) and (
      // instantiation is a template instantiation
      function_instantiation(instantiation, _) or
      class_instantiation(instantiation, _)
    )
  }
}

/**
 * A C++11 `static_assert` or C11 `_Static_assert` construct.
 */
class StaticAssert extends Locatable, @static_assert {
  override string toString() { result = "static_assert(..., \"" + getMessage() + "\")" }
  Expr getCondition()    { static_asserts(this, result, _, _) }
  string getMessage()    { static_asserts(this, _, result, _) }
  override Location getLocation() { static_asserts(this, _, _, result) }
}
