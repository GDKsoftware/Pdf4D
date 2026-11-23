// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.DocumentHandle;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Pdf4D.Api.GuardedWriter,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextOptions,
  Pdf4D.Common.Log,
  Pdf4D.Common.Quad,
  Pdf4D.Cos.Base,
  Pdf4D.Model.Annotation,
  Pdf4D.Model.Document,
  Pdf4D.Model.OutlineItem,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle,
  Pdf4D.Text.PositionedText,
  Pdf4D.Text.Stripper;

type
  // What every API object holds to keep the document alive. The handle never holds an API object, so there is no cycle.
  IPdfDocumentHandle = interface
    ['{9B4E1C63-D2A8-4075-A6F1-0C5D8B37E9A2}']

    function Document: TPDDocument;
    function Log: TPdfLog;
    function PageLabel(const Index: Integer): string;
    procedure WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);
    // The caller owns the result
    function ExtractPositioned(const Options: TPdfTextOptions): TPdfPositionedText;
    // The links of a page (PageIndex is its position in the page tree), see IPdfPage.Links
    function ReadLinks(const Page: TPDPage; const PageIndex: Integer): TArray<TPdfLink>;
  end;

  // Owns the document and, when the document was loaded from a file, the stream
  TPdfDocumentHandle = class(TInterfacedObject, IPdfDocumentHandle)
  private
    FDocument: TPDDocument;
    FOwnedStream: TStream;
    FLabels: TArray<string>;
    FAreLabelsBuilt: Boolean;
{$IFDEF PDF4D_TESTS}
    class var FStripperHook: TProc;
{$ENDIF}

    procedure BuildLabels;
    function ReadLabels: TArray<string>;
    function ModelItemOf(const Bookmark: IPdfOutlineItem): TPDOutlineItem;
    class procedure RaiseWriterFailure(const Writer: TPdfGuardedWriter); static;
    // The failure of the file that an EPdfException does not describe yet, as an EPdfParseException. Nil for an EPdfException and for
    // everything that is no input failure: those are raised as they are.
    class function TranslatedFailure(const Failure: Exception): Exception; static;
    class procedure RaiseTranslated(const Failure: Exception); static;
    procedure WriteTextInStripper(const Writer: TTextWriter; const Options: TPdfTextOptions);
    function ExtractPositionedInStripper(const Options: TPdfTextOptions): TPdfPositionedText;
    procedure ConfigureStripper(const Stripper: TPdfTextStripper; const Options: TPdfTextOptions);
    function ReadLinksOfPage(const Page: TPDPage; const PageIndex: Integer): TArray<TPdfLink>;
    function TryBuildLink(const Annotation: TPDAnnotation; const PageIndex: Integer; out Link: TPdfLink): Boolean;
    function TryResolveTarget(const Destination: TCosBase; out TargetPageIndex: Integer): Boolean;
    class function QuadsOf(const Annotation: TPDAnnotation): TArray<TPdfQuad>; static;
    class function QuadsOfPoints(const Points: TArray<Single>): TArray<TPdfQuad>; static;
    class function LimitedPoint(const X, Y: Single): TPointF; static;
    class function LimitedValue(const Value: Single): Single; static;
    class function QuadOfRect(const Rect: TPdfRectangle): TPdfQuad; static;

  public
    // OwnedStream may be nil. Both are freed with the handle, the document first.
    constructor Create(const Document: TPDDocument; const OwnedStream: TStream);
    destructor Destroy; override;

    function Document: TPDDocument;
    function Log: TPdfLog;
    function PageLabel(const Index: Integer): string;
    procedure WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);
    function ExtractPositioned(const Options: TPdfTextOptions): TPdfPositionedText;
    function ReadLinks(const Page: TPDPage; const PageIndex: Integer): TArray<TPdfLink>;

{$IFDEF PDF4D_TESTS}
    // For tests only, compiled when PDF4D_TESTS is defined: runs when a stripper is set up, inside the code that translates failures.
    // Set before use, reset to nil afterwards.
    class property StripperHook: TProc read FStripperHook write FStripperHook;
{$ENDIF}
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Pdf4D.Api.OutlineItem,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Names,
  Pdf4D.Model.PageLabels,
  Pdf4D.Text.PositionStripper;

