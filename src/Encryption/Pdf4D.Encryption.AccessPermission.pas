// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/AccessPermission.java (3.0.8)
unit Pdf4D.Encryption.AccessPermission;

interface

uses
  System.SysUtils;

type
  // The permissions of the current user of a document, as bits of the /P entry of the encryption dictionary
  TPdfAccessPermission = class
  private
    FPermissions: Integer;
    FReadOnly: Boolean;

    function IsPermissionBitOn(const Bit: Integer): Boolean;
    procedure SetPermissionBit(const Bit: Integer; const Value: Boolean);
    procedure ChangeBit(const Bit: Integer; const Value: Boolean);

  public
    // All permissions, bits 0 and 1 are zero as the standard demands
    constructor Create; overload;
    constructor Create(const P: Integer); overload;

    // Port of the byte[] constructor: the four bytes are the permissions, most significant byte first
    class function FromBytes(const Bytes: TArray<Byte>): TPdfAccessPermission; static;

    // Port of getOwnerAccessPermission: a new instance that the caller owns
    class function GetOwnerAccessPermission: TPdfAccessPermission; static;

    // A copy, with the same read only state
    function Clone: TPdfAccessPermission;

    function IsOwnerPermission: Boolean;

    function CanPrint: Boolean;
    function CanModify: Boolean;
    function CanExtractContent: Boolean;
    function CanModifyAnnotations: Boolean;
    function CanFillInForm: Boolean;
    function CanExtractForAccessibility: Boolean;
    function CanAssembleDocument: Boolean;
    function CanPrintFaithful: Boolean;

    // The setters do nothing once the instance is read only, like in PDFBox
    procedure SetCanPrint(const Value: Boolean);
    procedure SetCanModify(const Value: Boolean);
    procedure SetCanExtractContent(const Value: Boolean);
    procedure SetCanModifyAnnotations(const Value: Boolean);
    procedure SetCanFillInForm(const Value: Boolean);
    procedure SetCanExtractForAccessibility(const Value: Boolean);
    procedure SetCanAssembleDocument(const Value: Boolean);
    procedure SetCanPrintFaithful(const Value: Boolean);

    procedure SetReadOnly;

    property PermissionBytes: Integer read FPermissions;
    property IsReadOnly: Boolean read FReadOnly;
  end;

implementation

const
  DefaultPermissions: Integer = not 3;
  PrintBit = 3;
  ModificationBit = 4;
  ExtractBit = 5;
  ModifyAnnotationsBit = 6;
  FillInFormBit = 9;
  ExtractForAccessibilityBit = 10;
  AssembleDocumentBit = 11;
  FaithfulPrintBit = 12;
  BytesInPermissions = 4;
  BitsInByte = 8;

{ TPdfAccessPermission }

constructor TPdfAccessPermission.Create;
begin
  inherited Create;
  FPermissions := DefaultPermissions;
end;

constructor TPdfAccessPermission.Create(const P: Integer);
begin
  inherited Create;
  FPermissions := P;
end;

class function TPdfAccessPermission.FromBytes(const Bytes: TArray<Byte>): TPdfAccessPermission;
begin
  if Length(Bytes) < BytesInPermissions then
  begin
    raise EArgumentException.CreateFmt('Permissions need %d bytes, got %d', [BytesInPermissions, Length(Bytes)]);
  end;

  var Combined: Cardinal := 0;
  for var Position := 0 to BytesInPermissions - 1 do
  begin
    Combined := (Combined shl BitsInByte) or Bytes[Position];
  end;
  Result := TPdfAccessPermission.Create(Integer(Combined));
end;

class function TPdfAccessPermission.GetOwnerAccessPermission: TPdfAccessPermission;
begin
  Result := TPdfAccessPermission.Create;
  Result.SetCanAssembleDocument(True);
  Result.SetCanExtractContent(True);
  Result.SetCanExtractForAccessibility(True);
  Result.SetCanFillInForm(True);
  Result.SetCanModify(True);
  Result.SetCanModifyAnnotations(True);
  Result.SetCanPrint(True);
  Result.SetCanPrintFaithful(True);
