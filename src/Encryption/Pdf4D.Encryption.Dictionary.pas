// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/PDEncryption.java and PDCryptFilterDictionary.java (3.0.8)
// Only the read side is ported: the library does not write encrypted files.
unit Pdf4D.Encryption.Dictionary;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary;

type
  // A view on an entry of /CF in an encryption dictionary. The dictionary belongs to the document.
  TPdfCryptFilterDictionary = class
  private
    FDictionary: TCosDictionary;

  public
    constructor Create(const Dictionary: TCosDictionary);

    function GetLength: Integer;
    // The name of /CFM, False without one
    function TryGetCryptFilterMethod(out Method: string): Boolean;
    function IsEncryptMetaData: Boolean;

    property Dictionary: TCosDictionary read FDictionary;
  end;

  // A view on the encryption dictionary that the trailer points to. The dictionary belongs to the document, which has to
  // outlive this object.
  TPdfEncryption = class
  private
    FDictionary: TCosDictionary;

    function TryGetStringBytes(const Key: string; out Bytes: TBytes): Boolean;
    function TryGetPaddedStringBytes(const Key: string; const LengthUpToRevision4, LengthRevision5And6: Integer; out Bytes: TBytes): Boolean;
    function TryGetNameValue(const Key: string; out Name: string): Boolean;
    function GetFilterNameOrIdentity(const Key: string): string;

  public
    constructor Create(const Dictionary: TCosDictionary);

    // False when there is no /Filter, as PDFBox gives null then
    function TryGetFilter(out Filter: string): Boolean;
    function TryGetSubFilter(out SubFilter: string): Boolean;

    function GetVersion: Integer;
    function GetLength: Integer;
    function GetRevision: Integer;
    function GetPermissions: Integer;
    function IsEncryptMetaData: Boolean;

    // The owner and user entries, cut or filled with zeros to 32 bytes (revision 4 or lower) or 48 bytes (revision 5 and 6),
    // like PDFBox. False when the entry is missing. A value that is not a string raises EPdfParseException.
    function TryGetOwnerKey(out Bytes: TBytes): Boolean;
    function TryGetUserKey(out Bytes: TBytes): Boolean;
    // The /OE and /UE entries, cut or filled to 32 bytes
    function TryGetOwnerEncryptionKey(out Bytes: TBytes): Boolean;
    function TryGetUserEncryptionKey(out Bytes: TBytes): Boolean;
    function TryGetPerms(out Bytes: TBytes): Boolean;

    // The caller owns the result
    function TryGetStdCryptFilterDictionary(out Filter: TPdfCryptFilterDictionary): Boolean;
    function TryGetDefaultCryptFilterDictionary(out Filter: TPdfCryptFilterDictionary): Boolean;
    function TryGetCryptFilterDictionary(const CryptFilterName: string; out Filter: TPdfCryptFilterDictionary): Boolean;

    // /StmF and /StrF, Identity without them
    function GetStreamFilterName: string;
    function GetStringFilterName: string;

    property Dictionary: TCosDictionary read FDictionary;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfString;

const
  DefaultLength = 40;
  DefaultVersion = 0;
  OwnerUserLengthUpToRevision4 = 32;
  OwnerUserLengthRevision5And6 = 48;
  EncryptionKeyLength = 32;
  Revision4 = 4;
  Revision5 = 5;
  Revision6 = 6;

{ TPdfCryptFilterDictionary }

constructor TPdfCryptFilterDictionary.Create(const Dictionary: TCosDictionary);
begin
  inherited Create;
  FDictionary := Dictionary;
end;

function TPdfCryptFilterDictionary.GetLength: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.Length, DefaultLength);
end;

function TPdfCryptFilterDictionary.TryGetCryptFilterMethod(out Method: string): Boolean;
begin
  var Value: TCosBase;
  Result := (FDictionary.TryGetDictionaryObject(TCosNames.CFM, Value) and (Value is TCosName));
  if Result then
  begin
    Method := TCosName(Value).Name;
  end
  else
  begin
    Method := '';
  end;
end;

function TPdfCryptFilterDictionary.IsEncryptMetaData: Boolean;
begin
  Result := FDictionary.GetBoolean(TCosNames.EncryptMetadata, True);
end;

{ TPdfEncryption }

constructor TPdfEncryption.Create(const Dictionary: TCosDictionary);
begin
  inherited Create;
  FDictionary := Dictionary;
end;

function TPdfEncryption.TryGetNameValue(const Key: string; out Name: string): Boolean;
begin
  var Value: TCosBase;
  Result := (FDictionary.TryGetDictionaryObject(Key, Value) and (Value is TCosName));
  if Result then
  begin
    Name := TCosName(Value).Name;
  end
  else
  begin
    Name := '';
  end;
end;

function TPdfEncryption.GetFilterNameOrIdentity(const Key: string): string;
begin
  if not TryGetNameValue(Key, Result) then
  begin
    Result := TCosNames.Identity;
  end;
end;

