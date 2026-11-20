// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ColorBuilder;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Resources,
  Pdf4D.Graphics.Color,
  Pdf4D.Tests.Functions;

type
  // Makes the resources and colour space objects for the tests of the colour spaces, in a context whose log collects the
  // warnings. The builder owns everything that it hands out, except what a dictionary or an array has taken over.
  TColorTestBuilder = class
  private
    FFunctions: TFunctionTestBuilder;
    FOwned: TObjectList<TObject>;
    FResourceDictionary: TCosDictionary;
    FColorSpaces: TCosDictionary;
    FResources: TPDResources;

    function GetContext: TPDDocumentContext;

  public
    constructor Create;
    destructor Destroy; override;

    // sRGB.icc with the device model sRGB in the header, which the file of PDFBox does not have: PDICCBased takes the shortcut on it
    class function SrgbModelProfile: TBytes; static;

    function NewName(const Name: string): TCosBase;
    // [/ICCBased stream]; the stream has /N, holds Profile, and has an /Alternate when AlternateName is not empty
    function NewIccArray(const Profile: TBytes; const Components: Integer; const AlternateName: string = ''): TCosArray;
    function IccStreamOf(const IccArray: TCosArray): TCosStream;
    // An indirect reference to Target, which the reference owns from now on (the builder owns the reference). With it an object
    // can refer to the object that holds it, which a direct structure cannot.
    function NewReference(const Target: TCosBase; const Number: Integer): TCosBase;
    // Takes over Value
    procedure AddColorSpace(const Name: string; const Value: TCosBase);
    function CreateSpace(const Value: TCosBase; const WasDefault: Boolean = False): TPDColorSpace;
    function WarningCount: Integer;

    property Resources: TPDResources read FResources;
    property Functions: TFunctionTestBuilder read FFunctions;
    property Context: TPDDocumentContext read GetContext;
  end;

implementation

uses
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Graphics.Color.Factory,
  Pdf4D.Tests.IccBuilder;

const
  ModelOffset = 52;

{ TColorTestBuilder }

constructor TColorTestBuilder.Create;
begin
  inherited Create;
  FFunctions := TFunctionTestBuilder.Create;
  FOwned := TObjectList<TObject>.Create(True);
  FResourceDictionary := TCosDictionary.Create;
  FOwned.Add(FResourceDictionary);
  FColorSpaces := TCosDictionary.Create;
  FResourceDictionary.SetItem(TCosNames.ColorSpace, FColorSpaces);
  FResources := TPDResources.Create(FResourceDictionary, FFunctions.Context);
  FOwned.Add(FResources);
end;

destructor TColorTestBuilder.Destroy;
begin
  FOwned.Free;
  FFunctions.Free;
  inherited;
end;

class function TColorTestBuilder.SrgbModelProfile: TBytes;
begin
  Result := TIccTestFiles.ReadProfile('sRGB.icc');
  const Model = TEncoding.ASCII.GetBytes('sRGB');
  Move(Model[0], Result[ModelOffset], Length(Model));
end;

function TColorTestBuilder.GetContext: TPDDocumentContext;
begin
  Result := FFunctions.Context;
end;

function TColorTestBuilder.NewName(const Name: string): TCosBase;
begin
  Result := TCosName.Create(Name);
  FOwned.Add(Result);
end;

function TColorTestBuilder.NewIccArray(const Profile: TBytes; const Components: Integer; const AlternateName: string): TCosArray;
begin
  const Stream = TCosStream.Create;
  Stream.SetRawData(Profile);
  Stream.SetItem(TCosNames.N, TCosInteger.Create(Components));
  if AlternateName <> '' then
  begin
    Stream.SetItem(TCosNames.Alternate, TCosName.Create(AlternateName));
  end;

  Result := TCosArray.Create;
  FOwned.Add(Result);
  Result.Add(TCosName.Create(TCosNames.ICCBased));
  Result.Add(Stream);
end;

function TColorTestBuilder.IccStreamOf(const IccArray: TCosArray): TCosStream;
begin
  Result := TCosStream(IccArray.Get(1));
end;

function TColorTestBuilder.NewReference(const Target: TCosBase; const Number: Integer): TCosBase;
begin
  FOwned.Extract(Target);
  const Reference = TCosObject.Create(TCosObjectKey.Make(Number, 0), nil);
  Reference.SetObject(Target);
  FOwned.Add(Reference);
  Result := Reference;
end;

procedure TColorTestBuilder.AddColorSpace(const Name: string; const Value: TCosBase);
begin
  FOwned.Extract(Value);
  FColorSpaces.SetItem(Name, Value);
end;

function TColorTestBuilder.CreateSpace(const Value: TCosBase; const WasDefault: Boolean): TPDColorSpace;
begin
  Result := TPDColorSpaceFactory.Create(Value, FResources, WasDefault);
end;

function TColorTestBuilder.WarningCount: Integer;
begin
  Result := FFunctions.WarningCount;
end;

end.
