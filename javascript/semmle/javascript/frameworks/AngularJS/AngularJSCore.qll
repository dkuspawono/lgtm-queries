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
 * Provides the core classes for working with AngularJS applications.
 *
 * As the module grows, large features might move to separate files.
 *
 * INTERNAL: Do not import this module directly, import `AngularJS` instead.
 *
 * NOTE: The API of this library is not stable yet and may change in
 *       the future.
 *
 */

import javascript
private import AngularJS

/**
 * Holds if `nd` is a reference to the `angular` variable.
 */
predicate isAngularRef(DataFlowNode nd) {
  exists (Expr src | src = nd.getALocalSource() |
    // either as a global
    src.accessesGlobal("angular") or
    // or imported from a module named `angular`
    src.(ModuleInstance).getPath() = "angular"
  )
}

/**
 * Holds if `m` is of the form `angular.module("name", ...)`.
 */
private predicate isAngularModuleCall(MethodCallExpr m, string name) {
  isAngularRef(m.getReceiver()) and
  m.getMethodName() = "module" and
  m.getArgument(0).mayHaveStringValue(name)
}

/**
 * An AngularJS module for which there is a definition or at least a lookup.
 */
private newtype TAngularModule = MkAngularModule(string name) {
  isAngularModuleCall(_, name)
}

/**
 * An AngularJS module.
 */
class AngularModule extends TAngularModule {
  string name;

  AngularModule() {
    this = MkAngularModule(name)
  }

  /**
   * Get a definition for this module, that is, a call of the form
   * `angular.module("name", deps)`.
   */
  MethodCallExpr getADefinition() {
    isAngularModuleCall(result, name) and
    result.getNumArgument() > 1
  }

  /**
   * Gets a lookup of this module, that is, a call of the form
   * `angular.module("name")`.
   */
  MethodCallExpr getALookup() {
    isAngularModuleCall(result, name) and
    result.getNumArgument() = 1
  }

  /**
   * Get the array of dependencies from this module's definition.
   */
  ArrayExpr getDependencyArray() {
    getADefinition().getArgument(1).(DataFlowNode).getALocalSource() = result
  }

  /**
   * Gets another module that this module lists as a dependency.
   */
  AngularModule getADependency() {
    getDependencyArray().getAnElement().mayHaveStringValue(result.getName())
  }

  /**
   * Gets the name of this module.
   */
  string getName() { result = name }

  /**
   * Gets a textual representation of this module.
   */
  string toString() { result = name }
}

/**
 * Holds if `nd` is a reference to module `m`, that is, it is either
 * a definition of `m`, a lookup of `m`, or a chained method call on
 * `m`.
 */
predicate isModuleRef(DataFlowNode nd, AngularModule m) {
  exists (MethodCallExpr src | src = nd.getALocalSource() |
    src = m.getADefinition()
    or
    src = m.getALookup()
    or
    isModuleRef(src.getReceiver(), m) and
    // the one-argument variant of `info` is not chaining
    not (src.getMethodName() = "info" and src.getNumArgument() = 1)
  )
}

/**
 * A call to a method from the `angular.Module` API.
 */
class ModuleApiCall extends @callexpr {
  /** The module on which the method is called. */
  AngularModule mod;

  /** The name of the called method. */
  string methodName;

  ModuleApiCall() {
    exists (MethodCallExpr m | m = this |
      isModuleRef(m.getReceiver(), mod) and
      m.getMethodName() = methodName
    )
  }

  /**
   * Gets the `i`th argument of this method call.
   */
  Expr getArgument(int i) {
    result = this.(MethodCallExpr).getArgument(i)
  }

  /**
   * Gets a textual representation of this method call.
   */
  string toString() { result = this.(CallExpr).toString() }

  /**
   * Gets the name of the invoked method.
   */
  string getMethodName() {
    result = methodName
  }

}

class ModuleApiCallDependencyInjection extends DependencyInjection {

  ModuleApiCall call;

  string methodName;

  ModuleApiCallDependencyInjection() {
    this = call and
    methodName = call.getMethodName()
  }

