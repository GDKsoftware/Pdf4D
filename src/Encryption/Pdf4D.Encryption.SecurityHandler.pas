// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/SecurityHandler.java (3.0.8), the decrypting side
// Differences with PDFBox: the data of a stream is decrypted when it is read (TCosStream.Decryptor) and not when the stream
// is parsed, and a stream with its own Identity crypt filter is left alone as ISO 32000-1 7.6.5 says.
unit Pdf4D.Encryption.SecurityHandler;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString,
  Pdf4D.Encryption.AccessPermission,
  Pdf4D.Parser.Security.Interfaces;

type
  // The handler is not reference counted: the parser that uses it owns it, and the decryptors of the streams point to it.
  TSecurityHandler = class(TObject, ISecurityHandler)
  private
    FLog: TPdfLog;
    FKeyLength: Integer;
    FEncryptionKey: TBytes;
    FDecryptMetadata: Boolean;
    FUseAES: Boolean;
    FStreamFilterName: string;
    FStringFilterName: string;
    FCurrentAccessPermission: TPdfAccessPermission;

    class function Md5Of(const Data: TBytes): TBytes; static;
    class function ObjectKeyBytes(const Key: TCosObjectKey): TBytes; static;

    function CalcFinalKey(const Key: TCosObjectKey): TBytes;
    function DecryptBytes(const Data: TBytes; const Key: TCosObjectKey): TBytes;
    function DecryptAesWithKey(const AesKey, Data: TBytes): TBytes;
    function IsStreamExempt(const Stream: TCosStream): Boolean;
    function HasIdentityCryptFilter(const Stream: TCosStream): Boolean;
    function IsUnencryptedMetadata(const Stream: TCosStream): Boolean;
    function IsSignature(const Dictionary: TCosDictionary): Boolean;
    function TryGetTypeName(const Dictionary: TCosDictionary; out TypeName: string): Boolean;
    procedure DecryptDictionary(const Dictionary: TCosDictionary; const Key: TCosObjectKey);
    procedure DecryptEntries(const Dictionary: TCosDictionary; const Key: TCosObjectKey; const SkipContents: Boolean);
    procedure DecryptArray(const Items: TCosArray; const Key: TCosObjectKey);
    procedure DecryptValue(const Value: TCosBase; const Key: TCosObjectKey);
    procedure SetStreamDecryptor(const Stream: TCosStream; const Key: TCosObjectKey);

  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;

    procedure SetCurrentAccessPermission(const Value: TPdfAccessPermission);

    property Log: TPdfLog read FLog;
    property DecryptMetadata: Boolean read FDecryptMetadata write FDecryptMetadata;
    property StreamFilterName: string read FStreamFilterName write FStreamFilterName;
    property StringFilterName: string read FStringFilterName write FStringFilterName;

  public
    // The log is not owned and has to outlive the handler
    constructor Create(const Log: TPdfLog);
    destructor Destroy; override;

    // Port of decrypt: the strings in the object, and the objects it holds, are decrypted in place
    procedure Decrypt(const Value: TCosBase; const ObjectNumber: Int64; const Generation: Integer);

    // Port of decryptStream: the strings of the dictionary are decrypted now, the data when it is read
    procedure DecryptStream(const Stream: TCosStream; const ObjectNumber: Int64; const Generation: Integer);

    // Port of decryptString: the bytes of the string are replaced. A string that cannot be decrypted stays as it is and is logged.
    procedure DecryptString(const Value: TCosString; const Key: TCosObjectKey);

    // The decrypted data of the stream, or the data as it is for a stream that is not encrypted. Raises EPdfParseException
    // for data that cannot be decrypted.
    function DecryptStreamData(const Data: TBytes; const Key: TCosObjectKey; const Stream: TCosStream): TBytes;

    property KeyLength: Integer read FKeyLength write FKeyLength;
    property EncryptionKey: TBytes read FEncryptionKey write FEncryptionKey;
    property UseAES: Boolean read FUseAES write FUseAES;
    // Owned by the handler. Nil before the password is checked.
    property CurrentAccessPermission: TPdfAccessPermission read FCurrentAccessPermission;
  end;

implementation

uses
  System.Hash,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Crypto.AES,
  Pdf4D.Crypto.RC4;

