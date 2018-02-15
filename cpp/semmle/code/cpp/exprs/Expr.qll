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


import semmle.code.cpp.Element

/**
 * A C/C++ expression.
 */
class Expr extends StmtParent, @expr {
  /** Gets the nth child of this expression. */
  Expr getChild(int n) { exprparents(result,n,this) }

  /** Gets the number of direct children of this expression. */
  int getNumChild() { result = count(this.getAChild()) }

  /** Holds if e is the nth child of this expression. */
  predicate hasChild(Expr e, int n) { e = this.getChild(n) }

  /** Gets the enclosing function of this expression, if any. */
  Function getEnclosingFunction() { exprcontainers(this,result) }

  /** Gets the nearest enclosing set of curly braces around this expression in the source, if any. */
  Block getEnclosingBlock() {
      result = getEnclosingStmt().getEnclosingBlock()
  }

  override Stmt getEnclosingStmt() {
      result = this.getParent().(Expr).getEnclosingStmt() or
      result = this.getParent().(Stmt) or
      exists(Expr other | result = other.getEnclosingStmt() and other.getConversion() = this) or
      exists(DeclStmt d, LocalVariable v | d.getADeclaration() = v and v.getInitializer().getExpr() = this and result = d)
  }

  /** Gets the enclosing variable of this expression, if any. */
  Variable getEnclosingVariable() { exprcontainers(this,result) }

  /** Gets a child of this expression. */
  Expr getAChild() { exists (int n | result = this.getChild(n)) }

  /** Gets the parent of this expression, if any. */
  Element getParent() { exprparents(this,_,result) }

  /** Gets the location of this expression. */
  override Location getLocation() { exprs(this,_,result) } 

  /** Holds if this is an auxiliary expression generated by the compiler. */
  predicate isCompilerGenerated() {
    compgenerated(this) or
    this.getParent().(ConstructorFieldInit).isCompilerGenerated()
  }

  /**
   * Gets the type of this expression.
   *
   * As the type of an expression can sometimes be a TypedefType, calling getUnderlyingType()
   * is often more useful than calling this predicate.
   */
  Type getType() { expr_types(this,result,_) }

  /**
   * Gets the type of this expression after typedefs have been resolved.
   *
   * In most cases, this predicate will be the same as getType().  It will
   * only differ when the result of getType() is a TypedefType, in which
   * case this predicate will (possibly recursively) resolve the typedef.
   */
  Type getUnderlyingType() { result = this.getType().getUnderlyingType() }

  /**
   * Gets an integer indicating the type of expression that this represents.
   * 
   * Consider using subclasses of `Expr` rather than relying on this predicate. 
   */
  int getKind() { exprs(this,result,_) }

  /** Gets a textual representation of this expression. */
  override string toString() { none() }

  /** Gets the value of this expression, if it is a constant. */
  string getValue() { exists(@value v | values(v,result,_) and valuebind(v,this)) }

  /** Gets the source text for the value of this expression, if it is a constant. */
  string getValueText() { exists(@value v | values(v,_,result) and valuebind(v,this)) }
  
  /** Holds if this expression has a value that can be determined at compile time. */
  predicate isConstant() { valuebind(_,this) }

  /**
   * Holds if this expression is side-effect free (conservative
   * approximation). This predicate cannot be overridden;
   * override mayBeImpure() instead.
   *
   * Note that this predicate does not strictly correspond with
   * the usual definition of a 'pure' function because reading
   * from global state is permitted, just not writing / output.
   */
  final predicate isPure() {
    not this.mayBeImpure()
  }

  /**
   * Holds if it is possible that the expression may be impure. If we are not
   * sure, then it holds.
   */
  predicate mayBeImpure() {
    any()
  }

  /**
   * Holds if it is possible that the expression may be impure. If we are not
   * sure, then it holds. Unlike `mayBeImpure()`, this predicate does not
   * consider modifications to temporary local variables to be impure. If you
   * call a function in which nothing may be globally impure then the function
   * as a whole will have no side-effects, even if it mutates its own fresh
   * stack variables.
   */
  predicate mayBeGloballyImpure() {
    any()
  }

