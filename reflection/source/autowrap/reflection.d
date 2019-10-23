module autowrap.reflection;


public import autowrap.types: isModule, Modules, Module;
import std.meta: allSatisfy;
import std.traits: isArray, isCallable;
import std.typecons: Flag, No;


private alias I(alias T) = T;
private enum isString(alias T) = is(typeof(T) == string);


template AllFunctions(Modules modules) {
    import std.algorithm: map;
    import std.array: join;
    import std.typecons: Yes, No;  // needed for Module.toString in the mixin

    enum modulesList = modules.value.map!(a => a.toString).join(", ");
    mixin(`alias AllFunctions = AllFunctions!(`, modulesList, `);`);
}


template AllFunctions(Modules...) if(allSatisfy!(isString, Modules)) {
    import std.meta: staticMap;
    enum module_(string name) = Module(name);
    alias AllFunctions = staticMap!(Functions, staticMap!(module_, Modules));
}

template AllFunctions(Modules...) if(allSatisfy!(isModule, Modules)) {
    import std.meta: staticMap;
    alias AllFunctions = staticMap!(Functions, Modules);
}


template Functions(Module module_) {
    mixin(`import dmodule = ` ~ module_.name ~ `;`);
    alias Functions = Functions!(dmodule, module_.alwaysExport);
}


template Functions(alias module_, Flag!"alwaysExport" alwaysExport = No.alwaysExport)
    if(!is(typeof(module_) == string))
{
    import mirror.meta: MirrorModule = Module;
    import std.meta: staticMap, Filter;
    import std.traits: moduleName;

    alias mod = MirrorModule!(moduleName!module_);
    enum isExport(alias F) = isExportFunction!(F.symbol, alwaysExport);
    alias exportFunctions = Filter!(isExport, mod.FunctionsBySymbol);
    alias toFunctionSymbol(alias F) = FunctionSymbol!(F.identifier, module_, F.symbol);

    alias Functions = staticMap!(toFunctionSymbol, exportFunctions);
}


/**
   A template carrying information about a function.
 */
template FunctionSymbol(string N, alias M, alias S) {

    import std.traits: moduleName_ = moduleName;

    alias name = N;
    alias module_ = M;
    enum moduleName = moduleName_!module_;
    alias symbol = S;
}


template AllAggregates(Modules modules) {
    import std.algorithm: map;
    import std.array: join;
    import std.typecons: Yes, No;  // needed for Module.toString in the mixin

    enum modulesList = modules.value.map!(a => a.toString).join(", ");
    mixin(`alias AllAggregates = AllAggregates!(`, modulesList, `);`);
}


template AllAggregates(ModuleNames...) if(allSatisfy!(isString, ModuleNames)) {
    import std.meta: staticMap;

    enum module_(string name) = Module(name);
    enum Modules = staticMap!(module_, ModuleNames);

    alias AllAggregates = AllAggregates!(staticMap!(module_, ModuleNames));
}

template AllAggregates(Modules...) if(allSatisfy!(isModule, Modules)) {

    import std.meta: NoDuplicates, Filter;
    import std.traits: isCopyable, Unqual;
    import std.datetime: Date, DateTime;

    // definitions
    alias aggregates = AggregateDefinitionsInModules!Modules;

    // return and parameter types
    alias functionTypes = FunctionTypesInModules!Modules;

    alias copyables = Filter!(isCopyable, NoDuplicates!(aggregates, functionTypes));

    template notAlreadyWrapped(T) {
        alias Type = Unqual!T;
        enum notAlreadyWrapped = !is(Type == Date) && !is(Type == DateTime);
    }

    alias notWrapped = Filter!(notAlreadyWrapped, copyables);
    alias public_ = Filter!(isPublicSymbol, notWrapped);

    alias AllAggregates = public_;
}

private template AggregateDefinitionsInModules(Modules...) if(allSatisfy!(isModule, Modules)) {
    import std.meta: staticMap;
    alias AggregateDefinitionsInModules = staticMap!(AggregateDefinitionsInModule, Modules);
}