  /**
   * Gets the argument position for this method call that expects an injectable function.
   *
   * This method excludes the method names that are also present on the AngularJS '$provide' object.
   */
  private int injectableArgPos() {
    (methodName = "directive" or
      methodName = "filter" or methodName = "controller" or
      methodName = "animation") and result = 1
      or
      (methodName = "config" or methodName = "run") and result = 0
  }

  override DataFlowNode getAnInjectableFunction() {
    result = call.getArgument(injectableArgPos())
  }

}

/**
 * Holds if `name` is the name of a built-in AngularJS directive
 * (cf. https://docs.angularjs.org/api/ng/directive/).
 */
private predicate builtinDirective(string name) {
  name = "ngApp" or
  name = "ngBind" or
  name = "ngBindHtml" or
  name = "ngBindTemplate" or
  name = "ngBlur" or
  name = "ngChange" or
  name = "ngChecked" or
  name = "ngClass" or
  name = "ngClassEven" or
  name = "ngClassOdd" or
  name = "ngClick" or
  name = "ngCloak" or
  name = "ngController" or
  name = "ngCopy" or
  name = "ngCsp" or
  name = "ngCut" or
  name = "ngDblclick" or
  name = "ngDisabled" or
  name = "ngFocus" or
  name = "ngForm" or
  name = "ngHide" or
  name = "ngHref" or
  name = "ngIf" or
  name = "ngInclude" or
  name = "ngInit" or
  name = "ngJq" or
  name = "ngKeydown" or
  name = "ngKeypress" or
  name = "ngKeyup" or
  name = "ngList" or
  name = "ngMaxlength" or
  name = "ngMinlength" or
  name = "ngModel" or
  name = "ngModelOptions" or
  name = "ngMousedown" or
  name = "ngMouseenter" or
  name = "ngMouseleave" or
  name = "ngMousemove" or
  name = "ngMouseover" or
  name = "ngMouseup" or
  name = "ngNonBindable" or
  name = "ngOpen" or
  name = "ngOptions" or
  name = "ngPaste" or
  name = "ngPattern" or
  name = "ngPluralize" or
  name = "ngReadonly" or
  name = "ngRepeat" or
  name = "ngRequired" or
  name = "ngSelected" or
  name = "ngShow" or
  name = "ngSrc" or
  name = "ngSrcset" or
  name = "ngStyle" or
  name = "ngSubmit" or
  name = "ngSwitch" or
  name = "ngTransclude" or
  name = "ngValue"
}

private newtype TDirectiveInstance =
MkBuiltinDirective(string name) { builtinDirective(name) }
or
MkCustomDirective(DirectiveDefinition def)
or
MkCustomComponent(ComponentDefinition def)

/**
 * An AngularJS directive, either built-in or custom.
 */
class DirectiveInstance extends TDirectiveInstance {
  /**
   * Gets the name of this directive.
   */
  abstract string getName();

  /**
   * Gets a directive target matching this directive.
   */
  DirectiveTarget getATarget() {
    this.getName() = result.getName().(DirectiveTargetName).normalize()
  }

  /**
   * Gets a DOM element matching this directive.
   */
  DOM::ElementDefinition getAMatchingElement() {
    result = getATarget().getElement()
  }

  /** Gets a textual representation of this directive. */
  string toString() { result = getName() }

  /**
   * Gets a scope object for this directive.
   */
  AngularScope getAScope() {
    result.mayApplyTo(getAMatchingElement())
  }

}

/**
 * A built-in AngularJS directive.
 */
class BuiltinDirective extends DirectiveInstance, MkBuiltinDirective {
  string name;

  BuiltinDirective() {
    this = MkBuiltinDirective(name)
  }

  override string getName() { result = name }
}

/**
 * A custom AngularJS directive, either a general directive defined by `angular.directive`
 * or a component defined by `angular.component`.
 */
abstract class CustomDirective extends DirectiveInstance {
  /** Gets the element defining this directive. */
  abstract DataFlowNode getDefinition();

  /** Gets the member `name` of this directive. */
  abstract DataFlowNode getMember(string name);

  /** Gets the method `name` of this directive. */
  Function getMethod(string name) {
    result = getMember(name)
  }

