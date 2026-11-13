unit Pdf4D.Api.Document;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Api.Attachment.Interfaces,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Api.Field.Interfaces,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Encryption.AccessPermission,
  Pdf4D.Model.Document;

type
  TPdfDocument = class(TInterfacedObject, IPdfDocument)
  private
    FHandle: IPdfDocumentHandle;

    constructor Create(const Handle: IPdfDocumentHandle);

    class function OpenFile(const FileName: string): TFileStream; static;
    class function ReadStream(const Stream: TCosStream): TBytes; static;

  public
    // Loads a file. The document opens it for reading and keeps it open until the last interface of the document is
    // released. A file that cannot be opened raises EPdfFileException.
    class function Load(const FileName: string): IPdfDocument; overload; static;
    class function Load(const FileName: string; const Options: TPdfLoadOptions): IPdfDocument; overload; static;
    // The stream stays the property of the caller and must live as long as the document does
    class function Load(const Stream: TStream; const Options: TPdfLoadOptions): IPdfDocument; overload; static;

    function PageCount: Integer;
    function Pages: TArray<IPdfPage>;
    function Page(const Index: Integer): IPdfPage;
    function Version: Single;
    function IsEncrypted: Boolean;
    function Permissions: IPdfPermissions;
    function Info: IPdfDocumentInfo;
    function XmpMetadata: TBytes;
    function Outline: TArray<IPdfOutlineItem>;
    function Fields: TArray<IPdfField>;
    function Attachments: TArray<IPdfAttachment>;
    function CosDocument: TCosDocument;

    // The document of the model layer, for code that needs more than the interfaces give (the acceptance test that
    // compares with PDFBox reads the same objects PDFBox reads). Like CosDocument, it is valid as long as this document is.
    function ModelDocument: TPDDocument;
  end;

implementation

uses
  Pdf4D.Api.Attachment,
  Pdf4D.Api.Field,
  Pdf4D.Api.OutlineItem,
  Pdf4D.Api.Page,
  Pdf4D.Model.AcroForm,
  Pdf4D.Model.Outline,
  Pdf4D.Model.DocumentInformation;

type
  // A copy of the permissions of the inner layer, so that it does not depend on the document
  TPdfPermissions = class(TInterfacedObject, IPdfPermissions)
  private
    FPermission: TPdfAccessPermission;

  public
    constructor Create(const Source: TPdfAccessPermission);
    destructor Destroy; override;

    function CanPrint: Boolean;
    function CanModify: Boolean;
    function CanExtractContent: Boolean;
    function CanModifyAnnotations: Boolean;
    function CanFillInForm: Boolean;
    function CanExtractForAccessibility: Boolean;
    function CanAssembleDocument: Boolean;
    function CanPrintFaithful: Boolean;
    function IsOwnerPermission: Boolean;
    function Bits: Integer;
  end;

  TPdfDocumentInfo = class(TInterfacedObject, IPdfDocumentInfo)
  private
    FHandle: IPdfDocumentHandle;

    function Information: TPDDocumentInformation;

  public
    constructor Create(const Handle: IPdfDocumentHandle);

    function Title: string;
    function Author: string;
    function Subject: string;
    function Keywords: string;
    function Creator: string;
    function Producer: string;
    function TryGetCreationDate(out Value: TDateTime): Boolean; overload;
    function TryGetModificationDate(out Value: TDateTime): Boolean; overload;
    function TryGetCreationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean; overload;
    function TryGetModificationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean; overload;
    function Keys: TArray<string>;
    function TryGetValue(const Key: string; out Value: string): Boolean;
  end;

{ TPdfPermissions }

constructor TPdfPermissions.Create(const Source: TPdfAccessPermission);
begin
  inherited Create;
  FPermission := Source.Clone;
  FPermission.SetReadOnly;
end;

destructor TPdfPermissions.Destroy;
begin
  FPermission.Free;
  inherited;
end;

function TPdfPermissions.CanPrint: Boolean;
begin
  Result := FPermission.CanPrint;
end;

function TPdfPermissions.CanModify: Boolean;
begin
  Result := FPermission.CanModify;