  /**
   * Holds if this expression is an lvalue. An lvalue is an expression that
   * represents a location, rather than a value.
   * See [basic.lval] for more about lvalues.
   */
  predicate isLValueCategory() {
    expr_types(this, _, 3)
  }

  /**
   * Holds if this expression is an xvalue. An xvalue is a location whose
   * lifetime is about to end (e.g. an rvalue reference returned from a function
   * call).
   * See [basic.lval] for more about xvalues.
   */
  predicate isXValueCategory() {
    expr_types(this, _, 2)
  }

  /**
   * Holds if this expression is a prvalue. A prvalue is an expression that
   * represents a value, rather than a location.
   * See [basic.lval] for more about prvalues.
   */
  predicate isPRValueCategory() {
    expr_types(this, _, 1)
  }

  /**
   * Holds if this expression is a glvalue. A glvalue is either an lvalue or an
   * xvalue.
   */
  predicate isGLValueCategory() {
    isLValueCategory() or isXValueCategory()
  }

  /**
   * Holds if this expression is an rvalue. An rvalue is either a prvalue or an
   * xvalue.
   */
  predicate isRValueCategory() {
    isPRValueCategory() or isXValueCategory()
  }
  
  /**
   * Holds if this expression has undergone an lvalue-to-rvalue conversion to
   * extract its value.
   * for example:
   * ```
   *  y = x;
   * ```
   * The VariableAccess for `x` is a prvalue, and hasLValueToRValueConversion()
   * holds because the value of `x` was loaded from the location of `x`.
   * The VariableAccess for `y` is an lvalue, and hasLValueToRValueConversion()
   * does not hold because the value of `y` was not extracted.
   *
   * See [conv.lval] for more about the lvalue-to-rvalue conversion
   */
  predicate hasLValueToRValueConversion() {
    expr_isload(this)
  }

  /**
   * Holds if this expression is an LValue, in the sense of having an address.
   *
   * Being an LValue is best approximated as having an address.
   * This is a strict superset of modifiable LValues, which are best approximated by things which could be on the left-hand side of an assignment.
   * This is also a strict superset of expressions which provide an LValue, which is best approximated by things whose address is important.
   *
   * See [basic.lval] in the C++ language specification.
   * In C++03, every expression is either an LValue or an RValue.
   * In C++11, every expression is exactly one of an LValue, an XValue, or a PRValue (with RValues being the union of XValues and PRValues).
   * Using the C++11 terminology, this predicate selects expressions whose value category is lvalue.
   */
  predicate isLValue() {
    this instanceof StringLiteral /* C++ n3337 - 5.1.1 clause 1 */
    or this.(ParenthesisExpr).getExpr().isLValue() /* C++ n3337 - 5.1.1 clause 6 */
    or (this instanceof VariableAccess and not this instanceof FieldAccess) /* C++ n3337 - 5.1.1 clauses 8 and 9, variables and data members */
    or exists(FunctionAccess fa | fa = this | /* C++ n3337 - 5.1.1 clauses 8 and 9, functions */
      fa.getTarget().isStatic()
      or not fa.getTarget().isMember()
    )
    or this instanceof ArrayExpr /* C++ n3337 - 5.2.1 clause 1 */
    or this.getType() instanceof ReferenceType /* C++ n3337 - 5.2.2 clause 10
                                                              5.2.5 clause 4, no bullet point
                                                              5.2.7 clauses 2 and 5
                                                              5.2.9 clause 1
                                                              5.2.10 clause 1
                                                              5.2.11 clause 1
                                                              5.4 clause 1 */
    or this.(FieldAccess).getQualifier().isLValue() /* C++ n3337 - 5.2.5 clause 4, 2nd bullet point */
    or this instanceof TypeidOperator /* C++ n3337 - 5.2.8 clause 1 */
    or this instanceof PointerDereferenceExpr /* C++ n3337 - 5.3.1 clause 1 */
    or this instanceof PrefixIncrExpr /* C++ n3337 - 5.3.2 clause 1 */
    or this instanceof PrefixDecrExpr /* C++ n3337 - 5.3.2 clause 2 */
    or exists(ConditionalExpr ce | ce = this | /* C++ n3337 - 5.16 clause 4 */
      ce.getThen().isLValue() and
      ce.getElse().isLValue() and
      ce.getThen().getType() = ce.getElse().getType()
    )
    or this instanceof Assignment /* C++ n3337 - 5.17 clause 1 */
    or this.(CommaExpr).getRightOperand().isLValue() /* C++ n3337 - 5.18 clause 1 */
  }

