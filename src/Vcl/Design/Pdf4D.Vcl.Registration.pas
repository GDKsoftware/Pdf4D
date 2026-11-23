// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Registration;

{$EXCESSPRECISION OFF}

interface

// The entry point that the IDE calls when it loads the design-time package. It is the only global procedure of the library, because
// the IDE requires it.
procedure Register;

implementation

{$R icons\Pdf4D.Vcl.Palette.res}

uses
  System.Actions,
  System.Classes,
  System.TypInfo,
  DesignIntf,
  Vcl.Controls,
  Pdf4D.Viewer.Document,
  Pdf4D.Vcl.Document,
  Pdf4D.Vcl.Backend.Skia,
  Pdf4D.Vcl.PageView,
  Pdf4D.Vcl.Thumbnails,
  Pdf4D.Vcl.OutlineView,
  Pdf4D.Vcl.SearchBar,
  Pdf4D.Vcl.Actions,
  Pdf4D.Vcl.Toolbar,
  Pdf4D.Vcl.PrintDialog,
  Pdf4D.Vcl.Viewer,
  Pdf4D.Vcl.FileNameEditor;

const
  PaletteName = 'Pdf4D';

procedure Register;
begin
  // The components without a window of their own appear in VCL projects only, so that the same names can be registered for FMX
  GroupDescendentsWith(TPdf4DDocument, Vcl.Controls.TControl);
  GroupDescendentsWith(TPdf4DSkiaBackend, Vcl.Controls.TControl);
  GroupDescendentsWith(TPdf4DPrintDialog, Vcl.Controls.TControl);

  RegisterComponents(PaletteName, [
    TPdf4DDocument, TPdf4DSkiaBackend, TPdf4DPageView, TPdf4DThumbnails, TPdf4DOutlineView, TPdf4DSearchBar, TPdf4DToolbar,
    TPdf4DViewer, TPdf4DPrintDialog]);

  RegisterActions(PaletteName, [
    TPdf4DZoomInAction, TPdf4DZoomOutAction, TPdf4DZoomFitWidthAction, TPdf4DZoomFitPageAction, TPdf4DRotateClockwiseAction,
    TPdf4DRotateCounterclockwiseAction, TPdf4DCopyAction, TPdf4DFirstPageAction, TPdf4DPriorPageAction, TPdf4DNextPageAction,
    TPdf4DLastPageAction, TPdf4DPrintAction, TPdf4DSearchAction], nil);

  RegisterPropertyEditor(TypeInfo(string), TPdf4DCustomDocument, 'FileName', TPdf4DFileNameProperty);
end;

end.