end;

function TPdfPermissions.CanExtractContent: Boolean;
begin
  Result := FPermission.CanExtractContent;
end;

function TPdfPermissions.CanModifyAnnotations: Boolean;
begin
  Result := FPermission.CanModifyAnnotations;
end;

function TPdfPermissions.CanFillInForm: Boolean;
begin
  Result := FPermission.CanFillInForm;
end;

function TPdfPermissions.CanExtractForAccessibility: Boolean;
begin
  Result := FPermission.CanExtractForAccessibility;
end;

function TPdfPermissions.CanAssembleDocument: Boolean;
begin
  Result := FPermission.CanAssembleDocument;
end;

function TPdfPermissions.CanPrintFaithful: Boolean;
begin
  Result := FPermission.CanPrintFaithful;
end;

function TPdfPermissions.IsOwnerPermission: Boolean;
begin
  Result := FPermission.IsOwnerPermission;
end;

function TPdfPermissions.Bits: Integer;
begin
  Result := FPermission.PermissionBytes;
end;

{ TPdfDocumentInfo }

constructor TPdfDocumentInfo.Create(const Handle: IPdfDocumentHandle);
begin
  inherited Create;
  FHandle := Handle;
end;

function TPdfDocumentInfo.Information: TPDDocumentInformation;
begin
  Result := FHandle.Document.DocumentInformation;
end;

function TPdfDocumentInfo.Title: string;
begin
  Result := Information.Title;
end;

function TPdfDocumentInfo.Author: string;
begin
  Result := Information.Author;
end;

function TPdfDocumentInfo.Subject: string;
begin
  Result := Information.Subject;
end;

function TPdfDocumentInfo.Keywords: string;
begin
  Result := Information.Keywords;
end;

function TPdfDocumentInfo.Creator: string;
begin
  Result := Information.Creator;
end;

function TPdfDocumentInfo.Producer: string;
begin
  Result := Information.Producer;
end;

function TPdfDocumentInfo.TryGetCreationDate(out Value: TDateTime): Boolean;
begin
  var OffsetMinutes: Integer;
  Result := Information.TryGetCreationDate(Value, OffsetMinutes);
end;

function TPdfDocumentInfo.TryGetModificationDate(out Value: TDateTime): Boolean;
begin
  var OffsetMinutes: Integer;
  Result := Information.TryGetModificationDate(Value, OffsetMinutes);
end;

function TPdfDocumentInfo.TryGetCreationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Result := Information.TryGetCreationDate(Value, OffsetMinutes);
end;

function TPdfDocumentInfo.TryGetModificationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean;
begin
  Result := Information.TryGetModificationDate(Value, OffsetMinutes);
end;

function TPdfDocumentInfo.Keys: TArray<string>;
begin
  Result := Information.Keys;
end;

function TPdfDocumentInfo.TryGetValue(const Key: string; out Value: string): Boolean;
begin
  Result := Information.TryGetCustomValue(Key, Value);
end;

{ TPdfDocument }

constructor TPdfDocument.Create(const Handle: IPdfDocumentHandle);
begin
  inherited Create;
  FHandle := Handle;
end;

// A file that is missing or locked ends in an EPdfException like every other failure of a load, so that a caller needs
// one handler. The RTL raises EFOpenError (an EStreamError) for it.
class function TPdfDocument.OpenFile(const FileName: string): TFileStream;
begin
  try
    Result := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  except
    on Failure: EStreamError do
    begin
      raise EPdfFileException.CreateFmt('The file "%s" cannot be opened: %s', [FileName, Failure.Message]);
    end;
  end;
end;

class function TPdfDocument.Load(const FileName: string): IPdfDocument;
begin
  Result := Load(FileName, TPdfLoadOptions.Default);
end;

class function TPdfDocument.Load(const FileName: string; const Options: TPdfLoadOptions): IPdfDocument;
begin
  const Stream = OpenFile(FileName);
  var Document: TPDDocument;
  try
    Document := TPDDocument.Load(Stream, False, Options);
  except
    Stream.Free;
    raise;
  end;

  const Handle: IPdfDocumentHandle = TPdfDocumentHandle.Create(Document, Stream);
  Result := TPdfDocument.Create(Handle);