  /** Gets a link function of this directive. */
  abstract Function getALinkFunction();

  /** Holds if this directive's properties are bound to the controller. */
  abstract predicate bindsToController();

  /** Holds if this directive introduces an isolate scope. */
  abstract predicate hasIsolateScope();

  /** Gets a node that contributes to the return value of the factory function. */
  abstract DataFlowNode getAnInstantiation();

  /** Gets the controller function of this directive, if any. */
  InjectableFunction getController() {
    result = getMember("controller")
  }

  /** Gets the template URL of this directive, if any. */
  string getTemplateUrl() {
    getMember("templateUrl").(Expr).mayHaveStringValue(result)
  }

  /**
   * Gets a template file for this directive, if any.
   */
  HTMLFile getATemplateFile() {
    result.getAbsolutePath().regexpMatch(".*/\\Q" + getTemplateUrl() + "\\E")
  }

  /**
   * Gets a scope object for this directive.
   */
  AngularScope getAScope() {
    if hasIsolateScope() then
      result = MkIsolateScope(this)
    else
      result = DirectiveInstance.super.getAScope()
  }

  private string getRestrictionString() {
    getMember("restrict").(Expr).mayHaveStringValue(result)
  }

  private predicate hasTargetType(DirectiveTargetType type) {
    not exists(getRestrictionString()) or
    getRestrictionString().indexOf(type.toString()) != -1
  }

  override DirectiveTarget getATarget() {
    result = DirectiveInstance.super.getATarget() and
    hasTargetType(result.getType())
  }

}

/**
 * A custom AngularJS directive defined by `angular.directive`.
 */
class GeneralDirective extends CustomDirective, MkCustomDirective {
  /** The definition of this directive. */
  DirectiveDefinition definition;

  GeneralDirective() {
    this = MkCustomDirective(definition)
  }

  override string getName() {
    result = definition.getName()
  }

  override DataFlowNode getDefinition() {
    result = definition
  }

  /** Gets a node that contributes to the return value of the factory function. */
  override DataFlowNode getAnInstantiation() {
    exists (Function factory |
      factory = definition.getAFactoryFunction().(InjectableFunction).asFunction() and
      result = factory.getAReturnedExpr().(DataFlowNode).getALocalSource()
    )
  }

  override DataFlowNode getMember(string name) {
    exists (PropWriteNode pw |
      pw.getBase().getALocalSource() = getAnInstantiation() and
      pw.getPropertyName() = name and
      pw.getRhs().getALocalSource() = result
    )
  }

  /** Gets the compile function of this directive, if any. */
  Function getCompileFunction() {
    result = getMethod("compile")
  }

  /**
   * Gets a pre/post link function of this directive defined on its definition object.
   * If `kind` is `"pre"`, the result is a `preLink` function. If `kind` is `"post"`,
   * the result is a `postLink` function..
   *
   * See https://docs.angularjs.org/api/ng/service/$compile for documentation of
   * the directive definition API. We do not model the precedence of `compile` over
   * `link`.
   */
  private Function getLinkFunction(string kind) {
    // { link: function postLink() { ... } }
    kind = "post" and
    result = getMember("link")
    or
    // { link: { pre: function preLink() { ... }, post: function postLink() { ... } } }
    exists (PropWriteNode pwn |
      pwn.getBase() = getMember("link") and
      (kind = "pre" or kind = "post") and
      pwn.getPropertyName() = kind and
      result = pwn.getRhs().getALocalSource()
    )
    or
    // { compile: function() { ... return link; } }
    exists (DataFlowNode compileReturn, DataFlowNode compileReturnSrc |
      compileReturn = getCompileFunction().getAReturnedExpr() and
      compileReturnSrc = compileReturn.getALocalSource() |
      // link = function postLink() { ... }
      kind = "post" and
      result = compileReturnSrc
      or
      // link = { pre: function preLink() { ... }, post: function postLink() { ... } }
      exists (PropWriteNode pwn |
        pwn.getBase().getALocalSource() = compileReturnSrc and
        (kind = "pre" or kind = "post") and
        pwn.getPropertyName() = kind and
        result = pwn.getRhs().getALocalSource()
      )
    )
  }

