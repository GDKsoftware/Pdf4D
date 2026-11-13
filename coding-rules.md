# Coding rules

Pdf4D follows the GDK Delphi rules. This file lists where it deviates. Where it conflicts with the standard rule set, this file wins.

## Exceptions

1. **`System.Generics.Collections` instead of Spring4D.** Overrides: "use Spring.Collections". Reason: the library has no dependencies besides the RTL.
2. **Objects with explicit ownership instead of interfaces in the inner layer** (`Cos`, `Parser`, `Filter`, `Crypto`, `Encryption`, `Model`), with `try..finally` where needed. Overrides: "use interface references for automatic memory management". Reason: the object graph has cycles (page and `/Parent`), which reference counting would leak. The public API layer (`Api`) does use interfaces.
3. **Method names in the inner layer follow PDFBox** (`GetDictionaryObject`, `ParseCosDictionary`). Overrides: naming for behaviour. Reason: the Delphi code can be laid next to the Java code, so upstream fixes can be carried over.
4. **`var` parameters only** where a ported algorithm has to update a position or state and that cannot be done through a field. Overrides: "no `var` parameters".
5. **Long ported methods may keep the PDFBox order** as long as they stay readable. Splitting into private methods is preferred. Overrides: method decomposition.
6. **Inline variables and `const` stay mandatory**, as in the GDK rules.
7. **Shared, lazily made objects go through `TPdfSharedInstance` and `TPdfSharedCache`.** A `class destructor` may free such an object. No `initialization` or `finalization` sections. Overrides: the GDK rule on singletons. Reason: thread-safe lazy publication and leak detection (an object that is filled once and freed at shutdown is no leak).

## Additions

- Language level: Delphi 12. No Delphi 13-only syntax, such as the ternary `if` expression.
- Only `System.*` units in the library. No `Winapi.*`, `Vcl.*`, `FMX.*` or inline assembler.
- Every unit that ports PDFBox code names the PDFBox source files and the PDFBox version in its header.
- Zero hints and zero warnings on all platforms.
