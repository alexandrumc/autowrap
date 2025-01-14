module autowrap.pynih.python.object_;


struct PythonObject {
    import python.c: PyObject;
    import std.traits: Unqual;

    private PyObject* _obj;

    this(T)(auto ref T value) if(!is(Unqual!T == PyObject*)) {
        import autowrap.pynih.python.conv.d_to_python: toPython;
        _obj = value.toPython;
    }

    // can only be used on Python C API calls that create a new PyObject*
    // due to reference count issues
    private this(PyObject* obj) {
        _obj = obj;
    }

    // FIXME destructor should dec ref

    PythonObject str() const {
        return retPyObject!("PyObject_Str");
    }

    PythonObject repr() const {
        return retPyObject!("PyObject_Repr");
    }

    PythonObject bytes() const {
        return retPyObject!("PyObject_Bytes");
    }

    PythonObject type() const {
        return retPyObject!("PyObject_Type");
    }

    PythonObject dir() const {
        return retPyObject!("PyObject_Dir");
    }

    auto hash() const {
        return retDirect!"PyObject_Hash";
    }

    auto len() const {
        return retDirect!"PyObject_Length";
    }
    alias length = len;

    bool not() const {
        return cast(bool) retDirect!"PyObject_Not";
    }

    bool hasattr(in string attr) const {
        import std.string: toStringz;
        return cast(bool) retDirect!"PyObject_HasAttrString"(attr.toStringz);
    }

    bool hasattr(in PythonObject attr) const {
        return cast(bool) retDirect!"PyObject_HasAttr"(cast(PyObject*) attr._obj);
    }

    PythonObject getattr(in string attr) const {
        import std.string: toStringz;
        return retPyObject!"PyObject_GetAttrString"(attr.toStringz);
    }

    PythonObject getattr(in PythonObject attr) const {
        return retPyObject!"PyObject_GetAttr"(cast(PyObject*) attr._obj);
    }

    void setattr(T)(in string attr, auto ref T val) if(!is(Unqual!T == PythonObject)) {
        setattr(attr, PythonObject(val));
    }

    void setattr(in string attr, in PythonObject val) {
        import python.c: PyObject_SetAttrString;
        import autowrap.pynih.python.exception: PythonException;
        import std.string: toStringz;

        const res = PyObject_SetAttrString(cast(PyObject*) _obj, attr.toStringz, cast(PyObject*) val._obj);
        if(res == -1) throw new PythonException("Error setting attribute " ~ attr);
    }

    void setattr(T)(in PythonObject attr, auto ref T val) if(!is(Unqual!T == PythonObject)) {
        setattr(attr, PythonObject(val));
    }

    void setattr(in PythonObject attr, in PythonObject val) {
        import python.c: PyObject_SetAttr;
        import autowrap.pynih.python.exception: PythonException;

        const res = PyObject_SetAttr(cast(PyObject*) _obj, cast(PyObject*) attr._obj, cast(PyObject*) val._obj);
        if(res == -1) throw new PythonException("Error setting attribute ");

    }

    void delattr(in string attr) {
        import python.c: PyObject_SetAttrString;
        import autowrap.pynih.python.exception: PythonException;
        import std.string: toStringz;

        const res = PyObject_SetAttrString(cast(PyObject*) _obj, attr.toStringz, null);
        if(res == -1) throw new PythonException("Error setting attribute " ~ attr);
    }

    void delattr(in PythonObject attr) {
        import python.c: PyObject_SetAttr;
        import autowrap.pynih.python.exception: PythonException;

        const res = PyObject_SetAttr(cast(PyObject*) _obj, cast(PyObject*) attr._obj, null);
        if(res == -1) throw new PythonException("Error setting attribute ");
    }

    T to(T)() const {
        import autowrap.pynih.python.conv.python_to_d: to;
        return (cast(PyObject*) _obj).to!T;
    }

    string toString() const {
        import python.c: PyObject_Str;
        import autowrap.pynih.python.conv.python_to_d: to;
        return PyObject_Str(cast(PyObject*) _obj).to!string;
    }

    bool callable() const {
        return cast(bool) retDirect!"PyCallable_Check";
    }

    void del() {
        del(0, len);
    }

    void del(in size_t idx) {
        retDirect!"PySequence_DelItem"(idx);
    }

    void del(in size_t i0, in size_t i1) {
        retDirect!"PySequence_DelSlice"(i0, i1);
    }

    void del(in string key) {
        import std.string: toStringz;
        retDirect!"PyObject_DelItemString"(key.toStringz);
    }

    void del(in PythonObject key) {
        retDirect!"PyObject_DelItem"(cast(PyObject*) key._obj);
    }

    bool isInstance(in PythonObject klass) const {
        return cast(bool) retDirect!"PyObject_IsInstance"(cast(PyObject*) klass._obj);
    }

    bool isSubClass(in PythonObject klass) const {
        return cast(bool) retDirect!"PyObject_IsSubclass"(cast(PyObject*) klass._obj);
    }

