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
  // Separate caches, so that the same dictionary or stream can be the key in more than one of them
  TPDCacheScope = (General, ToUnicode, GlyphPrefix, FontHeight);

  // What the model objects of one document share: the log, the options and a cache of objects that are made from
  // dictionaries and streams of the document (fonts, for instance). The context is not thread safe, like the document.
  TPDDocumentContext = class
  private
    FCosDocument: TCosDocument;
    FLog: TPdfLog;
    FOptions: TPdfLoadOptions;
    FScopes: array[TPDCacheScope] of TObjectDictionary<TObject, TObject>;
    FToUnicodeMappings: Int64;
    FIsToUnicodeBudgetExhausted: Boolean;

    procedure Initialize(const Log: TPdfLog; const Options: TPdfLoadOptions);

  public
    // Does not own CosDocument. nil is allowed (tests): there is no log and the options are the defaults.
    constructor Create(const CosDocument: TCosDocument); overload;
    // For a model without a loaded document. Does not own Log, which may be nil.
    constructor Create(const Log: TPdfLog; const Options: TPdfLoadOptions); overload;
    destructor Destroy; override;

    // Key is the identity of a dictionary or stream. Value stays owned by the context.
    function TryGetCachedObject(const Key: TObject; out Value: TObject): Boolean; overload;
    function TryGetCachedObject(const Scope: TPDCacheScope; const Key: TObject; out Value: TObject): Boolean; overload;
    // The context becomes the owner of Value. A second value for the same Key raises EArgumentException.
    procedure AddCachedObject(const Key: TObject; const Value: TObject); overload;
    procedure AddCachedObject(const Scope: TPDCacheScope; const Key: TObject; const Value: TObject); overload;

    // The budget for the mappings of all ToUnicode CMaps of this document (Options.MaxToUnicodeMappings). A font asks
    // IsToUnicodeBudgetExhausted before it parses a ToUnicode CMap, and charges the mappings of the parsed CMap
    // afterwards. False means the CMap takes the total over the budget: the font treats it as absent. The first time
    // that happens a warning goes to the log; from then on every ToUnicode CMap of the document counts as absent.
    function IsToUnicodeBudgetExhausted: Boolean;
    function TryChargeToUnicodeMappings(const MappingCount: Integer): Boolean;

    property CosDocument: TCosDocument read FCosDocument;
    property Log: TPdfLog read FLog;
    property Options: TPdfLoadOptions read FOptions;
    // The mappings charged so far
    property ToUnicodeMappings: Int64 read FToUnicodeMappings;
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
  for var Scope := Low(TPDCacheScope) to High(TPDCacheScope) do
  begin
    FScopes[Scope] := TObjectDictionary<TObject, TObject>.Create([doOwnsValues], TIdentityComparer.Create);
  end;
end;

destructor TPDDocumentContext.Destroy;
begin
  for var Scope := Low(TPDCacheScope) to High(TPDCacheScope) do
  begin
    FScopes[Scope].Free;
  end;
  inherited;
end;

function TPDDocumentContext.TryGetCachedObject(const Key: TObject; out Value: TObject): Boolean;
begin
  Result := TryGetCachedObject(TPDCacheScope.General, Key, Value);
end;

function TPDDocumentContext.TryGetCachedObject(const Scope: TPDCacheScope; const Key: TObject; out Value: TObject): Boolean;
begin
  Result := FScopes[Scope].TryGetValue(Key, Value);
end;

function TPDDocumentContext.IsToUnicodeBudgetExhausted: Boolean;
begin
  Result := FIsToUnicodeBudgetExhausted;
end;

function TPDDocumentContext.TryChargeToUnicodeMappings(const MappingCount: Integer): Boolean;
begin
  if FIsToUnicodeBudgetExhausted then
  begin
    Exit(False);
  end;

  FToUnicodeMappings := FToUnicodeMappings + MappingCount;
  const IsOverBudget = (FToUnicodeMappings > FOptions.MaxToUnicodeMappings);
  if IsOverBudget then
  begin
    FIsToUnicodeBudgetExhausted := True;
    if Assigned(FLog) then
    begin
      FLog.Warning('The ToUnicode CMaps of this document exceed %d mappings in total; further ToUnicode CMaps are ignored',
                   [FOptions.MaxToUnicodeMappings]);
    end;
  end;
  Result := not IsOverBudget;
end;

procedure TPDDocumentContext.AddCachedObject(const Key: TObject; const Value: TObject);
begin
  AddCachedObject(TPDCacheScope.General, Key, Value);
end;

procedure TPDDocumentContext.AddCachedObject(const Scope: TPDCacheScope; const Key: TObject; const Value: TObject);
begin
  var Existing: TObject;
  if FScopes[Scope].TryGetValue(Key, Existing) then
  begin
    if Existing = Value then
    begin
      Exit;
    end;
    raise EArgumentException.Create('The context already holds a different object for this key');
  end;
  FScopes[Scope].Add(Key, Value);
end;

end.
