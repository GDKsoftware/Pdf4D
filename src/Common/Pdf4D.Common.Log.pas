// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Common.Log;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Defines;

type
  TPdfLog = class
  private
    FOnLog: TPdfLogEvent;

    procedure Write(const Level: TPdfLogLevel; const Message: string); overload;
    procedure Write(const Level: TPdfLogLevel; const Fmt: string; const Args: array of const); overload;

  public
    constructor Create(const OnLog: TPdfLogEvent);

    procedure Debug(const Message: string); overload;
    procedure Debug(const Fmt: string; const Args: array of const); overload;

    procedure Info(const Message: string); overload;
    procedure Info(const Fmt: string; const Args: array of const); overload;

    procedure Warning(const Message: string); overload;
    procedure Warning(const Fmt: string; const Args: array of const); overload;

    procedure Error(const Message: string); overload;
    procedure Error(const Fmt: string; const Args: array of const); overload;
  end;

implementation

{ TPdfLog }

constructor TPdfLog.Create(const OnLog: TPdfLogEvent);
begin
  inherited Create;
  FOnLog := OnLog;
end;

procedure TPdfLog.Debug(const Message: string);
begin
  Write(TPdfLogLevel.Debug, Message);
end;

procedure TPdfLog.Debug(const Fmt: string; const Args: array of const);
begin
  Write(TPdfLogLevel.Debug, Fmt, Args);
end;

procedure TPdfLog.Info(const Message: string);
begin
  Write(TPdfLogLevel.Info, Message);
end;

procedure TPdfLog.Info(const Fmt: string; const Args: array of const);
begin
  Write(TPdfLogLevel.Info, Fmt, Args);
end;

procedure TPdfLog.Warning(const Message: string);
begin
  Write(TPdfLogLevel.Warning, Message);
end;

procedure TPdfLog.Warning(const Fmt: string; const Args: array of const);
begin
  Write(TPdfLogLevel.Warning, Fmt, Args);
end;

procedure TPdfLog.Error(const Message: string);
begin
  Write(TPdfLogLevel.Error, Message);
end;

procedure TPdfLog.Error(const Fmt: string; const Args: array of const);
begin
  Write(TPdfLogLevel.Error, Fmt, Args);
end;

procedure TPdfLog.Write(const Level: TPdfLogLevel; const Message: string);
begin
  if not Assigned(FOnLog) then
  begin
    Exit;
  end;

  try
    FOnLog(Level, Message);
  except
    // Logging must never break the parser: a callback that raises is the caller's mistake, and the document is still valid
    on Exception do
    begin
      Exit;
    end;
  end;
end;

procedure TPdfLog.Write(const Level: TPdfLogLevel; const Fmt: string; const Args: array of const);
begin
  if not Assigned(FOnLog) then
  begin
    Exit;
  end;

  var Message: string;
  try
    Message := Format(Fmt, Args);
  except
    // A bad format string or arguments that do not fit it: the raw format is still better than nothing
    on Exception do
    begin
      Message := Fmt;
    end;
  end;
  Write(Level, Message);
end;

end.