    InputRange range() {
        return InputRange(iter);
    }

    PythonObject iter() const {
        return retPyObject!"PyObject_GetIter"();
    }

    PythonObject next() const {
        import python.c: PyIter_Next;
        return PythonObject(PyIter_Next(cast(PyObject*) _obj));
    }

    PythonObject keys() const {
        import python.c: PyDict_Check, PyMapping_Keys;
        if(PyDict_Check(cast(PyObject*) _obj))
            return retPyObject!"PyDict_Keys"();
        else if(auto keys = PyMapping_Keys(cast(PyObject*) _obj))
            return PythonObject(keys);
        else
            return getattr("keys");
    }

    PythonObject values() const {
        import python.c: PyDict_Check, PyMapping_Values;
        if(PyDict_Check(cast(PyObject*) _obj))
            return retPyObject!"PyDict_Values"();
        else if(auto keys = PyMapping_Values(cast(PyObject*) _obj))
            return PythonObject(keys);
        else
            return getattr("values");
    }

    PythonObject items() const {
        import python.c: PyDict_Check, PyMapping_Items;
        if(PyDict_Check(cast(PyObject*) _obj))
            return retPyObject!"PyDict_Items"();
        else if(auto keys = PyMapping_Items(cast(PyObject*) _obj))
            return PythonObject(keys);
        else
            return getattr("items");
    }

    PythonObject copy() const {
        import python.c: PyDict_Check;
        if(PyDict_Check(cast(PyObject*) _obj))
            return retPyObject!"PyDict_Copy"();
        else
            return getattr("copy");
    }

    bool merge(in PythonObject other, bool override_ = true) {
        import python.c: PyDict_Check;
        import autowrap.pynih.python.exception: PythonException;

        if(PyDict_Check(_obj))
            return cast(bool) retDirect!"PyDict_Merge"(cast(PyObject*) other._obj, cast(int) override_);
        else
            throw new PythonException("Cannot merge a non-dict");
    }

    int opCmp(in PythonObject other) const {
        import python.c: PyObject_RichCompareBool, Py_LT, Py_EQ, Py_GT;
        import autowrap.pynih.python.exception: PythonException;

        static int[int] pyOpToRet;
        if(pyOpToRet == pyOpToRet.init)
            pyOpToRet = [Py_LT: -1, Py_EQ: 0, Py_GT: 1];

        foreach(pyOp, ret; pyOpToRet) {
            const pyRes = PyObject_RichCompareBool(
                cast(PyObject*) _obj,
                cast(PyObject*) other._obj,
                pyOp
            );

            if(pyRes == -1)
                throw new PythonException("Error comparing Python objects");

            if(pyRes == 1)
                return ret;
        }

        assert(0);
    }

    PythonObject opDispatch(string identifier, A...)(auto ref A args) inout {
        import autowrap.pynih.python.exception: PythonException;

        auto value = getattr(identifier);

        if(value.callable) {
            return value(args);
        } else {
            if(args.length > 0)
                throw new PythonException("`" ~ identifier ~ "`" ~ " is not a callable");
            return value;
        }
    }

    import std.meta: anySatisfy, allSatisfy;
    private enum isPythonObject(T) = is(Unqual!T == PythonObject);

    PythonObject opCall(A...)(auto ref A args) if(!anySatisfy!(isPythonObject, A)) {
        import python.c: PyTuple_New, PyTuple_SetItem, PyObject_CallObject, Py_DecRef;
        import autowrap.pynih.python.conv.d_to_python: toPython;
        import autowrap.pynih.python.exception: PythonException;

        auto pyArgs = PyTuple_New(args.length);
        scope(exit) Py_DecRef(pyArgs);

        static foreach(i; 0 .. args.length) {
            PyTuple_SetItem(pyArgs, i, args[i].toPython);
        }

        auto ret = PyObject_CallObject(_obj, pyArgs);
        if(ret is null) throw new PythonException("Could not call callable");

        return PythonObject(ret);
    }

    PythonObject opCall(PythonObject args) {
        import python.c: PyObject_CallObject;
        import autowrap.pynih.python.exception: PythonException;

        auto ret = PyObject_CallObject(_obj, args._obj);
        if(ret is null) throw new PythonException("Could not call callable");

        return PythonObject(ret);
    }

    PythonObject opCall(PythonObject args, PythonObject kwargs) {
        import python.c: PyObject_Call;
        import autowrap.pynih.python.exception: PythonException;

        auto ret = PyObject_Call(_obj, args._obj, kwargs._obj);
        if(ret is null) throw new PythonException("Could not call callable");

        return PythonObject(ret);
    }

    PythonObject opIndex(in size_t idx) const {
        return retPyObject!"PySequence_GetItem"(idx);
    }

    PythonObject opIndex(in string key) const {
        import python.c: PyDict_Check;
        import std.string: toStringz;

        const keyz = key.toStringz;

        if(PyDict_Check(cast(PyObject*) _obj))
            return retPyObject!"PyDict_GetItemString"(keyz);
        else
            return retPyObject!"PyMapping_GetItemString"(keyz);
    }