private template AggregateDefinitionsInModule(Module module_) {

    mixin(`import dmodule  = ` ~ module_.name ~ `;`);
    import mirror.traits: RecursiveFieldTypes;
    import mirror.meta: MirrorModule = Module;
    import std.meta: Filter, staticMap, NoDuplicates, AliasSeq;

    alias mod = MirrorModule!(module_.name);
    alias userAggregates = Filter!(isUserAggregate, mod.Aggregates);
    alias recursives = Filter!(isUserAggregate, staticMap!(RecursiveFieldTypes, userAggregates));
    alias all = AliasSeq!(userAggregates, recursives);

    alias AggregateDefinitionsInModule = NoDuplicates!all;
}


// All return and parameter types of the functions in the given modules
private template FunctionTypesInModules(Modules...) if(allSatisfy!(isModule, Modules)) {
    import std.meta: staticMap;
    alias FunctionTypesInModules = staticMap!(FunctionTypesInModule, Modules);
}


// All return and parameter types of the functions in the given module
private template FunctionTypesInModule(Module module_) {

    mixin(`import dmodule  = ` ~ module_.name ~ `;`);
    import std.traits: ReturnType, Parameters;
    import std.meta: Filter, staticMap, AliasSeq, NoDuplicates;

    alias Member(string memberName) = Symbol!(dmodule, memberName);
    alias members = staticMap!(Member, __traits(allMembers, dmodule));
    template isWantedExportFunction(T...) if(T.length == 1) {
        import std.traits: isSomeFunction;
        alias F = T[0];
        static if(isSomeFunction!F)
            enum isWantedExportFunction = isExportFunction!(F, module_.alwaysExport);
        else
            enum isWantedExportFunction = false;
    }
    alias functions = Filter!(isWantedExportFunction, members);

    // all return types of all functions
    alias returns = NoDuplicates!(Filter!(isUserAggregate, staticMap!(PrimordialType, staticMap!(ReturnType, functions))));
    // recurse on the types in `returns` to also wrap the aggregate types of the members
    alias recursiveReturns = NoDuplicates!(staticMap!(RecursiveAggregates, returns));
    // all of the parameters types of all of the functions
    alias params = NoDuplicates!(Filter!(isUserAggregate, staticMap!(PrimordialType, staticMap!(Parameters, functions))));
    // recurse on the types in `params` to also wrap the aggregate types of the members
    alias recursiveParams = NoDuplicates!(staticMap!(RecursiveAggregates, returns));
    // chain all types
    alias functionTypes = AliasSeq!(returns, recursiveReturns, params, recursiveParams);

    alias FunctionTypesInModule = NoDuplicates!(Filter!(isUserAggregate, functionTypes));
}


template RecursiveAggregates(T) {
    mixin RecursiveAggregateImpl!(T, RecursiveAggregateHelper);
    alias RecursiveAggregates = RecursiveAggregateImpl;
}

// Only exists because if RecursiveAggregate recurses using itself dmd complains.
// So instead, we ping-pong between identical templates.
private template RecursiveAggregateHelper(T) {
    mixin RecursiveAggregateImpl!(T, RecursiveAggregates);
    alias RecursiveAggregateHelper = RecursiveAggregateImpl;
}

/**
   Only exists because if RecursiveAggregate recurses using itself dmd complains.
   Instead there's a canonical implementation and we ping-pong between two
   templates that mix this in.
 */
private mixin template RecursiveAggregateImpl(T, alias Other) {
    import std.meta: staticMap, Filter, AliasSeq, NoDuplicates;
    import std.traits: isInstanceOf, Unqual;
    import std.typecons: Typedef, TypedefType;
    import std.datetime: Date;

    static if(isInstanceOf!(Typedef, T)) {
        alias RecursiveAggregateImpl = TypedefType!T;
    } else static if (is(T == Date)) {
        alias RecursiveAggregateImpl = Date;
    } else static if(isUserAggregate!T) {
        alias AggMember(string memberName) = Symbol!(T, memberName);
        alias members = staticMap!(AggMember, __traits(allMembers, T));
        enum isNotMe(U) = !is(Unqual!T == Unqual!U);

        alias types = staticMap!(Type, members);
        alias primordials = staticMap!(PrimordialType, types);
        alias userAggregates = Filter!(isUserAggregate, primordials);
        alias aggregates = NoDuplicates!(Filter!(isNotMe, userAggregates));

        static if(aggregates.length == 0)
            alias RecursiveAggregateImpl = T;
        else
            alias RecursiveAggregateImpl = AliasSeq!(aggregates, staticMap!(Other, aggregates));
    } else
        alias RecursiveAggregateImpl = T;
}


