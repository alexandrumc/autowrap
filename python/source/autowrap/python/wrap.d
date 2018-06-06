/**
   Functions to wrap entities in D modules for Python consumption.

   These functions are usually not called directly, but from the mixin generated by
   autowrap.python.boilerplate.pydBoilerplate.
 */
module autowrap.python.wrap;

import std.meta: allSatisfy;
import std.traits: isArray;

version(unittest) {
    void shouldEqual(T, U)(auto ref T t, auto ref U u) {
        assert(t == u);
    }
}

private alias I(alias T) = T;
private enum isString(alias T) = is(typeof(T) == string);

private template Type(T...) if(T.length == 1) {
    static if(is(T[0]))
        alias Type = T[0];
    else
        alias Type = typeof(T[0]);
}

///  Wrap global functions from multiple modules
void wrapAllFunctions(ModuleNames...)() if(allSatisfy!(isString, ModuleNames)) {
    static foreach(moduleName; ModuleNames) {
        wrapFunctions!moduleName;
    }
}

///   Wrap glocal functions in a module, given as a string
void wrapFunctions(string moduleName)() {
    mixin(`import module_ = ` ~ moduleName ~ `;`);
    wrapFunctions!module_;
}

///   Wrap global functions in a module
void wrapFunctions(alias module_)() if(!is(typeof(module_) == string)) {
    import pyd.pyd: def, PyName;

    foreach(memberName; __traits(allMembers, module_)) {
        alias member = I!(__traits(getMember, module_, memberName));
        static if(isFunction!member) {
            def!(member, PyName!(toSnakeCase(memberName)));
        }
    }
}

/// Converts an identifier from camelCase or PascalCase to snake_case.
string toSnakeCase(in string str) @safe pure {

    import std.algorithm: all, map;
    import std.ascii: isUpper;

    if(str.all!isUpper) return str;

    string ret;

    string convert(in size_t index, in char c) {
        import std.ascii: isLower, toLower;

        const prefix = index == 0 ? "" : "_";
        const isHump =
            (index == 0 && c.isUpper) ||
            (index > 0 && c.isUpper && str[index - 1].isLower);

        return isHump ? prefix ~ c.toLower : "" ~ c;
    }

    foreach(i, c; str) {
        ret ~= convert(i, c);
    }

    return ret;
}


@("toSnakeCase empty")
@safe pure unittest {
    "".toSnakeCase.shouldEqual("");
}

@("toSnakeCase no caps")
@safe pure unittest {
    "foo".toSnakeCase.shouldEqual("foo");
}

@("toSnakeCase camelCase")
@safe pure unittest {
    "toSnakeCase".toSnakeCase.shouldEqual("to_snake_case");
}

@("toSnakeCase PascalCase")
@safe pure unittest {
    "PascalCase".toSnakeCase.shouldEqual("pascal_case");
}

@("toSnakeCase ALLCAPS")
@safe pure unittest {
    "ALLCAPS".toSnakeCase.shouldEqual("ALLCAPS");
}

// if a type is a struct or a class
private template isUserAggregate(A...) if(A.length == 1) {
    import std.datetime;
    import std.traits: Unqual, isInstanceOf;
    import std.typecons: Tuple;
    alias T = A[0];

    enum isUserAggregate =
        !is(Unqual!T == DateTime) &&
        !isInstanceOf!(Tuple, T) &&
        (is(T == struct) || is(T == class));
}

@("DateTime is not a user aggregate")
@safe pure unittest {
    import std.datetime: DateTime;
    static assert(!isUserAggregate!DateTime);
}

@("Tuple is not a user aggregate")
@safe pure unittest {
    import std.typecons: Tuple;
    static assert(!isUserAggregate!(Tuple!(int, double)));
}

// Given a parent (module, struct, ...) and a memberName, alias the actual member,
// or void if not possible
private template Symbol(alias parent, string memberName) {
    static if(__traits(compiles, I!(__traits(getMember, parent, memberName))))
        alias Symbol = I!(__traits(getMember, parent, memberName));
    else
        alias Symbol = void;
}

