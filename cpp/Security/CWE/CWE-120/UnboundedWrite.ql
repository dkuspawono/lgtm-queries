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
 * @name Unbounded write
 * @description Buffer write operations that do not control the length
 *              of data written may overflow.
 * @kind problem
 * @problem.severity error
 * @precision medium
 * @id cpp/unbounded-write
 * @tags reliability
 *       security
 *       external/cwe/cwe-120
 *       external/cwe/cwe-787
 *       external/cwe/cwe-805
 */
import semmle.code.cpp.security.BufferWrite
import semmle.code.cpp.security.Security
import semmle.code.cpp.security.TaintTracking

// --- Summary of CWE-120 violations ---
//
// The essence of CWE-120 is that string / buffer copies that are
// potentially unbounded, e.g. null terminated string copy,
// should be controlled e.g. by using strncpy instead of strcpy.
// In practice this is divided into several queries that
// handle slightly different sub-cases, exclude some acceptable uses,
// and produce reasonable messages to fit each issue.
//
// cases:
//    hasExplicitLimit()    exists(getMaxData())  exists(getBufferSize(bw.getDest(), _))) handled by
//    NO                    NO                    either                                      UnboundedWrite.ql isUnboundedWrite()
//    NO                    YES                   NO                                          UnboundedWrite.ql isMaybeUnboundedWrite()
//    NO                    YES                   YES                                         OverrunWrite.ql, OverrunWriteFloat.ql
//    YES                   either                YES                                         BadlyBoundedWrite.ql
//    YES                   either                NO                                          (assumed OK)

// --- CWE-120UnboundedWrite ---

predicate isUnboundedWrite(BufferWrite bw) {
  not bw.hasExplicitLimit()                           // has no explicit size limit
  and (not exists(bw.getMaxData()))                   // and we can't deduce an upper bound to the amount copied
}

/*predicate isMaybeUnboundedWrite(BufferWrite bw)
{
  not bw.hasExplicitLimit()                           // has no explicit size limit
  and exists(bw.getMaxData())                         // and we can deduce an upper bound to the amount copied
  and (not exists(getBufferSize(bw.getDest(), _)))    // but we can't work out the size of the destination to be sure
}*/

// --- user input reach ---

/**
 * Identifies expressions that are potentially tainted with user
 * input.  Most of the work for this is actually done by the
 * TaintTracking library.
 */
predicate tainted2(Expr expr, Expr inputSource, string inputCause) {
  (
    taintedIncludingGlobalVars(inputSource, expr, _) and
    inputCause = inputSource.toString()
  ) or exists(Expr e | tainted2(e, inputSource, inputCause) |
    // field accesses of a tainted struct are tainted
    e = expr.(FieldAccess).getQualifier()
  )
}

// --- put it together ---

from BufferWrite bw, Expr inputSource, string inputCause
where isUnboundedWrite(bw)
  and tainted2(bw.getASource(), inputSource, inputCause)
select bw,  "This '" + bw.getBWDesc() + "' with input from $@ may overflow the destination.", inputSource, inputCause
