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
 * @name Unmatchable caret in regular expression
 * @description Regular expressions containing a caret '^' in the middle cannot be matched, whatever the input.
 * @kind problem
 * @tags reliability
 *       correctness
 * @problem.severity error
 * @sub-severity low
 * @precision high
 * @id py/regex/unmatchable-caret
 */

import python
import semmle.python.regex

predicate unmatchable_caret(Regex r, int start) {
    not r.getAMode() = "MULTILINE" and
    not r.getAMode() = "VERBOSE" and
    r.specialCharacter(start, start+1, "^") and
    not r.firstItem(start, start+1)
}

from Regex r, int offset
where unmatchable_caret(r, offset)
select r, "This regular expression includes an unmatchable caret at offset " + offset.toString() + "."
