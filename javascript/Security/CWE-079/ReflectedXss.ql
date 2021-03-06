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
 * @name Reflected cross-site scripting
 * @description Writing user input directly to an HTTP response allows for
 *              a cross-site scripting vulnerability.
 * @kind problem
 * @problem.severity error
 * @precision high
 * @id js/reflected-xss
 * @tags security
 *       external/cwe/cwe-079
 *       external/cwe/cwe-116
 */

import javascript
import semmle.javascript.security.dataflow.ReflectedXss

from XssDataFlowConfiguration xss, DataFlow::Node source, DataFlow::Node sink
where xss.flowsFrom(sink, source)
select sink, "Cross-site scripting vulnerability due to $@.",
       source, "user-provided value"