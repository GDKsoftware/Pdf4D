// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ResourceStrings;

interface

resourcestring
  SNoRenderBackend = 'No render backend. Put a TPdf4DSkiaBackend on the form and link it to the document, or set RenderBackend.';
  SOverlayWhileNotOpen = 'An overlay can be added only while the document is open.';
  SOverlayPageOutside = 'Page %d is outside the document.';
  SOverlayNoQuads = 'An overlay needs at least one quad.';
  SOverlayQuadNotFinite = 'The quads of an overlay must have finite coordinates.';
  SDocumentNotOpen = 'The document is not open.';
  SNoStream = 'Open needs a stream.';
  SWorkerStopped = 'The document worker stopped after a fatal error.';
  SWorkerFatal = 'The document worker stopped after a fatal error: %s';
  SWorkerAbandonFailed = 'Handing back a queued job failed: %s';
  SWorkerThreadFailed = 'The document worker thread ended with an exception: %s';
  SPrintAbortFailed = 'Aborting the print document failed: %s';
  SPrintFailedAndAbortFailed = '%s (aborting the document failed: %s)';
  SPrintBandDrawFailed = 'A band of the page could not be drawn';
  SPrintBandRenderFailed = 'A band of the page could not be rendered';
  SPrintBeginFailed = 'The print document could not be begun';
  SPrintStretchFailed = 'A band of the page could not be sent to the printer';
  SPrintAlreadyRunning = 'A print job is running already.';
  SPrintNeedsDocument = 'Printing needs a document.';
  SPrintDialogCaption = 'Print';
  SPrintPrinterLabel = 'Printer';
  SPrintProperties = 'Properties...';
  SPrintRangeGroup = 'Pages';
  SPrintRangeAll = 'All pages';
  SPrintRangeCurrent = 'Current page (%d)';
  SPrintRangePages = 'Pages';
  SPrintRangeTo = 'to';
  SPrintScaleGroup = 'Size';
  SPrintScaleFit = 'Fit to the paper';
  SPrintScaleActualSize = 'Actual size';
  SPrintCopiesLabel = 'Copies';
  SPrintOk = 'Print';
  SPrintCancel = 'Cancel';
  SPrintProgressCaption = 'Printing';
  SPrintProgressPage = 'Printing page %d of %d';
  SPrintProgressStarting = 'Starting the print job';
  SPrintFailedMessage = 'Printing failed: %s';
  SWorkerEndFailed = 'Releasing the document when the worker ended failed: %s';
  SSearchResultCount = '%d of %d';
  SSearchNoResults = 'No results';
  SSearching = 'Searching'#$2026;
  SSearchMatchCase = 'Match case';
  SSearchPriorHint = 'Previous result';
  SSearchNextHint = 'Next result';
  SActionHintWithKey = '%s (%s)';
  SActionZoomIn = 'Zoom in';
  SActionZoomOut = 'Zoom out';
  SActionFitWidthHint = 'Fit the page to the width of the window';
  SActionFitPageHint = 'Fit the whole page in the window';
  SActionRotateClockwise = 'Rotate clockwise';
  SActionRotateCounterclockwise = 'Rotate counterclockwise';
  SActionCopy = 'Copy';
  SActionFirstPage = 'First page';
  SActionPriorPage = 'Previous page';
  SActionNextPage = 'Next page';
  SActionLastPage = 'Last page';
  SActionPrint = 'Print';
  SActionSearch = 'Search';
  SZoomFitWidth = 'Fit width';
  SZoomFitPage = 'Fit page';
  SZoomHint = 'Zoom';
  SPageNumberHint = 'Page number';
  SPageCountOf = ' / %d';
  SViewerTabPages = 'Pages';
  SViewerTabBookmarks = 'Bookmarks';
  SPasswordCaption = 'Password';
  SPasswordPrompt = 'The document is protected. Enter its password:';

implementation

end.