const
  LinkSubType = 'Link';
  QuadPointCount = 8;
  // The limit that /Rect values get (a Java int), so that a quad of a link is as big as its rectangle can be
  MaxQuadValue = 2147483647;

{ TPdfDocumentHandle }

constructor TPdfDocumentHandle.Create(const Document: TPDDocument; const OwnedStream: TStream);
begin
  inherited Create;
  FDocument := Document;
  FOwnedStream := OwnedStream;
end;

destructor TPdfDocumentHandle.Destroy;
begin
  FDocument.Free;
  FOwnedStream.Free;
  inherited;
end;

function TPdfDocumentHandle.Document: TPDDocument;
begin
  Result := FDocument;
end;

function TPdfDocumentHandle.Log: TPdfLog;
begin
  Result := FDocument.CosDocument.Log;
end;

function TPdfDocumentHandle.PageLabel(const Index: Integer): string;
begin
  BuildLabels;

  const IsKnown = ((Index >= 0) and (Index < Length(FLabels)));
  if IsKnown then
  begin
    Result := FLabels[Index];
  end
  else
  begin
    Result := '';
  end;
end;

procedure TPdfDocumentHandle.BuildLabels;
begin
  if not FAreLabelsBuilt then
  begin
    FLabels := ReadLabels;
    FAreLabelsBuilt := True;
  end;
end;

// A document whose labels cannot be made still has pages: the labels are empty and the problem goes to the log
function TPdfDocumentHandle.ReadLabels: TArray<string>;
begin
  Result := nil;

  var Dictionary: TCosDictionary;
  if not FDocument.Catalog.TryGetPageLabels(Dictionary) then
  begin
    Exit;
  end;

  try
    const PageLabels = TPDPageLabels.Create(FDocument, Dictionary);
    try
      Result := PageLabels.GetLabelsByPageIndices;
    finally
      PageLabels.Free;
    end;
  except
    on Failure: EPdfException do
    begin
      Log.Error('The page labels cannot be made: %s', [Failure.Message]);
      Result := nil;
    end;
  end;
end;

// A bookmark that is not one of this document is a mistake of the caller
function TPdfDocumentHandle.ModelItemOf(const Bookmark: IPdfOutlineItem): TPDOutlineItem;
begin
  if not Assigned(Bookmark) then
  begin
    Exit(nil);
  end;

  if not (Bookmark is TPdfOutlineItem) then
  begin
    raise EArgumentException.Create('The bookmark does not come from this library');
  end;

  const Item = (Bookmark as TPdfOutlineItem);
  if (Item.Handle as TObject) <> Self then
  begin
    raise EArgumentException.Create('The bookmark belongs to another document');
  end;
  Result := Item.ModelItem;
end;

procedure TPdfDocumentHandle.WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);
begin
  if not Assigned(Writer) then
  begin
    raise EArgumentNilException.Create('Writer');
  end;

  const Guarded = TPdfGuardedWriter.Create(Writer);
  try
    try
      WriteTextInStripper(Guarded, Options);
    except
      on Failure: EPdfException do
      begin
        RaiseWriterFailure(Guarded);
        raise;
      end;
      on Failure: Exception do
      begin
        RaiseWriterFailure(Guarded);
        RaiseTranslated(Failure);
        raise;
      end;
    end;
    RaiseWriterFailure(Guarded);
  finally
    Guarded.Free;
  end;
end;

// The exception of the writer of the caller comes back as it was, not as a failure of the file
class procedure TPdfDocumentHandle.RaiseWriterFailure(const Writer: TPdfGuardedWriter);
begin
  if Writer.HasFailure then
  begin
    raise Writer.TakeFailure;
  end;
end;

function TPdfDocumentHandle.ExtractPositioned(const Options: TPdfTextOptions): TPdfPositionedText;
begin
  try
    Result := ExtractPositionedInStripper(Options);
  except
    on Failure: EPdfException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      RaiseTranslated(Failure);
      raise;
    end;
  end;
end;

function TPdfDocumentHandle.ReadLinks(const Page: TPDPage; const PageIndex: Integer): TArray<TPdfLink>;
begin
  try
    Result := ReadLinksOfPage(Page, PageIndex);
  except
    on Failure: EPdfException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      if TPdfFailure.IsInputFailure(Failure) then
      begin
        raise EPdfParseException.CreateFmt('The links cannot be read: %s', [Failure.Message]);
      end;
      raise;
    end;
  end;