  /**
   * Gets the precedence of the main operator of this expression;
   * higher precedence binds tighter.
   */
  int getPrecedence() {
    none()
  }

  /**
   * Holds if this expression has a conversion.
   *
   * Type casts and parameterized expressions are not part of the main
   * expression tree structure but attached on the nodes they convert,
   * for example:
   * ```
   *  2 + (int)(bool)1
   * ```
   * has the main tree:
   * ```
   *  2 + 1
   * ```
   * and 1 has a bool conversion, while the bool conversion itself has
   * an int conversion.
   */
  predicate hasConversion() { exists(Expr e | exprconv(this,e)) }

  /**
   * Holds if this expression has an implicit conversion.
   * 
   * For example in `char *str = 0`, the `0` has an implicit conversion to type `char *`.
   */
  predicate hasImplicitConversion() { exists(Expr e | exprconv(this,e) and e.(Cast).isImplicit()) }

  /**
   * Holds if this expression has an explicit conversion.
   * 
   * For example in `(MyClass *)ptr`, the `ptr` has an explicit
   * conversion to type `MyClass *`.
   */
  predicate hasExplicitConversion() { exists(Expr e | exprconv(this,e) and not e.(Cast).isImplicit()) }

  /**
   * Gets the conversion associated with this expression, if any.
   */
  Expr getConversion() { exprconv(this,result) }

  /**
   * Gets a string describing the conversion associated with this expression,
   * or "" if there is none.
   */
  string getConversionString() { (result = this.getConversion().toString() and this.hasConversion()) or (result = "" and not this.hasConversion()) }

  /** Gets the fully converted form of this expression, including all type casts and other conversions. */
  cached
  Expr getFullyConverted() {
    if this.hasConversion() then
      result = this.getConversion().getFullyConverted()
    else
      result = this
  }

  /**
   * Gets this expression with all of its explicit casts, but none of its
   * implicit casts. More precisely this takes conversions up to the last
   * explicit cast (there may be implicit conversions along the way), but does
   * not include conversions after the last explicit cast.
   *
   * C++ example: `C c = (B)d` might have three casts: (1) an implicit cast
   * from A to some D, (2) an explicit cast from D to B, and (3) an implicit
   * cast from B to C. Only (1) and (2) would be included.
   */
  Expr getExplicitlyConverted() {
    // result is this or one of its conversions
    result = this.getConversion*() and
    // result is not an implicit conversion - it's either the expr or an explicit cast
    (result = this or not result.(Cast).isImplicit()) and
    // there is no further explicit conversion after result
    not exists(Cast other | other = result.getConversion+() and not other.isImplicit())
  }

  /**
   * Gets this expression with all of its initial implicit casts, but none of
   * its explicit casts. More precisely, this takes all implicit conversions
   * up to (but not including) the first explicit cast (if any).
   */
  Expr getImplicitlyConverted() {
    if this.hasImplicitConversion() then
      result = this.getConversion().getImplicitlyConverted()
    else
      result = this
  }
 
  /**
   * Gets the type of this expression, after any implicit conversions and explicit casts, and after resolving typedefs.
   *
   * As an example, consider the AST fragment `(i64)(void*)0` in the context of `typedef long long i64;`. The fragment
   * contains three expressions: two CStyleCasts and one literal Zero. For all three expressions, the result of this
   * predicate will be `long long`.
   */
  Type getActualType() {
    result = this.getFullyConverted().getType().getUnderlyingType()
  }

