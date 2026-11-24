// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RestrictedDocument;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils;

type
  // A document that the viewer tests share for the permission rules
  TRestrictedDocument = class
  public
    // The first page of the invoice, protected so that the user may neither print nor copy; the content is not encrypted
    class function Build: TBytes; static;
  end;

implementation

uses
  System.Hash,
  Pdf4D.Crypto.RC4,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Model.Tests.Support;

class function TRestrictedDocument.Build: TBytes;
const
  PasswordPadding: array[0..31] of Byte = ($28, $BF, $4E, $5E, $4E, $75, $8A, $41, $64, $00, $4E, $56, $FF, $FA, $01, $08,
                                           $2E, $2E, $00, $B6, $D0, $68, $3E, $80, $2F, $0C, $A9, $FE, $64, $53, $69, $7A);
  // Bits 3 (print) and 5 (copy) are cleared from the default of all permissions
  Permissions = -24;
  KeyLength = 16;
  AdditionalKeyRounds = 50;
  AdditionalUserRounds = 19;
  OwnerEntry = $11;
  DocumentIdByte = $42;
  PageContent = 'BT /F1 12 Tf 100 700 Td (Factuur 2024-0815) Tj 0 -20 Td (Nummer: 2024-0815) Tj ET';

  function Md5Of(const Data: TBytes): TBytes;
  begin
    const Hash = THashMD5.Create;
    Hash.Update(Data);
    Result := Hash.HashAsBytes;
  end;

  function ToHex(const Data: TBytes): string;
  begin
    Result := '';
    for var Value in Data do
    begin
      Result := Result + IntToHex(Value, 2);
    end;
  end;

begin
  var Padding: TBytes;
  SetLength(Padding, Length(PasswordPadding));
  Move(PasswordPadding[0], Padding[0], Length(PasswordPadding));

  var OwnerKey: TBytes;
  SetLength(OwnerKey, 32);
  FillChar(OwnerKey[0], Length(OwnerKey), OwnerEntry);

  var DocumentId: TBytes;
  SetLength(DocumentId, 16);
  FillChar(DocumentId[0], Length(DocumentId), DocumentIdByte);

  // Algorithm 2 of ISO 32000-1 for an empty user password, revision 4
  var Permission := Permissions;
  var PermissionBytes: TBytes;
  SetLength(PermissionBytes, SizeOf(Permission));
  Move(Permission, PermissionBytes[0], SizeOf(Permission));
  var Key := Md5Of(Padding + OwnerKey + PermissionBytes + DocumentId);
  for var Pass := 1 to AdditionalKeyRounds do
  begin
    Key := Md5Of(Copy(Key, 0, KeyLength));
  end;
  Key := Copy(Key, 0, KeyLength);

  // Algorithm 5: the user entry
  var UserEntry := TRC4Cipher.Process(Key, Md5Of(Padding + DocumentId));
  for var Pass := 1 to AdditionalUserRounds do
  begin
    var RoundKey := Copy(Key, 0, Length(Key));
    for var Index := 0 to High(RoundKey) do
    begin
      RoundKey[Index] := RoundKey[Index] xor Byte(Pass);
    end;
    UserEntry := TRC4Cipher.Process(RoundKey, UserEntry);
  end;
  SetLength(UserEntry, 32);

  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 10 0 R >> >> >>');
    Builder.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(PageContent));
    Builder.AddObject(10, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    Builder.AddObject(20, Format('<< /Filter /Standard /V 4 /R 4 /Length 128 /CF << /StdCF << /CFM /AESV2 /AuthEvent /DocOpen /Length 16 >> >> ' +
                                 '/StmF /Identity /StrF /Identity /O <%s> /U <%s> /P %d >>', [ToHex(OwnerKey), ToHex(UserEntry), Permissions]));
    Builder.TrailerExtra := Format('/Encrypt 20 0 R /ID [<%s> <%s>]', [ToHex(DocumentId), ToHex(DocumentId)]);
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

end.
