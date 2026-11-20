// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Renderer.Interfaces;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Render.Options;

type
  IPdfCancelToken = interface
    ['{7D20B6C3-5E19-4A8F-8C47-1F9B3E6D0A24}']
    // Thread safe
    function IsCancelled: Boolean;
  end;

  {$SCOPEDENUMS ON}
  TPdfRenderStatus = (Completed, Cancelled);
  {$SCOPEDENUMS OFF}

  TPdfRenderParams = record
    // Pixels per point (DPI / 72), > 0
    Scale: Single;
    // 0, 90, 180 or 270, clockwise, added to /Rotate
    ExtraRotation: Integer;
    // Pixels of the whole page at Scale; empty: the whole page
    Region: TRect;
    Options: TPdfRenderOptions;
    // Nil: cannot be cancelled
    Cancel: IPdfCancelToken;

    // The whole page with default options; raises EArgumentOutOfRangeException when Scale <= 0
    class function Create(const Scale: Single): TPdfRenderParams; static;
    class function FromDpi(const Dpi: Single): TPdfRenderParams; static;
  end;

implementation

const
  PointsPerInch = 72;

{ TPdfRenderParams }

class function TPdfRenderParams.Create(const Scale: Single): TPdfRenderParams;
begin
  const IsPositive = (Scale > 0);
  if not IsPositive then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Render scale %g is not positive', [Scale]);
  end;

  Result := Default(TPdfRenderParams);
  Result.Scale := Scale;
  Result.Region := TRect.Empty;
  Result.Options := TPdfRenderOptions.Default;
end;

class function TPdfRenderParams.FromDpi(const Dpi: Single): TPdfRenderParams;
begin
  Result := Create(Dpi / PointsPerInch);
end;

end.