  /** Holds if this expression is parenthesised. */
  predicate isParenthesised() { this.getConversion() instanceof ParenthesisExpr }

  /** Gets the function containing this control-flow node. */
  Function getControlFlowScope() {
    result = this.getEnclosingFunction()
  }
}

/**
 * A C/C++ operation.
 */
abstract class Operation extends Expr {
  /** Gets the operator of this operation. */
  abstract string getOperator();

  /** Gets an operand of this operation. */
  Expr getAnOperand() {
    result = this.getAChild()
  }
}

/**
 * A C/C++ unary operation.
 */
abstract class UnaryOperation extends Operation {
  /** Gets the operand of this unary operation. */
  Expr getOperand() { this.hasChild(result,0) }

  override string toString() { result = this.getOperator() + " ..." }

  override predicate mayBeImpure() {
    this.getOperand().mayBeImpure()
  }
  override predicate mayBeGloballyImpure() {
    this.getOperand().mayBeGloballyImpure()
  }
}

/**
 * A C/C++ binary operation.
 */
abstract class BinaryOperation extends Operation {
  /** Gets the left operand of this binary operation. */
  Expr getLeftOperand() { this.hasChild(result,0) }

  /** Gets the right operand of this binary operation. */
  Expr getRightOperand() { this.hasChild(result,1) }

  override string toString() { result = "... " + this.getOperator() + " ..." }

  override predicate mayBeImpure() {
    this.getLeftOperand().mayBeImpure() or
    this.getRightOperand().mayBeImpure()
  }
  override predicate mayBeGloballyImpure() {
    this.getLeftOperand().mayBeGloballyImpure() or
    this.getRightOperand().mayBeGloballyImpure()
  }
}

/**
 * A C++11 parenthesized braced initializer list within a template.
 *
 * This is used to represent particular syntax within templates where the final
 * form of the expression is not known. In actual instantiations, it will have
 * been turned into a constructor call or aggregate initializer or similar.
 */
class ParenthesizedBracedInitializerList extends Expr, @braced_init_list {
  override string toString() { result = "({...})" }
}

/**
 * A C/C++ parenthesis expression.
*/
class ParenthesisExpr extends Conversion, @parexpr {
  override string toString() { result = "(...)" }
}

/**
 * A C/C++ expression that has not been resolved.
 */
class ErrorExpr extends Expr, @errorexpr {
  override string toString() { result = "<error expr>" }
}

/**
 * A Microsoft C/C++ __assume expression.
 */
class AssumeExpr extends Expr, @assume {
  override string toString() { result = "__assume(...)" }
}

/**
 * A C/C++ comma expression.
 */
class CommaExpr extends Expr, @commaexpr {
  /**
   * Gets the left operand, which is the one whose value is discarded.
   */
  Expr getLeftOperand() { this.hasChild(result,0) }

  /**
   * Gets the right operand, which is the one whose value is equal to the value
   * of the comma expression itself.
   */
  Expr getRightOperand() { this.hasChild(result,1) }

  override string toString() { result = "... , ..." }

  override int getPrecedence() { result = 0 }

  override predicate mayBeImpure() {
    this.getLeftOperand().mayBeImpure() or
    this.getRightOperand().mayBeImpure()
  }
  override predicate mayBeGloballyImpure() {
    this.getLeftOperand().mayBeGloballyImpure() or
    this.getRightOperand().mayBeGloballyImpure()
  }
}

/**
 * A C/C++ address-of expression.
 */
class AddressOfExpr extends UnaryOperation, @address_of {
  /** Gets the function or variable whose address is taken. */
  Declaration getAddressable() {
       result = this.getOperand().(Access).getTarget()
       // this handles the case where we are taking the address of a reference variable
    or result = this.getOperand().(ReferenceDereferenceExpr).getChild(0).(Access).getTarget()
  }

  override string getOperator() { result = "&" }

  override int getPrecedence() { result = 15 }

  override predicate mayBeImpure() {
    this.getOperand().mayBeImpure()
  }
  override predicate mayBeGloballyImpure() {
    this.getOperand().mayBeGloballyImpure()
  }
}

