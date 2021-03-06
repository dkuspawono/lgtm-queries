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

import semmle.code.cpp.Declaration

/**
 * A C++ friend declaration [N4140 11.3].
 * For example:
 *
 *   class A {
 *     friend void f(int);
 *     friend class X;
 *   };
 *
 *   void f(int x) { ... }
 *   class X { ... };
 */
class FriendDecl extends Declaration, @frienddecl {
  /**
   * Gets the location of this friend declaration. The result is the
   * location of the friend declaration itself, not the class or function
   * that it refers to. Note: to get the target of the friend declaration,
   * use `getFriend`.
   */
  override Location getADeclarationLocation() { result = this.getLocation() }

  /**
   * Implements the abstract method `Declaration.getDefinitionLocation`. A
   * friend declaration cannot be a definition because it is only a link to
   * another class or function. But we have to provide an implementation of
   * this method, so we use the location of the declaration as the location
   * of the definition. Note: to get the target of the friend declaration,
   * use `getFriend`.
   */
  override Location getDefinitionLocation() { result = this.getLocation() }

  /** Gets the location of this friend declaration. */
  override Location getLocation() { frienddecls(this,_,_,result) }

  /** Gets a descriptive string for this friend declaration. */
  override string getName() {
    result = this.getDeclaringClass().getName() + "'s friend"
  }

  /**
   * Friend declarations do not have specifiers. It makes no difference
   * whether they are declared in a public, protected or private section of
   * the class.
   */
  override Specifier getASpecifier() { none() }

  /**
   * Gets the target of this friend declaration.
   * For example: `X` in `class A { friend class X }`.
   */
  AccessHolder getFriend() { frienddecls(this,_,result,_) }

  /**
   * Gets the declaring class (also known as the befriending class).
   * For example: `A` in `class A { friend class X }`.
   */
  Class getDeclaringClass() { frienddecls(this,result,_,_) }

  /* Holds if this declaration is a top-level declaration. */
  override predicate isTopLevel() { none() }
}
