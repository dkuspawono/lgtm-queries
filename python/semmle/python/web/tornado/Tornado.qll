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

import python

import semmle.python.security.TaintTracking

private ClassObject theTornadoRequestHandlerClass() {
    exists(ModuleObject web |
        web.getName() = "tornado.web" and
        result = web.getAttribute("RequestHandler")
    )
}

ClassObject aTornadoRequestHandlerClass() {
    result.getASuperType() = theTornadoRequestHandlerClass()
}

FunctionObject getTornadoRequestHandlerMethod(string name) {
    result = theTornadoRequestHandlerClass().declaredAttribute(name)
}