end;

function TPdfAccessPermission.Clone: TPdfAccessPermission;
begin
  Result := TPdfAccessPermission.Create(FPermissions);
  Result.FReadOnly := FReadOnly;
end;

function TPdfAccessPermission.IsPermissionBitOn(const Bit: Integer): Boolean;
begin
  Result := ((FPermissions and (1 shl (Bit - 1))) <> 0);
end;

procedure TPdfAccessPermission.ChangeBit(const Bit: Integer; const Value: Boolean);
begin
  if Value then
  begin
    FPermissions := FPermissions or (1 shl (Bit - 1));
  end
  else
  begin
    FPermissions := FPermissions and (not (1 shl (Bit - 1)));
  end;
end;

procedure TPdfAccessPermission.SetPermissionBit(const Bit: Integer; const Value: Boolean);
begin
  if not FReadOnly then
  begin
    ChangeBit(Bit, Value);
  end;
end;

function TPdfAccessPermission.IsOwnerPermission: Boolean;
begin
  Result := (CanAssembleDocument and
             CanExtractContent and
             CanExtractForAccessibility and
             CanFillInForm and
             CanModify and
             CanModifyAnnotations and
             CanPrint and
             CanPrintFaithful);
end;

function TPdfAccessPermission.CanPrint: Boolean;
begin
  Result := IsPermissionBitOn(PrintBit);
end;

function TPdfAccessPermission.CanModify: Boolean;
begin
  Result := IsPermissionBitOn(ModificationBit);
end;

function TPdfAccessPermission.CanExtractContent: Boolean;
begin
  Result := IsPermissionBitOn(ExtractBit);
end;

function TPdfAccessPermission.CanModifyAnnotations: Boolean;
begin
  Result := IsPermissionBitOn(ModifyAnnotationsBit);
end;

function TPdfAccessPermission.CanFillInForm: Boolean;
begin
  Result := IsPermissionBitOn(FillInFormBit);
end;

function TPdfAccessPermission.CanExtractForAccessibility: Boolean;
begin
  Result := IsPermissionBitOn(ExtractForAccessibilityBit);
end;

function TPdfAccessPermission.CanAssembleDocument: Boolean;
begin
  Result := IsPermissionBitOn(AssembleDocumentBit);
end;

function TPdfAccessPermission.CanPrintFaithful: Boolean;
begin
  Result := IsPermissionBitOn(FaithfulPrintBit);
end;

procedure TPdfAccessPermission.SetCanPrint(const Value: Boolean);
begin
  SetPermissionBit(PrintBit, Value);
end;

procedure TPdfAccessPermission.SetCanModify(const Value: Boolean);
begin
  SetPermissionBit(ModificationBit, Value);
end;

procedure TPdfAccessPermission.SetCanExtractContent(const Value: Boolean);
begin
  SetPermissionBit(ExtractBit, Value);
end;

procedure TPdfAccessPermission.SetCanModifyAnnotations(const Value: Boolean);
begin
  SetPermissionBit(ModifyAnnotationsBit, Value);
end;

procedure TPdfAccessPermission.SetCanFillInForm(const Value: Boolean);
begin
  SetPermissionBit(FillInFormBit, Value);
end;

procedure TPdfAccessPermission.SetCanExtractForAccessibility(const Value: Boolean);
begin
  SetPermissionBit(ExtractForAccessibilityBit, Value);
end;

procedure TPdfAccessPermission.SetCanAssembleDocument(const Value: Boolean);
begin
  SetPermissionBit(AssembleDocumentBit, Value);
end;

procedure TPdfAccessPermission.SetCanPrintFaithful(const Value: Boolean);
begin
  SetPermissionBit(FaithfulPrintBit, Value);
end;

procedure TPdfAccessPermission.SetReadOnly;
begin
  FReadOnly := True;
end;

end.
