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
 * @name First parameter of a class method is not named 'cls'
 * @description Using an alternative name for the first argument of a class method makes code more
 *              difficult to read; PEP8 states that the first argument to class methods should be 'cls'.
 * @kind problem
 * @tags maintainability
 *       readability
 *       convention
 * @problem.severity recommendation
 * @sub-severity high
 * @precision high
 * @id py/not-named-cls
 */

import python

predicate first_arg_cls(Function f) {
    exists(string argname | argname = f.getArgName(0) |
        argname = "cls" or
        /* Not PEP8, but relatively common */
        argname = "mcls"
    )
}

predicate is_type_method(Function f) {
    exists(ClassObject c | c.getPyClass() = f.getScope() and c.getASuperType() = theTypeType())
}

predicate classmethod_decorators_only(Function f) {
    forall(Expr decorator |
        decorator = f.getADecorator() |
            ((Name) decorator).getId() = "classmethod")
}

from Function f, string message
where (f.getADecorator().(Name).getId() = "classmethod" or is_type_method(f)) and 
not first_arg_cls(f) and classmethod_decorators_only(f) and
not f.getName() = "__new__" and
(
  if exists(f.getArgName(0)) then
      message = "Class methods or methods of a type deriving from type should have 'cls', rather than '" + 
            f.getArgName(0) + "', as their first argument."
  else
      message = "Class methods or methods of a type deriving from type should have 'cls' as their first argument."
)

select f, message
