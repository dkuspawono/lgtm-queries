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

import java

/**
 * An Objective-C Native Interface (OCNI) comment.
 */
class OCNIComment extends Javadoc {
  OCNIComment() {
    // The comment must start with `-[` ...
    getChild(0).getText().matches("-[%") and
    // ... and it must end with `]-`.
    getChild(getNumChild()-1).getText().matches("%]-")
  }
}

/** Auxiliary predicate: `ocni` is an OCNI comment associated with method `m`. */
private predicate ocniComment(OCNIComment ocni, Method m) {
  // The associated callable must be marked as `native` ...
  m.isNative() and
  // ... and the comment has to be contained in `m`.
  ocni.getFile() = m.getFile() and
  ocni.getLocation().getStartLine() in [m.getLocation().getStartLine()..m.getLocation().getEndLine()]
}

/**
 * An Objective-C Native Interface (OCNI) comment that contains Objective-C code
 * implementing a native method.
 */
class OCNIMethodComment extends OCNIComment {
  OCNIMethodComment() {
    ocniComment(this, _)
  }

  /** Get the method implemented by this comment. */
  Method getImplementedMethod() {
    ocniComment(this, result)
  }
}

/**
 * An Objective-C Native Interface (OCNI) native import comment.
 */
class OCNIImport extends OCNIComment {
  OCNIImport() {
    getAChild().getText().regexpMatch(".*#(import|include).*") and
    not exists (RefType rt | rt.getFile() = this.getFile() |
      rt.getLocation().getStartLine() < getLocation().getStartLine()
    )
  }
}
