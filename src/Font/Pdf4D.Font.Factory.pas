// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDFontFactory.java (3.0.8)
// Port of: PDResources.getFont and its font cache (3.0.8), as GetFont
unit Pdf4D.Font.Factory;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Model.DocumentContext;

type
  // Makes the right font class for a font dictionary. Type 1 (with or without /FontFile3) and MMType1 are known; the other
  // subtypes raise EPdfUnsupportedFeatureException until their classes exist.
  TPDFontFactory = class
  private
    class function HasFontFile3(const Dictionary: TCosDictionary): Boolean; static;
    class function CreateType1Font(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont; static;
    class procedure CheckFontType(const Dictionary: TCosDictionary; const Context: TPDDocumentContext); static;
    class procedure LogWarning(const Context: TPDDocumentContext; const Fmt: string; const Args: array of const); static;
    class procedure LogError(const Context: TPDDocumentContext; const Fmt: string; const Args: array of const); static;

  public
    // PDFontFactory.createFont: a new font that the caller owns. Dictionary stays with the document and has to outlive the
    // font. Context may be nil. An unknown or missing subtype gives a Type 1 font, as Acrobat does (PDFBOX-1988).
    class function CreateFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont; static;
    // The font of a dictionary, made once per document: the font is kept by Context, so the caller does not own it and
    // must not use it after the document is freed. Without a Context this is CreateFont, and the caller owns the font;
    // that is why Context is required here.
    class function GetFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont; static;
    // Helvetica with WinAnsiEncoding, like PDType1Font.HELVETICA. The caller owns the font.
    class function CreateDefaultFont(const Context: TPDDocumentContext): TPDFont; static;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Font.Type1,
  Pdf4D.Font.Type1C;

const
  HelveticaName = 'Helvetica';

{ TPDFontFactory }

class procedure TPDFontFactory.LogWarning(const Context: TPDDocumentContext; const Fmt: string; const Args: array of const);
begin
  if Assigned(Context) and Assigned(Context.Log) then
  begin
    Context.Log.Warning(Fmt, Args);
  end;
end;

class procedure TPDFontFactory.LogError(const Context: TPDDocumentContext; const Fmt: string; const Args: array of const);
begin
  if Assigned(Context) and Assigned(Context.Log) then
  begin
    Context.Log.Error(Fmt, Args);
  end;
end;

class function TPDFontFactory.HasFontFile3(const Dictionary: TCosDictionary): Boolean;
begin
  var Descriptor: TCosDictionary;
  Result := (Dictionary.TryGetCosDictionary(TCosNames.FontDescriptor, Descriptor) and Descriptor.ContainsKey(TCosNames.FontFile3));
end;

class function TPDFontFactory.CreateType1Font(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont;
begin
  if HasFontFile3(Dictionary) then
  begin
    Result := TPDType1CFont.Create(Dictionary, Context);
  end
  else
  begin
    Result := TPDType1Font.Create(Dictionary, Context);
  end;
end;

class procedure TPDFontFactory.CheckFontType(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  const TypeName = Dictionary.GetNameAsString(TCosNames.Type_, TCosNames.Font);
  if TypeName <> TCosNames.Font then
  begin
    LogError(Context, 'Expected ''Font'' dictionary but found ''%s''', [TypeName]);
  end;
end;

class function TPDFontFactory.CreateFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont;
begin
  if not Assigned(Dictionary) then
  begin
    raise EArgumentNilException.Create('A font needs a font dictionary');
  end;

  CheckFontType(Dictionary, Context);
  const SubType = Dictionary.GetNameAsString(TCosNames.Subtype, '');
  if (SubType = TCosNames.Type1) or (SubType = TCosNames.MMType1) then
  begin
    Result := CreateType1Font(Dictionary, Context);
  end
  else if (SubType = TCosNames.TrueType) or (SubType = TCosNames.Type3) or (SubType = TCosNames.Type0) then
  begin
    raise EPdfUnsupportedFeatureException.CreateFmt('Font subtype %s is not supported yet', [SubType]);
  end
  else if (SubType = TCosNames.CIDFontType0) or (SubType = TCosNames.CIDFontType2) then
  begin
    raise EPdfParseException.CreateFmt('%s descendant font not allowed', [SubType]);
  end
  else
  begin
    // Assuming a Type 1 font (see PDFBOX-1988) because it seems that Adobe Reader does this. However, we may need more
    // sophisticated logic perhaps looking at the FontFile.
    LogWarning(Context, 'Invalid font subtype ''%s''', [SubType]);
    Result := TPDType1Font.Create(Dictionary, Context);
  end;
end;

class function TPDFontFactory.GetFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont;
begin
  if (not Assigned(Context)) or (not Assigned(Dictionary)) then
  begin
    raise EArgumentNilException.Create('A cached font needs a font dictionary and a document context');
  end;

  var Cached: TObject;
  if Context.TryGetCachedObject(Dictionary, Cached) then
  begin
    Exit(TPDFont(Cached));
  end;

  Result := CreateFont(Dictionary, Context);
  try
    Context.AddCachedObject(Dictionary, Result);
  except
    Result.Free;
    raise;
  end;
end;

class function TPDFontFactory.CreateDefaultFont(const Context: TPDDocumentContext): TPDFont;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem(TCosNames.Type_, TCosName.Create(TCosNames.Font));
    Dictionary.SetItem(TCosNames.Subtype, TCosName.Create(TCosNames.Type1));
    Dictionary.SetItem(TCosNames.BaseFont, TCosName.Create(HelveticaName));
    Dictionary.SetItem(TCosNames.Encoding, TCosName.Create(TCosNames.WinAnsiEncoding));
    Result := TPDType1Font.Create(Dictionary, Context);
  except
    Dictionary.Free;
    raise;
  end;
  Result.OwnDictionary;
end;

end.
