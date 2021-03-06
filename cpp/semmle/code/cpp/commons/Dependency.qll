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

import semmle.code.cpp.Element
import semmle.code.cpp.Declaration
import semmle.code.cpp.Function
import semmle.code.cpp.Variable

/**
 * An Element that can be the source of a transitive dependency.  This is any
 * Element that is not in a template instantiation, plus declarations of template
 * specializations (even though they are technically in an instantiation) because
 * we need to generate (at least) a dependency from them to the general declaration.
 */
class DependsSource extends Element {
  DependsSource() {
    // not inside a template instantiation
    not exists(Element other | isFromTemplateInstantiation(other)) or

    // allow DeclarationEntrys of template specializations
    function_instantiation(this.(DeclarationEntry).getDeclaration(), _) or
    class_instantiation(this.(DeclarationEntry).getDeclaration(), _)
  }
}

/**
 * A program element which can be the target of inter-function or inter-file dependencies.
 *
 * This is the union of Declaration, DeclarationEntry and Macro, minus various kinds of declaration:
 *  * FriendDecl is not included, as a friend declaration cannot be the target of a dependency (nor, as it happens, can they be a source).
 *  * TemplateParameter and related UserTypes are not included, as they are intrinsic sub-components of their associated template.
 *  * Template instantiations are excluded, as the template itself is more useful as a dependency target.
 *  * Stack variables and local types are excluded, as they are lexically tied to their enclosing function, and intra-function dependencies
 *    can only be inter-file dependencies in pathological cases.
 *  * Builtin functions and macros are excluded, as dependencies on them do not translate to inter-file dependencies (note that static functions
 *    and declarations within anonymous namespaces cannot be excluded for this reason, as the declaration can be in a header).
 *  * DeclarationEntrys are only needed if they're not definitions, for the definition to declaration dependency.
 */
class Symbol extends DependsSource {
  Symbol() {
    (
      exists(EnumConstant ec | this = ec and not ec.getDeclaringEnum() instanceof LocalEnum) or
      (this instanceof Macro and this.getFile().getFullName() != "") or
      (this instanceof DeclarationEntry and
        not this.(VariableDeclarationEntry).getVariable() instanceof LocalScopeVariable and
        not this.(FunctionDeclarationEntry).getFunction() instanceof BuiltInFunction and
        not this.(TypeDeclarationEntry).getType() instanceof LocalEnum and
        not this.(TypeDeclarationEntry).getType() instanceof LocalClass and
        not this.(TypeDeclarationEntry).getType() instanceof LocalTypedefType and
        not this.(TypeDeclarationEntry).getType() instanceof TemplateParameter
      ) or
      (this instanceof NamespaceDeclarationEntry)
    )
  }

  /**
   * Gets an element which depends upon this symbol.
   *
   * To a first approximation, dependent elements can be thought of as occurrences of the symbol's name: instances of `VariableAccess`
   * for `Variable` symbols, instances of `MacroInvocation` for `Macro` symbols, and so on.
   *
   *  category:
   *   1 - C/C++ compile-time dependency
   *   2 - C/C++ link-time dependency (or transitive dependency with a link-time component)
   */
  cached
  Element getADependentElement(int category) {
    dependsOnFull(result, this, category)
  }
}

/**
 * Associates a Declaration with it's DeclarationEntries, or (for a template
 * instantiation) with the DeclarationEntries of its template.
 */
cached predicate getDeclarationEntries(Declaration decl, DeclarationEntry de)
{
  (
    decl = de.getDeclaration() or
    function_instantiation(decl, de.getDeclaration()) or
    class_instantiation(decl, de.getDeclaration())
  ) and
  /*
   * ParameterDeclarationEntries are special, as (a) they can only be accessed
   * from within the definition, and (b) non-definition PDEs may be commonly
   * included. Thus, for PDEs, we point only to the definition.
   */
  (de instanceof ParameterDeclarationEntry implies de.isDefinition())
}

/**
 * A 'simple' dependency from src to dest.  This type of dependency
 * does not make any special account of templates.
 *
 * Consider using Symbol.getADependentElement() rather than directly
 * accessing this predicate.
 */
predicate dependsOnSimple(Element src, Element dest) {
  dependsOnSimpleInline(src, dest) or
  dependency_macroUse(src, dest)
}

/**
 * A 'simple' dependency that might be inlined.
 */
