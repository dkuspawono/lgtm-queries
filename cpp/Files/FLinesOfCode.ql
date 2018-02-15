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
 * @name Lines of code in files
 * @kind treemap
 * @description Measures the number of lines in a file that contain
 *              code (rather than lines that only contain comments
 *              or are blank)
 * @treemap.warnOn highValues
 * @metricType file
 * @metricAggregate avg sum max
 * @precision very-high
 * @id cpp/lines-of-code-in-files
 * @tags maintainability
 *       complexity
 */
import cpp

from File f
where f.fromSource()
select f, f.getMetrics().getNumberOfLinesOfCode() as n
order by n desc