/**
   Wrap all aggregates found in the given modules, specified by their name
   (to avoid importing all of them first).

   This function wraps all struct and class definitions, and also all struct and class
   types that are parameters or return types of any functions found.
 */
void wrapAllAggregates(ModuleNames...)() if(allSatisfy!(isString, ModuleNames)) {

    import std.meta: Unique = NoDuplicates;

    // definitions
    alias aggregates = AggregatesInModules!ModuleNames;

    // return and parameter types
    alias functionTypes = FunctionTypesInModules!ModuleNames;

    // it's an error in pyd to call wrap_class twice
    alias allAggregates = Unique!(aggregates, functionTypes);

    static foreach(aggregate; allAggregates) {
        static if(__traits(compiles, wrapAggregate!aggregate))
            wrapAggregate!aggregate;
        else
            pragma(msg, "ERROR! Could not wrap ", aggregate.stringof);
    }
}

// All return and parameter types of the functions in the given modules
private template FunctionTypesInModules(ModuleNames...) if(allSatisfy!(isString, ModuleNames)) {
    import std.meta: staticMap;
    alias FunctionTypesInModules = staticMap!(FunctionTypesInModuleName, ModuleNames);
}

// All return and parameter types of the functions in the given module
private template FunctionTypesInModuleName(string moduleName) {

    mixin(`import module_  = ` ~ moduleName ~ `;`);
    import std.traits: ReturnType, Parameters;
    import std.meta: Filter, staticMap, AliasSeq, NoDuplicates;

    alias Member(string memberName) = Symbol!(module_, memberName);
    alias members = staticMap!(Member, __traits(allMembers, module_));
    alias functions = Filter!(isFunction, members);

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
    alias FunctionTypesInModuleName = NoDuplicates!(Filter!(isUserAggregate, functionTypes));
}

private template RecursiveAggregates(T) {
    import std.meta: staticMap, Filter, AliasSeq, NoDuplicates;
    import std.traits: isInstanceOf;
    import std.typecons: Typedef, TypedefType;
    import std.datetime: Date;

    static if(isInstanceOf!(Typedef, T)) {
        alias RecursiveAggregates = TypedefType!T;
    } else static if (is(T == Date)) {
        alias RecursiveAggregates = Date;
    } else static if(isUserAggregate!T) {
        alias AggMember(string memberName) = Symbol!(T, memberName);
        alias members = staticMap!(AggMember, __traits(allMembers, T));
        alias types = staticMap!(Type, members);
        alias aggregates = NoDuplicates!(Filter!(isUserAggregate, staticMap!(PrimordialType, types)));

        static if(aggregates.length == 0)
            alias RecursiveAggregates = T;
        else
            alias RecursiveAggregates = AliasSeq!(aggregates, staticMap!(RecursiveAggregateHelper, aggregates));
    } else
        alias RecursiveAggregates = T;

}

// Only exists because if RecursiveAggregate recurses using itself dmd complains.
// So instead, we ping-pong between identical templates.
private template RecursiveAggregateHelper(T) {
    import std.meta: staticMap, Filter, AliasSeq, NoDuplicates;
    import std.traits: isInstanceOf;
    import std.typecons: Typedef, TypedefType;
    import std.datetime: Date;

    static if(isInstanceOf!(Typedef, T)) {
        alias RecursiveAggregates = TypedefType!T;
    } else static if (is(T == Date)) {
        alias RecursiveAggregates = Date;
    } else static if(isUserAggregate!T) {
        alias AggMember(string memberName) = Symbol!(T, memberName);
        alias members = staticMap!(AggMember, __traits(allMembers, T));
        alias types = staticMap!(Type, members);
        alias aggregates = NoDuplicates!(Filter!(isUserAggregate, staticMap!(PrimordialType, types)));

        static if(aggregates.length == 0)
            alias RecursiveAggregateHelper = T;
        else
            alias RecursiveAggregateHelper = AliasSeq!(aggregates, staticMap!(RecursiveAggregates, aggregates));
    } else
        alias RecursiveAggregatesHelper = T;
}

