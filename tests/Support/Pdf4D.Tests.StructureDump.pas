// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.StructureDump;

interface

uses
  System.SysUtils,
  Pdf4D.Api.Document.Interfaces;

type
  // Writes the structure dump of docs/golden-format.md, the same text that the PDFBox oracle (tools/oracle/Pdf4DOracle.java)
  // writes. The sections come in the order of the oracle, because reading one section loads objects that the object section
  // then lists.
  TStructureDump = record
  private
    class function EscapeText(const Text: string): string; static;
    class function NameText(const Name: string): string; static;
    class function HexOf(const Bytes: TBytes): string; static;
    class function FloatText(const Value: Single): string; static;

    class function Canonical(const Value: TObject): string; static;
    class function CanonicalDictionary(const Dictionary: TObject): string; static;
    class function CanonicalStream(const Stream: TObject; const IsStrict: Boolean): string; static;
  public
    // The text of a float as the golden format wants it: the shortest decimal of the 32 bit value (Float.toString), rounded
    // half up to 4 decimals, without trailing zeros, "0" for zero
    class function FormatFloat(const Value: Single): string; static;
    // Float.toString for the values of a version: 1.7, 2.0
    class function FormatVersion(const Value: Single): string; static;
    class function EscapedText(const Text: string): string; static;

    // Lenient: every exception of a section becomes an "error" line, as the oracle does. Strict: only a PDF exception becomes an "error"
    // line, any other exception (an access violation, a range error) goes to the caller.
    class function Dump(const Document: IPdfDocument; const IsStrict: Boolean = False): string; static;
    // The single line for a file that cannot be loaded
    class function DumpLoadError(const E: Exception): string; static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.Hash,
  System.Generics.Collections,
  System.Generics.Defaults,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString,
  Pdf4D.Model.AcroForm,
  Pdf4D.Model.DateConverter,
  Pdf4D.Model.Document,
  Pdf4D.Model.EmbeddedFile,
  Pdf4D.Model.Field,
  Pdf4D.Model.Outline,
  Pdf4D.Model.OutlineItem,
  Pdf4D.Model.PageLabels,
  Pdf4D.Model.Rectangle;

const
  LineFeed = #10;
  OutlineDepthLimit = 64;
  FloatDecimals = 4;

{ TStructureDump }

class function TStructureDump.HexOf(const Bytes: TBytes): string;
begin
  const Digits = '0123456789abcdef';
  SetLength(Result, 2 * Length(Bytes));
  for var Index := 0 to High(Bytes) do
  begin
    Result[2 * Index + 1] := Digits[(Bytes[Index] shr 4) + 1];
    Result[2 * Index + 2] := Digits[(Bytes[Index] and $F) + 1];
  end;
end;

// Port of nameText of the oracle
class function TStructureDump.NameText(const Name: string): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Value in TEncoding.UTF8.GetBytes(Name) do
    begin
      if (Value < $21) or (Value > $7E) or CharInSet(Chr(Value), ['#', '(', ')', '<', '>', '[', ']', '{', '}', '/', '%']) then
      begin
        Builder.Append('#').Append(IntToHex(Value, 2));
      end
      else
      begin
        Builder.Append(Chr(Value));
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