end;

class function TPdfDocument.Load(const Stream: TStream; const Options: TPdfLoadOptions): IPdfDocument;
begin
  const Document = TPDDocument.Load(Stream, False, Options);
  const Handle: IPdfDocumentHandle = TPdfDocumentHandle.Create(Document, nil);
  Result := TPdfDocument.Create(Handle);
end;

function TPdfDocument.PageCount: Integer;
begin
  Result := FHandle.Document.Pages.EnumeratedCount;
end;

function TPdfDocument.Pages: TArray<IPdfPage>;
begin
  const Tree = FHandle.Document.Pages;
  SetLength(Result, Tree.EnumeratedCount);
  for var Position := 0 to High(Result) do
  begin
    Result[Position] := TPdfPage.Create(FHandle, Tree.Get(Position), Position);
  end;
end;

function TPdfDocument.Page(const Index: Integer): IPdfPage;
begin
  const Count = PageCount;
  const IsInRange = ((Index >= 0) and (Index < Count));
  if not IsInRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Page index %d is outside the %d pages of the document', [Index, Count]);
  end;

  Result := TPdfPage.Create(FHandle, FHandle.Document.Pages.Get(Index), Index);
end;

function TPdfDocument.Version: Single;
begin
  Result := FHandle.Document.Version;
end;

function TPdfDocument.IsEncrypted: Boolean;
begin
  Result := FHandle.Document.IsEncrypted;
end;

function TPdfDocument.Permissions: IPdfPermissions;
begin
  Result := TPdfPermissions.Create(FHandle.Document.AccessPermission);
end;

function TPdfDocument.Info: IPdfDocumentInfo;
begin
  Result := TPdfDocumentInfo.Create(FHandle);
end;

function TPdfDocument.XmpMetadata: TBytes;
begin
  var Metadata: TCosStream;
  if FHandle.Document.Catalog.TryGetMetadata(Metadata) then
  begin
    Result := ReadStream(Metadata);
  end
  else
  begin
    Result := nil;
  end;
end;

class function TPdfDocument.ReadStream(const Stream: TCosStream): TBytes;
begin
  try
    const Decoded = Stream.CreateDecodedStream;
    try
      if Decoded.Size > High(Integer) then
      begin
        raise EPdfLimitExceededException.Create('The metadata stream is too large');
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
  except
    on Failure: EPdfException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      if not TPdfFailure.IsInputFailure(Failure) then
      begin
        raise;
      end;
      raise EPdfParseException.CreateFmt('The metadata stream cannot be read: %s', [Failure.Message]);
    end;
  end;
end;

function TPdfDocument.Outline: TArray<IPdfOutlineItem>;
begin
  var Root: TPDDocumentOutline;
  if FHandle.Document.Catalog.TryGetOutline(Root) then
  begin
    Result := TPdfOutlineItem.Wrap(FHandle, Root.Children);
  end
  else
  begin
    Result := nil;
  end;
end;

// One bad field does not end the listing of the others, but a form whose field list cannot be made is empty
function TPdfDocument.Fields: TArray<IPdfField>;
begin
  Result := nil;

  var Form: TPDAcroForm;
  if not FHandle.Document.Catalog.TryGetAcroForm(Form) then
  begin
    Exit;
  end;

  try
    Result := TPdfField.Wrap(FHandle, Form.Fields);
  except
    on Failure: EPdfException do
    begin
      FHandle.Log.Error('The fields of the form cannot be listed: %s', [Failure.Message]);
      Result := nil;
    end;
  end;
end;

function TPdfDocument.Attachments: TArray<IPdfAttachment>;
begin
  Result := TPdfAttachment.Wrap(FHandle, FHandle.Document.GetEmbeddedFiles);
end;

function TPdfDocument.CosDocument: TCosDocument;
begin
  Result := FHandle.Document.CosDocument;
end;

function TPdfDocument.ModelDocument: TPDDocument;
begin
  Result := FHandle.Document;
end;

end.
