// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.DocumentHandle;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Api.GuardedWriter,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.TextOptions,
  Pdf4D.Common.Log,
  Pdf4D.Model.Document,
  Pdf4D.Model.OutlineItem;

type
  // What every API object holds to keep the document alive. The handle never holds an API object, so there is no cycle.
  IPdfDocumentHandle = interface
    ['{9B4E1C63-D2A8-4075-A6F1-0C5D8B37E9A2}']

    function Document: TPDDocument;
    function Log: TPdfLog;
    function PageLabel(const Index: Integer): string;
    procedure WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);
  end;

  // Owns the document and, when the document was loaded from a file, the stream
  TPdfDocumentHandle = class(TInterfacedObject, IPdfDocumentHandle)
  private
    FDocument: TPDDocument;
    FOwnedStream: TStream;
    FLabels: TArray<string>;
    FAreLabelsBuilt: Boolean;

    procedure BuildLabels;
    function ReadLabels: TArray<string>;
    function ModelItemOf(const Bookmark: IPdfOutlineItem): TPDOutlineItem;
    class procedure RaiseWriterFailure(const Writer: TPdfGuardedWriter); static;
    procedure WriteTextInStripper(const Writer: TTextWriter; const Options: TPdfTextOptions);

  public
    // OwnedStream may be nil. Both are freed with the handle, the document first.
    constructor Create(const Document: TPDDocument; const OwnedStream: TStream);
    destructor Destroy; override;

    function Document: TPDDocument;
    function Log: TPdfLog;
    function PageLabel(const Index: Integer): string;
    procedure WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);
  end;

implementation

uses
  Pdf4D.Api.OutlineItem,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.PageLabels,
  Pdf4D.Text.Stripper;

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
        if not TPdfFailure.IsInputFailure(Failure) then
        begin
          raise;
        end;
        raise EPdfParseException.CreateFmt('The text cannot be extracted: %s', [Failure.Message]);
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

procedure TPdfDocumentHandle.WriteTextInStripper(const Writer: TTextWriter; const Options: TPdfTextOptions);
begin
  const Stripper = TPdfTextStripper.Create;
  try
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

    Stripper.WriteText(FDocument, Writer);
  finally
    Stripper.Free;
  end;
end;

end.
