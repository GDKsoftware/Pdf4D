unit Pdf4D.Common.Log;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Defines;

type
  TPdfLog = class
  private
    FOnLog: TPdfLogEvent;

    procedure Write(const Level: TPdfLogLevel; const Message: string);

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
  Write(TPdfLogLevel.Debug, Format(Fmt, Args));
end;

procedure TPdfLog.Info(const Message: string);
begin
  Write(TPdfLogLevel.Info, Message);
end;

procedure TPdfLog.Info(const Fmt: string; const Args: array of const);
begin
  Write(TPdfLogLevel.Info, Format(Fmt, Args));
end;

procedure TPdfLog.Warning(const Message: string);
begin
  Write(TPdfLogLevel.Warning, Message);
end;

procedure TPdfLog.Warning(const Fmt: string; const Args: array of const);
begin
  Write(TPdfLogLevel.Warning, Format(Fmt, Args));
end;

procedure TPdfLog.Error(const Message: string);
begin
  Write(TPdfLogLevel.Error, Message);
end;

procedure TPdfLog.Error(const Fmt: string; const Args: array of const);
begin
  Write(TPdfLogLevel.Error, Format(Fmt, Args));
end;

procedure TPdfLog.Write(const Level: TPdfLogLevel; const Message: string);
begin
  const HasCallback = Assigned(FOnLog);
  if HasCallback then
  begin
    FOnLog(Level, Message);
  end;
end;

end.