  /** Gets the pre-link function of this directive. */
  Function getPreLinkFunction() {
    result = getLinkFunction("pre")
  }

  /** Gets the post-link function of this directive. */
  Function getPostLinkFunction() {
    result = getLinkFunction("post")
  }

  override Function getALinkFunction() {
    result = getLinkFunction(_)
  }

  override predicate bindsToController() {
    getMember("bindToController").(Expr).mayHaveBooleanValue(true)
  }

  predicate hasIsolateScope() {
    getMember("scope") instanceof ObjectExpr
  }
}

/**
 * An AngularJS component defined by `angular.component`.
 */
class ComponentDirective extends CustomDirective, MkCustomComponent {
  /** The definition of this component. */
  ComponentDefinition comp;

  ComponentDirective() {
    this = MkCustomComponent(comp)
  }

  override string getName() {
    result = comp.getName()
  }

  override DataFlowNode getDefinition() {
    result = comp
  }

  override DataFlowNode getMember(string name) {
    exists (PropWriteNode pwn |
      pwn.getBase().getALocalSource() = comp.getConfig() and
      pwn.getPropertyName() = name and
      result = pwn.getRhs().getALocalSource()
    )
  }

  override Function getALinkFunction() {
    none()
  }

  override predicate bindsToController() {
    none()
  }

  override predicate hasIsolateScope() {
    any()
  }

  override DataFlowNode getAnInstantiation() {
    result = comp.getConfig()
  }

}

private newtype TDirectiveTargetType = E() or A() or C() or M()

/**
 * The type of a directive target, indicating whether it is an element ("E"),
 * an attribute ("A"), a class name ("C") or a comment ("M").
 */
class DirectiveTargetType extends TDirectiveTargetType {
  /**
   * Gets a textual representation of this target type.
   */
  string toString() {
    this = E() and result = "E" or
    this = A() and result = "A" or
    this = C() and result = "C" or
    this = M() and result = "M"
  }
}

/**
 * A syntactic element to which an AngularJS directive can be attached.
 */
abstract class DirectiveTarget extends Locatable {
  /**
   * Gets the name of this directive target, which is used to match it up
   * with any AngularJS directives that apply to it.
   *
   * This name is not normalized.
   */
  abstract string getName();

  /**
   * Gets the element which AngularJS directives attached to this target
   * match.
   */
  abstract DOM::ElementDefinition getElement();

  /**
   * Gets the type of this directive target.
   */
  abstract DirectiveTargetType getType();
}

/**
 * A DOM element, viewed as directive target.
 */
private class DomElementAsElement extends DirectiveTarget {
  DOM::ElementDefinition element;
  DomElementAsElement() { this = element }
  override string getName() { result = element.getName() }
  override DOM::ElementDefinition getElement() { result = element }
  override DirectiveTargetType getType() { result = E() }
}

/**
 * A DOM attribute, viewed as a directive target.
 */
private class DomAttributeAsElement extends DirectiveTarget {
  DOM::AttributeDefinition attr;
  DomAttributeAsElement() { this = attr }
  override string getName() { result = attr.getName() }
  override DOM::ElementDefinition getElement() { result = attr.getElement() }
  override DirectiveTargetType getType() { result = A() }
  DOM::AttributeDefinition asAttribute() { result = attr }
}

/**
 * The name of a directive target.
 *
 * This class implements directive name normalization as described in
 * https://docs.angularjs.org/guide/directive: leading `x-` or `data-`
 * is stripped, then the `:`, `-` or `_`-delimited name is converted to
 * camel case.
 */
class DirectiveTargetName extends string {
  DirectiveTargetName() {
    this = any(DirectiveTarget e).getName()
  }

  /**
   * Gets the `i`th component of this name, where `-`,
   * `:` and `_` count as component delimiters.
   */
  string getRawComponent(int i) {
    result = toLowerCase().regexpFind("(?<=^|[-:_])[a-zA-Z0-9]+(?=$|[-:_])", i, _)
  }