// must be a global template for staticMap
private template Type(T...) if(T.length == 1) {
    import std.traits: isSomeFunction;
    import std.meta: AliasSeq;

    static if(isSomeFunction!(T[0]))
        alias Type = AliasSeq!();
    else static if(is(T[0]))
        alias Type = T[0];
    else
        alias Type = typeof(T[0]);
}

// if a type is a struct or a class
template isUserAggregate(A...) if(A.length == 1) {
    import std.datetime;
    import std.traits: Unqual, isInstanceOf;
    import std.typecons: Tuple;
    alias T = A[0];

    enum isUserAggregate =
        !is(Unqual!T == DateTime) &&
        !is(Unqual!T == TimeOfDay) &&
        !isInstanceOf!(Tuple, T) &&
        (is(T == struct) || is(T == class));
}


// Given a parent (module, struct, ...) and a memberName, alias the actual member,
// or void if not possible
package template Symbol(alias parent, string memberName) {
    static if(__traits(compiles, I!(__traits(getMember, parent, memberName))))
        alias Symbol = I!(__traits(getMember, parent, memberName));
    else
        alias Symbol = void;
}


// T -> T, T[] -> T, T[][] -> T, T* -> T
template PrimordialType(T) {
    import mirror.traits: FundamentalType;
    import std.traits: Unqual;
    alias PrimordialType = Unqual!(FundamentalType!T);
}


package template isExportFunction(alias F, Flag!"alwaysExport" alwaysExport = No.alwaysExport) {
    import std.traits: isFunction;

    static if(!isFunction!F)
        enum isExportFunction = false;
    else {
        version(AutowrapAlwaysExport) {
            enum linkage = __traits(getLinkage, F);
            enum isExportFunction = linkage != "C" && linkage != "C++";
        } else version(AutowrapAlwaysExportC) {
            enum linkage = __traits(getLinkage, F);
            enum isExportFunction = linkage == "C" || linkage == "C++";
        } else
            enum isExportFunction = isExportSymbol!(F, alwaysExport);
    }
}


private template isExportSymbol(alias S, Flag!"alwaysExport" alwaysExport = No.alwaysExport) {
    static if(__traits(compiles, __traits(getProtection, S)))
        enum isExportSymbol = isPublicSymbol!S && (alwaysExport || __traits(getProtection, S) == "export");
    else
        enum isExportSymbol = false;
}

private template isPublicSymbol(alias S) {
    enum isPublicSymbol = __traits(getProtection, S) == "export" || __traits(getProtection, S) == "public";
}


template PublicFieldNames(T) {
    import std.meta: Filter, AliasSeq;
    import std.traits: FieldNameTuple;

    enum isPublic(string fieldName) = __traits(getProtection, __traits(getMember, T, fieldName)) == "public";
    alias publicFields = Filter!(isPublic, FieldNameTuple!T);

    // FIXME - See #54
    static if(is(T == class))
        alias PublicFieldNames = AliasSeq!();
    else
        alias PublicFieldNames = publicFields;
}


template PublicFieldTypes(T) {
    import std.meta: staticMap;

    alias fieldType(string name) = typeof(__traits(getMember, T, name));

    alias PublicFieldTypes = staticMap!(fieldType, PublicFieldNames!T);
}


template Properties(functions...) {
    import std.meta: Filter;
    alias Properties = Filter!(isProperty, functions);
}


template isProperty(alias F) {
    import std.traits: functionAttributes, FunctionAttribute;
    enum isProperty = functionAttributes!F & FunctionAttribute.property;
}


template isStatic(alias F) {
    import std.traits: hasStaticMember;
    enum isStatic = hasStaticMember!(__traits(parent, F), __traits(identifier, F));
}


// From a function symbol to an AliasSeq of `Parameter`
template FunctionParameters(A...) if(A.length == 1 && isCallable!(A[0])) {
    import std.traits: Parameters, ParameterIdentifierTuple, ParameterDefaults;
    import std.meta: staticMap, aliasSeqOf;
    import std.range: iota;

    alias F = A[0];

    alias parameter(size_t i) = Parameter!(
        Parameters!F[i],
        ParameterIdentifierTuple!F[i],
        ParameterDefaults!F[i]
    );

    alias FunctionParameters = staticMap!(parameter, aliasSeqOf!(Parameters!F.length.iota));
}


