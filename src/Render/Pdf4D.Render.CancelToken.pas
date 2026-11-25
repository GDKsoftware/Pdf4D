// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.CancelToken;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Render.Renderer.Interfaces;

type
  // The one render object that any thread may use: Cancel can be called from every thread
  TPdfCancelToken = class(TInterfacedObject, IPdfCancelToken)
  private
    FCancelled: Integer;

  public
    // Thread safe
    procedure Cancel;
    // Thread safe
    function IsCancelled: Boolean;
  end;

implementation

uses
  System.SyncObjs;

const
  NotCancelled = 0;
  CancelRequested = 1;

{ TPdfCancelToken }

procedure TPdfCancelToken.Cancel;
begin
  TInterlocked.Exchange(FCancelled, CancelRequested);
end;

function TPdfCancelToken.IsCancelled: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FCancelled, NotCancelled, NotCancelled) = CancelRequested);
end;

end.
