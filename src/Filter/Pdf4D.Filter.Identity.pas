// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/IdentityFilter.java and CryptFilter.java (3.0.8)
unit Pdf4D.Filter.Identity;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Filter.Base;

type
  TIdentityFilter = class(TPdfFilter)
  public
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); override;
  end;

  // Only the identity crypt filter passes data through. The data of a stream with another crypt filter was
  // decrypted when it was read, by the security handler.
  TCryptFilter = class(TIdentityFilter)
  public
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); override;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names;

{ TIdentityFilter }

procedure TIdentityFilter.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer);
begin
  Output.CopyFrom(Input, 0);
end;

{ TCryptFilter }

procedure TCryptFilter.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer);
begin
  // Like PDFBox, the name is read from the dictionary of the stream
  const EncryptionName = Parameters.GetNameAsString(TCosNames.Name, TCosNames.Identity);
  if EncryptionName <> TCosNames.Identity then
  begin
    raise EPdfUnsupportedFeatureException.CreateFmt('Unsupported crypt filter %s', [EncryptionName]);
  end;

  inherited;
end;

end.
