// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSDocument.java (3.0.8)
unit Pdf4D.Cos.Document;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.Resolver.Interfaces,
  Pdf4D.Encryption.AccessPermission,
  Pdf4D.Encryption.Dictionary,
  Pdf4D.IO.RandomAccessRead;

type
  // Owner of everything in a loaded file. Destruction order: the object pool (proxies and their content),
  // the trailer, the resolver's implementing object (the parser, which may read the source) and last the source.
  TCosDocument = class
  private
    FSource: TRandomAccessRead;
    FOptions: TPdfLoadOptions;
    FLog: TPdfLog;
    FKeyComparer: IEqualityComparer<TCosObjectKey>;
    FPool: TObjectDictionary<TCosObjectKey, TCosObject>;
    FXrefTable: TDictionary<TCosObjectKey, Int64>;
    FTrailer: TCosDictionary;
    FForwarder: TCosObjectResolverBase;
    FResolver: ICosObjectResolver;
    FResolverOwner: TObject;
    FVersion: Single;
    FStartXref: Int64;
    FIsXRefStream: Boolean;
    FHasHybridXRef: Boolean;
    FHighestXRefObjectNumber: Int64;
    FEncryption: TPdfEncryption;
    FAccessPermission: TPdfAccessPermission;

  public
    constructor Create(const Source: TRandomAccessRead; const Options: TPdfLoadOptions);
    destructor Destroy; override;

    // Sets the resolver. A non-nil Owner is the object that implements it (the parser) and is freed by the
    // document, after the objects it loaded and before the source. Replaces an earlier resolver and owner.
    procedure SetResolver(const Resolver: ICosObjectResolver; const Owner: TObject);

    // Creates the proxy when it does not exist yet, so a forward reference works. The document owns it.
    function GetObjectFromPool(const Key: TCosObjectKey): TCosObject;

    function ObjectKeys: TArray<TCosObjectKey>;

    // Replace what the document owns. Passing the object that is there already changes nothing.
    procedure SetEncryption(const Value: TPdfEncryption);
    procedure SetAccessPermission(const Value: TPdfAccessPermission);

    property Source: TRandomAccessRead read FSource;
    property Resolver: ICosObjectResolver read FResolver;
    property Trailer: TCosDictionary read FTrailer;
    property Version: Single read FVersion write FVersion;
    // What the xref parsing found, like the values that COSParser sets on COSDocument: the offset of the first xref
    // section, whether the last one is an xref stream, whether a /XRefStm was read and the highest object number of
    // the xref table
    property StartXref: Int64 read FStartXref write FStartXref;
    property IsXRefStream: Boolean read FIsXRefStream write FIsXRefStream;
    property HasHybridXRef: Boolean read FHasHybridXRef write FHasHybridXRef;
    property HighestXRefObjectNumber: Int64 read FHighestXRefObjectNumber write FHighestXRefObjectNumber;
    // The offset of an object, or -N for an object in the object stream N, like PDFBox
    property XrefTable: TDictionary<TCosObjectKey, Int64> read FXrefTable;
    property Log: TPdfLog read FLog;
    property Options: TPdfLoadOptions read FOptions;
    // The encryption dictionary of the trailer, nil for a document that is not encrypted. It looks into the dictionary, so
    // it is freed before the objects.
    property Encryption: TPdfEncryption read FEncryption;
    // What the password that opened the document allows. All permissions for a document that is not encrypted.
    property AccessPermission: TPdfAccessPermission read FAccessPermission;
  end;

implementation

uses
  Pdf4D.Cos.Base;

type
  // The proxies resolve through the document, so SetResolver can come after the first proxy exists
  TCosDocumentResolver = class(TCosObjectResolverBase)
  private
    FDocument: TCosDocument;

  public
    constructor Create(const Document: TCosDocument);

    function ResolveObject(const Key: TCosObjectKey): TCosBase; override;
  end;

{ TCosDocumentResolver }

constructor TCosDocumentResolver.Create(const Document: TCosDocument);
begin
  inherited Create;
  FDocument := Document;
end;

function TCosDocumentResolver.ResolveObject(const Key: TCosObjectKey): TCosBase;
begin
  const Target = FDocument.Resolver;
  if Assigned(Target) then
  begin
    Result := Target.ResolveObject(Key);
  end
  else
  begin
    Result := nil;
  end;
end;

{ TCosDocument }

constructor TCosDocument.Create(const Source: TRandomAccessRead; const Options: TPdfLoadOptions);
begin
  inherited Create;
  FSource := Source;
  FOptions := Options;
  FLog := TPdfLog.Create(Options.OnLog);
  FKeyComparer := TCosObjectKeyComparer.Create;
  FPool := TObjectDictionary<TCosObjectKey, TCosObject>.Create([doOwnsValues], FKeyComparer);
  FXrefTable := TDictionary<TCosObjectKey, Int64>.Create(FKeyComparer);
  FTrailer := TCosDictionary.Create;
  FForwarder := TCosDocumentResolver.Create(Self);
  FVersion := 1.4;
  FAccessPermission := TPdfAccessPermission.GetOwnerAccessPermission;
end;

destructor TCosDocument.Destroy;
begin
  FEncryption.Free;
  FAccessPermission.Free;
  // The proxies hold interface references to the forwarder: they have to go first
  FPool.Free;
  FTrailer.Free;
  FForwarder.Free;
  FXrefTable.Free;
  FResolver := nil;
  FResolverOwner.Free;
  FLog.Free;
  FSource.Free;
  inherited;
end;

procedure TCosDocument.SetResolver(const Resolver: ICosObjectResolver; const Owner: TObject);
begin
  const PreviousOwner = FResolverOwner;
  FResolver := nil;
  FResolverOwner := Owner;
  FResolver := Resolver;
  if PreviousOwner <> Owner then
  begin
    PreviousOwner.Free;
  end;
end;

procedure TCosDocument.SetEncryption(const Value: TPdfEncryption);
begin
  if FEncryption <> Value then
  begin
    FEncryption.Free;
    FEncryption := Value;
  end;
end;

procedure TCosDocument.SetAccessPermission(const Value: TPdfAccessPermission);
begin
  if FAccessPermission <> Value then
  begin
    FAccessPermission.Free;
    FAccessPermission := Value;
  end;
end;

function TCosDocument.GetObjectFromPool(const Key: TCosObjectKey): TCosObject;
begin
  if not FPool.TryGetValue(Key, Result) then
  begin
    Result := TCosObject.Create(Key, FForwarder);
    FPool.Add(Key, Result);
  end;
end;

function TCosDocument.ObjectKeys: TArray<TCosObjectKey>;
begin
  Result := FXrefTable.Keys.ToArray;
  const Comparer: IComparer<TCosObjectKey> = TCosObjectKeyComparer.Create;
  TArray.Sort<TCosObjectKey>(Result, Comparer);
end;

end.