template Parameter(T, string id, D...) if(D.length == 1) {
    alias Type = T;
    enum identifier = id;

    static if(is(D[0] == void))
        alias Default = void;
    else
        enum Default = D[0];
}

template isParameter(alias T) {
    import std.traits: TemplateOf;
    enum isParameter = __traits(isSame, TemplateOf!T, Parameter);
}


template NumDefaultParameters(A...) if(A.length == 1 && isCallable!(A[0])) {
    import std.meta: Filter;
    import std.traits: ParameterDefaults;

    alias F = A[0];

    template notVoid(T...) if(T.length == 1) {
        enum notVoid = !is(T[0] == void);
    }

    enum NumDefaultParameters = Filter!(notVoid, ParameterDefaults!F).length;
}


template NumRequiredParameters(A...) if(A.length == 1 && isCallable!(A[0])) {
    import std.traits: Parameters;
    alias F = A[0];
    enum NumRequiredParameters = Parameters!F.length - NumDefaultParameters!F;
}


template BinaryOperators(T) {
    import std.meta: staticMap, Filter, AliasSeq;
    import std.traits: hasMember;

    // See https://dlang.org/spec/operatoroverloading.html#binary
    private alias overloadable = AliasSeq!(
        "+", "-",  "*",  "/",  "%", "^^",  "&",
        "|", "^", "<<", ">>", ">>>", "~", "in",
    );

    static if(hasMember!(T, "opBinary") || hasMember!(T, "opBinaryRight")) {

        private enum hasOperatorDir(BinOpDir dir, string op) = is(typeof(probeOperator!(T, functionName(dir), op)));
        private enum hasOperator(string op) =
            hasOperatorDir!(BinOpDir.left, op)
            || hasOperatorDir!(BinOpDir.right, op);

        alias ops = Filter!(hasOperator, overloadable);

        template toBinOp(string op) {
            enum hasLeft  = hasOperatorDir!(BinOpDir.left, op);
            enum hasRight = hasOperatorDir!(BinOpDir.right, op);

            static if(hasLeft && hasRight)
                enum toBinOp = BinaryOperator(op, BinOpDir.left | BinOpDir.right);
            else static if(hasLeft)
                enum toBinOp = BinaryOperator(op, BinOpDir.left);
            else static if(hasRight)
                enum toBinOp = BinaryOperator(op, BinOpDir.right);
            else
                static assert(false);
        }

        alias BinaryOperators = staticMap!(toBinOp, ops);
    } else
        alias BinaryOperators = AliasSeq!();
}


/**
   Tests if T has a template function named `funcName`
   with a string template parameter `op`.
 */
private auto probeOperator(T, string funcName, string op)() {
    import std.traits: Parameters;

    mixin(`alias func = T.` ~ funcName ~ `;`);
    alias P = Parameters!(func!op);

    mixin(`return T.init.` ~ funcName ~ `!op(P.init);`);
}


struct BinaryOperator {
    string op;
    BinOpDir dirs;  /// left, right, or both
}


enum BinOpDir {
    left = 1,
    right = 2,
}


string functionName(BinOpDir dir) {
    final switch(dir) with(BinOpDir) {
        case left: return "opBinary";
        case right: return "opBinaryRight";
    }
    assert(0);
}



template UnaryOperators(T) {
    import std.meta: AliasSeq, Filter;

    alias overloadable = AliasSeq!("-", "+", "~", "*", "++", "--");
    enum hasOperator(string op) = is(typeof(probeOperator!(T, "opUnary", op)));
    alias UnaryOperators = Filter!(hasOperator, overloadable);
}


template AssignOperators(T) {
    import std.meta: AliasSeq, Filter;

    // See https://dlang.org/spec/operatoroverloading.html#op-assign
    private alias overloadable = AliasSeq!(
        "+", "-",  "*",  "/",  "%", "^^",  "&",
        "|", "^", "<<", ">>", ">>>", "~",
    );

    private enum hasOperator(string op) = is(typeof(probeOperator!(T, "opOpAssign", op)));
    alias AssignOperators = Filter!(hasOperator, overloadable);
}