private
predicate dependsOnSimpleInline(Element src, Element dest) {
  dependency_functionUse(src, dest) or
  dependency_typeUse(src, dest) or
  dependency_variableUse(src, dest) or
  dependency_usingDeclaration(src, dest) or
  dependency_usingNamespace(src, dest) or
  dependency_enumConstantUse(src, dest) or
  dependency_outOfLineDeclaration(src, dest) or
  dependency_outOfLineInitializer(src, dest) or
  dependency_functionSpecialization(src, dest) or
  dependency_classSpecialization(src, dest)
}

/**
 * Does a simple, non-template dependency exist between two particular Locations?
 */
private predicate dependsLocation(File f1, int sl1, int sc1, int el1, int ec1, File f2, int sl2, int sc2, int el2, int ec2) {
  exists(Element src, Element dest, Location loc1, Location loc2 |
    dependsOnSimpleInline(src, dest) and
    src instanceof DependsSource and
    loc1 = src.getLocation() and
    f1 = loc1.getFile() and
    sl1 = loc1.getStartLine() and
    sc1 = loc1.getStartColumn() and
    el1 = loc1.getEndLine() and
    ec1 = loc1.getEndColumn() and
    loc2 = dest.getLocation() and
    f2 = loc2.getFile() and
    sl2 = loc2.getStartLine() and
    sc2 = loc2.getStartColumn() and
    el2 = loc2.getEndLine() and
    ec2 = loc2.getEndColumn()
  )
}

/**
 * Does a simple dependency from a template have a non-template alternative?
 */
private predicate dependsNonTemplateAlternative(Location loc1, Location loc2) {
  exists(Element src, Element dest |
    dependsOnSimpleInline(src, dest) and
    src.isFromTemplateInstantiation(_) and
    src.getLocation() = loc1 and
    dest.getLocation() = loc2
  ) and
  dependsLocation(loc1.getFile(), loc1.getStartLine(), loc1.getStartColumn(), loc1.getEndLine(), loc1.getEndColumn(), loc2.getFile(), loc2.getStartLine(), loc2.getStartColumn(), loc2.getEndLine(), loc2.getEndColumn())
}

/**
 * A simple dependency from src to a declaration dest, where the definition is not
 * needed at compile time.
 */
predicate dependsOnDeclOnly(Element src, Element dest) {
  dependency_functionUse(src, dest) or
  dependency_variableUse(src, dest) or
  dependency_pointerTypeUse(src, dest)
}

/**
 * A dependency from src to dest.  This predicate inlines
 * template dependencies.
 */
pragma[noopt]
private predicate dependsOnViaTemplate(Declaration src, Element dest) {
  // A template instantiation depends on everything that anything
  // inside it depends upon.  This effectively inlines the things
  // inside at the point where the template is called or
  // referenced.
  exists(Element internal, Location internalLocation, Location destLocation |
    // internal is an element in the template {function or class} instantiation that cannot
    // itself be a transitive dependency source
    internal.isFromTemplateInstantiation(src) and

    // don't generate template dependencies through a member function of a template class;
    // these dependencies are also generated through the class, which has to be referenced
    // somewhere anyway.
    not exists(Class c |
      internal.isFromTemplateInstantiation(c) and
      src.getDeclaringType() = c
    ) and

    // dest is anything that the internal element depends upon
    dependsOnSimpleInline(internal, dest) and

    // is there something in the template (not the instantiation) that's generating
    // (better) dependencies from internal anyway?
    internalLocation = internal.getLocation() and
    destLocation = dest.getLocation() and
    not dependsNonTemplateAlternative(internalLocation, destLocation)
  )
}

/**
 * Does one dependsOnSimple and any number of dependsOnViaTemplate steps.
 *
 * Consider using Symbol.getADependentElement() rather than directly
 * accessing this predicate.
 */
predicate dependsOnTransitive(Element src, Element dest) {
  exists(Element mid1 |
    // begin with a simple step
    dependsOnSimpleInline((DependsSource)src, mid1) and

    // any number of recursive steps
    (
      mid1 = dest or // mid1 is not necessarily a Declaration
      dependsOnViaTemplate+(mid1, dest)
    )
  ) or dependency_macroUse(src, dest)
}

/**
 * A dependency that targets a TypeDeclarationEntry.
 */
private predicate dependsOnTDE(Element src, Type t, TypeDeclarationEntry dest) {
  dependsOnTransitive(src, t) and
  getDeclarationEntries(t, dest)
}

