// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Commands;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.PageViewController;

type
  {$SCOPEDENUMS ON}
  TPdfViewerCommand = (FirstPage, PriorPage, NextPage, LastPage, ZoomIn, ZoomOut, ZoomFitWidth, ZoomFitPage, RotateClockwise,
                       RotateCounterclockwise, Copy, Print, Search);
  {$SCOPEDENUMS OFF}

  // The text of a zoom in a zoom list: the name of a fit mode, or a percentage
  TPdfZoomText = record
  private
    class function StepIndex(const Percentage: Integer): Integer; static;

  public
    // The fit modes, then the percentages of PdfZoomSteps
    class function Items: TArray<string>; static;
    // The position of the zoom in Items; -1 for a factor between the steps
    class function IndexOf(const Mode: TPdfZoomMode; const Zoom: Single): Integer; static;
    // 'Fit width', 'Fit page' or the factor as a whole percentage ('125%')
    class function Format(const Mode: TPdfZoomMode; const Zoom: Single): string; static;
    // The name of a fit mode, or a percentage above zero with or without '%'; spaces around it do not count. Zoom is the factor for
    // TPdfZoomMode.Factor.
    class function TryParse(const Text: string; out Mode: TPdfZoomMode; out Zoom: Single): Boolean; static;
  end;

  // When the commands of a viewer apply and what they do, for the actions and toolbars of every framework. Document is the document that
  // a command works on; Controller is the page view of the zoom, rotate and copy commands, and may be nil for the others.
  TPdfViewerCommands = class
  public
    class function IsOpen(const Document: TPdf4DCustomDocument): Boolean; static;
    class function CanExecute(const Command: TPdfViewerCommand; const Document: TPdf4DCustomDocument;
                              const Controller: TPdfPageViewController): Boolean; static;
    // The fit commands are checked while the page view has their mode
    class function IsChecked(const Command: TPdfViewerCommand; const Controller: TPdfPageViewController): Boolean; static;
    // Runs a command on the document or the page view. Copy, Print and Search need the clipboard, a dialog or a search bar of the
    // framework: for them it raises EPdfViewerException. Raises EInvalidOpException when CanExecute is False.
    class procedure Execute(const Command: TPdfViewerCommand; const Document: TPdf4DCustomDocument;
                            const Controller: TPdfPageViewController); static;

    // The page number field: the number of the current page, empty while the document is not open
    class function PageNumberText(const Document: TPdf4DCustomDocument): string; static;
    // ' / 3' after the page number field
    class function PageCountText(const Document: TPdf4DCustomDocument): string; static;
    // Goes to the page with this number (1-based, spaces do not count); False for a text that is no page of the open document
    class function TryGoToPageNumber(const Document: TPdf4DCustomDocument; const Text: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Viewer.ResourceStrings;

const
  PercentSign = '%';
  FitWidthItem = 0;
  FitPageItem = 1;
  FirstStepItem = 2;
  UnsupportedZoomMode = 'Unsupported zoom mode: %d';
  UnsupportedCommand = 'Unsupported viewer command: %d';

{ TPdfZoomText }

class function TPdfZoomText.StepIndex(const Percentage: Integer): Integer;
begin
  Result := -1;
  for var Index := Low(PdfZoomSteps) to High(PdfZoomSteps) do
  begin
    if PdfZoomSteps[Index] = Percentage then
    begin
      Exit(Index);
    end;
  end;
end;

class function TPdfZoomText.Items: TArray<string>;
begin
  Result := [SZoomFitWidth, SZoomFitPage];
  for var Percentage in PdfZoomSteps do
  begin
    Result := Result + [Percentage.ToString + PercentSign];
  end;
end;

class function TPdfZoomText.IndexOf(const Mode: TPdfZoomMode; const Zoom: Single): Integer;
begin
  case Mode of
    TPdfZoomMode.FitWidth:
      Result := FitWidthItem;
    TPdfZoomMode.FitPage:
      Result := FitPageItem;
    TPdfZoomMode.Factor:
      begin
        const Step = StepIndex(Round(Zoom * PercentPerFactor));
        Result := -1;
        if Step >= 0 then
        begin
          Result := FirstStepItem + Step;
        end;
      end;
  else
    raise ENotSupportedException.CreateFmt(UnsupportedZoomMode, [Ord(Mode)]);
  end;
end;

class function TPdfZoomText.Format(const Mode: TPdfZoomMode; const Zoom: Single): string;
begin
  case Mode of
    TPdfZoomMode.FitWidth:
      Result := SZoomFitWidth;
    TPdfZoomMode.FitPage:
      Result := SZoomFitPage;
    TPdfZoomMode.Factor:
      Result := Round(Zoom * PercentPerFactor).ToString + PercentSign;
  else
    raise ENotSupportedException.CreateFmt(UnsupportedZoomMode, [Ord(Mode)]);
  end;
end;

class function TPdfZoomText.TryParse(const Text: string; out Mode: TPdfZoomMode; out Zoom: Single): Boolean;
begin
  Mode := TPdfZoomMode.Factor;
  Zoom := 0;
  const Trimmed = Text.Trim;

  if SameText(Trimmed, SZoomFitWidth) then
  begin
    Mode := TPdfZoomMode.FitWidth;
    Exit(True);
  end;

  if SameText(Trimmed, SZoomFitPage) then
  begin
    Mode := TPdfZoomMode.FitPage;
    Exit(True);
  end;

  var Percentage: Double;
  const Number = Trimmed.TrimRight([PercentSign]).Trim;
  Result := TryStrToFloat(Number, Percentage) and (Percentage > 0);
  if Result then
  begin
    Zoom := Percentage / PercentPerFactor;
  end;
end;

{ TPdfViewerCommands }

class function TPdfViewerCommands.IsOpen(const Document: TPdf4DCustomDocument): Boolean;
begin
  Result := Assigned(Document) and (Document.State = TPdfDocumentState.Open);
end;

class function TPdfViewerCommands.CanExecute(const Command: TPdfViewerCommand; const Document: TPdf4DCustomDocument;
                                             const Controller: TPdfPageViewController): Boolean;
begin
  if not IsOpen(Document) then
  begin
    Exit(False);
  end;

  case Command of
    TPdfViewerCommand.FirstPage, TPdfViewerCommand.PriorPage:
      Result := (Document.CurrentPage > 0);
    TPdfViewerCommand.NextPage, TPdfViewerCommand.LastPage:
      Result := (Document.CurrentPage < Document.PageCount - 1);
    TPdfViewerCommand.ZoomIn, TPdfViewerCommand.ZoomOut, TPdfViewerCommand.ZoomFitWidth, TPdfViewerCommand.ZoomFitPage,
    TPdfViewerCommand.RotateClockwise, TPdfViewerCommand.RotateCounterclockwise:
      Result := Assigned(Controller);
    TPdfViewerCommand.Copy:
      begin
        var Selection: TPdfTextSelection;
        Result := Assigned(Controller) and Document.CanCopy and Controller.TryGetSelection(Selection);
      end;
    TPdfViewerCommand.Print:
      Result := Document.CanPrint;
    TPdfViewerCommand.Search:
      Result := True;
  else
    raise ENotSupportedException.CreateFmt(UnsupportedCommand, [Ord(Command)]);
  end;
end;

class function TPdfViewerCommands.IsChecked(const Command: TPdfViewerCommand; const Controller: TPdfPageViewController): Boolean;
begin
  Result := False;
  if not Assigned(Controller) then
  begin
    Exit;
  end;

  if Command = TPdfViewerCommand.ZoomFitWidth then
  begin
    Result := (Controller.ZoomMode = TPdfZoomMode.FitWidth);
  end
  else if Command = TPdfViewerCommand.ZoomFitPage then
  begin
    Result := (Controller.ZoomMode = TPdfZoomMode.FitPage);
  end;
end;

class procedure TPdfViewerCommands.Execute(const Command: TPdfViewerCommand; const Document: TPdf4DCustomDocument;
                                           const Controller: TPdfPageViewController);
begin
  const IsFrameworkCommand = (Command in [TPdfViewerCommand.Copy, TPdfViewerCommand.Print, TPdfViewerCommand.Search]);
  if IsFrameworkCommand then
  begin
    raise EPdfViewerException.CreateFmt('Viewer command %d is run by the framework', [Ord(Command)]);
  end;

  if not CanExecute(Command, Document, Controller) then
  begin
    raise EInvalidOpException.CreateFmt('Viewer command %d does not apply now', [Ord(Command)]);
  end;

  case Command of
    TPdfViewerCommand.FirstPage:
      Document.CurrentPage := 0;
    TPdfViewerCommand.PriorPage:
      Document.CurrentPage := Document.CurrentPage - 1;
    TPdfViewerCommand.NextPage:
      Document.CurrentPage := Document.CurrentPage + 1;
    TPdfViewerCommand.LastPage:
      Document.CurrentPage := Document.PageCount - 1;
    TPdfViewerCommand.ZoomIn:
      Controller.ZoomIn;
    TPdfViewerCommand.ZoomOut:
      Controller.ZoomOut;
    TPdfViewerCommand.ZoomFitWidth:
      Controller.ZoomMode := TPdfZoomMode.FitWidth;
    TPdfViewerCommand.ZoomFitPage:
      Controller.ZoomMode := TPdfZoomMode.FitPage;
    TPdfViewerCommand.RotateClockwise:
      Controller.RotateClockwise;
    TPdfViewerCommand.RotateCounterclockwise:
      Controller.RotateCounterclockwise;
  else
    raise ENotSupportedException.CreateFmt(UnsupportedCommand, [Ord(Command)]);
  end;
end;

class function TPdfViewerCommands.PageNumberText(const Document: TPdf4DCustomDocument): string;
begin
  Result := '';
  if IsOpen(Document) then
  begin
    Result := (Document.CurrentPage + 1).ToString;
  end;
end;

class function TPdfViewerCommands.PageCountText(const Document: TPdf4DCustomDocument): string;
begin
  var Count := 0;
  if IsOpen(Document) then
  begin
    Count := Document.PageCount;
  end;
  Result := System.SysUtils.Format(SPageCountOf, [Count]);
end;

class function TPdfViewerCommands.TryGoToPageNumber(const Document: TPdf4DCustomDocument; const Text: string): Boolean;
begin
  var Number := 0;
  Result := IsOpen(Document) and TryStrToInt(Text.Trim, Number) and InRange(Number, 1, Document.PageCount);
  if Result then
  begin
    Document.CurrentPage := Number - 1;
  end;
end;

end.
