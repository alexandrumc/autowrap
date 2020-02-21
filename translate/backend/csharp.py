from contextlib import contextmanager


class Writer:
    def __init__(self, out_file):
        self.out_file = out_file
        self.indent_level = 0

    def write(self, val):
        self.out_file.write(f"{val}")

    def writeln(self, line):
        self.indent()
        self.write(f"{line}\n")

    def indent(self):
        self.write(f"{self.indent_level * 4 * ' '}")

    def open_block(self):
        self.writeln("{")
        self.indent_level += 1

    def close_block(self):
        self.indent_level -= 1
        self.writeln("}")


@contextmanager
def NamedBlock(writer, attr, line):
    try:
        writer.writeln(attr)
        writer.writeln(line)
        writer.open_block()
        yield writer
    finally:
        writer.close_block()


def translate(source_code, filename):
    from python_to_ir import transform

    tests = transform(source_code)

    with open(filename, "w") as file:
        writer = Writer(file)

        writer.writeln("// this file is autogenerated, do not modify by hand")

        with NamedBlock(writer,
                        "",
                        f"namespace Autowrap.CSharp.Tests") as block:
            _write_imports(block, tests)

            # we use the fully-qualified names to avoid name-collisions
            # with the symbols from the test
            with NamedBlock(
                    block,
                    "[Microsoft.VisualStudio.TestTools.UnitTesting.TestClass]",
                    "public class TestMain"
            ) as block:

                for test in tests:
                    _translate_test(block, test)


def _write_imports(writer, tests):
    from ir import Import

    def imports_in_test(test):
        return [s.module for s in test.statements if isinstance(s, Import)]

    nested_imports = [imports_in_test(test) for test in tests]
    flat_imports = [i for sublist in nested_imports for i in sublist]
    unique_imports = sorted(set(flat_imports))
    # Filter datetime out of the Python tests
    imports = [i for i in unique_imports if i != "datetime"]

    for import_ in imports:
        writer.writeln(f"using {import_.capitalize()};")

    writer.writeln('using Microsoft.VisualStudio.TestTools.UnitTesting;')

    writer.writeln("")


def _translate_test(writer, test):

    with NamedBlock(
        writer,
        "[Microsoft.VisualStudio.TestTools.UnitTesting.TestMethod]",
        f"public void {test.name}()"
    ) as block:

        for statement in test.statements:
            translation = _translate(statement)
            if translation != "":
                block.writeln(f"// {translation};")


def _translate(node):
    import sys

    this_module = sys.modules[__name__]
    node_type = type(node).__name__
    function_name = '_translate_' + node_type

    assert hasattr(this_module, function_name), \
        f"No C# handler for IR type {node_type}"

    return eval(f"{function_name}(node)")


def _translate_Assertion(assertion):
    actual = _translate(assertion.lhs)
    expected = _translate(assertion.rhs)
    return f"Assert.AreEqual({expected}, {actual})"


def _translate_int(val):
    return f"{val}"


def _translate_str(val):
    return f'{val}'


def _translate_Import(import_):
    # nothing to do here since imports from Python have to become top-level
    # using declarations in C#
    return ""


def _translate_Assignment(assignment):
    lhs = _translate(assignment.lhs)
    rhs = _translate(assignment.rhs)
    return f"var {lhs} = {rhs}"


def _translate_FunctionCall(call):
    receiver = _translate(call.receiver)
    args = ", ".join([_translate(x) for x in call.args])

    return f"{receiver}({args})"


def _translate_IfPyd(ifpyd):
    return f"// TODO: ifpyd {ifpyd}"


def _translate_IfPynih(ifpynih):
    return f"// TODO: ifpynih {ifpynih}"


def _translate_ShouldThrow(should_throw):
    return f"// TODO: ShouldThrow {should_throw}"


def _translate_Sequence(seq):
    return f"{{{seq}}}"


def _translate_NumLiteral(val):
    return f"{val.value}"


def _translate_BytesLiteral(val):
    return f"{val.value}"


def _translate_StringLiteral(val):
    return f'"{val.value}"'


def _translate_Attribute(val):
    instance = _translate(val.instance)
    attribute = _translate(val.attribute)
    return f"{instance}.{attribute.capitalize()}"
