// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/CFFCharset.java, CFFCharsetType1.java, CFFISOAdobeCharset.java,
// CFFExpertCharset.java and CFFExpertSubsetCharset.java (3.0.8)
unit Pdf4D.FontBox.Cff.Charset;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.SharedInstance;

type
  // Maps glyph ids to SIDs (or CIDs) and glyph names. A charset made by the parser is owned by its font. The predefined
  // ones are shared and never change after they are made.
  TCFFCharset = class abstract
  public
    function IsCIDFont: Boolean; virtual; abstract;
    procedure AddSID(const GID, SID: Integer; const Name: string); virtual; abstract;
    procedure AddCID(const GID, CID: Integer); virtual; abstract;
    // 0 (.notdef) for a GID that is not in the charset
    function GetSIDForGID(const GID: Integer): Integer; virtual; abstract;
    // 0 (.notdef) for an SID that is not in the charset
    function GetGIDForSID(const SID: Integer): Integer; virtual; abstract;
    function GetGIDForCID(const CID: Integer): Integer; virtual; abstract;
    // 0 (.notdef) for a name that is not in the charset
    function GetSID(const Name: string): Integer; virtual; abstract;
    function TryGetNameForGID(const GID: Integer; out Name: string): Boolean; virtual; abstract;
    function GetCIDForGID(const GID: Integer): Integer; virtual; abstract;

    // Raises EPdfParseException when the GID is not in the charset
    function GetNameForGID(const GID: Integer): string;
  end;

  // The charset of a Type 1-equivalent font. The CID methods raise EInvalidOpException.
  TCFFCharsetType1 = class(TCFFCharset)
  private
    FSIDToGID: TDictionary<Integer, Integer>;
    FGIDToSID: TDictionary<Integer, Integer>;
    FNameToSID: TDictionary<string, Integer>;
    FGIDToName: TDictionary<Integer, string>;

  protected
    // Adds the standard strings with these SIDs as the glyphs 0, 1, 2, ...
    procedure AddStandardSIDs(const SIDs: array of Word);

  public
    constructor Create;
    destructor Destroy; override;

    function IsCIDFont: Boolean; override;
    procedure AddSID(const GID, SID: Integer; const Name: string); override;
    procedure AddCID(const GID, CID: Integer); override;
    function GetSIDForGID(const GID: Integer): Integer; override;
    function GetGIDForSID(const SID: Integer): Integer; override;
    function GetGIDForCID(const CID: Integer): Integer; override;
    function GetSID(const Name: string): Integer; override;
    function TryGetNameForGID(const GID: Integer; out Name: string): Boolean; override;
    function GetCIDForGID(const GID: Integer): Integer; override;
  end;

  // Charset id 0
  TCFFISOAdobeCharset = class(TCFFCharsetType1)
  private
    class var FShared: TPdfSharedInstance<TCFFISOAdobeCharset>;

    class destructor Destroy;

  public
    constructor Create;

    // The shared instance, which the caller does not own
    class function Instance: TCFFISOAdobeCharset; static;
  end;

  // Charset id 1
  TCFFExpertCharset = class(TCFFCharsetType1)
  private
    class var FShared: TPdfSharedInstance<TCFFExpertCharset>;

    class destructor Destroy;

  public
    constructor Create;

    // The shared instance, which the caller does not own
    class function Instance: TCFFExpertCharset; static;
  end;

  // Charset id 2
  TCFFExpertSubsetCharset = class(TCFFCharsetType1)
  private
    class var FShared: TPdfSharedInstance<TCFFExpertSubsetCharset>;

    class destructor Destroy;

  public
    constructor Create;

    // The shared instance, which the caller does not own
    class function Instance: TCFFExpertSubsetCharset; static;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.StandardStrings;

const
  NotACIDFont = 'Not a CIDFont';

  ISOAdobeSIDs: array[0..228] of Word = (
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
    31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58,
    59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86,
    87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133,
    134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155,
    156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177,
    178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199,
    200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221,
    222, 223, 224, 225, 226, 227, 228
  );

  ExpertSIDs: array[0..165] of Word = (
    0, 1, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 13, 14, 15, 99, 239, 240, 241, 242, 243, 244, 245, 246,
    247, 248, 27, 28, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 109,
    110, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287,
    288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309,
    310, 311, 312, 313, 314, 315, 316, 317, 318, 158, 155, 163, 319, 320, 321, 322, 323, 324, 325, 326, 150, 164,
    169, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347,
    348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369,
    370, 371, 372, 373, 374, 375, 376, 377, 378
  );

  ExpertSubsetSIDs: array[0..86] of Word = (
    0, 1, 231, 232, 235, 236, 237, 238, 13, 14, 15, 99, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 27, 28,
    249, 250, 251, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 109, 110, 267, 268, 269,
    270, 272, 300, 301, 302, 305, 314, 315, 158, 155, 163, 320, 321, 322, 323, 324, 325, 326, 150, 164, 169, 327,
    328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346
  );

