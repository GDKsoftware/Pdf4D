// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/PDPageLabels.java and PDPageLabelRange.java (3.0.8),
// the read side
unit Pdf4D.Model.PageLabels;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Document;

const
  // The most pages that GetLabelsByPageIndices makes labels for, and the most characters in all labels together. PDFBox
  // has no limit and runs out of memory on a /Count or a start value that is large enough.
  MaxPageLabelCount = 10000000;
  MaxPageLabelCharacters = 32000000;

type
  // Port of PDPageLabelRange, as a value that is read from the dictionary of the range
  TPDPageLabelRange = record
  public
    // False for a null in the number tree. PDFBox then has a null range, which fails when it makes a label.
    IsPresent: Boolean;
    HasStyle: Boolean;
    Style: string;
    Start: Integer;
    HasPrefix: Boolean;
    Prefix: string;

    // Port of the constructor PDPageLabelRange(COSDictionary) and its getters: /S is a name (a string is accepted as in
    // getNameAsString), /St an integer with default 1, /P a string
    class function FromDictionary(const Dictionary: TCosDictionary): TPDPageLabelRange; static;
    class function DecimalRange: TPDPageLabelRange; static;
  end;

  TPDPageLabels = class
  private
    FDocument: TPDDocument;
    FLabels: TDictionary<Integer, TPDPageLabelRange>;
    FRemainingCharacters: Int64;

    procedure FindLabels(const Root: TCosDictionary);
    procedure Fill(const Result: TArray<string>; const NumberOfPages: Integer);
    procedure FillRange(const Result: TArray<string>; const Range: TPDPageLabelRange; const FirstPage, PageCount: Int64; const NumberOfPages: Integer);
    function MakeLabel(const Range: TPDPageLabelRange; const Offset: Integer): string;
    function GetNumber(const Number: Integer; const Style: string): string;
    function MakeRomanLabel(const Number: Integer): string;
    function MakeLetterLabel(const Number: Integer): string;
    procedure Spend(const Characters: Int64);
    function GetPageRangeCount: Integer;

  public
    // Port of PDPageLabels(PDDocument): only the default range, which numbers the pages 1, 2, 3 in decimals. It does
    // not read /PageLabels of the catalog, as in PDFBox 3.0.8. The document is not owned.
    constructor Create(const Document: TPDDocument); overload;
    // Port of PDPageLabels(PDDocument, COSDictionary): the default range and the ranges of the number tree in Dictionary,
    // which may be nil. Raises EPdfParseException when a value of the tree is no dictionary.
    constructor Create(const Document: TPDDocument; const Dictionary: TCosDictionary); overload;
    destructor Destroy; override;

    function TryGetPageLabelRange(const StartPage: Integer; out Range: TPDPageLabelRange): Boolean;

    // Port of getLabelsByPageIndices: the array has as many entries as the /Count of the page tree (PDDocument.getNumberOfPages),
    // but never more than the pages that the walk of the tree finds: a label beyond the real pages cannot be asked for, and a
    // /Count that is far too large must not allocate for nothing. An entry that has no label is empty. Raises EPdfParseException for a negative /Count
    // and for a null range that has pages (a NullPointerException in PDFBox), and EPdfLimitExceededException beyond
    // MaxPageLabelCount pages or MaxPageLabelCharacters characters.
    function GetLabelsByPageIndices: TArray<string>;

    property PageRangeCount: Integer read GetPageRangeCount;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfString,
  Pdf4D.Model.NumberTree;