function TPdfEncryption.TryGetFilter(out Filter: string): Boolean;
begin
  Filter := FDictionary.GetNameAsString(TCosNames.Filter, '');
  Result := (Filter <> '');
end;

function TPdfEncryption.TryGetSubFilter(out SubFilter: string): Boolean;
begin
  SubFilter := FDictionary.GetNameAsString(TCosNames.SubFilter, '');
  Result := (SubFilter <> '');
end;

function TPdfEncryption.GetVersion: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.V, DefaultVersion);
end;

function TPdfEncryption.GetLength: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.Length, DefaultLength);
end;

function TPdfEncryption.GetRevision: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.R, DefaultVersion);
end;

function TPdfEncryption.GetPermissions: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.P, 0);
end;

// The default is true, see 7.6.3.2 Standard Encryption Dictionary of ISO 32000-1
function TPdfEncryption.IsEncryptMetaData: Boolean;
begin
  Result := FDictionary.GetBoolean(TCosNames.EncryptMetadata, True);
end;

function TPdfEncryption.TryGetStringBytes(const Key: string; out Bytes: TBytes): Boolean;
begin
  Bytes := nil;
  var Value: TCosBase;
  Result := FDictionary.TryGetDictionaryObject(Key, Value);
  if not Result then
  begin
    Exit;
  end;

  // PDFBox casts here and fails with a ClassCastException
  if not (Value is TCosString) then
  begin
    raise EPdfParseException.CreateFmt('The /%s entry of the encryption dictionary is not a string', [Key]);
  end;
  Bytes := Copy(TCosString(Value).Bytes);
end;

// Arrays.copyOf: cut, or filled with zeros
function TPdfEncryption.TryGetPaddedStringBytes(const Key: string; const LengthUpToRevision4, LengthRevision5And6: Integer; out Bytes: TBytes): Boolean;
begin
  Result := TryGetStringBytes(Key, Bytes);
  if not Result then
  begin
    Exit;
  end;

  const Revision = GetRevision;
  if Revision <= Revision4 then
  begin
    SetLength(Bytes, LengthUpToRevision4);
  end
  else if (Revision = Revision5) or (Revision = Revision6) then
  begin
    SetLength(Bytes, LengthRevision5And6);
  end;
end;

function TPdfEncryption.TryGetOwnerKey(out Bytes: TBytes): Boolean;
begin
  Result := TryGetPaddedStringBytes(TCosNames.O, OwnerUserLengthUpToRevision4, OwnerUserLengthRevision5And6, Bytes);
end;

function TPdfEncryption.TryGetUserKey(out Bytes: TBytes): Boolean;
begin
  Result := TryGetPaddedStringBytes(TCosNames.U, OwnerUserLengthUpToRevision4, OwnerUserLengthRevision5And6, Bytes);
end;

function TPdfEncryption.TryGetOwnerEncryptionKey(out Bytes: TBytes): Boolean;
begin
  Result := TryGetStringBytes(TCosNames.OE, Bytes);
  if Result then
  begin
    SetLength(Bytes, EncryptionKeyLength);
  end;
end;

function TPdfEncryption.TryGetUserEncryptionKey(out Bytes: TBytes): Boolean;
begin
  Result := TryGetStringBytes(TCosNames.UE, Bytes);
  if Result then
  begin
    SetLength(Bytes, EncryptionKeyLength);
  end;
end;

function TPdfEncryption.TryGetPerms(out Bytes: TBytes): Boolean;
begin
  Result := TryGetStringBytes(TCosNames.Perms, Bytes);
end;

function TPdfEncryption.TryGetCryptFilterDictionary(const CryptFilterName: string; out Filter: TPdfCryptFilterDictionary): Boolean;
begin
  Filter := nil;
  // See CF in Table 20 of ISO 32000-1: entries common to all encryption dictionaries
  var FilterDictionaries: TCosDictionary;
  var CryptDictionary: TCosDictionary;
  Result := (FDictionary.TryGetCosDictionary(TCosNames.CF, FilterDictionaries) and
             FilterDictionaries.TryGetCosDictionary(CryptFilterName, CryptDictionary));
  if Result then
  begin
    Filter := TPdfCryptFilterDictionary.Create(CryptDictionary);
  end;
end;

function TPdfEncryption.TryGetStdCryptFilterDictionary(out Filter: TPdfCryptFilterDictionary): Boolean;
begin
  Result := TryGetCryptFilterDictionary(TCosNames.StdCF, Filter);
end;

function TPdfEncryption.TryGetDefaultCryptFilterDictionary(out Filter: TPdfCryptFilterDictionary): Boolean;
begin
  Result := TryGetCryptFilterDictionary(TCosNames.DefaultCryptFilter, Filter);
end;

function TPdfEncryption.GetStreamFilterName: string;
begin
  Result := GetFilterNameOrIdentity(TCosNames.StmF);
end;

function TPdfEncryption.GetStringFilterName: string;
begin
  Result := GetFilterNameOrIdentity(TCosNames.StrF);
end;

end.
