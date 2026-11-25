// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Registration;

{$EXCESSPRECISION OFF}

interface

// The entry point that the IDE calls when it loads the design-time package. It is the only global procedure of the library, because
// the IDE requires it.
procedure Register;

implementation

// The palette bitmaps are those of the VCL components, a copy of the file made by tools\make-palette-icons.ps1: the bitmaps are named after
// the class and every package has its own resources, so the same names in both design-time packages do not meet
{$R icons\Pdf4D.FMX.Palette.res}

uses
  System.Actions,
  System.Classes,
  System.TypInfo,
  DesignIntf,
  FMX.Controls,
  Pdf4D.FMX.Document,
  Pdf4D.FMX.Backend.Skia,
  Pdf4D.FMX.PageView,
  Pdf4D.FMX.Thumbnails,
  Pdf4D.FMX.OutlineView,
  Pdf4D.FMX.SearchBar,
  Pdf4D.FMX.Actions,
  Pdf4D.FMX.Toolbar,
  Pdf4D.FMX.PrintDialog,
  Pdf4D.FMX.Viewer,
  Pdf4D.FMX.FileNameEditor;

const
  PaletteName = 'Pdf4D';

procedure Register;
begin
  // The components without a window of their own appear in FMX projects only, so that the same names can be registered for FMX
  GroupDescendentsWith(TPdf4DDocument, FMX.Controls.TControl);
  GroupDescendentsWith(TPdf4DSkiaBackend, FMX.Controls.TControl);
  GroupDescendentsWith(TPdf4DPrintDialog, FMX.Controls.TControl);

  RegisterComponents(PaletteName, [
    TPdf4DDocument, TPdf4DSkiaBackend, TPdf4DPageView, TPdf4DThumbnails, TPdf4DOutlineView, TPdf4DSearchBar, TPdf4DToolbar,
    TPdf4DViewer, TPdf4DPrintDialog]);

  RegisterActions(PaletteName, [
    TPdf4DZoomInAction, TPdf4DZoomOutAction, TPdf4DZoomFitWidthAction, TPdf4DZoomFitPageAction, TPdf4DRotateClockwiseAction,
    TPdf4DRotateCounterclockwiseAction, TPdf4DCopyAction, TPdf4DFirstPageAction, TPdf4DPriorPageAction, TPdf4DNextPageAction,
    TPdf4DLastPageAction, TPdf4DPrintAction, TPdf4DSearchAction], nil);

  RegisterPropertyEditor(TypeInfo(string), TPdf4DDocument, 'FileName', TPdf4DFileNameProperty);
end;

end.
