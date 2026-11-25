// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Dispatcher;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils;

type
  IPdfViewerDispatcher = interface
    ['{6A0D3F81-2B57-4C9E-8E14-7F5B9C2A1D63}']
    // From any thread; runs Proc later on the UI thread, in posting order
    procedure Post(const Proc: TProc);
  end;

  // The default dispatcher: the procedures run on the main thread when it processes its queue
  TPdfQueueDispatcher = class(TInterfacedObject, IPdfViewerDispatcher)
  public
    procedure Post(const Proc: TProc);
  end;

implementation

uses
  System.Classes;

{ TPdfQueueDispatcher }

procedure TPdfQueueDispatcher.Post(const Proc: TProc);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      Proc();
    end);
end;

end.
