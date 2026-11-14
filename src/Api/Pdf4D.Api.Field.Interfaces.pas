// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Field.Interfaces;

interface

uses
  Pdf4D.Model.Field;

type
  IPdfField = interface;

  // A field of the interactive form. The field keeps its document alive.
  //
  // A field with broken data does not break the document: Value and Values give an empty result for it and the problem
  // goes to the log callback of the load options.
  IPdfField = interface
    ['{C2F5A8D1-3B79-4E06-8A4C-9D1E7B3F6052}']

    function Kind: TPdfFieldKind;
    // The partial name (/T)
    function Name: string;
    function FullyQualifiedName: string;
    // The value as text. A check box and a radio button give their on value or Off, a combo box and a list box the
    // values as "[a, b]". A push button, a signature field and a non terminal field give an empty string.
    function Value: string;
    // The /V of a choice field as separate values
    function Values: TArray<string>;
    function Children: TArray<IPdfField>;
  end;

implementation

end.