  /**
   * Holds if the first component of this name is `x` or `data`,
   * and hence should be stripped when normalizing.
   */
  predicate stripFirstComponent() {
    getRawComponent(0) = "x" or getRawComponent(0) = "data"
  }

  /**
   * Gets the `i`th component of this name after processing:
   * the first component is stripped if it is `x` or `data`,
   * and all components except the first are capitalized.
   */
  string getProcessedComponent(int i) {
    exists (int j, string raw |
      i >= 0 and
      if stripFirstComponent() then j = i+1 else j = i |
      raw = getRawComponent(j) and
      if i = 0 then result = raw else result = capitalize(raw)
    )
  }

  /**
   * Gets the camelCase version of this name.
   */
  string normalize() {
    result = concat(string c, int i | c = getProcessedComponent(i) | c, "" order by i)
  }
}


/**
 * A call to a getter method of the `$location` service, viewed as a source of
 * user-controlled data.
 *
 * To avoid false positives, we don't consider `$location.url` and similar as
 * remote flow sources, since they are only partly user-controlled.
 *
 * See https://docs.angularjs.org/api/ng/service/$location for details.
 */
private class LocationFlowSource extends RemoteFlowSource {
  LocationFlowSource() {
    exists (ServiceReference service, MethodCallExpr mce, string m, int n |
      service.getName() = "$location" and
      this.asExpr() = mce and
      mce = service.getAMethodCall(m) and
      n = mce.getNumArgument() |
      m = "search" and n < 2 or
      m = "hash" and n = 0
    )
  }

  override string getSourceType() {
    result = "$location"
  }
}

/**
 * An access to a property of the `$routeParams` service, viewed as a source
 * of user-controlled data.
 *
 * See https://docs.angularjs.org/api/ngRoute/service/$routeParams for more details.
 */
private class RouteParamSource extends RemoteFlowSource {
  RouteParamSource() {
    exists (ServiceReference service |
      service.getName() = "$routeParams" and
      this.asExpr() = service.getAPropertyAccess(_)
    )
  }

  override string getSourceType() {
    result = "$routeParams"
  }
}

/**
 * AngularJS expose a jQuery-like interface through `angular.html(..)`.
 * The interface may be backed by an actual jQuery implementation.
 */
private class JQLiteObject extends JQueryObject {

  JQLiteObject() {
    exists(MethodCallExpr mce |
      this = mce and
      isAngularRef(mce.getReceiver()) and
      mce.getMethodName() = "element"
    ) or
    exists(SimpleParameter param |
      // element parameters to user-functions invoked by AngularJS
      param = any(LinkFunction link).getElementParameter() or
      exists(GeneralDirective d |
        param = d.getCompileFunction().getParameter(0) or
        param = d.getCompileFunction().getAReturnedExpr().(DataFlowNode).getALocalSource().(Function).getParameter(1) or
        param = d.getMember("template").(Function).getParameter(0) or
        param = d.getMember("templateUrl").(Function).getParameter(0)
      ) |
      this = param.getAnInitialUse()
    ) or
    exists(ServiceReference element |
      element.getName() = "$rootElement" or
      element.getName() = "$document" |
      this = element.getAnAccess()
    )
  }
}

/**
 * A call to an AngularJS function.
 *
 * Used for exposing behavior that is similar to the behavior of other libraries.
 */
abstract class AngularJSCall extends CallExpr {

  /**
   * Holds if `e` is an argument that this call interprets as HTML.
   */
  abstract predicate interpretsArgumentAsHtml(Expr e);

  /**
   * Holds if `e` is an argument that this call stores globally, e.g. in a cookie.
   */
  abstract predicate storesArgumentGlobally(Expr e);

  /**
   * Holds if `e` is an argument that this call interprets as code.
   */
  abstract predicate interpretsArgumentAsCode(Expr e);

}

/**
 * A call to a method on the AngularJS object itself.
 */
private class AngularMethodCall extends AngularJSCall {

  MethodCallExpr mce;

  AngularMethodCall() {
    isAngularRef(mce.getReceiver()) and
    mce = this
  }