const
  StyleDecimal = 'D';
  StyleRomanUpper = 'R';
  StyleRomanLower = 'r';
  StyleLettersUpper = 'A';
  StyleLettersLower = 'a';

  Romans: array[0..2] of array[0..9] of string = (
    ('', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix'),
    ('', 'x', 'xx', 'xxx', 'xl', 'l', 'lx', 'lxx', 'lxxx', 'xc'),
    ('', 'c', 'cc', 'ccc', 'cd', 'd', 'dc', 'dcc', 'dccc', 'cm'));

{ TPDPageLabelRange }

class function TPDPageLabelRange.FromDictionary(const Dictionary: TCosDictionary): TPDPageLabelRange;
begin
  Result.IsPresent := True;
  // getNameAsString gives null for an entry that is neither a name nor a string
  var Raw: TCosBase;
  Result.HasStyle := (Dictionary.TryGetDictionaryObject(TCosNames.S, Raw) and ((Raw is TCosName) or (Raw is TCosString)));
  Result.Style := Dictionary.GetNameAsString(TCosNames.S, '');
  Result.Start := Dictionary.GetInt(TCosNames.St, 1);
  Result.HasPrefix := Dictionary.TryGetString(TCosNames.P, Result.Prefix);
end;

class function TPDPageLabelRange.DecimalRange: TPDPageLabelRange;
begin
  Result.IsPresent := True;
  Result.HasStyle := True;
  Result.Style := StyleDecimal;
  Result.Start := 1;
  Result.HasPrefix := False;
  Result.Prefix := '';
end;

{ TPDPageLabels }

constructor TPDPageLabels.Create(const Document: TPDDocument);
begin
  inherited Create;
  FDocument := Document;
  FLabels := TDictionary<Integer, TPDPageLabelRange>.Create;
  FLabels.AddOrSetValue(0, TPDPageLabelRange.DecimalRange);
end;

constructor TPDPageLabels.Create(const Document: TPDDocument; const Dictionary: TCosDictionary);
begin
  Create(Document);
  if Assigned(Dictionary) then
  begin
    FindLabels(Dictionary);
  end;
end;

destructor TPDPageLabels.Destroy;
begin
  FLabels.Free;
  inherited;
end;

procedure TPDPageLabels.FindLabels(const Root: TCosDictionary);
begin
  const Tree = TPDNumberTreeNode.Create(Root,
    function(const Value: TCosBase): TCosBase
    begin
      // PDFBox makes the range with the constructor that takes a COSDictionary, and a stream is no COSDictionary
      if not ((Value is TCosDictionary) and not (Value is TCosStream)) then
      begin
        raise EPdfParseException.Create('Error while trying to create a page label range in the number tree');
      end;
      Result := Value;
    end, FDocument.CosDocument.Log);
  try
    for var Pair in Tree.GetAll do
    begin
      if Pair.Key >= 0 then
      begin
        if Assigned(Pair.Value) then
        begin
          FLabels.AddOrSetValue(Pair.Key, TPDPageLabelRange.FromDictionary(TCosDictionary(Pair.Value)));
        end
        else
        begin
          FLabels.AddOrSetValue(Pair.Key, Default(TPDPageLabelRange));
        end;
      end;
    end;
  finally
    Tree.Free;
  end;
end;

function TPDPageLabels.GetPageRangeCount: Integer;
begin
  Result := FLabels.Count;
end;

function TPDPageLabels.TryGetPageLabelRange(const StartPage: Integer; out Range: TPDPageLabelRange): Boolean;
begin
  Result := FLabels.TryGetValue(StartPage, Range);
end;

procedure TPDPageLabels.Spend(const Characters: Int64);
begin
  if Characters > FRemainingCharacters then
  begin
    raise EPdfLimitExceededException.CreateFmt('The page labels have more than %d characters', [MaxPageLabelCharacters]);
  end;
  Dec(FRemainingCharacters, Characters);
end;

function TPDPageLabels.MakeRomanLabel(const Number: Integer): string;
begin
  var Remaining := Number;
  var Power := 0;
  Result := '';
  while (Power < 3) and (Remaining > 0) do
  begin
    Result := Romans[Power][Remaining mod 10] + Result;
    Remaining := Remaining div 10;
    Inc(Power);
  end;

  // As many m as there are thousands, which is what Acrobat does for a number beyond 3999
  if Remaining > 0 then
  begin
    Spend(Remaining);
    Result := StringOfChar('m', Remaining) + Result;
  end;
end;

function TPDPageLabels.MakeLetterLabel(const Number: Integer): string;
begin
  var Letters := Number div 26;
  var Position := Number mod 26;
  if Position > 0 then
  begin
    Inc(Letters);
  end;
  if Letters <= 0 then
  begin
    Exit('');
  end;

  Spend(Letters);
  // A remainder of 0 is a z
  if Position = 0 then
  begin
    Position := 26;
  end;
  Result := StringOfChar(Char(Ord('a') + Position - 1), Letters);
end;

function TPDPageLabels.GetNumber(const Number: Integer; const Style: string): string;
begin
  if Style = StyleLettersLower then
  begin
    Result := MakeLetterLabel(Number);
  end
  else if Style = StyleLettersUpper then
  begin
    Result := MakeLetterLabel(Number).ToUpperInvariant;
  end
  else if Style = StyleRomanLower then
  begin
    Result := MakeRomanLabel(Number);
  end
  else if Style = StyleRomanUpper then
  begin
    Result := MakeRomanLabel(Number).ToUpperInvariant;
  end
  else
  begin
    // The decimal style and, as PDFBox does, every other style
    Result := IntToStr(Number);
  end;
end;

function TPDPageLabels.MakeLabel(const Range: TPDPageLabelRange; const Offset: Integer): string;
begin
  Result := '';
  if Range.HasPrefix then
  begin
    // PDFBOX-1047: some labels have a null byte and garbage behind it
    const NullPosition = Range.Prefix.IndexOf(#0);
    if NullPosition >= 0 then
    begin
      Result := Range.Prefix.Substring(0, NullPosition);
    end
    else
    begin
      Result := Range.Prefix;
    end;
    Spend(Result.Length);
  end;

  if Range.HasStyle then
  begin
    // The sum wraps around like an int does in Java
    const Number = Integer(Cardinal(Range.Start) + Cardinal(Offset));
    Result := Result + GetNumber(Number, Range.Style);
  end;
end;

procedure TPDPageLabels.FillRange(const Result: TArray<string>; const Range: TPDPageLabelRange; const FirstPage, PageCount: Int64; const NumberOfPages: Integer);
begin
  if PageCount <= 0 then
  begin
    Exit;
  end;

  if not Range.IsPresent then
  begin
    raise EPdfParseException.Create('A page label range in the number tree is null');
  end;

  // The labels of pages beyond the last page are made by PDFBox and dropped, so they are not made here
  const LastPage = Min(FirstPage + PageCount, Int64(NumberOfPages));
  for var Page := FirstPage to LastPage - 1 do
  begin
    Result[Page] := MakeLabel(Range, Integer(Page - FirstPage));
  end;
end;

procedure TPDPageLabels.Fill(const Result: TArray<string>; const NumberOfPages: Integer);
begin
  // The ranges in the order of their first page, which is what the TreeMap of PDFBox is for
  var Starts := FLabels.Keys.ToArray;
  TArray.Sort<Integer>(Starts);

  var FirstPage: Int64 := 0;
  for var Position := 0 to High(Starts) do
  begin
    var PageCount: Int64;
    if Position < High(Starts) then
    begin
      PageCount := Int64(Starts[Position + 1]) - Starts[Position];
    end
    else
    begin
      PageCount := Int64(NumberOfPages) - Starts[Position];
    end;

    FillRange(Result, FLabels[Starts[Position]], FirstPage, PageCount, NumberOfPages);
    FirstPage := FirstPage + PageCount;
  end;
end;

function TPDPageLabels.GetLabelsByPageIndices: TArray<string>;
begin
  const CountEntry = FDocument.Pages.Count;
  if CountEntry < 0 then
  begin
    raise EPdfParseException.CreateFmt('The page tree has a negative page count of %d', [CountEntry]);
  end;
  const NumberOfPages = Min(CountEntry, FDocument.Pages.EnumeratedCount);
  if NumberOfPages > MaxPageLabelCount then
  begin
    raise EPdfLimitExceededException.CreateFmt('The page tree has %d pages, more than the %d that page labels are made for', [NumberOfPages, MaxPageLabelCount]);
  end;

  FRemainingCharacters := MaxPageLabelCharacters;
  SetLength(Result, NumberOfPages);
  Fill(Result, NumberOfPages);
end;

end.
