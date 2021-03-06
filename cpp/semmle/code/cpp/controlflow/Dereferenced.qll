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

import default
import Nullness

/**
 * Holds if the call `fc` will dereference argument `i`.
 */
predicate callDereferences(FunctionCall fc, int i)
{
  exists(string name |
    fc.getTarget().hasQualifiedName(name) and
    (
      (name = "bcopy" and i in [0..1]) or
      (name = "memcpy" and i in [0..1]) or
      (name = "memmove" and i in [0..1]) or
      (name = "strcpy" and i in [0..1]) or
      (name = "strncpy" and i in [0..1]) or
      (name = "strdup" and i = 0) or
      (name = "strndup" and i = 0) or
      (name = "strlen" and i = 0) or
      (name = "printf" and fc.getArgument(i).getType() instanceof PointerType) or
      (name = "fprintf" and fc.getArgument(i).getType() instanceof PointerType) or
      (name = "sprintf" and fc.getArgument(i).getType() instanceof PointerType) or
      (name = "snprintf" and fc.getArgument(i).getType() instanceof PointerType) or
      (name = "vprintf" and fc.getArgument(i).getType() instanceof PointerType) or
      (name = "vfprintf" and fc.getArgument(i).getType() instanceof PointerType) or
      (name = "vsprintf" and fc.getArgument(i).getType() instanceof PointerType) or
      (name = "vsnprintf" and fc.getArgument(i).getType() instanceof PointerType)
    )
  )
}

/**
 * Holds if evaluation of `op` dereferences `e`.
 */
predicate dereferencedByOperation(Expr op, Expr e)
{
  exists(PointerDereferenceExpr deref |
    deref.getAChild() = e and deref = op and
    not deref.getParent*() instanceof SizeofOperator)
  or
  exists(CrementOperation crement |
    dereferencedByOperation(e, op) and crement.getOperand() = e)
  or
  exists(ArrayExpr ae |
    (not ae.getParent() instanceof AddressOfExpr and
      not ae.getParent*() instanceof SizeofOperator) and
    ae = op and
    (
      (e = ae.getArrayBase() and e.getType() instanceof PointerType)
      or
      (e = ae.getArrayOffset() and e.getType() instanceof PointerType)
    )
  )
  or
  exists(AddressOfExpr addof, ArrayExpr ae |
    dereferencedByOperation(addof, op) and addof.getOperand() = ae and
    (e = ae.getArrayBase() or e = ae.getArrayOffset()) and
    e.getType() instanceof PointerType)
  or
  exists(UnaryArithmeticOperation arithop |
    dereferencedByOperation(arithop, op) and e = arithop.getAnOperand() and e.getType() instanceof PointerType)
  or
  exists(BinaryArithmeticOperation arithop |
    dereferencedByOperation(arithop, op) and e = arithop.getAnOperand() and e.getType() instanceof PointerType)
  or

  exists(FunctionCall fc, int i |
    (callDereferences(fc, i) or functionCallDereferences(fc, i))
    and e = fc.getArgument(i) and op = fc)
  or
  // ptr->Field
  e = op.(FieldAccess).getQualifier() and isClassPointerType(e.getType())
  or
  // ptr->method()
  e = op.(Call).getQualifier() and isClassPointerType(e.getType())
}

private predicate isClassPointerType(Type t) {
  t.getUnderlyingType().(PointerType).getBaseType().getUnderlyingType() instanceof Class
}

/**
 * Holds if `e` will be dereferenced after being evaluated.
 */
predicate dereferenced(Expr e)
{
  dereferencedByOperation(_, e)
}

pragma[noinline]
private predicate functionCallDereferences(FunctionCall fc, int i)
{
  functionDereferences(fc.getTarget(), i)
}

/**
 * Holds if the body of a function `f` is likely to dereference its `i`th
 * parameter unconditionally. This analysis does not account for reassignment.
 */
predicate functionDereferences(Function f, int i)
{
  exists(VariableAccess access, Parameter p |
    p = f.getParameter(i) and
    dereferenced(access) and
    access = p.getAnAccess() and
    not checkedValid(p, access))
}