{ TCFFCharset }

function TCFFCharset.GetNameForGID(const GID: Integer): string;
begin
  if not TryGetNameForGID(GID, Result) then
  begin
    raise EPdfParseException.CreateFmt('The charset has no glyph %d', [GID]);
  end;
end;

{ TCFFCharsetType1 }

constructor TCFFCharsetType1.Create;
begin
  inherited Create;
  FSIDToGID := TDictionary<Integer, Integer>.Create(250);
  FGIDToSID := TDictionary<Integer, Integer>.Create(250);
  FNameToSID := TDictionary<string, Integer>.Create(250);
  FGIDToName := TDictionary<Integer, string>.Create(250);
end;

destructor TCFFCharsetType1.Destroy;
begin
  FGIDToName.Free;
  FNameToSID.Free;
  FGIDToSID.Free;
  FSIDToGID.Free;
  inherited;
end;

procedure TCFFCharsetType1.AddStandardSIDs(const SIDs: array of Word);
begin
  for var GID := 0 to High(SIDs) do
  begin
    AddSID(GID, SIDs[GID], TCFFStandardString.GetName(SIDs[GID]));
  end;
end;

function TCFFCharsetType1.IsCIDFont: Boolean;
begin
  Result := False;
end;

procedure TCFFCharsetType1.AddSID(const GID, SID: Integer; const Name: string);
begin
  FSIDToGID.AddOrSetValue(SID, GID);
  FGIDToSID.AddOrSetValue(GID, SID);
  FNameToSID.AddOrSetValue(Name, SID);
  FGIDToName.AddOrSetValue(GID, Name);
end;

procedure TCFFCharsetType1.AddCID(const GID, CID: Integer);
begin
  raise EInvalidOpException.Create(NotACIDFont);
end;

function TCFFCharsetType1.GetSIDForGID(const GID: Integer): Integer;
begin
  if not FGIDToSID.TryGetValue(GID, Result) then
  begin
    Result := 0;
  end;
end;

function TCFFCharsetType1.GetGIDForSID(const SID: Integer): Integer;
begin
  if not FSIDToGID.TryGetValue(SID, Result) then
  begin
    Result := 0;
  end;
end;

function TCFFCharsetType1.GetGIDForCID(const CID: Integer): Integer;
begin
  raise EInvalidOpException.Create(NotACIDFont);
end;

function TCFFCharsetType1.GetSID(const Name: string): Integer;
begin
  if not FNameToSID.TryGetValue(Name, Result) then
  begin
    Result := 0;
  end;
end;

function TCFFCharsetType1.TryGetNameForGID(const GID: Integer; out Name: string): Boolean;
begin
  Result := FGIDToName.TryGetValue(GID, Name);
end;

function TCFFCharsetType1.GetCIDForGID(const GID: Integer): Integer;
begin
  raise EInvalidOpException.Create(NotACIDFont);
end;

{ TCFFISOAdobeCharset }

class destructor TCFFISOAdobeCharset.Destroy;
begin
  FShared.Release;
end;

class function TCFFISOAdobeCharset.Instance: TCFFISOAdobeCharset;
begin
  Result := FShared.Get(
    function: TCFFISOAdobeCharset
    begin
      Result := TCFFISOAdobeCharset.Create;
    end);
end;

constructor TCFFISOAdobeCharset.Create;
begin
  inherited Create;
  AddStandardSIDs(ISOAdobeSIDs);
end;

{ TCFFExpertCharset }

class destructor TCFFExpertCharset.Destroy;
begin
  FShared.Release;
end;

class function TCFFExpertCharset.Instance: TCFFExpertCharset;
begin
  Result := FShared.Get(
    function: TCFFExpertCharset
    begin
      Result := TCFFExpertCharset.Create;
    end);
end;

constructor TCFFExpertCharset.Create;
begin
  inherited Create;
  AddStandardSIDs(ExpertSIDs);
end;

{ TCFFExpertSubsetCharset }

class destructor TCFFExpertSubsetCharset.Destroy;
begin
  FShared.Release;
end;

class function TCFFExpertSubsetCharset.Instance: TCFFExpertSubsetCharset;
begin
  Result := FShared.Get(
    function: TCFFExpertSubsetCharset
    begin
      Result := TCFFExpertSubsetCharset.Create;
    end);
end;

constructor TCFFExpertSubsetCharset.Create;
begin
  inherited Create;
  AddStandardSIDs(ExpertSubsetSIDs);
end;

end.