/**
 * A dependency that targets a visible TypeDeclarationEntry.
 */
private pragma[noopt] predicate dependsOnVisibleTDE(Element src, Type t, TypeDeclarationEntry dest) {
  dependsOnTDE(src, t, dest) and
  exists(File g | g = dest.getFile() |
    exists(File f | f = src.getFile() |
      f.getAnIncludedFile*() = g
    )
  )
}

/**
 * A dependency that targets a DeclarationEntry
 */
private predicate dependsOnDeclarationEntry(Element src, DeclarationEntry dest) {
  exists(Type t |
    // dependency from a Type use -> unique visible TDE
    dependsOnVisibleTDE(src, t, dest) and
    strictcount(TypeDeclarationEntry alt |
      dependsOnVisibleTDE(src, t, alt)
    ) = 1
  ) or exists(TypedefType mid |
    // dependency from a TypedefType use -> any (visible) TDE
    dependsOnTransitive(src, mid) and
    getDeclarationEntries(mid, (TypeDeclarationEntry)dest)
  ) or exists(Declaration mid |
    // dependency from a Variable / Function use -> any (visible) declaration entry
    dependsOnTransitive(src, mid) and
    not mid instanceof Type and
    not mid instanceof EnumConstant and

    getDeclarationEntries(mid, (DeclarationEntry)dest) and
    not dest instanceof TypeDeclarationEntry
  ) or exists(Declaration mid |
    // dependency from a Type / Variable / Function use -> any (visible) definition
    dependsOnTransitive(src, mid) and
    not mid instanceof EnumConstant and

    getDeclarationEntries(mid, (DeclarationEntry)dest) and

    // must be definition
    dest.(DeclarationEntry).isDefinition()
  )
}

/**
 * The full dependsOn relation, made up of dependsOnTransitive plus some logic
 * to fix up the results for Declarations to most reasonable DeclarationEntrys.
 */
private predicate dependsOnFull(Element src, Element dest, int category) {
  (
    // direct result
    dependsOnTransitive(src, dest) and
    (
      not dest instanceof Declaration or
      dest instanceof EnumConstant
    ) and
    category = 1
  ) or (
    // result to a visible DeclarationEntry
    dependsOnDeclarationEntry(src, dest) and
    src.getFile().getAnIncludedFile*() = dest.getFile() and
    category = 1
  ) or exists(Declaration mid |
    // dependency from a Variable / Function use -> non-visible definition (link time)
    dependsOnTransitive(src, mid) and
    not mid instanceof EnumConstant and

    getDeclarationEntries(mid, (DeclarationEntry)dest) and
    not dest instanceof TypeDeclarationEntry and

    // must be definition
    dest.(DeclarationEntry).isDefinition() and

    // must not be visible (else covered above)
    not src.getFile().getAnIncludedFile*() = dest.getFile() and

    // filter out FDEs that are only defined in the dummy link target
    (
      (
        dest instanceof FunctionDeclarationEntry and
        isLinkerAwareExtracted()
      ) implies exists(LinkTarget lt | not lt.isDummy() |
        lt.getAFunction() = dest.(FunctionDeclarationEntry).getFunction()
      )
    ) and

    category = 2
  )
}

/**
 * A dependency caused by a function call / use.
 */
private
predicate dependency_functionUse(Element src, Function dest) {
  funbind(src, dest)
}

/**
 * A Type which refers to a UserType.
 */
private cached predicate refersToUserType(Type a, UserType b) {
  a.refersTo(b)
}

/**
 * A Type which refers to a type directly, without using a pointer or reference.
 */
private predicate refersToDirectlyNonPointer(Type a, Type b) {
  a.refersToDirectly(b) and
  not a instanceof PointerType and
  not a instanceof ReferenceType
}

/**
 * A Type which refers to a UserType, but only through a pointer or reference.
 */
private cached predicate refersToUserTypePointer(Type a, UserType b) {
  refersToUserType(a, b) and
  not refersToDirectlyNonPointer*(a, b)
}

/**
 * A dependency caused by a type use.
 */
private
predicate dependency_typeUse(Element src, UserType dest) {
  refersToUserType(typeUsedBy(src), dest)
}

/**
 * A dependency caused by a pointer/reference type use only.
 */
predicate dependency_pointerTypeUse(Element src, UserType dest) {
  refersToUserTypePointer(typeUsedBy(src), dest)
}

/**
 * The Types that must be defined for a particular Element.
 */