    PythonObject opIndex(in PythonObject key) const {
        import std.string: toStringz;
        return retPyObject!"PyObject_GetItem"(cast(PyObject*) key._obj);
    }

    void opIndexAssign(K, V)(auto ref V _value, auto ref K _key) {

        import std.traits: isIntegral;

        static if(isPythonObject!V)
            alias value = _value;
        else
            auto value = PythonObject(_value);

        static if(isIntegral!K) {
            retPyObject!"PySequence_SetItem"(
                _key,
                cast(PyObject*) value._obj,
            );
        } else {

            static if(isPythonObject!K)
                alias key = _key;
            else
                auto key = PythonObject(_key);

            retPyObject!"PyObject_SetItem"(
                cast(PyObject*) key._obj,
                cast(PyObject*) value._obj,
            );
        }
    }

    PythonObject opSlice(size_t i0, size_t i1) const {
        return retPyObject!"PySequence_GetSlice"(i0, i1);
    }

    PythonObject opSlice() const {
        return this[0 .. len];
    }

    void opSliceAssign(in PythonObject val, in size_t i0, in size_t i1) {
        retDirect!"PySequence_SetSlice"(i0, i1, cast(PyObject*) val._obj);
    }

    void opSliceAssign(in PythonObject val) {
        retDirect!"PySequence_SetSlice"(0, len, cast(PyObject*) val._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "+") {
        return retPyObject!"PyNumber_Add"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "-") {
        return retPyObject!"PyNumber_Subtract"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "*") {
        return retPyObject!"PyNumber_Multiply"(other._obj);
    }

    PythonObject opBinary(string op)(int i) if(op == "*") {
        return retPyObject!"PySequence_Repeat"(i);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "/") {
        return retPyObject!"PyNumber_TrueDivide"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "%") {
        return retPyObject!"PyNumber_Remainder"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "^^") {
        import python.c: Py_IncRef, Py_None;
        Py_IncRef(Py_None);
        return retPyObject!"PyNumber_Power"(other._obj, Py_None);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "<<") {
        return retPyObject!"PyNumber_Lshift"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == ">>") {
        return retPyObject!"PyNumber_Rshift"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "&") {
        return retPyObject!"PyNumber_And"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "|") {
        return retPyObject!"PyNumber_Or"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "^") {
        return retPyObject!"PyNumber_Xor"(other._obj);
    }

    PythonObject opBinary(string op)(PythonObject other) if(op == "~") {
        return retPyObject!"PySequence_Concat"(other._obj);
    }

    PythonObject opUnary(string op)() if(op == "+") {
        return retPyObject!"PyNumber_Positive"();
    }

    PythonObject opUnary(string op)() if(op == "-") {
        return retPyObject!"PyNumber_Negative"();
    }

    PythonObject opUnary(string op)() if(op == "~") {
        return retPyObject!"PyNumber_Invert"();
    }

    bool opBinaryRight(string op)(in PythonObject key) if(op == "in") {
        return cast(bool) retDirect!"PySequence_Contains"(cast(PyObject*) key._obj);
    }

    bool opBinaryRight(string op, T)(auto ref T key) if(op == "in" && !is(Unqual!T == PythonObject)) {
        return cast(bool) retDirect!"PySequence_Contains"(cast(PyObject*) PythonObject(key)._obj);
    }

private:

    PythonObject retPyObject(string funcName, A...)(auto ref A args) const {
        import std.format: format;

        enum code = q{

            import autowrap.pynih.python.exception: PythonException;
            import python.c: %s;
            import std.traits: isPointer;

            auto obj = %s(cast(PyObject*) _obj, args);
            static if(isPointer!(typeof(obj)))
                if(obj is null) throw new PythonException("%s returned null");

            return PythonObject(obj);

        }.format(funcName, funcName, funcName);

        mixin(code);
    }

    auto retDirect(string cApiFunc, A...)(auto ref A args) const {

        import std.format: format;

        enum code = q{

            import autowrap.pynih.python.exception: PythonException;
            import python.c: %s;

            const ret = %s(cast(PyObject*) _obj, args);
            if(ret == -1)
                throw new PythonException("Could not call %s");

            return ret;

        }.format(cApiFunc, cApiFunc, cApiFunc);

        mixin(code);
    }
}


struct InputRange {
    import python.c: PyObject;

    private PythonObject _iter;
    private PythonObject _front;

    private this(PythonObject iter) {
        import python.c: PyObject_GetIter;
        import autowrap.pynih.python.exception: PythonException;

        _iter._obj = iter._obj;
        if (_iter._obj is null)
            throw new PythonException("No iterable for object");

        popFront;
    }

    // FIXME
    // ~this() {
    //     import python.c: Py_DecRef;
    //     Py_DecRef(_iter);
    // }

    void popFront() {
        _front = _iter.next;
    }

    bool empty() const {
        return _front._obj is null;
    }

    auto front() inout {
        return _front;
    }
}
