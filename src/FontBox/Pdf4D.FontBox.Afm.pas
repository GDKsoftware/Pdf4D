// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/afm/FontMetrics.java, CharMetric.java, KernPair.java, Ligature.java,
// TrackKern.java, Composite.java and CompositePart.java (3.0.8)
unit Pdf4D.FontBox.Afm;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.FontBox.BoundingBox;

type
  TLigature = record
    Successor: string;
    Ligature: string;

    class function Create(const Successor, Ligature: string): TLigature; static;
  end;

  TKernPair = record
    FirstKernCharacter: string;
    SecondKernCharacter: string;
    X: Single;
    Y: Single;

    class function Create(const FirstKernCharacter, SecondKernCharacter: string; const X, Y: Single): TKernPair; static;
  end;

  TTrackKern = record
    Degree: Integer;
    MinPointSize: Single;
    MinKern: Single;
    MaxPointSize: Single;
    MaxKern: Single;

    class function Create(const Degree: Integer; const MinPointSize, MinKern, MaxPointSize, MaxKern: Single): TTrackKern; static;
  end;

  TCompositePart = record
    Name: string;
    XDisplacement: Integer;
    YDisplacement: Integer;

    class function Create(const Name: string; const XDisplacement, YDisplacement: Integer): TCompositePart; static;
  end;

  TComposite = class
  private
    FName: string;
    FParts: TList<TCompositePart>;

  public
    constructor Create(const Name: string);
    destructor Destroy; override;

    procedure AddPart(const Part: TCompositePart);

    property Name: string read FName;
    property Parts: TList<TCompositePart> read FParts;
  end;

  // The two-element arrays (W, W0, W1, Vv) are empty when the AFM file does not give them.
  TCharMetric = class
  private
    FCharacterCode: Integer;
    FWx: Single;
    FW0x: Single;
    FW1x: Single;
    FWy: Single;
    FW0y: Single;
    FW1y: Single;
    FW: TArray<Single>;
    FW0: TArray<Single>;
    FW1: TArray<Single>;
    FVv: TArray<Single>;
    FName: string;
    FHasBoundingBox: Boolean;
    FBoundingBox: TBoundingBox;
    FLigatures: TList<TLigature>;

    procedure SetBoundingBox(const Value: TBoundingBox);

  public
    constructor Create;
    destructor Destroy; override;

    procedure AddLigature(const Ligature: TLigature);

    property CharacterCode: Integer read FCharacterCode write FCharacterCode;
    property Wx: Single read FWx write FWx;
    property W0x: Single read FW0x write FW0x;
    property W1x: Single read FW1x write FW1x;
    property Wy: Single read FWy write FWy;
    property W0y: Single read FW0y write FW0y;
    property W1y: Single read FW1y write FW1y;
    property W: TArray<Single> read FW write FW;
    property W0: TArray<Single> read FW0 write FW0;
    property W1: TArray<Single> read FW1 write FW1;
    property Vv: TArray<Single> read FVv write FVv;
    property Name: string read FName write FName;
    property HasBoundingBox: Boolean read FHasBoundingBox;
    property BoundingBox: TBoundingBox read FBoundingBox write SetBoundingBox;
    property Ligatures: TList<TLigature> read FLigatures;
  end;

  // The metrics of one font. The lists belong to the object; after a parser has returned it, the object is not changed
  // any more, so it can be shared between threads.
  TFontMetrics = class
  private
    FAFMVersion: Single;
    FMetricSets: Integer;
    FFontName: string;
    FFullName: string;
    FFamilyName: string;
    FWeight: string;
    FHasFontBBox: Boolean;
    FFontBBox: TBoundingBox;
    FFontVersion: string;
    FNotice: string;
    FEncodingScheme: string;
    FMappingScheme: Integer;
    FEscChar: Integer;
    FCharacterSet: string;
    FCharacters: Integer;
    FIsBaseFont: Boolean;
    FVVector: TArray<Single>;
    FIsFixedVSet: Boolean;
    FIsFixedV: Boolean;
    FCapHeight: Single;
    FXHeight: Single;
    FAscender: Single;
    FDescender: Single;
    FComments: TList<string>;
    FUnderlinePosition: Single;
    FUnderlineThickness: Single;
    FItalicAngle: Single;
    FCharWidth: TArray<Single>;
    FIsFixedPitch: Boolean;
    FStandardHorizontalWidth: Single;
    FStandardVerticalWidth: Single;
    FCharMetrics: TObjectList<TCharMetric>;
    FCharMetricsMap: TDictionary<string, TCharMetric>;
    FTrackKern: TList<TTrackKern>;
    FComposites: TObjectList<TComposite>;
    FKernPairs: TList<TKernPair>;
    FKernPairs0: TList<TKernPair>;
    FKernPairs1: TList<TKernPair>;

    procedure SetMetricSets(const Value: Integer);
    procedure SetFontBBox(const Value: TBoundingBox);
    function GetIsFixedV: Boolean;
    procedure SetIsFixedV(const Value: Boolean);

  public
    constructor Create;
    destructor Destroy; override;

    // The advance width of the glyph, or 0 when there is no glyph of that name
    function GetCharacterWidth(const Name: string): Single;
    function GetCharacterHeight(const Name: string): Single;
    function GetAverageCharacterWidth: Single;

    procedure AddComment(const Comment: string);
    // The metric becomes property of this object
    procedure AddCharMetric(const Metric: TCharMetric);
    procedure AddTrackKern(const Kern: TTrackKern);
    // The composite becomes property of this object
    procedure AddComposite(const Composite: TComposite);
    procedure AddKernPair(const KernPair: TKernPair);
    procedure AddKernPair0(const KernPair: TKernPair);
    procedure AddKernPair1(const KernPair: TKernPair);

    property AFMVersion: Single read FAFMVersion write FAFMVersion;
    // 0, 1 or 2
    property MetricSets: Integer read FMetricSets write SetMetricSets;
    property FontName: string read FFontName write FFontName;
    property FullName: string read FFullName write FFullName;
    property FamilyName: string read FFamilyName write FFamilyName;
    property Weight: string read FWeight write FWeight;
    property HasFontBBox: Boolean read FHasFontBBox;
    property FontBBox: TBoundingBox read FFontBBox write SetFontBBox;
    property FontVersion: string read FFontVersion write FFontVersion;
    property Notice: string read FNotice write FNotice;
    property EncodingScheme: string read FEncodingScheme write FEncodingScheme;
    property MappingScheme: Integer read FMappingScheme write FMappingScheme;
    property EscChar: Integer read FEscChar write FEscChar;
    property CharacterSet: string read FCharacterSet write FCharacterSet;
    property Characters: Integer read FCharacters write FCharacters;
    property IsBaseFont: Boolean read FIsBaseFont write FIsBaseFont;
    // Empty when the file has no vector
    property VVector: TArray<Single> read FVVector write FVVector;
    // Without an explicit value, true when there is a V vector
    property IsFixedV: Boolean read GetIsFixedV write SetIsFixedV;
    property CapHeight: Single read FCapHeight write FCapHeight;
    property XHeight: Single read FXHeight write FXHeight;
    property Ascender: Single read FAscender write FAscender;
    property Descender: Single read FDescender write FDescender;
    property Comments: TList<string> read FComments;
    property UnderlinePosition: Single read FUnderlinePosition write FUnderlinePosition;
    property UnderlineThickness: Single read FUnderlineThickness write FUnderlineThickness;
    property ItalicAngle: Single read FItalicAngle write FItalicAngle;
    // Empty when the file has no value
    property CharWidth: TArray<Single> read FCharWidth write FCharWidth;
    property IsFixedPitch: Boolean read FIsFixedPitch write FIsFixedPitch;
    property StandardHorizontalWidth: Single read FStandardHorizontalWidth write FStandardHorizontalWidth;
    property StandardVerticalWidth: Single read FStandardVerticalWidth write FStandardVerticalWidth;
    property CharMetrics: TObjectList<TCharMetric> read FCharMetrics;
    property TrackKern: TList<TTrackKern> read FTrackKern;
    property Composites: TObjectList<TComposite> read FComposites;
    property KernPairs: TList<TKernPair> read FKernPairs;
    property KernPairs0: TList<TKernPair> read FKernPairs0;
    property KernPairs1: TList<TKernPair> read FKernPairs1;
  end;