private
Type typeUsedBy(Element src) {
  (
    result = src.(VariableDeclarationEntry).getType() and not src.(VariableDeclarationEntry).getVariable().declaredUsingAutoType()
  ) or (
    result = src.(FunctionDeclarationEntry).getType()
  ) or (
    result = src.(Cast).getType() and not src.(Cast).isImplicit()
  ) or (
    result = src.(ClassDerivation).getBaseClass()
  ) or (
    result = src.(TypeDeclarationEntry).getType().(TypedefType).getBaseType()
  ) or (
    result = src.(TypeDeclarationEntry).getDeclaration().(Enum).getExplicitUnderlyingType()
  ) or (
    result = src.(SizeofTypeOperator).getTypeOperand()
  ) or exists(Function f |
    funbind(src, f) and result = f.getATemplateArgument()
  ) or (
    result = src.(NewExpr).getType() and not result.(Class).hasConstructor()
  ) or (
    result = src.(NewArrayExpr).getType() and not result.(ArrayType).getBaseType().(Class).hasConstructor()
  ) or (
    result = src.(DeleteExpr).getExpr().getType() and not result.(PointerType).getBaseType().(Class).hasDestructor()
  ) or (
    result = src.(DeleteArrayExpr).getExpr().getType() and not result.(PointerType).getBaseType().(Class).hasDestructor()
  )
}

/**
 * A dependency caused by a variable use.
 */
private
predicate dependency_variableUse(VariableAccess src, Variable dest) {
  src.getTarget() = dest and
  not dest instanceof LocalScopeVariable
}

/**
 * A dependency caused by an enum constant use.
 */
private
predicate dependency_enumConstantUse(EnumConstantAccess src, EnumConstant dest) {
  src.getTarget() = dest
}

/**
 * A dependency caused by a macro access.
 */
private
predicate dependency_macroUse(MacroAccess src, Macro dest) {
  src.getMacro() = dest
}

/**
 * A dependency caused by a 'using' declaration 'using X::Y'.
 */
private
predicate dependency_usingDeclaration(UsingDeclarationEntry src, Declaration dest) {
  src.getDeclaration() = dest
}

/**
 * A dependency caused by a 'using' directive 'using namespace X'.
 */
private
predicate dependency_usingNamespace(UsingDirectiveEntry src, NamespaceDeclarationEntry dest) {
  exists(Namespace nsdecl |
    nsdecl = src.getNamespace() and
    dest.getNamespace() = nsdecl and
    dest.getFile().getAnIncludedFile*() = src.getFile() and
    (
      dest.getFile() = src.getFile() implies
      dest.getLocation().getStartLine() < src.getLocation().getStartLine()
    ) and
    none() // temporarily disabled until we have suitable UI in Architect
  )
}

/**
 * A dependency from the definition of a class member to a corresponding declaration.  This
 * ensures that an externally defined class member has a dependency on (something in) the
 * class definition.
 */
private
predicate dependency_outOfLineDeclaration(DeclarationEntry src, DeclarationEntry dest) {
  src.getDeclaration().hasDeclaringType() and
  src.isDefinition() and
  (
    dest.getDeclaration() = src.getDeclaration() or

    // also permit out of line declarations to jump from the declaration of a specialized
    // function to it's definition in the primary template.  Note that the specialization
    // in this case may be on a template class parameter.
    function_instantiation(src.getDeclaration(), dest.getDeclaration())
  ) and
  not dest.isDefinition()
}

/**
 * A dependency from an initialization of a (static) class member to a corresponding
 * declaration.
 */
private
predicate dependency_outOfLineInitializer(Initializer src, DeclarationEntry dest) {
  src.getDeclaration().hasDeclaringType() and
  dest.getDeclaration() = src.getDeclaration() and
  not dest.isDefinition()
}

/**
 * A dependency from a template function specialization to the general one.
 */
private
predicate dependency_functionSpecialization(DeclarationEntry src, DeclarationEntry dest) {
  exists(FunctionTemplateSpecialization fts |
    src.getDeclaration() = fts and
    dest.getDeclaration() = fts.getPrimaryTemplate()
  )
}

/**
 * A dependency from a template class specialization to the most general one.
 */
private
predicate dependency_classSpecialization(DeclarationEntry src, DeclarationEntry dest) {
  exists(ClassTemplateSpecialization cts |
    src.getDeclaration() = cts and
    dest.getDeclaration() = cts.getPrimaryTemplate()
  )
}
