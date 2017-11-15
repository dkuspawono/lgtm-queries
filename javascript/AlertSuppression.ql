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

/**
 * @name Alert suppression
 * @description Generates information about alert suppressions.
 * @kind alert-suppression
 * @id js/alert-suppression
 */

import javascript

/**
 * An alert suppression comment.
 */
class SuppressionComment extends LineComment {
  string annotation;

  SuppressionComment() {
    annotation = getText().regexpCapture("\\s*(lgtm\\s*(?:\\[[^\\]]*\\]|\\b(?!\\[))).*", 1)
  }

  /** Gets the suppression annotation in this comment. */
  string getAnnotation() {
    result = annotation
  }

  /**
  * Holds if this comment applies to the range from column `startcolumn` of line `startline`
  * to column `endcolumn` of line `endline` in file `filepath`.
  */
  predicate covers(string filepath, int startline, int startcolumn, int endline, int endcolumn) {
    this.getLocation().hasLocationInfo(filepath, startline, _, endline, endcolumn) and
    startcolumn = 1
  }

  /** Gets the scope of this suppression. */
  SuppressionScope getScope() {
    this = result.getSuppressionComment()
  }
}

/**
 * The scope of an alert suppression comment.
 */
class SuppressionScope extends @comment {
  SuppressionScope() {
    this instanceof SuppressionComment
  }

  /** Gets a suppression comment with this scope. */
  SuppressionComment getSuppressionComment() {
    result = this
  }

  /**
  * Holds if this element is at the specified location.
  * The location spans column `startcolumn` of line `startline` to
  * column `endcolumn` of line `endline` in file `filepath`.
  * For more information, see
  * [LGTM locations](https://lgtm.com/docs/ql/locations).
  */
  predicate hasLocationInfo(string filepath, int startline, int startcolumn, int endline, int endcolumn) {
    this.(SuppressionComment).covers(filepath, startline, startcolumn, endline, endcolumn)
  }

  /** Gets a textual representation of this element. */
  string toString() {
    result = "suppression range"
  }
}

from SuppressionComment c
select c,                 // suppression comment
       c.getText(),       // text of suppression comment (excluding delimiters)
       c.getAnnotation(), // text of suppression annotation
       c.getScope()       // scope of suppression