implementation

{ TLigature }

class function TLigature.Create(const Successor, Ligature: string): TLigature;
begin
  Result.Successor := Successor;
  Result.Ligature  := Ligature;
end;

{ TKernPair }

class function TKernPair.Create(const FirstKernCharacter, SecondKernCharacter: string; const X, Y: Single): TKernPair;
begin
  Result.FirstKernCharacter  := FirstKernCharacter;
  Result.SecondKernCharacter := SecondKernCharacter;
  Result.X                   := X;
  Result.Y                   := Y;
end;

{ TTrackKern }

class function TTrackKern.Create(const Degree: Integer; const MinPointSize, MinKern, MaxPointSize, MaxKern: Single): TTrackKern;
begin
  Result.Degree       := Degree;
  Result.MinPointSize := MinPointSize;
  Result.MinKern      := MinKern;
  Result.MaxPointSize := MaxPointSize;
  Result.MaxKern      := MaxKern;
end;

{ TCompositePart }

class function TCompositePart.Create(const Name: string; const XDisplacement, YDisplacement: Integer): TCompositePart;
begin
  Result.Name          := Name;
  Result.XDisplacement := XDisplacement;
  Result.YDisplacement := YDisplacement;
end;

{ TComposite }

constructor TComposite.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
  FParts := TList<TCompositePart>.Create;
