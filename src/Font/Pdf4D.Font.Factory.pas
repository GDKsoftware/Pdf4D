// Copyright 2026 GDK Software
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
  Pdf4D.Font.CIDFont,
  Pdf4D.Model.DocumentContext;

type
  // Stands in for CreateFont inside GetFont; tests use it to make a font fail in a chosen way
  TPDFontCreator = reference to function(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont;

  // Makes the right font class for a font dictionary: Type 1 (with or without /FontFile3), MMType1, TrueType, Type 3 and Type0.
  TPDFontFactory = class
  private
{$IFDEF PDF4D_TESTS}
    class var FCreatorOverride: TPDFontCreator;
{$ENDIF}

    class function HasFontFile3(const Dictionary: TCosDictionary): Boolean; static;
    class function CreateType1Font(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont; static;
    class procedure CheckFontType(const Dictionary: TCosDictionary; const Context: TPDDocumentContext); static;
    class procedure LogWarning(const Context: TPDDocumentContext; const Fmt: string; const Args: array of const); static;
    class procedure LogError(const Context: TPDDocumentContext; const Fmt: string; const Args: array of const); static;
    class procedure RememberFailure(const Dictionary: TCosDictionary; const Context: TPDDocumentContext); static;
    class function CreateNewFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont; static;

  public
    // PDFontFactory.createFont: a new font that the caller owns. Dictionary stays with the document and has to outlive the
    // font. Context may be nil. An unknown or missing subtype gives a Type 1 font, as Acrobat does (PDFBOX-1988).
    class function CreateFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont; static;
    // The font of a dictionary, made once per document: the font is kept by Context, so the caller does not own it and
    // must not use it after the document is freed. Without a Context this is CreateFont, and the caller owns the font;
    // that is why Context is required here.
    // A dictionary that failed once is remembered by the context: it is not parsed again (the font program of a Type 0
    // font can be big), and GetFont raises EPdfParseException for it at once. That holds for every failure except a mistake
    // in the library (access violation, invalid pointer): a hostile font program can drive the font code into exceptions
    // that are no EPdfException, and those reach the caller as EPdfParseException.
    class function GetFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont; static;
    // True when an earlier GetFont for Dictionary failed
    class function HasFailed(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): Boolean; static;
    // Helvetica with WinAnsiEncoding, like PDType1Font.HELVETICA. The caller owns the font.
    class function CreateDefaultFont(const Context: TPDDocumentContext): TPDFont; static;
    // PDFontFactory.createDescendantFont: the CID font of a Type 0 font, which the caller owns. Parent stays the owner of
    // nothing and has to outlive the font. Raises EPdfParseException for a dictionary that is not a font or has another
    // subtype than CIDFontType0 or CIDFontType2.
    class function CreateDescendantFont(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent): TPDCIDFont; static;
{$IFDEF PDF4D_TESTS}
    // For tests only, compiled when PDF4D_TESTS is defined: replaces the font creation in GetFont. Set before use, reset to nil afterwards.
    class property CreatorOverride: TPDFontCreator read FCreatorOverride write FCreatorOverride;
{$ENDIF}
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Font.CIDFontType0,
  Pdf4D.Font.CIDFontType2,
  Pdf4D.Font.Type0,
  Pdf4D.Font.Type1,
  Pdf4D.Font.Type3,
  Pdf4D.Font.TrueType,
  Pdf4D.Font.Type1C;

type
  // What the context holds for a font dictionary that could not be made
  TPDFontFailure = class
  end;

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
  else if SubType = TCosNames.TrueType then
  begin
    Result := TPDTrueTypeFont.Create(Dictionary, Context);
  end
  else if SubType = TCosNames.Type0 then
  begin
    Result := TPDType0Font.Create(Dictionary, Context);
  end
  else if SubType = TCosNames.Type3 then
  begin
    Result := TPDType3Font.Create(Dictionary, Context);
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

class function TPDFontFactory.CreateDescendantFont(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent): TPDCIDFont;
begin
  if not Assigned(Dictionary) then
  begin
    raise EArgumentNilException.Create('A descendant font needs a font dictionary');
  end;

  const TypeName = Dictionary.GetNameAsString(TCosNames.Type_, TCosNames.Font);
  if TypeName <> TCosNames.Font then
  begin
    raise EPdfParseException.CreateFmt('Expected ''Font'' dictionary but found ''%s''', [TypeName]);
  end;

  const SubType = Dictionary.GetNameAsString(TCosNames.Subtype, '');
  if SubType = TCosNames.CIDFontType2 then
  begin
    Result := TPDCIDFontType2.Create(Dictionary, Parent);
  end
  else if SubType = TCosNames.CIDFontType0 then
  begin
    Result := TPDCIDFontType0.Create(Dictionary, Parent);
  end
  else
  begin
    raise EPdfParseException.CreateFmt('Invalid font type: %s', [TypeName]);
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
    if Cached is TPDFontFailure then
    begin
      raise EPdfParseException.Create('The font could not be read earlier');
    end;
    Exit(TPDFont(Cached));
  end;

  try
    Result := CreateNewFont(Dictionary, Context);
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        raise;
      end;

      RememberFailure(Dictionary, Context);
      if Failure is EPdfException then
      begin
        raise;
      end;

      LogError(Context, 'The font could not be made: %s: %s', [Failure.ClassName, Failure.Message]);
      raise EPdfParseException.CreateFmt('The font could not be made: %s: %s', [Failure.ClassName, Failure.Message]);
    end;
  end;
  try
    Context.AddCachedObject(Dictionary, Result);
  except
    Result.Free;
    raise;
  end;
end;

class function TPDFontFactory.CreateNewFont(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont;
begin
{$IFDEF PDF4D_TESTS}
  if Assigned(FCreatorOverride) then
  begin
    Exit(FCreatorOverride(Dictionary, Context));
  end;

{$ENDIF}
  Result := CreateFont(Dictionary, Context);
end;

class function TPDFontFactory.HasFailed(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): Boolean;
begin
  var Cached: TObject;
  Result := (Assigned(Context) and Assigned(Dictionary) and Context.TryGetCachedObject(Dictionary, Cached) and (Cached is TPDFontFailure));
end;

class procedure TPDFontFactory.RememberFailure(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  const Marker = TPDFontFailure.Create;
  try
    Context.AddCachedObject(Dictionary, Marker);
  except
    Marker.Free;
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