/**
 * An implicit conversion from type T to type T&amp;.
 *
 * This typically occurs when an expression of type T is used to initialize a variable or parameter of
 * type T&amp;, and is to reference types what AddressOfExpr is to pointer types - though this class is
 * considered to be a conversion rather than an operation, and as such doesn't occur in the main AST.
 */
class ReferenceToExpr extends Conversion, @reference_to {
  override string toString() { result = "(reference to)" }

  override int getPrecedence() { result = 15 }
}

/**
 * An instance of unary operator * applied to a built-in type.
 *
 * For user-defined types, see OverloadedPointerDereferenceExpr.
 */
class PointerDereferenceExpr extends UnaryOperation, @indirect {
  /**
   * DEPRECATED: Use getOperand() instead.
   *
   * Gets the expression that is being dereferenced.
   */
  deprecated Expr getExpr() {
    result = getOperand()
  }

  override string getOperator() { result = "*" }

  override int getPrecedence() { result = 15 }

  override predicate mayBeImpure() {
    this.getChild(0).mayBeImpure() or
    this.getChild(0).getFullyConverted().getType().(DerivedType).getBaseType().isVolatile()
  }
  override predicate mayBeGloballyImpure() {
    this.getChild(0).mayBeGloballyImpure() or
    this.getChild(0).getFullyConverted().getType().(DerivedType).getBaseType().isVolatile()
  }
}

/**
 * An implicit conversion from type T&amp; to type T.
 *
 * This typically occurs when an variable of type T&amp; is used in a context which expects type T, and
 * is to reference types what PointerDereferenceExpr is to pointer types - though this class is
 * considered to be a conversion rather than an operation, and as such doesn't occur in the main AST.
 */
class ReferenceDereferenceExpr extends Conversion, @ref_indirect {
  override string toString() { result = "(reference dereference)" }
}

/**
 * A C++ `new` (non-array) expression.
 */
class NewExpr extends Expr, @new_expr {
  override string toString() { result = "new" }

  override int getPrecedence() { result = 15 }

  /**
   * Gets the type that is being allocated.
   *
   * For example, for `new int` the result is `int`.
   */
  Type getAllocatedType() {
    new_allocated_type(this, result)
  }

  /**
   * Gets the call to a non-default `operator new` which allocates storage, if any.
   *
   * As a rule of thumb, there will be an allocator call precisely when the type
   * being allocated has a custom `operator new`, or when an argument list appears
   * after the `new` keyword and before the name of the type being allocated.
   *
   * In particular note that uses of placement-new and nothrow-new will have an
   * allocator call.
   */
  FunctionCall getAllocatorCall() { result = this.getChild(0) }

  /**
   * Gets the call or expression which initializes the first element of the array, if any.
   *
   * As examples, for `new int(4)`, this will be `4`, and for `new std::vector(4)`, this will
   * be a call to the constructor `std::vector::vector(size_t)` with `4` as an argument.
   */
  Expr getInitializer() { result = this.getChild(1) }
}

/**
 * A C++ `new[]` (array) expression.
 */
class NewArrayExpr extends Expr, @new_array_expr {
  override string toString() { result = "new[]" }

  override int getPrecedence() { result = 15 }

  /**
   * Gets the type that is being allocated.
   *
   * For example, for `new int[5]` the result is `int[5]`.
   */
  Type getAllocatedType() {
    new_array_allocated_type(this, result)
  }

  /**
   * Gets the call to a non-default `operator new[]` which allocates storage for the array, if any.
   *
   * If the default `operator new[]` is used, then there will be no call.
   */
  FunctionCall getAllocatorCall() { result = this.getChild(0) }

  /**
   * Gets the call or expression which initializes the first element of the array, if any.
   *
   * This will either be a call to the default constructor for the array's element type (as
   * in `new std::string[10]`), or a literal zero for arrays of scalars which are zero-initialized
   * due to extra parentheses (as in `new int[10]()`).
   *
   * At runtime, the constructor will be called once for each element in the array, but the
   * constructor call only exists once in the AST.
   */
  Expr getInitializer() { result = this.getChild(1) }