// Port of escapeText of the oracle
class function TStructureDump.EscapeText(const Text: string): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Character in Text do
    begin
      case Character of
        '\': Builder.Append('\\');
        #10: Builder.Append('\n');
        #13: Builder.Append('\r');
        #9: Builder.Append('\t');
      else
        if (Character < ' ') or (Character = #$7F) then
        begin
          Builder.Append('\x').Append(IntToHex(Ord(Character), 2));
        end
        else
        begin
          Builder.Append(Character);
        end;
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TStructureDump.EscapedText(const Text: string): string;
begin
  Result := EscapeText(Text);
end;

// The shortest decimal digits (no dot) and the decimal exponent of the first digit of a positive single, as Float.toString
// writes them
procedure ShortestDigits(const Value: Single; out Digits: string; out Exponent: Integer);
begin
  Digits := '';
  Exponent := 0;
  for var Precision := 1 to 9 do
  begin
    const Text = FloatToStrF(Value, ffExponent, Precision, 2, TFormatSettings.Invariant);
    const Split = Text.IndexOf('E');
    if Precision = 9 then
    begin
      Digits := Text.Substring(0, Split).Replace('.', '');
      Exponent := StrToInt(Text.Substring(Split + 1).Replace('+', ''));
      Break;
    end;
    if Single(StrToFloat(Text, TFormatSettings.Invariant)) = Value then
    begin
      Digits := Text.Substring(0, Split).Replace('.', '');
      Exponent := StrToInt(Text.Substring(Split + 1).Replace('+', ''));
      Break;
    end;
  end;

  while (Digits.Length > 1) and Digits.EndsWith('0') do
  begin
    Digits := Digits.Substring(0, Digits.Length - 1);
  end;
end;

// The integer and the fraction digits of a positive single in plain notation
procedure PlainDigits(const Value: Single; out IntegerPart, Fraction: string);
begin
  var Digits: string;
  var Exponent: Integer;
  ShortestDigits(Value, Digits, Exponent);

  if Exponent >= 0 then
  begin
    if Digits.Length <= Exponent + 1 then
    begin
      IntegerPart := Digits + StringOfChar('0', Exponent + 1 - Digits.Length);
      Fraction := '';
    end
    else
    begin
      IntegerPart := Digits.Substring(0, Exponent + 1);
      Fraction := Digits.Substring(Exponent + 1);
    end;
  end
  else
  begin
    IntegerPart := '0';
    Fraction := StringOfChar('0', -Exponent - 1) + Digits;
  end;
end;

class function TStructureDump.FormatVersion(const Value: Single): string;
begin
  if IsNaN(Value) or IsInfinite(Value) then
  begin
    Exit(FloatText(Value));
  end;
  if Value = 0 then
  begin
    Exit('0.0');
  end;

  var IntegerPart: string;
  var Fraction: string;
  PlainDigits(Abs(Value), IntegerPart, Fraction);
  if Fraction = '' then
  begin
    Fraction := '0';
  end;
  Result := IntegerPart + '.' + Fraction;
  if Value < 0 then
  begin
    Result := '-' + Result;
  end;
end;

class function TStructureDump.FloatText(const Value: Single): string;
begin
  if IsNaN(Value) then
  begin
    Result := 'NaN';
  end
  else if IsInfinite(Value) then
  begin
    if Value > 0 then
    begin
      Result := 'Infinity';
    end
    else
    begin
      Result := '-Infinity';
    end;
  end
  else
  begin
    Result := FormatFloat(Value);
  end;
end;

class function TStructureDump.FormatFloat(const Value: Single): string;
begin
  if IsNaN(Value) or IsInfinite(Value) then
  begin
    Exit(FloatText(Value));
  end;
  if Value = 0 then
  begin
    Exit('0');
  end;

  var IntegerPart: string;
  var Fraction: string;
  PlainDigits(Abs(Value), IntegerPart, Fraction);

  // Round half up at the 4th decimal, on the decimal digits
  var Kept := IntegerPart + Fraction.Substring(0, Min(FloatDecimals, Fraction.Length)).PadRight(FloatDecimals, '0');
  if (Fraction.Length > FloatDecimals) and (Fraction[FloatDecimals + 1] >= '5') then
  begin
    var Position := Kept.Length;
    while Position >= 1 do
    begin
      if Kept[Position] = '9' then
      begin
        Kept[Position] := '0';
        Dec(Position);
      end
      else
      begin
        Kept[Position] := Chr(Ord(Kept[Position]) + 1);
        Break;
      end;
    end;
    if Position < 1 then
    begin
      Kept := '1' + Kept;
    end;
  end;

  IntegerPart := Kept.Substring(0, Kept.Length - FloatDecimals);
  Fraction := Kept.Substring(Kept.Length - FloatDecimals);
  while Fraction.EndsWith('0') do
  begin
    Fraction := Fraction.Substring(0, Fraction.Length - 1);
  end;

  const IsZero = (Fraction = '') and (IntegerPart.Replace('0', '') = '');
  if IsZero then
  begin
    Exit('0');
  end;

  Result := IntegerPart;
  if Fraction <> '' then
  begin
    Result := Result + '.' + Fraction;
  end;
  if Value < 0 then
  begin
    Result := '-' + Result;
  end;
end;

class function TStructureDump.Canonical(const Value: TObject): string;
begin
  if (Value = nil) or (Value is TCosNull) then
  begin
    Exit('null');
  end;

  if Value is TCosObject then
  begin
    const Key = TCosObject(Value).Key;
    Exit(IntToStr(Key.Number) + ' ' + IntToStr(Key.Generation) + ' R');
  end;

  if Value is TCosBoolean then
  begin
    if TCosBoolean(Value).Value then
    begin
      Result := 'true';
    end
    else
    begin
      Result := 'false';
    end;
  end
  else if Value is TCosInteger then
  begin
    Result := IntToStr(TCosInteger(Value).Value);
  end
  else if Value is TCosFloat then
  begin
    Result := FloatText(TCosFloat(Value).FloatValue);
  end
  else if Value is TCosName then
  begin
    Result := '/' + NameText(TCosName(Value).Name);
  end
  else if Value is TCosString then
  begin
    Result := '<' + HexOf(TCosString(Value).Bytes) + '>';
  end
  else if Value is TCosArray then
  begin
    const Items = TStringBuilder.Create;
    try
      var IsFirst := True;
      for var Item in TCosArray(Value) do
      begin
        if not IsFirst then
        begin
          Items.Append(' ');
        end;
        IsFirst := False;
        Items.Append(Canonical(Item));
      end;
      Result := '[' + Items.ToString + ']';
    finally
      Items.Free;
    end;
  end
  else if Value is TCosDictionary then
  begin
    Result := CanonicalDictionary(Value);
  end
  else
  begin
    raise EPdfException.CreateFmt('Unsupported COS type %s', [Value.ClassName]);
  end;
end;

class function TStructureDump.CanonicalDictionary(const Dictionary: TObject): string;
begin
  const Source = TCosDictionary(Dictionary);
  const Sorted = TDictionary<string, string>.Create;
  try
    for var Key in Source.Keys do
    begin
      Sorted.AddOrSetValue(NameText(Key), Canonical(Source.GetItem(Key)));
    end;

    var Names := Sorted.Keys.ToArray;
    TArray.Sort<string>(Names, TComparer<string>.Construct(
      function(const Left, Right: string): Integer
      begin
        Result := CompareStr(Left, Right);
      end));

    const Builder = TStringBuilder.Create('<<');
    try
      for var Index := 0 to High(Names) do
      begin
        if Index > 0 then
        begin
          Builder.Append(' ');
        end;
        Builder.Append('/').Append(Names[Index]).Append(' ').Append(Sorted[Names[Index]]);
      end;
      Result := Builder.Append('>>').ToString;
    finally
      Builder.Free;
    end;
  finally
    Sorted.Free;
  end;
end;

class function TStructureDump.CanonicalStream(const Stream: TObject; const IsStrict: Boolean): string;
begin
  const Source = TCosStream(Stream);
  const Header = CanonicalDictionary(Source);
  try
    const Decoded = Source.DecodeUntilImageFilter;
    const Hash = THashSHA2.Create(SHA256);
    Hash.Update(Decoded.Data);

    Result := Header + ' stream';
    if Length(Decoded.RemainingFilters) > 0 then
    begin
      Result := Result + ' partial=' + string.Join(',', Decoded.RemainingFilters);
    end;
    Result := Result + ' sha256=' + Hash.HashAsString;
  except
    on Failure: Exception do
    begin
      if IsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Result := Header + ' stream error';
    end;
  end;
end;

class function TStructureDump.DumpLoadError(const E: Exception): string;
begin
  var Kind := 'parse';
  if E is EPdfInvalidPasswordException then
  begin
    Kind := 'wrong-password';
  end
  else if E is EPdfUnsupportedFeatureException then
  begin
    Kind := 'unsupported';
  end;
  Result := 'load-error: ' + Kind + LineFeed;
end;

type
  TDumpWriter = class
  private
    FLines: TStringBuilder;
    FModel: TPDDocument;
    FIsStrict: Boolean;
    FPageCosObjects: TList<TCosDictionary>;

    procedure Add(const Line: string);
    procedure AddVersion;
    procedure AddEncryption;
    procedure AddPages;
    procedure AddInfo;
    procedure AddXmp;
    procedure AddOutline;
    procedure AddOutlineLevel(const Node: TPDOutlineNode; const Level: Integer; const Seen: TDictionary<TObject, Boolean>);
    procedure AddFields;
    procedure AddField(const Item: TPDField);
    procedure AddAttachments;
    procedure AddObjects;
    function ObjectLine(const Key: TCosObjectKey; out IsSkipped: Boolean): string;
    function RectangleText(const Rectangle: TPdfRectangle): string;
    function LabelsOf: TArray<string>;
    function PageNumberOf(const Item: TPDOutlineItem): string;

  public
    constructor Create(const Model: TPDDocument; const IsStrict: Boolean);
    destructor Destroy; override;

    function Write: string;
  end;

{ TDumpWriter }

constructor TDumpWriter.Create(const Model: TPDDocument; const IsStrict: Boolean);
begin
  inherited Create;
  FModel := Model;
  FIsStrict := IsStrict;
  FLines := TStringBuilder.Create;
  FPageCosObjects := TList<TCosDictionary>.Create;
end;

destructor TDumpWriter.Destroy;
begin
  FPageCosObjects.Free;
  FLines.Free;
  inherited;
end;

procedure TDumpWriter.Add(const Line: string);
begin
  FLines.Append(Line).Append(LineFeed);
end;

function TDumpWriter.RectangleText(const Rectangle: TPdfRectangle): string;
begin
  Result := '[' + TStructureDump.FormatFloat(Rectangle.LowerLeftX) + ' ' + TStructureDump.FormatFloat(Rectangle.LowerLeftY) + ' ' +
            TStructureDump.FormatFloat(Rectangle.UpperRightX) + ' ' + TStructureDump.FormatFloat(Rectangle.UpperRightY) + ']';
end;

procedure TDumpWriter.AddVersion;
begin
  try
    Add('version: ' + TStructureDump.FormatVersion(FModel.Version));
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Add('version: error');
    end;
  end;
end;

procedure TDumpWriter.AddEncryption;
begin
  const IsEncrypted = FModel.IsEncrypted;
  if IsEncrypted then
  begin
    Add('encrypted: true');
  end
  else
  begin
    Add('encrypted: false');
  end;

  var Permissions := 'none';
  if IsEncrypted then
  begin
    try
      Permissions := IntToStr(FModel.CosDocument.Encryption.GetPermissions);
    except
      on Failure: Exception do
      begin
        if FIsStrict and not (Failure is EPdfException) then
        begin
          raise;
        end;
        Permissions := 'error';
      end;
    end;
  end;
  Add('permissions: ' + Permissions);
end;

// The labels of /PageLabels, none without it and none when reading them fails
function TDumpWriter.LabelsOf: TArray<string>;
begin
  Result := nil;
  try
    var Dictionary: TCosDictionary;
    if FModel.Catalog.TryGetPageLabels(Dictionary) then
    begin
      const Labels = TPDPageLabels.Create(FModel, Dictionary);
      try
        Result := Labels.GetLabelsByPageIndices;
      finally
        Labels.Free;
      end;
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Result := nil;
    end;
  end;
end;

procedure TDumpWriter.AddPages;
begin
  var IsFailed := False;
  try
    const Tree = FModel.Pages;
    for var Position := 0 to Tree.EnumeratedCount - 1 do
    begin
      FPageCosObjects.Add(Tree.Get(Position).CosObject);
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      IsFailed := True;
    end;
  end;

  if IsFailed and (FPageCosObjects.Count = 0) then
  begin
    Add('pages: error');
  end
  else
  begin
    Add('pages: ' + IntToStr(FPageCosObjects.Count));
  end;

  const Labels = LabelsOf;
  for var Position := 0 to FPageCosObjects.Count - 1 do
  begin
    try
      const Page = FModel.Pages.Get(Position);
      var PageLabel := '';
      if Position < Length(Labels) then
      begin
        PageLabel := Labels[Position];
      end;
      Add('page ' + IntToStr(Position + 1) + ': media=' + RectangleText(Page.MediaBox) + ' crop=' + RectangleText(Page.CropBox) +
          ' rotate=' + IntToStr(Page.Rotation) + ' label=' + TStructureDump.EscapedText(PageLabel));
    except
      on Failure: Exception do
      begin
        if FIsStrict and not (Failure is EPdfException) then
        begin
          raise;
        end;
        Add('page ' + IntToStr(Position + 1) + ': error');
      end;
    end;
  end;
end;

procedure TDumpWriter.AddInfo;
begin
  try
    var Value: TCosBase;
    if not FModel.CosDocument.Trailer.TryGetDictionaryObject(TCosNames.Info, Value) then
    begin
      Exit;
    end;
    if not (Value is TCosDictionary) then
    begin
      Exit;
    end;

    const Info = TCosDictionary(Value);
    const Lines = TDictionary<string, string>.Create;
    try
      for var Key in Info.Keys do
      begin
        var Text: string;
        try
          var Entry: TCosBase;
          if not Info.TryGetDictionaryObject(Key, Entry) then
          begin
            Entry := nil;
          end;

          if Entry is TCosString then
          begin
            var IsoDate := '';
            if (Key = TCosNames.CreationDate) or (Key = TCosNames.ModDate) then
            begin
              var Moment: TDateTime;
              var Offset: Integer;
              if TDateConverter.TryParse(TCosString(Entry).GetString, Moment, Offset) then
              begin
                IsoDate := TDateConverter.ToIso8601(Moment, Offset);
              end;
            end;
            if IsoDate <> '' then
            begin
              Text := IsoDate;
            end
            else
            begin
              Text := TStructureDump.EscapedText(TCosString(Entry).GetString);
            end;
          end
          else
          begin
            Text := TStructureDump.Canonical(Entry);
          end;
        except
          on Failure: Exception do
          begin
            if FIsStrict and not (Failure is EPdfException) then
            begin
              raise;
            end;
            Text := '<error>';
          end;
        end;
        Lines.AddOrSetValue(TStructureDump.NameText(Key), Text);
      end;

      var Keys := Lines.Keys.ToArray;
      TArray.Sort<string>(Keys, TComparer<string>.Construct(
        function(const Left, Right: string): Integer
        begin
          Result := CompareStr(Left, Right);
        end));
      for var Key in Keys do
      begin
        Add('info ' + Key + ': ' + Lines[Key]);
      end;
    finally
      Lines.Free;
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Add('info: error');
    end;
  end;
end;

procedure TDumpWriter.AddXmp;
begin
  var Text := 'none';
  try
    var Metadata: TCosStream;
    if FModel.Catalog.TryGetMetadata(Metadata) then
    begin
      const Decoded = Metadata.CreateDecodedStream;
      try
        Text := IntToStr(Decoded.Size);
      finally
        Decoded.Free;
      end;
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Text := 'error';
    end;
  end;
  Add('xmp: ' + Text);
end;

function TDumpWriter.PageNumberOf(const Item: TPDOutlineItem): string;
begin
  Result := '?';
  try
    var PageIndex: Integer;
    if Item.TryGetPageIndex(PageIndex) then
    begin
      Result := IntToStr(PageIndex + 1);
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Result := '?';
    end;
  end;
end;

procedure TDumpWriter.AddOutlineLevel(const Node: TPDOutlineNode; const Level: Integer; const Seen: TDictionary<TObject, Boolean>);
begin
  for var Item in Node do
  begin
    // The oracle remembers an item before it looks at the depth
    const IsRepeated = Seen.ContainsKey(Item.CosObject);
    Seen.AddOrSetValue(Item.CosObject, True);
    if IsRepeated or (Level > OutlineDepthLimit) then
    begin
      Continue;
    end;

    Add('outline: ' + StringOfChar(' ', 2 * Level) + TStructureDump.EscapedText(Item.Title) + ' -> ' + PageNumberOf(Item));
    AddOutlineLevel(Item, Level + 1, Seen);
  end;
end;

procedure TDumpWriter.AddOutline;
begin
  try
    var Outline: TPDDocumentOutline;
    if FModel.Catalog.TryGetOutline(Outline) then
    begin
      const Seen = TDictionary<TObject, Boolean>.Create;
      try
        AddOutlineLevel(Outline, 0, Seen);
      finally
        Seen.Free;
      end;
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Add('outline: error');
    end;
  end;
end;

procedure TDumpWriter.AddField(const Item: TPDField);
begin
  var KindName: string;
  case Item.Kind of
    TPdfFieldKind.Text        : KindName := 'text';
    TPdfFieldKind.CheckBox    : KindName := 'checkbox';
    TPdfFieldKind.RadioButton : KindName := 'radio';
    TPdfFieldKind.PushButton  : KindName := 'pushbutton';
    TPdfFieldKind.ComboBox    : KindName := 'combo';
    TPdfFieldKind.ListBox     : KindName := 'list';
    TPdfFieldKind.Signature   : KindName := 'signature';
    TPdfFieldKind.NonTerminal : KindName := 'nonterminal';
  else
    KindName := 'unknown';
  end;

  var Name: string;
  try
    Name := TStructureDump.EscapedText(Item.FullyQualifiedName);
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Name := '<error>';
    end;
  end;

  var Value := '';
  try
    case Item.Kind of
      TPdfFieldKind.NonTerminal:
      begin
        Value := '';
      end;
      TPdfFieldKind.ComboBox, TPdfFieldKind.ListBox:
      begin
        const Parts = TList<string>.Create;
        try
          for var Part in Item.Values do
          begin
            Parts.Add(TStructureDump.EscapedText(Part));
          end;
          Value := string.Join(',', Parts.ToArray);
        finally
          Parts.Free;
        end;
      end;
    else
      Value := TStructureDump.EscapedText(Item.ValueAsString);
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Value := '<error>';
    end;
  end;

  Add('field: ' + Name + ' | ' + KindName + ' | ' + Value);
end;

procedure TDumpWriter.AddFields;
begin
  try
    var Form: TPDAcroForm;
    if FModel.Catalog.TryGetAcroForm(Form) then
    begin
      for var Item in Form.GetFieldTree do
      begin
        AddField(Item);
      end;
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Add('field: error');
    end;
  end;
end;

procedure TDumpWriter.AddAttachments;
begin
  try
    for var Attachment in FModel.GetEmbeddedFiles do
    begin
      var Size: string := '?';
      var Value: Integer;
      if Attachment.TryGetSize(Value) then
      begin
        Size := IntToStr(Value);
      end;
      Add('attachment: ' + TStructureDump.EscapedText(Attachment.FileName) + ' | ' + Size);
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Add('attachment: error');
    end;
  end;
end;

function TDumpWriter.ObjectLine(const Key: TCosObjectKey; out IsSkipped: Boolean): string;
begin
  IsSkipped := False;
  const Prefix = 'object ' + IntToStr(Key.Number) + ' ' + IntToStr(Key.Generation) + ': ';
  try
    const Base = FModel.CosDocument.GetObjectFromPool(Key).GetObject;
    if Base is TCosDictionary then
    begin
      var TypeValue: TCosBase;
      if TCosDictionary(Base).TryGetDictionaryObject(TCosNames.Type_, TypeValue) and (TypeValue is TCosName) then
      begin
        const TypeName = TCosName(TypeValue).Name;
        if (TypeName = TCosNames.ObjStm) or (TypeName = TCosNames.XRef) then
        begin
          IsSkipped := True;
          Exit('');
        end;
      end;
    end;

    if Base is TCosStream then
    begin
      Result := Prefix + TStructureDump.CanonicalStream(Base, FIsStrict);
    end
    else
    begin
      Result := Prefix + TStructureDump.Canonical(Base);
    end;
  except
    on Failure: Exception do
    begin
      if FIsStrict and not (Failure is EPdfException) then
      begin
        raise;
      end;
      Result := Prefix + 'error';
    end;
  end;
end;

procedure TDumpWriter.AddObjects;
begin
  // The keys as they are now: objects that the sections before this one loaded or found are in the table
  for var Key in FModel.CosDocument.ObjectKeys do
  begin
    var IsSkipped: Boolean;
    const Line = ObjectLine(Key, IsSkipped);
    if not IsSkipped then
    begin
      Add(Line);
    end;
  end;
end;

function TDumpWriter.Write: string;
begin
  AddVersion;
  AddEncryption;
  AddPages;
  AddInfo;
  AddXmp;
  AddOutline;
  AddFields;
  AddAttachments;
  AddObjects;
  Result := FLines.ToString;
end;

class function TStructureDump.Dump(const Document: IPdfDocument; const IsStrict: Boolean): string;
begin
  const Writer = TDumpWriter.Create((Document as TPdfDocument).ModelDocument, IsStrict);
  try
    Result := Writer.Write;
  finally
    Writer.Free;
  end;
end;

end.
