// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/filespecification/PDComplexFileSpecification.java and
// PDEmbeddedFile.java, pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDEmbeddedFilesNameTreeNode.java (3.0.8), the read
// side
unit Pdf4D.Model.EmbeddedFile;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary;

type
  // An entry of the name tree /Names /EmbeddedFiles: its key, its file specification and the stream of the file. It
  // does not own the dictionaries.
  TPDEmbeddedFile = class
  private
    FKey: string;
    FSpecification: TCosDictionary;

    function TryGetStream(out Stream: TCosStream): Boolean;
    function TryGetParamsDate(const Key: string; out Value: TDateTime; out OffsetMinutes: Integer): Boolean;

  public
    // Specification is the value in the tree, nil when that is a null: PDFBox makes an empty file specification then
    constructor Create(const Key: string; const Specification: TCosDictionary);

    // Port of PDEmbeddedFilesNameTreeNode.convertCOSToPD: a dictionary or a null, anything else raises EPdfParseException
    class function ConvertTreeValue(const Value: TCosBase): TCosBase; static;

    // Port of PDComplexFileSpecification.getFilename: the first of /UF, /DOS, /Mac, /Unix and /F that is a string
    function TryGetFilename(out FileName: string): Boolean;

    // The filename of the specification, and the key in the name tree when it has none
    function FileName: string;

    // Port of getFileDescription, /Desc of the specification
    function TryGetDescription(out Description: string): Boolean;
    function Description: string;

    // Port of PDComplexFileSpecification.getEmbeddedFile: the stream /EF /F. False when there is none: the other
    // streams of /EF (/UF, /DOS, /Mac, /Unix) are not looked at, as in PDFBox.
    function HasEmbeddedStream: Boolean;

    // /Subtype of the stream, the media type. False without stream or without /Subtype.
    function TryGetSubtype(out Subtype: string): Boolean;

    // Port of PDEmbeddedFile.getSize: /Params /Size of the stream when it is 0 or more. The length of the stream is not
    // used. False without stream.
    function TryGetSize(out Size: Integer): Boolean;

    // Port of getCreationDate and getModDate, as in TPDDocumentInformation
    function TryGetCreationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
    function TryGetModDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;

    // The data of the file, decoded through the filters of the stream. Raises EPdfParseException when the entry has no
    // stream, and the exceptions of TCosStream.CreateDecodedStream, among them EPdfLimitExceededException when the data
    // is larger than the limit of the document.
    function GetData: TBytes;

    property Key: string read FKey;
    property CosObject: TCosDictionary read FSpecification;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfString,
  Pdf4D.Model.DateConverter;

{ TPDEmbeddedFile }

constructor TPDEmbeddedFile.Create(const Key: string; const Specification: TCosDictionary);
begin
  inherited Create;
  FKey := Key;
  FSpecification := Specification;
end;

class function TPDEmbeddedFile.ConvertTreeValue(const Value: TCosBase): TCosBase;
begin
  if Assigned(Value) and not (Value is TCosDictionary) then
  begin
    raise EPdfParseException.Create('A dictionary is expected as value of an embedded file in the name tree');
  end;
  Result := Value;
end;

function TPDEmbeddedFile.TryGetFilename(out FileName: string): Boolean;
begin
  FileName := '';
  if not Assigned(FSpecification) then
  begin
    Exit(False);
  end;

  Result := (FSpecification.TryGetString(TCosNames.UF, FileName) or
             FSpecification.TryGetString(TCosNames.DOS, FileName) or
             FSpecification.TryGetString(TCosNames.Mac, FileName) or
             FSpecification.TryGetString(TCosNames.Unix, FileName) or
             FSpecification.TryGetString(TCosNames.F, FileName));
end;

function TPDEmbeddedFile.FileName: string;
begin
  if not TryGetFilename(Result) then
  begin
    Result := FKey;
  end;
end;

function TPDEmbeddedFile.TryGetDescription(out Description: string): Boolean;
begin
  Description := '';
  Result := (Assigned(FSpecification) and FSpecification.TryGetString(TCosNames.Desc, Description));
end;

function TPDEmbeddedFile.Description: string;
begin
  if not TryGetDescription(Result) then
  begin
    Result := '';
  end;
end;

function TPDEmbeddedFile.TryGetStream(out Stream: TCosStream): Boolean;
begin
  Stream := nil;
  var Files: TCosDictionary;
  Result := (Assigned(FSpecification) and FSpecification.TryGetCosDictionary(TCosNames.EF, Files) and
             Files.TryGetCosStream(TCosNames.F, Stream));
end;

function TPDEmbeddedFile.HasEmbeddedStream: Boolean;
begin
  var Stream: TCosStream;
  Result := TryGetStream(Stream);
end;

function TPDEmbeddedFile.TryGetSubtype(out Subtype: string): Boolean;
begin
  Subtype := '';
  var Stream: TCosStream;
  var Raw: TCosBase;
  Result := (TryGetStream(Stream) and Stream.TryGetDictionaryObject(TCosNames.Subtype, Raw) and
             ((Raw is TCosName) or (Raw is TCosString)));
  if Result then
  begin
    Subtype := Stream.GetNameAsString(TCosNames.Subtype, '');
  end;
end;

function TPDEmbeddedFile.TryGetSize(out Size: Integer): Boolean;
begin
  Size := -1;
  var Stream: TCosStream;
  var Params: TCosDictionary;
  if TryGetStream(Stream) and Stream.TryGetCosDictionary(TCosNames.Params, Params) then
  begin
    Size := Params.GetInt(TCosNames.Size, -1);
  end;
  Result := (Size >= 0);
end;

function TPDEmbeddedFile.TryGetParamsDate(const Key: string; out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Value := 0;
  OffsetMinutes := 0;
  var Stream: TCosStream;
  var Params: TCosDictionary;
  var Item: TCosBase;
  // Port of COSDictionary.getDate: only a string can hold a date
  Result := (TryGetStream(Stream) and Stream.TryGetCosDictionary(TCosNames.Params, Params) and
             Params.TryGetDictionaryObject(Key, Item) and (Item is TCosString) and
             TDateConverter.TryParse(TCosString(Item).GetString, Value, OffsetMinutes));
end;

function TPDEmbeddedFile.TryGetCreationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Result := TryGetParamsDate(TCosNames.CreationDate, Value, OffsetMinutes);
end;

function TPDEmbeddedFile.TryGetModDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Result := TryGetParamsDate(TCosNames.ModDate, Value, OffsetMinutes);
end;

function TPDEmbeddedFile.GetData: TBytes;
begin
  var Stream: TCosStream;
  if not TryGetStream(Stream) then
  begin
    raise EPdfParseException.CreateFmt('The entry "%s" has no embedded file stream', [FKey]);
  end;

  const Decoded = Stream.CreateDecodedStream;
  try
    if Decoded.Size > High(Integer) then
    begin
      raise EPdfLimitExceededException.CreateFmt('The embedded file "%s" is too large', [FKey]);
    end;
    SetLength(Result, Decoded.Size);
    if Length(Result) > 0 then
    begin
      Decoded.Position := 0;
      Decoded.ReadBuffer(Result[0], Length(Result));
    end;
  finally
    Decoded.Free;
  end;
end;

end.