const
  DefaultKeyLength = 40;
  AesBlockSize = 16;
  Aes256KeyBytes = 32;
  MaxPerObjectKeyBytes = 16;
  ObjectKeyExtraBytes = 5;
  ByteMask = $FF;
  BitsPerByte = 8;
  GenerationByteCount = 2;
  ObjectNumberByteCount = 3;
  XpacketLength = 10;
  AesSalt: array[0..3] of Byte = ($73, $41, $6C, $54);
  XpacketStart: array[0..9] of Byte = (Ord('<'), Ord('?'), Ord('x'), Ord('p'), Ord('a'), Ord('c'), Ord('k'), Ord('e'), Ord('t'), Ord(' '));

{ TSecurityHandler }

constructor TSecurityHandler.Create(const Log: TPdfLog);
begin
  inherited Create;
  FLog := Log;
  FKeyLength := DefaultKeyLength;
end;

destructor TSecurityHandler.Destroy;
begin
  FCurrentAccessPermission.Free;
  inherited;
end;

function TSecurityHandler.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
  begin
    Result := 0;
  end
  else
  begin
    Result := HResult($80004002);
  end;
end;

function TSecurityHandler._AddRef: Integer;
begin
  Result := -1;
end;

function TSecurityHandler._Release: Integer;
begin
  Result := -1;
end;

procedure TSecurityHandler.SetCurrentAccessPermission(const Value: TPdfAccessPermission);
begin
  if FCurrentAccessPermission <> Value then
  begin
    FCurrentAccessPermission.Free;
    FCurrentAccessPermission := Value;
  end;
end;

class function TSecurityHandler.Md5Of(const Data: TBytes): TBytes;
begin
  var Hash := THashMD5.Create;
  Hash.Update(Data);
  Result := Hash.HashAsBytes;
end;

// The object number as three bytes and the generation as two bytes, least significant byte first
class function TSecurityHandler.ObjectKeyBytes(const Key: TCosObjectKey): TBytes;
begin
  SetLength(Result, ObjectNumberByteCount + GenerationByteCount);
  for var Position := 0 to ObjectNumberByteCount - 1 do
  begin
    Result[Position] := Byte((Key.Number shr (Position * BitsPerByte)) and ByteMask);
  end;
  for var Position := 0 to GenerationByteCount - 1 do
  begin
    Result[ObjectNumberByteCount + Position] := Byte((Int64(Key.Generation) shr (Position * BitsPerByte)) and ByteMask);
  end;
end;

// Algorithm 1 of ISO 32000-1: the key for RC4 and AES-128
function TSecurityHandler.CalcFinalKey(const Key: TCosObjectKey): TBytes;
begin
  var Material := Copy(FEncryptionKey);
  Material := Material + ObjectKeyBytes(Key);
  if FUseAES then
  begin
    for var SaltByte in AesSalt do
    begin
      Material := Material + [SaltByte];
    end;
  end;

  const Digest = Md5Of(Material);
  const FinalLength = Min(Length(FEncryptionKey) + ObjectKeyExtraBytes, MaxPerObjectKeyBytes);
  Result := Copy(Digest, 0, FinalLength);
end;

// AES with CBC and PKCS#5 padding, the initialization vector is the first block of the data
function TSecurityHandler.DecryptAesWithKey(const AesKey, Data: TBytes): TBytes;
begin
  if Length(Data) = 0 then
  begin
    Exit(nil);
  end;
  if Length(Data) < AesBlockSize then
  begin
    raise EPdfParseException.CreateFmt('AES initialization vector not fully read: only %d bytes read instead of %d', [Length(Data), AesBlockSize]);
  end;

  const InitializationVector = Copy(Data, 0, AesBlockSize);
  const Encrypted = Copy(Data, AesBlockSize, Length(Data) - AesBlockSize);
  const Cipher = TAESCipher.Create(AesKey);
  try
    var WasLenient: Boolean;
    Result := Cipher.DecryptCbc(InitializationVector, Encrypted, True, WasLenient);
    if WasLenient then
    begin
      FLog.Debug('A GeneralSecurityException occurred when decrypting some stream data');
    end;
  finally
    Cipher.Free;
  end;
end;

