// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Model.DocumentContext;

interface

uses
  System.SysUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Document;

type
  // What the model objects of one document share: the log, the options and a cache of objects that are made from
  // dictionaries and streams of the document (fonts, for instance). The context is not thread safe, like the document.
  TPDDocumentContext = class
  private
    FCosDocument: TCosDocument;
    FLog: TPdfLog;
    FOptions: TPdfLoadOptions;
    FObjects: TObjectDictionary<TObject, TObject>;

    procedure Initialize(const Log: TPdfLog; const Options: TPdfLoadOptions);

  public
    // Does not own CosDocument. nil is allowed (tests): there is no log and the options are the defaults.
    constructor Create(const CosDocument: TCosDocument); overload;
    // For a model without a loaded document. Does not own Log, which may be nil.
    constructor Create(const Log: TPdfLog; const Options: TPdfLoadOptions); overload;
    destructor Destroy; override;

    // Key is the identity of a dictionary or stream. Value stays owned by the context.
    function TryGetCachedObject(const Key: TObject; out Value: TObject): Boolean;
    // The context becomes the owner of Value. A second value for the same Key raises EArgumentException.
    procedure AddCachedObject(const Key: TObject; const Value: TObject);

    property CosDocument: TCosDocument read FCosDocument;
    property Log: TPdfLog read FLog;
    property Options: TPdfLoadOptions read FOptions;
  end;

implementation

type
  TIdentityComparer = class(TEqualityComparer<TObject>)
  public
    function Equals(const Left, Right: TObject): Boolean; override;
    function GetHashCode(const Value: TObject): Integer; override;
  end;

{ TIdentityComparer }

function TIdentityComparer.Equals(const Left, Right: TObject): Boolean;
begin
  Result := (Left = Right);
end;

function TIdentityComparer.GetHashCode(const Value: TObject): Integer;
begin
  Result := Integer((NativeUInt(Value) shr 4) and $7FFFFFFF);
end;

{ TPDDocumentContext }

constructor TPDDocumentContext.Create(const CosDocument: TCosDocument);
begin
  inherited Create;
  FCosDocument := CosDocument;
  if Assigned(CosDocument) then
  begin
    Initialize(CosDocument.Log, CosDocument.Options);
  end
  else
  begin
    Initialize(nil, TPdfLoadOptions.Default);
  end;
end;

constructor TPDDocumentContext.Create(const Log: TPdfLog; const Options: TPdfLoadOptions);
begin
  inherited Create;
  Initialize(Log, Options);
end;

procedure TPDDocumentContext.Initialize(const Log: TPdfLog; const Options: TPdfLoadOptions);
begin
  FLog := Log;
  FOptions := Options;
  FObjects := TObjectDictionary<TObject, TObject>.Create([doOwnsValues], TIdentityComparer.Create);
end;

destructor TPDDocumentContext.Destroy;
begin
  FObjects.Free;
  inherited;
end;

function TPDDocumentContext.TryGetCachedObject(const Key: TObject; out Value: TObject): Boolean;
begin
  Result := FObjects.TryGetValue(Key, Value);
end;

procedure TPDDocumentContext.AddCachedObject(const Key: TObject; const Value: TObject);
begin
  var Existing: TObject;
  if FObjects.TryGetValue(Key, Existing) then
  begin
    if Existing = Value then
    begin
      Exit;
    end;
    raise EArgumentException.Create('The context already holds a different object for this key');
  end;
  FObjects.Add(Key, Value);
end;

end.
