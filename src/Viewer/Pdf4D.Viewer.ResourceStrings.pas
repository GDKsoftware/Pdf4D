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
  SWorkerEndFailed = 'Releasing the document when the worker ended failed: %s';
  SSearchResultCount = '%d of %d';
  SSearchNoResults = 'No results';
  SSearching = 'Searching'#$2026;
  SSearchMatchCase = 'Match case';
  SSearchPriorHint = 'Previous result';
  SSearchNextHint = 'Next result';

implementation

end.
