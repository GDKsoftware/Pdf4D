// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.FontProvider;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Provider;

type
  // A font that the test provider has read from a file. It owns the font and has read it completely, so it can be shared.
  TTestFontInfo = class(TFontInfo)
  private
    FPostScriptName: string;
    FFormat: TFontFormat;
    FFont: TFontBoxFont;
    FHasCIDSystemInfo: Boolean;
    FCIDSystemInfo: TPDCIDSystemInfo;
    FFamilyClass: Integer;
    FWeightClass: Integer;
    FCodePageRange1: Integer;
    FCodePageRange2: Integer;
    FMacStyle: Integer;
    FPanose: TBytes;

    procedure ReadTrueTypeFont(const Data: TBytes; const IsOpenType: Boolean);
    procedure ReadType1Font(const Data: TBytes);

  public
    // Reads a .ttf, .otf or .pfb file. A file that cannot be read raises.
    constructor Create(const FileName: string);
    destructor Destroy; override;

    function PostScriptName: string; override;
    function Format: TFontFormat; override;
    function TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean; override;
    function GetFont: TFontBoxFont; override;
    function FamilyClass: Integer; override;
    function WeightClass: Integer; override;
    function CodePageRange1: Integer; override;
    function CodePageRange2: Integer; override;
    function MacStyle: Integer; override;
    function TryGetPanose(out Panose: TPDPanoseClassification): Boolean; override;
  end;

  // A font provider for the tests: only the font files that it is given, and never the fonts of the machine. A name that is not
  // rooted is a file in tests/fonts.
  TTestFontProvider = class(TInterfacedObject, IPdfFontProvider)
  private
    FInfos: TObjectList<TFontInfo>;

  public
    class function Empty: IPdfFontProvider; static;

    constructor Create(const FontFiles: TArray<string>);
    destructor Destroy; override;

    function FontInfos: TArray<TFontInfo>;
    function ToDebugString: string;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.FontBox.TrueType.Tables,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Tests.TestFonts;

{ TTestFontInfo }

constructor TTestFontInfo.Create(const FileName: string);
begin
  inherited Create;
  FFamilyClass := -1;
  FWeightClass := -1;
  FMacStyle := -1;

  const Data = TFile.ReadAllBytes(FileName);
  const Extension = TPath.GetExtension(FileName).ToLowerInvariant;
  if Extension = '.pfb' then
  begin
    ReadType1Font(Data);
  end
  else
  begin
    ReadTrueTypeFont(Data, (Extension = '.otf'));
  end;
end;

destructor TTestFontInfo.Destroy;
begin
  FFont.Free;
  inherited;
end;

procedure TTestFontInfo.ReadType1Font(const Data: TBytes);
begin
  const Font = TType1Font.CreateWithPFB(Data);
  FFont := Font;
  FFormat := TFontFormat.PFB;
  FPostScriptName := Font.Name;
end;

procedure TTestFontInfo.ReadTrueTypeFont(const Data: TBytes; const IsOpenType: Boolean);
begin
  var Font: TTrueTypeFont;
  if IsOpenType then
  begin
    const Parser = TOTFParser.Create;
    try
      Font := Parser.Parse(Data);
    finally
      Parser.Free;
    end;
  end
  else
  begin
    const Parser = TTTFParser.Create;
    try
      Font := Parser.Parse(Data);
    finally
      Parser.Free;
    end;
  end;

  FFont := Font;
  FPostScriptName := Font.Name;
  FMacStyle := Font.Header.MacStyle;

  var OS2: TOS2WindowsMetricsTable;
  if Font.TryGetOS2Windows(OS2) then
  begin
    FFamilyClass := OS2.FamilyClass;
    FWeightClass := OS2.WeightClass;
    FCodePageRange1 := Integer(Cardinal(OS2.CodePageRange1 and $FFFFFFFF));
    FCodePageRange2 := Integer(Cardinal(OS2.CodePageRange2 and $FFFFFFFF));
    FPanose := Copy(OS2.Panose);
  end;

  const IsPostScript = ((Font is TOpenTypeFont) and TOpenTypeFont(Font).IsPostScript);
  if IsPostScript then
  begin
    FFormat := TFontFormat.OTF;
    const Cff = TOpenTypeFont(Font).CFF;
    if Cff is TCFFCIDFont then
    begin
      const CidFont = TCFFCIDFont(Cff);
      FHasCIDSystemInfo := True;
      FCIDSystemInfo := TPDCIDSystemInfo.Create(CidFont.Registry, CidFont.Ordering, CidFont.Supplement);
    end;
  end
  else
  begin
    FFormat := TFontFormat.TTF;
  end;
end;

function TTestFontInfo.PostScriptName: string;
begin
  Result := FPostScriptName;
end;

function TTestFontInfo.Format: TFontFormat;
begin
  Result := FFormat;
end;

function TTestFontInfo.TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean;
begin
  Info := FCIDSystemInfo;
  Result := FHasCIDSystemInfo;
end;

function TTestFontInfo.GetFont: TFontBoxFont;
begin
  Result := FFont;
end;

function TTestFontInfo.FamilyClass: Integer;
begin
  Result := FFamilyClass;
end;

function TTestFontInfo.WeightClass: Integer;
begin
  Result := FWeightClass;
end;

function TTestFontInfo.CodePageRange1: Integer;
begin
  Result := FCodePageRange1;
end;

function TTestFontInfo.CodePageRange2: Integer;
begin
  Result := FCodePageRange2;
end;

function TTestFontInfo.MacStyle: Integer;
begin
  Result := FMacStyle;
end;

function TTestFontInfo.TryGetPanose(out Panose: TPDPanoseClassification): Boolean;
begin
  Panose.Bytes := Copy(FPanose);
  Result := (Length(FPanose) >= TPDPanoseClassification.Length);
end;

{ TTestFontProvider }

class function TTestFontProvider.Empty: IPdfFontProvider;
begin
  Result := TTestFontProvider.Create(nil);
end;

constructor TTestFontProvider.Create(const FontFiles: TArray<string>);
begin
  inherited Create;
  FInfos := TObjectList<TFontInfo>.Create(True);
  for var FontFile in FontFiles do
  begin
    var FullPath := FontFile;
    if not TPath.IsPathRooted(FontFile) then
    begin
      FullPath := TTestFonts.Path(FontFile);
    end;
    FInfos.Add(TTestFontInfo.Create(FullPath));
  end;
end;

destructor TTestFontProvider.Destroy;
begin
  FInfos.Free;
  inherited;
end;

function TTestFontProvider.FontInfos: TArray<TFontInfo>;
begin
  Result := FInfos.ToArray;
end;

function TTestFontProvider.ToDebugString: string;
begin
  const Lines = TStringBuilder.Create;
  try
    for var Info in FInfos do
    begin
      Lines.AppendLine(Info.ToString);
    end;
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

end.
