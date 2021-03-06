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
 * @name Field masks field in super class
 * @description Hiding a field in a superclass by redeclaring it in a subclass might be
 *              unintentional, especially if references to the hidden field are not qualified using
 *              'super'.
 * @kind problem
 * @problem.severity warning
 * @precision medium
 * @id java/field-masks-super-field
 * @tags maintainability
 *       readability
 */
import java

class VisibleInstanceField extends Field {
  VisibleInstanceField() {
    not this.isPrivate() and
    not this.isStatic()
  }
}

from RefType type, RefType supertype, 
     VisibleInstanceField masked, VisibleInstanceField masking
where type.getASourceSupertype+() = supertype and
      masking.getDeclaringType() = type and 
      masked.getDeclaringType() = supertype and
      masked.getName() = masking.getName() and
      // Exclude intentional masking.
      not exists(VarAccess va | va.getVariable() = masked | 
        va.getQualifier() instanceof SuperAccess
      ) and
      type.fromSource()
select masking, "This field shadows another field called $@ in a superclass.",
  masked, masked.getName()
