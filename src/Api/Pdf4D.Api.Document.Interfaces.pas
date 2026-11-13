unit Pdf4D.Api.Document.Interfaces;

interface

uses
  System.SysUtils,
  Pdf4D.Api.Attachment.Interfaces,
  Pdf4D.Api.Field.Interfaces,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Cos.Document,
  Pdf4D.Encryption.AccessPermission;

type
  // The /Info dictionary. A text entry that is missing gives an empty string.
  IPdfDocumentInfo = interface
    ['{1A9C4E70-6B3D-4F25-8E1A-D07B5C92E468}']

    function Title: string;
    function Author: string;
    function Subject: string;
    function Keywords: string;
    function Creator: string;
    function Producer: string;
    // The wall clock time of the date, without its time zone. False when the entry is missing or is no date.
    function TryGetCreationDate(out Value: TDateTime): Boolean;
    function TryGetModificationDate(out Value: TDateTime): Boolean;
    // All keys in the order of the file
    function Keys: TArray<string>;
    function TryGetValue(const Key: string; out Value: string): Boolean;
  end;

  // A loaded document. It lives as long as any interface that came from it: a page, an outline item, a field or an
  // attachment keeps it alive, also when the IPdfDocument itself is released.
  //
  // Failures of the file itself end in an EPdfException descendant. An index outside the pages raises
  // EArgumentOutOfRangeException.
  IPdfDocument = interface
    ['{F6B2D834-0E71-4A9C-B5D3-3C8A1E7F9024}']

    function PageCount: Integer;
    function Pages: TArray<IPdfPage>;
    // Zero based
    function Page(const Index: Integer): IPdfPage;

    function Version: Single;
    function IsEncrypted: Boolean;
    // Owned by the document: do not free it
    function Permissions: TPdfAccessPermission;

    function Info: IPdfDocumentInfo;
    // The XMP metadata stream, empty when there is none
    function XmpMetadata: TBytes;

    // The bookmarks, empty when there is no outline
    function Outline: TArray<IPdfOutlineItem>;
    // The fields of the form itself, empty when there is no form
    function Fields: TArray<IPdfField>;
    function Attachments: TArray<IPdfAttachment>;

    // The document of the inner layer. It stays valid only as long as this interface (or any other interface of the
    // same document) is alive. The same holds for every object that you get from it.
    function CosDocument: TCosDocument;
  end;

implementation

end.