end;

destructor TComposite.Destroy;
begin
  FParts.Free;
  inherited;
end;

procedure TComposite.AddPart(const Part: TCompositePart);
begin
  FParts.Add(Part);
end;

{ TCharMetric }

constructor TCharMetric.Create;
begin
  inherited Create;
  FLigatures := TList<TLigature>.Create;
end;

destructor TCharMetric.Destroy;
begin
  FLigatures.Free;
  inherited;
end;

procedure TCharMetric.AddLigature(const Ligature: TLigature);
begin
  FLigatures.Add(Ligature);
end;

procedure TCharMetric.SetBoundingBox(const Value: TBoundingBox);
begin
  FBoundingBox := Value;
  FHasBoundingBox := True;
end;

{ TFontMetrics }

constructor TFontMetrics.Create;
begin
  inherited Create;
  FIsBaseFont := True;
  FComments := TList<string>.Create;
  FCharMetrics := TObjectList<TCharMetric>.Create(True);
  FCharMetricsMap := TDictionary<string, TCharMetric>.Create;
  FTrackKern := TList<TTrackKern>.Create;
  FComposites := TObjectList<TComposite>.Create(True);
  FKernPairs := TList<TKernPair>.Create;
  FKernPairs0 := TList<TKernPair>.Create;
  FKernPairs1 := TList<TKernPair>.Create;
end;

destructor TFontMetrics.Destroy;
begin
  FKernPairs1.Free;
  FKernPairs0.Free;
  FKernPairs.Free;
  FComposites.Free;
  FTrackKern.Free;
  FCharMetricsMap.Free;
  FCharMetrics.Free;
  FComments.Free;
  inherited;
end;

function TFontMetrics.GetCharacterWidth(const Name: string): Single;
begin
  var Metric: TCharMetric;
  if FCharMetricsMap.TryGetValue(Name, Metric) then
  begin
    Result := Metric.Wx;
  end
  else
  begin
    Result := 0;
  end;
end;

function TFontMetrics.GetCharacterHeight(const Name: string): Single;
begin
  Result := 0;
  var Metric: TCharMetric;
  if not FCharMetricsMap.TryGetValue(Name, Metric) then
  begin
    Exit;
  end;

  Result := Metric.Wy;
  const HasNoHeight = (Result = 0);
  if HasNoHeight and Metric.HasBoundingBox then
  begin
    Result := Metric.BoundingBox.Height;
  end;
end;

function TFontMetrics.GetAverageCharacterWidth: Single;
begin
  var TotalWidths: Single := 0;
  var CharacterCount: Single := 0;
  for var Metric in FCharMetrics do
  begin
    if Metric.Wx > 0 then
    begin
      TotalWidths := TotalWidths + Metric.Wx;
      CharacterCount := CharacterCount + 1;
    end;
  end;

  if TotalWidths > 0 then
  begin
    Result := TotalWidths / CharacterCount;
  end
  else
  begin
    Result := 0;
  end;
end;

procedure TFontMetrics.AddComment(const Comment: string);
begin
  FComments.Add(Comment);
end;

procedure TFontMetrics.AddCharMetric(const Metric: TCharMetric);
begin
  FCharMetrics.Add(Metric);
  FCharMetricsMap.AddOrSetValue(Metric.Name, Metric);
end;

procedure TFontMetrics.AddTrackKern(const Kern: TTrackKern);
begin
  FTrackKern.Add(Kern);
end;

procedure TFontMetrics.AddComposite(const Composite: TComposite);
begin
  FComposites.Add(Composite);
end;

procedure TFontMetrics.AddKernPair(const KernPair: TKernPair);
begin
  FKernPairs.Add(KernPair);
end;

procedure TFontMetrics.AddKernPair0(const KernPair: TKernPair);
begin
  FKernPairs0.Add(KernPair);
end;

procedure TFontMetrics.AddKernPair1(const KernPair: TKernPair);
begin
  FKernPairs1.Add(KernPair);
end;

procedure TFontMetrics.SetMetricSets(const Value: Integer);
begin
  const IsOutOfRange = ((Value < 0) or (Value > 2));
  if IsOutOfRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The metricSets attribute must be 0, 1 or 2 and not %d', [Value]);
  end;
  FMetricSets := Value;
end;

procedure TFontMetrics.SetFontBBox(const Value: TBoundingBox);
begin
  FFontBBox := Value;
  FHasFontBBox := True;
end;

function TFontMetrics.GetIsFixedV: Boolean;
begin
  if FIsFixedVSet then
  begin
    Result := FIsFixedV;
  end
  else
  begin
    Result := (Length(FVVector) > 0);
  end;
end;

procedure TFontMetrics.SetIsFixedV(const Value: Boolean);
begin
  FIsFixedV := Value;
  FIsFixedVSet := True;
end;

end.