// Port of encryptData with decrypt true
function TSecurityHandler.DecryptBytes(const Data: TBytes; const Key: TCosObjectKey): TBytes;
begin
  try
    // Algorithm 1.A is for AES-256, algorithm 1 for RC4 and AES-128
    const IsAes256 = (FUseAES and (Length(FEncryptionKey) = Aes256KeyBytes));
    if IsAes256 then
    begin
      Result := DecryptAesWithKey(FEncryptionKey, Data);
    end
    else if FUseAES then
    begin
      const ObjectKey = CalcFinalKey(Key);
      Result := DecryptAesWithKey(ObjectKey, Data);
    end
    else
    begin
      const ObjectKey = CalcFinalKey(Key);
      Result := TRC4Cipher.Process(ObjectKey, Data);
    end;
  except
    on Failure: EArgumentException do
    begin
      raise EPdfParseException.CreateFmt('The data of object %d cannot be decrypted: %s', [Key.Number, Failure.Message]);
    end;
  end;
end;

{ strings and streams }

procedure TSecurityHandler.DecryptString(const Value: TCosString; const Key: TCosObjectKey);
begin
  // A string encrypted with the identity filter
  if FStringFilterName = TCosNames.Identity then
  begin
    Exit;
  end;

  try
    Value.Bytes := DecryptBytes(Value.Bytes, Key);
  except
    on Failure: EPdfParseException do
    begin
      FLog.Error('Failed to decrypt COSString of length %d in object %d: %s', [Length(Value.Bytes), Key.Number, Failure.Message]);
    end;
  end;
end;

function TSecurityHandler.DecryptStreamData(const Data: TBytes; const Key: TCosObjectKey; const Stream: TCosStream): TBytes;
begin
  if IsStreamExempt(Stream) then
  begin
    Exit(Data);
  end;

  try
    Result := DecryptBytes(Data, Key);
  except
    on EPdfParseException do
    begin
      FLog.Error('Failed to decrypt the data of object %d %d obj', [Key.Number, Key.Generation]);
      raise;
    end;
  end;
end;

function TSecurityHandler.TryGetTypeName(const Dictionary: TCosDictionary; out TypeName: string): Boolean;
begin
  var Value: TCosBase;
  Result := (Dictionary.TryGetDictionaryObject(TCosNames.Type_, Value) and (Value is TCosName));
  if Result then
  begin
    TypeName := TCosName(Value).Name;
  end
  else
  begin
    TypeName := '';
  end;
end;

// A stream with /Filter [/Crypt ...] and /Name /Identity (the default) in its decode parameters is not encrypted
function TSecurityHandler.HasIdentityCryptFilter(const Stream: TCosStream): Boolean;
begin
  var FilterNames: TArray<string>;
  try
    FilterNames := Stream.GetFilterNames;
  except
    on EPdfParseException do
    begin
      Exit(False);
    end;
  end;

  const StartsWithCrypt = ((Length(FilterNames) > 0) and (FilterNames[0] = TCosNames.Crypt));
  if not StartsWithCrypt then
  begin
    Exit(False);
  end;

  var Parameters: TCosBase;
  if not Stream.TryGetDictionaryObject(TCosNames.DecodeParms, Parameters) then
  begin
    Exit(True);
  end;

  if Parameters is TCosArray then
  begin
    const Items = TCosArray(Parameters);
    Parameters := nil;
    if Items.Count > 0 then
    begin
      Parameters := Items.GetObject(0);
    end;
  end;

  const HasParameters = (Parameters is TCosDictionary);
  if not HasParameters then
  begin
    Exit(True);
  end;
  Result := (TCosDictionary(Parameters).GetNameAsString(TCosNames.Name, TCosNames.Identity) = TCosNames.Identity);
end;

function TSecurityHandler.IsStreamExempt(const Stream: TCosStream): Boolean;
begin
  // A stream encrypted with the identity filter
  if FStreamFilterName = TCosNames.Identity then
  begin
    Exit(True);
  end;

  var TypeName: string;
  const HasType = TryGetTypeName(Stream, TypeName);
  const IsMetadata = (HasType and (TypeName = TCosNames.Metadata));
  if IsMetadata and (not FDecryptMetadata) then
  begin
    Exit(True);
  end;

  // The cross-reference stream shall not be encrypted
  const IsXRef = (HasType and (TypeName = TCosNames.XRef));
  if IsXRef then
  begin
    Exit(True);
  end;

  Result := HasIdentityCryptFilter(Stream);
end;