private template AggregatesInModules(ModuleNames...) if(allSatisfy!(isString, ModuleNames)) {
    import std.meta: staticMap;
    alias AggregatesInModules = staticMap!(AggregatesInModuleName, ModuleNames);
}

private template AggregatesInModuleName(string moduleName) {

    mixin(`import module_  = ` ~ moduleName ~ `;`);
    import std.meta: Filter, staticMap;

    alias Member(string memberName) = Symbol!(module_, memberName);
    alias members = staticMap!(Member, __traits(allMembers, module_));
    alias AggregatesInModuleName = Filter!(isUserAggregate, members);
}

/**
   Wrap aggregate of type T.
 */
auto wrapAggregate(T)() if(isUserAggregate!T) {

    import pyd.pyd: wrap_class, Member, Def, Init;
    import std.meta: staticMap, Filter, AliasSeq;
    import std.traits: Parameters, FieldNameTuple, hasMember;
    import std.typecons: Tuple;

    alias AggMember(string memberName) = Symbol!(T, memberName);
    alias members = staticMap!(AggMember, __traits(allMembers, T));

    alias memberFunctions = Filter!(isMemberFunction, members);

    static if(hasMember!(T, "__ctor"))
        alias constructors = AliasSeq!(__traits(getOverloads, T, "__ctor"));
    else
        alias constructors = AliasSeq!();

    // If we staticMap with std.traits.Parameters, we end up with a collapsed tuple
    // i.e. with one constructor that takes int and another that takes int, string,
    // we'd end up with 3 elements (int, int, string) instead of 2 ((int), (int, string))
    // so we package them up in a std.typecons.Tuple to avoid flattening
    // each being an AliasSeq of types for the constructor
    alias ParametersTuple(alias F) = Tuple!(Parameters!F);

    // A tuple, with as many elements as constructors. Each element is a
    // std.typecons.Tuple of the constructor parameter types.
    alias constructorParamTuples = staticMap!(ParametersTuple, constructors);

    // Apply pyd's Init to the unpacked types of the parameter Tuple.
    alias InitTuple(alias Tuple) = Init!(Tuple.Types);

    enum isPublic(string fieldName) = __traits(getProtection, __traits(getMember, T, fieldName)) == "public";
    alias publicFields = Filter!(isPublic, FieldNameTuple!T);

    wrap_class!(
        T,
        staticMap!(Member, publicFields),
        staticMap!(Def, memberFunctions),
        staticMap!(InitTuple, constructorParamTuples),
   );
}

// must be a global template
private template isMemberFunction(A...) if(A.length == 1) {
    alias T = A[0];
    static if(__traits(compiles, __traits(identifier, T)))
        enum isMemberFunction = isFunction!T && __traits(identifier, T) != "__ctor";
    else
        enum isMemberFunction = false;
}

// T -> T, T[] -> T, T[][] -> T
private template PrimordialType(T) if(isArray!T) {
    import std.range.primitives: ElementType;
    static if(isArray!(ElementType!T))
        alias PrimordialType = PrimordialType!(ElementType!T);
    else
        alias PrimordialType = ElementType!T;
}

// T -> T, T[] -> T, T[][] -> T
private template PrimordialType(T) if(!isArray!T) {
    alias PrimordialType = T;
}


@("PrimordialType")
unittest {
    static assert(is(PrimordialType!int == int));
    static assert(is(PrimordialType!(int[]) == int));
    static assert(is(PrimordialType!(int[][]) == int));
    static assert(is(PrimordialType!(double[][]) == double));
    static assert(is(PrimordialType!(string[][]) == dchar));
}

private template isFunction(alias T) {
    import std.traits: isFunction_ = isFunction;
    enum isFunction = isFunction_!T && __traits(getProtection, T) == "export";
}
