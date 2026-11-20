// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/PDSoftMask.java (3.0.8)
unit Pdf4D.Graphics.SoftMask;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.&Function,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.FormXObject;

type
  // PDSoftMask, immutable once made by the gs operator. The graphics state and its clones share it.
  IPdfSoftMask = interface
    ['{3C6E9A15-8B2D-4F70-A4C1-E57D20B98F36}']
    // 'Alpha' or 'Luminosity'
    function SubType: string;
    // The transparency group that makes the mask; not owned
    function Group: TPDFormXObject;
    // The /BC entry as the numbers of the file; False when it is missing
    function TryGetBackdropColor(out Components: TArray<Single>): Boolean;
    // nil for /Identity and when /TR is missing or cannot be made; not owned
    function TransferFunction: TPDFunction;
    // The CTM at the moment that gs set the soft mask
    function InitialTransformationMatrix: TPdfMatrix;
  end;

  TPDSoftMask = class(TInterfacedObject, IPdfSoftMask)
  private
    FSubType: string;
    FGroup: TPDFormXObject;
    FBackdrop: TArray<Single>;
    FHasBackdrop: Boolean;
    FTransfer: TPDFunction;
    FInitialMatrix: TPdfMatrix;

    constructor Create(const Dictionary: TCosDictionary; const Group: TPDFormXObject; const Context: TPDDocumentContext;
                       const InitialMatrix: TPdfMatrix);
    procedure ReadBackdrop(const Dictionary: TCosDictionary);
    procedure ReadTransfer(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);

  public
    // PDSoftMask.create for the value of /SMask of an ExtGState: False for a name (/None, but also another name) and for a dictionary
    // without a group stream, which PDFBox paints without mask. The mask does not own the group stream, the document does.
    class function TryCreate(const Value: TCosBase; const Context: TPDDocumentContext; const InitialMatrix: TPdfMatrix;
                             out Mask: IPdfSoftMask): Boolean; static;

    destructor Destroy; override;

    function SubType: string;
    function Group: TPDFormXObject;
    function TryGetBackdropColor(out Components: TArray<Single>): Boolean;
    function TransferFunction: TPDFunction;
    function InitialTransformationMatrix: TPdfMatrix;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray;

resourcestring
  TransferNotMade = 'The /TR of a soft mask is ignored: %s';

{ TPDSoftMask }

class function TPDSoftMask.TryCreate(const Value: TCosBase; const Context: TPDDocumentContext; const InitialMatrix: TPdfMatrix;
                                     out Mask: IPdfSoftMask): Boolean;
begin
  Mask := nil;
  if not (Value is TCosDictionary) then
  begin
    Exit(False);
  end;

  const Dictionary = TCosDictionary(Value);
  var GroupStream: TCosBase;
  const HasGroup = (Dictionary.TryGetDictionaryObject(TCosNames.G, GroupStream) and (GroupStream is TCosStream));
  if not HasGroup then
  begin
    Exit(False);
  end;

  Mask := TPDSoftMask.Create(Dictionary, TPDFormXObject.Create(TCosStream(GroupStream)), Context, InitialMatrix);
  Result := True;
end;

constructor TPDSoftMask.Create(const Dictionary: TCosDictionary; const Group: TPDFormXObject; const Context: TPDDocumentContext;
                               const InitialMatrix: TPdfMatrix);
begin
  inherited Create;
  FGroup := Group;
  FInitialMatrix := InitialMatrix;
  FSubType := TCosNames.Luminosity;

  var SubTypeValue: TCosBase;
  if Dictionary.TryGetDictionaryObject(TCosNames.S, SubTypeValue) and (SubTypeValue is TCosName) then
  begin
    FSubType := TCosName(SubTypeValue).Name;
  end;

  ReadBackdrop(Dictionary);
  ReadTransfer(Dictionary, Context);
end;

destructor TPDSoftMask.Destroy;
begin
  FTransfer.Free;
  FGroup.Free;
  inherited;
end;

procedure TPDSoftMask.ReadBackdrop(const Dictionary: TCosDictionary);
begin
  var Items: TCosArray;
  if not Dictionary.TryGetCosArray(TCosNames.BC, Items) then
  begin
    Exit;
  end;

  SetLength(FBackdrop, Items.Count);
  for var Index := 0 to Items.Count - 1 do
  begin
    const Item = Items.GetObject(Index);
    if Item is TCosNumber then
    begin
      FBackdrop[Index] := TCosNumber(Item).FloatValue;
    end;
  end;
  FHasBackdrop := True;
end;

procedure TPDSoftMask.ReadTransfer(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  var Value: TCosBase;
  if not Dictionary.TryGetDictionaryObject(TCosNames.TR, Value) then
  begin
    Exit;
  end;

  const IsIdentity = ((Value is TCosName) and (TCosName(Value).Name = TCosNames.Identity));
  if IsIdentity then
  begin
    Exit;
  end;

  try
    FTransfer := TPDFunction.Create(Value, Context);
  except
    on Error: EPdfParseException do
    begin
      if Assigned(Context.Log) then
      begin
        Context.Log.Warning(TransferNotMade, [Error.Message]);
      end;
    end;
  end;
end;

function TPDSoftMask.SubType: string;
begin
  Result := FSubType;
end;

function TPDSoftMask.Group: TPDFormXObject;
begin
  Result := FGroup;
end;

function TPDSoftMask.TryGetBackdropColor(out Components: TArray<Single>): Boolean;
begin
  Components := FBackdrop;
  Result := FHasBackdrop;
end;

function TPDSoftMask.TransferFunction: TPDFunction;
begin
  Result := FTransfer;
end;

function TPDSoftMask.InitialTransformationMatrix: TPdfMatrix;
begin
  Result := FInitialMatrix;
end;

end.
