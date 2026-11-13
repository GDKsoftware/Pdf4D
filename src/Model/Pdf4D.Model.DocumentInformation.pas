// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDDocumentInformation.java (3.0.8), the read side
unit Pdf4D.Model.DocumentInformation;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary;

type
  // The /Info dictionary of the trailer. It holds the dictionary and does not own it.
  // A text entry that is missing or is no string gives an empty string, use TryGetCustomValue to tell the two apart.
  TPDDocumentInformation = class
  private
    FInfo: TCosDictionary;

    function TryGetDate(const Key: string; out Value: TDateTime; out OffsetMinutes: Integer): Boolean;

  public
    constructor Create(const Info: TCosDictionary);

    function Title: string;
    function Author: string;
    function Subject: string;
    function Keywords: string;
    function Creator: string;
    function Producer: string;
    // The name of /Trapped (True, False or Unknown), empty when there is none
    function Trapped: string;

    // Port of getCreationDate and getModificationDate: false when the entry is missing or its text is no date. The
    // value is the wall clock time of the date and the offset is that of its time zone, see TDateConverter.
    function TryGetCreationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
    function TryGetModificationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;

    // All keys in the order of the file. PDFBox's getMetadataKeys sorts them, sort the result to get the same.
    function Keys: TArray<string>;
    // Port of getCustomMetadataValue: false when there is no string under the key
    function TryGetCustomValue(const Key: string; out Value: string): Boolean;

    // The dictionary with its raw values
    property CosObject: TCosDictionary read FInfo;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfString,
  Pdf4D.Model.DateConverter;

{ TPDDocumentInformation }

constructor TPDDocumentInformation.Create(const Info: TCosDictionary);
begin
  inherited Create;
  FInfo := Info;
end;

function TPDDocumentInformation.Title: string;
begin
  Result := FInfo.GetString(TCosNames.Title, '');
end;

function TPDDocumentInformation.Author: string;
begin
  Result := FInfo.GetString(TCosNames.Author, '');
end;

function TPDDocumentInformation.Subject: string;
begin
  Result := FInfo.GetString(TCosNames.Subject, '');
end;

function TPDDocumentInformation.Keywords: string;
begin
  Result := FInfo.GetString(TCosNames.Keywords, '');
end;

function TPDDocumentInformation.Creator: string;
begin
  Result := FInfo.GetString(TCosNames.Creator, '');
end;

function TPDDocumentInformation.Producer: string;
begin
  Result := FInfo.GetString(TCosNames.Producer, '');
end;

function TPDDocumentInformation.Trapped: string;
begin
  Result := FInfo.GetNameAsString(TCosNames.Trapped, '');
end;

// Port of COSDictionary.getDate: only a string can hold a date
function TPDDocumentInformation.TryGetDate(const Key: string; out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  var Item: TCosBase;
  Result := (FInfo.TryGetDictionaryObject(Key, Item) and (Item is TCosString) and
             TDateConverter.TryParse(TCosString(Item).GetString, Value, OffsetMinutes));
  if not Result then
  begin
    Value := 0;
    OffsetMinutes := 0;
  end;
end;

function TPDDocumentInformation.TryGetCreationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Result := TryGetDate(TCosNames.CreationDate, Value, OffsetMinutes);
end;

function TPDDocumentInformation.TryGetModificationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Result := TryGetDate(TCosNames.ModDate, Value, OffsetMinutes);
end;

function TPDDocumentInformation.Keys: TArray<string>;
begin
  Result := FInfo.Keys;
end;

function TPDDocumentInformation.TryGetCustomValue(const Key: string; out Value: string): Boolean;
begin
  var Item: TCosBase;
  Result := (FInfo.TryGetDictionaryObject(Key, Item) and (Item is TCosString));
  if Result then
  begin
    Value := TCosString(Item).GetString;
  end
  else
  begin
    Value := '';
  end;
end;

end.