  /**
   * Gets the extent of the non-constant array dimension, if any.
   *
   * As examples, for `new char[n]` and `new char[n][10]`, this gives `n`, but for `new char[10]` this
   * gives nothing, as the 10 is considered part of the type.
   */
  Expr getExtent() { result = this.getChild(2) }
}

/**
 * A C++ `delete` (non-array) expression.
 */
class DeleteExpr extends Expr, @delete_expr {
  override string toString() { result = "delete" }

  override int getPrecedence() { result = 15 }

  /**
   * Gets the call to a destructor which occurs prior to the object's memory being deallocated, if any.
   */
  DestructorCall getDestructorCall() { result = this.getChild(1) }

  /**
   * Gets the call to a non-default `operator delete` which deallocates storage, if any.
   *
   * This will only be present when the type being deleted has a custom `operator delete`.
   */
  FunctionCall getAllocatorCall() { result = this.getChild(0) }

  /**
   * Gets the object being deleted.
   */
  Expr getExpr() { result = this.getChild(3) or result = this.getChild(1).getChild(-1) }
}

/**
 * A C++ `delete[]` (array) expression.
 */
class DeleteArrayExpr extends Expr, @delete_array_expr {
  override string toString() { result = "delete[]" }

  override int getPrecedence() { result = 15 }

  /**
   * Gets the call to a destructor which occurs prior to the array's memory being deallocated, if any.
   *
   * At runtime, the destructor will be called once for each element in the array, but the
   * destructor call only exists once in the AST.
   */
  DestructorCall getDestructorCall() { result = this.getChild(1) }

  /**
   * Gets the call to a non-default `operator delete` which deallocates storage, if any.
   *
   * This will only be present when the type being deleted has a custom `operator delete`.
   */
  FunctionCall getAllocatorCall() { result = this.getChild(0) }

  /**
   * Gets the array being deleted.
   */
  Expr getExpr() { result = this.getChild(3) or result = this.getChild(1).getChild(-1) }
}

/**
 * A compound statement enclosed in parentheses used as an expression (a GNU extension to C/C++).
 */
class StmtExpr extends Expr, @expr_stmt {
  override string toString() { result = "(statement expression)" }

  /**
   * Gets the statement enclosed by this `StmtExpr`.
   */
  Stmt getStmt() { result.getParent() = this }

  /**
   * Gets the result expression of the enclosed statement. For example,
   * `a+b` is the result expression in this example:
   *
   * ```
   * x = ({ dosomething(); a+b; });
   * ```
   */
  Expr getResultExpr() {
    result = getStmtResultExpr(getStmt())
  }
}

/** Get the result expression of a statement. (Helper function for StmtExpr.) */
private Expr getStmtResultExpr(Stmt stmt) {
  result = stmt.(ExprStmt).getExpr() or
  result = getStmtResultExpr(stmt.(Block).getLastStmt())
}

/**
 * A C/C++ this expression.
 */
class ThisExpr extends Expr, @thisaccess {
  override string toString() { result = "this" }

  override predicate mayBeImpure() {
    none()
  }
  override predicate mayBeGloballyImpure() {
    none()
  }
}

/**
 * A code block expression, for example `^ int (int x, int y) {return x + y;}`.
 *
 * Blocks are a language extension supported by Clang, and by Apple's
 * branch of GCC.
 */
class BlockExpr extends Literal {
  BlockExpr() {
    code_block(this, _)
  }

  override string toString() { result = "^ { ... }" }

  /**
   * Gets the (anonymous) function associated with this code block expression.
   */
  Function getFunction() {
    code_block(this, result)
  }
}

/**
 * A C++11 `noexcept` expression, for example `noexcept(1 + 2)`.
 */
class NoExceptExpr extends Expr, @noexceptexpr {
  override string toString() { result = "noexcept(...)" }

  /**
   * Gets the expression inside this noexcept expression.
   */
  Expr getExpr() {
    result = this.getChild(0)
  }
}