end;

function TPdfDocumentHandle.ReadLinksOfPage(const Page: TPDPage; const PageIndex: Integer): TArray<TPdfLink>;
begin
  const Links = TList<TPdfLink>.Create;
  try
    const Annotations = Page.Annotations;
    try
      for var Annotation in Annotations do
      begin
        var Link: TPdfLink;
        const IsLink = ((Annotation.SubType = LinkSubType) and TryBuildLink(Annotation, PageIndex, Link));
        if IsLink then
        begin
          Links.Add(Link);
        end;
      end;
    finally
      Annotations.Free;
    end;
    Result := Links.ToArray;
  finally
    Links.Free;
  end;
end;

function TPdfDocumentHandle.TryBuildLink(const Annotation: TPDAnnotation; const PageIndex: Integer; out Link: TPdfLink): Boolean;
begin
  Link := Default(TPdfLink);
  Link.PageIndex := PageIndex;

  if not Annotation.HasRect then
  begin
    Log.Warning('A link on page %d is skipped: it has no valid /Rect', [PageIndex + 1]);
    Exit(False);
  end;
  Link.Quads := QuadsOf(Annotation);

  var Destination: TCosBase;
  if Annotation.TryGetDestination(Destination) then
  begin
    var TargetPageIndex: Integer;
    Result := TryResolveTarget(Destination, TargetPageIndex);
    if Result then
    begin
      Link.Kind := TPdfLinkKind.GoTo;
      Link.TargetPageIndex := TargetPageIndex;
    end
    else
    begin
      Log.Warning('A link on page %d is skipped: its destination is no page of the document', [PageIndex + 1]);
    end;
    Exit;
  end;

  if Annotation.TryGetUri(Link.Uri) then
  begin
    Link.Kind := TPdfLinkKind.Uri;
    Exit(True);
  end;

  // A GoTo without /D and a URI without a string are broken actions, not actions this viewer does not know
  const ActionType = Annotation.ActionType;
  const IsBrokenAction = (ActionType = TCosNames.GoTo_) or (ActionType = TCosNames.URI);
  if IsBrokenAction then
  begin
    Log.Warning('A link on page %d is skipped: its %s action is incomplete', [PageIndex + 1, ActionType]);
    Exit(False);
  end;

  Link.Kind := TPdfLinkKind.Other;
  Result := Annotation.HasAction;
  if not Result then
  begin
    Log.Warning('A link on page %d is skipped: it has no destination and no action', [PageIndex + 1]);
  end;
end;

function TPdfDocumentHandle.TryResolveTarget(const Destination: TCosBase; out TargetPageIndex: Integer): Boolean;
begin
  const Resolver = FDocument.Catalog.DestinationResolver;
  Result := Resolver.TryResolvePageIndex(Destination, TargetPageIndex);
end;

// QuadPoints that are no whole number of quads, or hold a value that is not finite, are no reason to lose the link: the /Rect is used
class function TPdfDocumentHandle.QuadsOf(const Annotation: TPDAnnotation): TArray<TPdfQuad>;
begin
  Result := QuadsOfPoints(Annotation.QuadPoints);

  var AreAllFinite := (Length(Result) > 0);
  for var Quad in Result do
  begin
    AreAllFinite := (AreAllFinite and Quad.IsFinite);
  end;

  if not AreAllFinite then
  begin
    Result := [QuadOfRect(Annotation.Rect)];
  end;
end;

// The points in the files of real viewers run top left, top right, bottom left, bottom right, not counterclockwise as the specification
// says; a quad of the text layout starts at the bottom left
class function TPdfDocumentHandle.QuadsOfPoints(const Points: TArray<Single>): TArray<TPdfQuad>;
begin
  SetLength(Result, Length(Points) div QuadPointCount);
  for var Index := 0 to High(Result) do
  begin
    const Start = Index * QuadPointCount;
    const TopLeft = LimitedPoint(Points[Start], Points[Start + 1]);
    const TopRight = LimitedPoint(Points[Start + 2], Points[Start + 3]);
    const BottomLeft = LimitedPoint(Points[Start + 4], Points[Start + 5]);
    const BottomRight = LimitedPoint(Points[Start + 6], Points[Start + 7]);
    Result[Index] := TPdfQuad.Create(BottomLeft, BottomRight, TopRight, TopLeft);
  end;