  override predicate interpretsArgumentAsHtml(Expr e) {
    mce.getMethodName() = "element" and
    e = mce.getArgument(0)
  }

  override predicate storesArgumentGlobally(Expr e) {
    none()
  }

  override predicate interpretsArgumentAsCode(Expr e) {
    none()
  }
}

/**
 * A call to a method on a builtin service.
 */
private class ServiceMethodCall extends AngularJSCall {

  MethodCallExpr mce;

  ServiceMethodCall() {
    exists(BuiltinServiceReference service |
      service.getAMethodCall(_) = this and
      mce = this
    )
  }

  override predicate interpretsArgumentAsHtml(Expr e) {
    exists(ServiceReference service, string methodName |
      service.getName() = "$sce" and
      mce = service.getAMethodCall(methodName) |
      (
        // specialized call
        (methodName = "trustAsHtml" or methodName = "trustAsCss") and
        e = mce.getArgument(0)
      ) or (
        // generic call with enum argument
        methodName = "trustAs" and
        exists(PropReadNode prn |
          prn = mce.getArgument(0) and
          (prn = service.getAPropertyAccess("HTML") or prn = service.getAPropertyAccess("CSS")) and
          e = mce.getArgument(1)
        )
      )
    )
  }

  override predicate storesArgumentGlobally(Expr e) {
    exists(ServiceReference service, string serviceName, string methodName |
      service.getName() = serviceName and
      mce = service.getAMethodCall(methodName) |
      ( // AngularJS caches (only available during runtime, so similar to sessionStorage)
        (serviceName = "$cacheFactory" or serviceName = "$templateCache") and
        methodName = "put" and
        e = mce.getArgument(1)
      ) or
      (
        serviceName = "$cookies" and
        (methodName = "put" or methodName = "putObject") and
        e = mce.getArgument(1)
      )
    )
  }

  override predicate interpretsArgumentAsCode(Expr e) {
    exists(ScopeServiceReference scope, string methodName |
      methodName = "$apply" or
      methodName = "$applyAsync" or
      methodName = "$eval" or
      methodName = "$evalAsync" or
      methodName = "$watch" or
      methodName = "$watchCollection" or
      methodName = "$watchGroup" |
      e = scope.getAMethodCall(methodName).getArgument(0)
    ) or
    exists(ServiceReference service |
      service.getName() = "$compile" or
      service.getName() = "$parse" or
      service.getName() = "$interpolate" |
      e = service.getACall().getArgument(0)
    ) or
    exists(ServiceReference service, CallExpr filter, CallExpr filterInvocation |
      // `$filter('orderBy')(collection, expression)`
      service.getName() = "$filter" and
      filter = service.getACall() and
      filter.getArgument(0).mayHaveStringValue("orderBy") and
      filterInvocation.getCallee() = filter and
      e = filterInvocation.getArgument(1)
    )
  }
}

/**
 * A link-function used in a custom AngularJS directive.
 */
class LinkFunction extends Function {
  LinkFunction() {
    this = any(GeneralDirective d).getALinkFunction()
  }

  /**
   * Gets the scope parameter of this function.
   */
  SimpleParameter getScopeParameter() {
    result = getParameter(0)
  }

  /**
   * Gets the element parameter of this function (contains a jqLite-wrapped DOM element).
   */
  SimpleParameter getElementParameter() {
    result = getParameter(1)
  }

  /**
   * Gets the attributes parameter of this function.
   */
  SimpleParameter getAttributesParameter() {
    result = getParameter(2)
  }

  /**
   * Gets the controller parameter of this function.
   */
  SimpleParameter getControllerParameter() {
    result = getParameter(3)
  }

  /**
   * Gets the transclude-function parameter of this function.
   */
  SimpleParameter getTranscludeFnParameter() {
    result = getParameter(4)
  }
}

/**
 * An abstract representation of a set of AngularJS scope objects.
 */
private newtype TAngularScope =
  MkHtmlFileScope(HTMLFile file) {
    any(DirectiveInstance d).getAMatchingElement().getFile() = file or
    any(CustomDirective d).getATemplateFile() = file
  } or
  MkIsolateScope(CustomDirective dir) {
    dir.hasIsolateScope()
  } or
  MkElementScope(DOM::ElementDefinition elem) {
    any(DirectiveInstance d | not d.(CustomDirective).hasIsolateScope()).getAMatchingElement() = elem
  }