// PDFBOX-3229: the metadata is not encrypted in some files despite /EncryptMetadata missing
function TSecurityHandler.IsUnencryptedMetadata(const Stream: TCosStream): Boolean;
begin
  Result := False;
  var TypeName: string;
  const IsMetadata = (TryGetTypeName(Stream, TypeName) and (TypeName = TCosNames.Metadata));
  if not IsMetadata then
  begin
    Exit;
  end;

  const Start = Stream.ReadRawPrefix(XpacketLength);
  if Length(Start) < XpacketLength then
  begin
    FLog.Debug('Tried reading %d bytes but only %d bytes read', [XpacketLength, Length(Start)]);
    Exit;
  end;

  Result := CompareMem(@Start[0], @XpacketStart[0], XpacketLength);

  if Result then
  begin
    FLog.Warning('Metadata is not encrypted, but was expected to be');
    FLog.Warning('Read PDF specification about EncryptMetadata (default value: true)');
  end;
end;

procedure TSecurityHandler.SetStreamDecryptor(const Stream: TCosStream; const Key: TCosObjectKey);
begin
  Stream.Decryptor :=
    function(Data: TBytes): TBytes
    begin
      Result := DecryptStreamData(Data, Key, Stream);
    end;
end;

procedure TSecurityHandler.DecryptStream(const Stream: TCosStream; const ObjectNumber: Int64; const Generation: Integer);
begin
  if IsStreamExempt(Stream) or IsUnencryptedMetadata(Stream) then
  begin
    Exit;
  end;

  const Key = TCosObjectKey.Make(ObjectNumber, Generation);
  DecryptDictionary(Stream, Key);
  SetStreamDecryptor(Stream, Key);
end;

{ dictionaries and arrays }

// Port of the signature test of decryptDictionary. PDFBOX-4466: /Type is optional.
function TSecurityHandler.IsSignature(const Dictionary: TCosDictionary): Boolean;
begin
  var TypeName: string;
  if TryGetTypeName(Dictionary, TypeName) and ((TypeName = TCosNames.Sig) or (TypeName = TCosNames.DocTimeStamp)) then
  begin
    Exit(True);
  end;

  var ContentsValue: TCosBase;
  var RangeValue: TCosBase;
  const HasContentsAndRange = (Dictionary.ContainsKey(TCosNames.Contents) and Dictionary.ContainsKey(TCosNames.ByteRange));
  Result := (HasContentsAndRange and
             Dictionary.TryGetDictionaryObject(TCosNames.Contents, ContentsValue) and (ContentsValue is TCosString) and
             Dictionary.TryGetDictionaryObject(TCosNames.ByteRange, RangeValue) and (RangeValue is TCosArray));
end;

procedure TSecurityHandler.DecryptValue(const Value: TCosBase; const Key: TCosObjectKey);
begin
  // Within a dictionary or array only these kinds of objects have to be decrypted. A reference is not followed.
  if Value is TCosString then
  begin
    DecryptString(TCosString(Value), Key);
  end
  else if Value is TCosArray then
  begin
    DecryptArray(TCosArray(Value), Key);
  end
  else if Value is TCosStream then
  begin
    DecryptStream(TCosStream(Value), Key.Number, Key.Generation);
  end
  else if Value is TCosDictionary then
  begin
    DecryptDictionary(TCosDictionary(Value), Key);
  end;
end;

procedure TSecurityHandler.DecryptEntries(const Dictionary: TCosDictionary; const Key: TCosObjectKey; const SkipContents: Boolean);
begin
  for var EntryKey in Dictionary.Keys do
  begin
    // The contents of a signature is not encrypted
    const IsSkipped = (SkipContents and (EntryKey = TCosNames.Contents));
    if not IsSkipped then
    begin
      const Entry = Dictionary.GetItem(EntryKey);
      DecryptValue(Entry, Key);
    end;
  end;
end;

procedure TSecurityHandler.DecryptDictionary(const Dictionary: TCosDictionary; const Key: TCosObjectKey);
begin
  // PDFBOX-2936: avoid orphan /CF dictionaries found in US government files
  if Assigned(Dictionary.GetItem(TCosNames.CF)) then
  begin
    Exit;
  end;

  const IsSignatureDictionary = IsSignature(Dictionary);
  DecryptEntries(Dictionary, Key, IsSignatureDictionary);
end;

procedure TSecurityHandler.DecryptArray(const Items: TCosArray; const Key: TCosObjectKey);
begin
  for var Item in Items do
  begin
    DecryptValue(Item, Key);
  end;
end;

procedure TSecurityHandler.Decrypt(const Value: TCosBase; const ObjectNumber: Int64; const Generation: Integer);
begin
  if not Assigned(Value) then
  begin
    Exit;
  end;

  DecryptValue(Value, TCosObjectKey.Make(ObjectNumber, Generation));
end;

end.
