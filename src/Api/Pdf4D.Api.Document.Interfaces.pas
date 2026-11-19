// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Document.Interfaces;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Api.Attachment.Interfaces,
  Pdf4D.Api.Field.Interfaces,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Api.TextOptions,
  Pdf4D.Cos.Document;

type
  // What the current user may do with the document: a copy of the permission bits of the encryption dictionary (all permissions
  // for a document without encryption). It does not depend on the document and stays valid after it is released.
  IPdfPermissions = interface
    ['{5D7E2A91-3C84-4B06-A1F5-9E0B6D4C8372}']

    function CanPrint: Boolean;
    function CanModify: Boolean;
    function CanExtractContent: Boolean;
    function CanModifyAnnotations: Boolean;
    function CanFillInForm: Boolean;
    function CanExtractForAccessibility: Boolean;
    function CanAssembleDocument: Boolean;
    function CanPrintFaithful: Boolean;
    function IsOwnerPermission: Boolean;
    // The bits as the /P entry holds them
    function Bits: Integer;
  end;

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
    function TryGetCreationDate(out Value: TDateTime): Boolean; overload;
    function TryGetModificationDate(out Value: TDateTime): Boolean; overload;
    // The same with the offset of the time zone of the date in minutes east of UTC (+01:00 is 60): Value minus OffsetMinutes
    // is the UTC time
    function TryGetCreationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean; overload;
    function TryGetModificationDate(out Value: TDateTime; out OffsetMinutes: Integer): Boolean; overload;
    // All keys in the order of the file
    function Keys: TArray<string>;
    function TryGetValue(const Key: string; out Value: string): Boolean;
  end;

  // A loaded document. It lives as long as any interface that came from it: a page, an outline item, a field or an
  // attachment keeps it alive, also when the IPdfDocument itself is released.
  //
  // Input problems (the file, its content) raise EPdfException descendants; invalid arguments raise EArgument* exceptions: an
  // index outside the pages raises EArgumentOutOfRangeException, and a bookmark of another document or one that this library
  // did not make raises EArgumentException. An exception of the Writer that is given to WriteText is raised as it was.
  IPdfDocument = interface
    ['{F6B2D834-0E71-4A9C-B5D3-3C8A1E7F9024}']

    function PageCount: Integer;
    function Pages: TArray<IPdfPage>;
    // Zero based
    function Page(const Index: Integer): IPdfPage;

    function Version: Single;
    function IsEncrypted: Boolean;
    function Permissions: IPdfPermissions;

    function Info: IPdfDocumentInfo;
    // The XMP metadata stream, empty when there is none
    function XmpMetadata: TBytes;

    // The bookmarks, empty when there is no outline
    function Outline: TArray<IPdfOutlineItem>;
    // The fields of the form itself, empty when there is no form
    function Fields: TArray<IPdfField>;
    function Attachments: TArray<IPdfAttachment>;

    // The text of all pages with the default options, as PDFBox's PDFTextStripper writes it, except that right-to-left text
    // comes in the order of the file (there is no bidi pass, see docs/porting.md)
    function ExtractText: string; overload;
    function ExtractText(const Options: TPdfTextOptions): string; overload;
    // Writes the text to Writer instead of returning it
    procedure WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);

    // The same text as ExtractText with the same options, with the place of every character. Raises the same exceptions as ExtractText.
    function ExtractTextWithPositions: IPdfPositionedText; overload;
    function ExtractTextWithPositions(const Options: TPdfTextOptions): IPdfPositionedText; overload;

    // The document of the inner layer. It stays valid only as long as this interface (or any other interface of the
    // same document) is alive. The same holds for every object that you get from it.
    function CosDocument: TCosDocument;
  end;

implementation

end.