/**
 * An abstract representation of a set of AngularJS scope objects.
 */
class AngularScope extends TAngularScope {

  /** Gets a textual representation of this element. */
  abstract string toString();

  /**
   * Gets an access to this scope object.
   */
  DataFlowNode getAnAccess() {
    exists (CustomDirective d |
      this = d.getAScope() |
      exists (SimpleParameter p |
        p = d.getController().getDependencyParameter("$scope") or
        p = d.getALinkFunction().getParameter(0) |
        result.(Expr).mayReferToParameter(p)
      ) or
      exists (ThisExpr dis |
        result.getALocalSource() = dis and
        dis.getBinder() = d.getController().asFunction() and
        d.bindsToController()
      ) or
      d.hasIsolateScope() and result = d.getMember("scope")
    ) or
    exists (DirectiveController c, DOM::ElementDefinition elem, SimpleParameter p |
      c.boundTo(elem) and
      this.mayApplyTo(elem) and
      p = c.getFactoryFunction().getDependencyParameter("$scope") and
      result.(Expr).mayReferToParameter(p)
    )
  }

  /**
   * Holds if this scope may be the scope object of `elt`, i.e. the value of `angular.element(elt).scope()`.
   */
  predicate mayApplyTo(DOM::ElementDefinition elt) {
    this = MkIsolateScope(any(CustomDirective d | d.getAMatchingElement() = elt)) or
    this = MkElementScope(elt) or
    this = MkHtmlFileScope(elt.getFile()) and elt instanceof HTMLElement
  }
}

/**
 * An abstract representation of all the AngularJS scope objects in an HTML file.
 */
class HtmlFileScope extends AngularScope, MkHtmlFileScope {

  HTMLFile f;

  HtmlFileScope() { this = MkHtmlFileScope(f) }

  override string toString() {
    result = "scope in " + f.getBaseName()
  }

}

/**
 * An abstract representation of the AngularJS isolate scope of a directive.
 */
class IsolateScope extends AngularScope, MkIsolateScope {

  CustomDirective dir;

  IsolateScope() { this = MkIsolateScope(dir) }

  override string toString() {
    result = "isolate scope for " + dir.getName()
  }

  /**
   * Gets the directive of this isolate scope.
   */
  CustomDirective getDirective(){
    result = dir
  }

}

/**
 * An abstract representation of all the AngularJS scope objects for a DOM element.
 */
class ElementScope extends AngularScope, MkElementScope {

  DOM::ElementDefinition elem;

  ElementScope() { this = MkElementScope(elem) }

  override string toString() {
    result = "scope for " + elem
  }

}

/**
 * Holds if `nd` is a reference to the `$routeProvider` service, that is,
 * it is either an access of `$routeProvider`, or a chained method call on
 * `$routeProvider`.
 */
predicate isRouteProviderRef(DataFlowNode nd) {
  isBuiltinServiceRef(nd, "$routeProvider") or
  exists (MethodCallExpr mce |
    mce.getMethodName() = "when" or
    mce.getMethodName() = "otherwise" |
    isRouteProviderRef(mce.getReceiver()) and
    nd.getALocalSource() = mce
  )
}

/**
 * A setup of an AngularJS "route", using the `$routeProvider` API.
 */
class RouteSetup extends MethodCallExpr, DependencyInjection {

  int optionsArgumentIndex;

  RouteSetup() {
    exists (string methodName |
      isRouteProviderRef(getReceiver()) and
      methodName = getMethodName() |
      (methodName = "otherwise" and optionsArgumentIndex = 0) or
      (methodName = "when" and optionsArgumentIndex = 1)
    )
  }

  /**
   * Gets the value of property `name` of the params-object provided to this call.
   */
  DataFlowNode getRouteParam(string name) {
    exists(DataFlowNode nd |
      hasOptionArgument(optionsArgumentIndex, name, nd) and
      result = nd.getALocalSource()
    )
  }