end;

// A finite value beyond what /Rect allows is limited the same way; a value that is not finite stays, so that QuadsOf can see it
class function TPdfDocumentHandle.LimitedPoint(const X, Y: Single): TPointF;
begin
  Result := TPointF.Create(LimitedValue(X), LimitedValue(Y));
end;

class function TPdfDocumentHandle.LimitedValue(const Value: Single): Single;
begin
  if Value.IsNan or Value.IsInfinity then
  begin
    Exit(Value);
  end;

  Result := EnsureRange(Value, -MaxQuadValue, MaxQuadValue);
end;

class function TPdfDocumentHandle.QuadOfRect(const Rect: TPdfRectangle): TPdfQuad;
begin
  Result := TPdfQuad.Create(TPointF.Create(Rect.LowerLeftX, Rect.LowerLeftY),
                            TPointF.Create(Rect.UpperRightX, Rect.LowerLeftY),
                            TPointF.Create(Rect.UpperRightX, Rect.UpperRightY),
                            TPointF.Create(Rect.LowerLeftX, Rect.UpperRightY));
end;

class function TPdfDocumentHandle.TranslatedFailure(const Failure: Exception): Exception;
begin
  const IsTranslated = ((not (Failure is EPdfException)) and TPdfFailure.IsInputFailure(Failure));
  if IsTranslated then
  begin
    Result := EPdfParseException.CreateFmt('The text cannot be extracted: %s', [Failure.Message]);
  end
  else
  begin
    Result := nil;
  end;
end;

class procedure TPdfDocumentHandle.RaiseTranslated(const Failure: Exception);
begin
  const Translated = TranslatedFailure(Failure);
  if Assigned(Translated) then
  begin
    raise Translated;
  end;
end;

function TPdfDocumentHandle.ExtractPositionedInStripper(const Options: TPdfTextOptions): TPdfPositionedText;
begin
  const Stripper = TPdfPositionStripper.Create;
  try
    ConfigureStripper(Stripper, Options);

    Result := Stripper.Extract(FDocument);
  finally
    Stripper.Free;
  end;
end;

procedure TPdfDocumentHandle.WriteTextInStripper(const Writer: TTextWriter; const Options: TPdfTextOptions);
begin
  const Stripper = TPdfTextStripper.Create;
  try
    ConfigureStripper(Stripper, Options);

    Stripper.WriteText(FDocument, Writer);
  finally
    Stripper.Free;
  end;
end;

procedure TPdfDocumentHandle.ConfigureStripper(const Stripper: TPdfTextStripper; const Options: TPdfTextOptions);
begin
{$IFDEF PDF4D_TESTS}
  if Assigned(FStripperHook) then
  begin
    FStripperHook;
  end;

{$ENDIF}
  Stripper.SortByPosition := Options.SortByPosition;
  Stripper.StartPage := Options.StartPage;
  Stripper.EndPage := Options.EndPage;
  Stripper.StartBookmark := ModelItemOf(Options.StartBookmark);
  Stripper.EndBookmark := ModelItemOf(Options.EndBookmark);
  Stripper.SuppressDuplicateOverlappingText := Options.SuppressDuplicateOverlappingText;
  Stripper.ShouldSeparateByBeads := Options.ShouldSeparateByBeads;
  Stripper.AddMoreFormatting := Options.AddMoreFormatting;
  Stripper.IgnoreContentStreamSpaceGlyphs := Options.IgnoreContentStreamSpaceGlyphs;
  Stripper.LineSeparator := Options.LineSeparator;
  Stripper.WordSeparator := Options.WordSeparator;
  Stripper.ParagraphStart := Options.ParagraphStart;
  Stripper.ParagraphEnd := Options.ParagraphEnd;
  Stripper.PageStart := Options.PageStart;
  Stripper.PageEnd := Options.PageEnd;
  Stripper.ArticleStart := Options.ArticleStart;
  Stripper.ArticleEnd := Options.ArticleEnd;
  Stripper.SpacingTolerance := Options.SpacingTolerance;
  Stripper.AverageCharTolerance := Options.AverageCharTolerance;
  Stripper.IndentThreshold := Options.IndentThreshold;
  Stripper.DropThreshold := Options.DropThreshold;
end;

end.
