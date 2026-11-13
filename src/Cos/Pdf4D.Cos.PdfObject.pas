// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSObject.java (3.0.8)
unit Pdf4D.Cos.PdfObject;

interface

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.Resolver.Interfaces;

type
  // An indirect reference. The document owns the instance (through its object pool); the instance owns the
  // loaded content. Arrays and dictionaries only point to it and never free it, so a reference cycle cannot
  // loop in a destructor.
  TCosObject = class(TCosBase)
  private
    FKey: TCosObjectKey;
    FResolver: ICosObjectResolver;
    FObject: TCosBase;
    FLoading: Boolean;
    FCycleGuard: TCosNull;

    function LoadFromResolver: TCosBase;
    function CycleGuard: TCosBase;

  public
    constructor Create(const Key: TCosObjectKey; const Resolver: ICosObjectResolver);
    destructor Destroy; override;

    // Loads on first use through the resolver and caches the result. Never nil: a failed load is a TCosNull.
    function GetObject: TCosBase;

    // Hands over loaded content, for a parser that has the object at hand. A previous content is freed.
    procedure SetObject(const Value: TCosBase);

    function IsLoaded: Boolean;
    function IsObjectNull: Boolean;

    property Key: TCosObjectKey read FKey;
  end;

implementation

{ TCosObject }

constructor TCosObject.Create(const Key: TCosObjectKey; const Resolver: ICosObjectResolver);
begin
  inherited Create;
  FKey := Key;
  FResolver := Resolver;
end;

destructor TCosObject.Destroy;
begin
  FObject.Free;
  FCycleGuard.Free;
  FResolver := nil;
  inherited;
end;

function TCosObject.GetObject: TCosBase;
begin
  if Assigned(FObject) then
  begin
    Exit(FObject);
  end;

  // The object is being loaded and its content refers to itself
  if FLoading then
  begin
    Exit(CycleGuard);
  end;

  FLoading := True;
  try
    FObject := LoadFromResolver;
  finally
    FLoading := False;
  end;
  Result := FObject;
end;

procedure TCosObject.SetObject(const Value: TCosBase);
begin
  if Value = FObject then
  begin
    Exit;
  end;

  const Previous = FObject;
  if Assigned(Value) then
  begin
    FObject := Value;
  end
  else
  begin
    FObject := TCosNull.Create;
  end;
  Previous.Free;
end;

function TCosObject.IsLoaded: Boolean;
begin
  Result := Assigned(FObject);
end;

function TCosObject.IsObjectNull: Boolean;
begin
  Result := (GetObject is TCosNull);
end;

function TCosObject.LoadFromResolver: TCosBase;
begin
  Result := nil;
  if Assigned(FResolver) then
  begin
    Result := FResolver.ResolveObject(FKey);
  end;

  if not Assigned(Result) then
  begin
    Result := TCosNull.Create;
  end;
end;

function TCosObject.CycleGuard: TCosBase;
begin
  if not Assigned(FCycleGuard) then
  begin
    FCycleGuard := TCosNull.Create;
  end;
  Result := FCycleGuard;
end;

end.