  /**
   * Gets the "controller" value of this call, possibly resolving a service name.
   */
  InjectableFunction getController() {
    exists(DataFlowNode controllerProperty |
      // NB: can not use `.getController` here, since that involves a cast to InjectableFunction, and that cast only succeeds because of this method
      controllerProperty = getRouteParam("controller") |
      result = controllerProperty or
      exists(ControllerDefinition def |
        controllerProperty.(Expr).mayHaveStringValue(def.getName()) |
        result = def.getAService()
      )
    )
  }

  override DataFlowNode getAnInjectableFunction() {
    result = getRouteParam("controller")
  }

}

/**
 * An AngularJS controller instance.
 */
abstract class Controller extends DataFlowNode {

  /**
   * Holds if this controller is bound to `elem`.
   */
  abstract predicate boundTo(DOM::ElementDefinition elem);

  /**
   * Holds if this controller is bound to `elem` as `alias`.
   */
  abstract predicate boundToAs(DOM::ElementDefinition elem, string alias);

  /**
   * Gets the factory function of this controller.
   */
  abstract InjectableFunction getFactoryFunction();

}

/**
 * A controller instantiated through a directive, e.g. `<div ngController="myController"/>`.
 */
private class DirectiveController extends Controller {

  ControllerDefinition def;

  DirectiveController() {
    this = def
  }

  private predicate boundAnonymously(DOM::ElementDefinition elem) {
    exists (DirectiveInstance instance, DomAttributeAsElement attr |
      instance.getName() = "ngController" and
      instance.getATarget() = attr and
      elem = attr.getElement() and
      attr.asAttribute().getStringValue() = def.getName()
    )
  }

  override predicate boundTo(DOM::ElementDefinition elem) {
    boundAnonymously(elem) or boundToAs(elem, _)
  }

  override predicate boundToAs(DOM::ElementDefinition elem, string alias) {
    exists (DirectiveInstance instance, DomAttributeAsElement attr |
      instance.getName() = "ngController" and
      instance.getATarget() = attr and
      elem = attr.getElement() and
      exists(string attributeValue, string pattern |
        attributeValue = attr.asAttribute().getStringValue() and
        pattern = "([^ ]+) +as +([^ ]+)" |
        attributeValue.regexpCapture(pattern, 1) = def.getName() and
        attributeValue.regexpCapture(pattern, 2) = alias
      )
    )
  }

  override InjectableFunction getFactoryFunction() {
    result = def.getAFactoryFunction()
  }

}

/**
 * A controller instantiated through routes, e.g. `$routeProvider.otherwise({controller: ...})`.
 */
private class RouteInstantiatedController extends Controller {

  RouteSetup setup;

  RouteInstantiatedController() {
    this = setup
  }

  override InjectableFunction getFactoryFunction() {
    result = setup.getController()
  }

  override predicate boundTo(DOM::ElementDefinition elem) {
    exists (string url, HTMLFile template |
      setup.getRouteParam("templateUrl").(Expr).mayHaveStringValue(url) and
      template.getAbsolutePath().regexpMatch(".*\\Q" + url + "\\E") and
      elem.getFile() = template
    )
  }

  override predicate boundToAs(DOM::ElementDefinition elem, string name) {
    boundTo(elem) and
    setup.getRouteParam("controllerAs").(Expr).mayHaveStringValue(name)
  }

}

/**
 * Dataflow for the arguments of AngularJS dependency-injected functions.
 */
private class DependencyInjectedArgumentInitializer extends AnalyzedFlowNode {
  AnalyzedFlowNode service;

  DependencyInjectedArgumentInitializer() {
    exists (AngularJS::InjectableFunction f, SimpleParameter param,
            AngularJS::CustomServiceDefinition def |
      this.asExpr() = param.getAnInitialUse() and
      def.getServiceReference() = f.getAResolvedDependency(param) and
      service.asExpr() = def.getAService()
    )
  }

  override AbstractValue getAValue() {
    result = AnalyzedFlowNode.super.getAValue() or
    result = service.getALocalValue()
  }
}
