// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.GuardedWriter;

interface

uses
  System.SysUtils,
  System.Classes;

type
  // Raised inside the text extraction to stop it after the destination writer failed
  EPdfWriterAborted = class(Exception);

  // Passes the text of the extraction on to the writer of the caller. When that writer raises, the exception is kept and the
  // extraction is stopped with EPdfWriterAborted, so that the caller can get its own exception back after the clean-up.
  // The extraction only writes strings; Write(Char), WriteLine, WriteLine(string) and WriteLine(Char) are forwarded too, the other overloads
  // write into a buffer of this object that nobody reads.
  TPdfGuardedWriter = class(TStringWriter)
  private
    FDestination: TTextWriter;
    FFailure: TObject;

  private
    procedure KeepFailure;

  public
    // The destination is not owned
    constructor Create(const Destination: TTextWriter);
    destructor Destroy; override;

    procedure Write(const Value: string); override;
    procedure Write(Value: Char); override;
    procedure WriteLine; override;
    procedure WriteLine(const Value: string); override;
    procedure WriteLine(Value: Char); override;

    function HasFailure: Boolean;
    // The exception of the destination. The caller raises it, which hands it over to the exception handling.
    function TakeFailure: TObject;
  end;

implementation

{ TPdfGuardedWriter }

constructor TPdfGuardedWriter.Create(const Destination: TTextWriter);
begin
  inherited Create;
  FDestination := Destination;
end;

destructor TPdfGuardedWriter.Destroy;
begin
  FFailure.Free;
  inherited;
end;

procedure TPdfGuardedWriter.KeepFailure;
begin
  FFailure.Free;
  FFailure := AcquireExceptionObject;
  raise EPdfWriterAborted.Create('The destination writer failed');
end;

procedure TPdfGuardedWriter.Write(const Value: string);
begin
  try
    FDestination.Write(Value);
  except
    KeepFailure;
  end;
end;

procedure TPdfGuardedWriter.Write(Value: Char);
begin
  try
    FDestination.Write(Value);
  except
    KeepFailure;
  end;
end;

procedure TPdfGuardedWriter.WriteLine;
begin
  try
    FDestination.WriteLine;
  except
    KeepFailure;
  end;
end;

procedure TPdfGuardedWriter.WriteLine(const Value: string);
begin
  try
    FDestination.WriteLine(Value);
  except
    KeepFailure;
  end;
end;

procedure TPdfGuardedWriter.WriteLine(Value: Char);
begin
  try
    FDestination.WriteLine(Value);
  except
    KeepFailure;
  end;
end;

function TPdfGuardedWriter.HasFailure: Boolean;
begin
  Result := Assigned(FFailure);
end;

function TPdfGuardedWriter.TakeFailure: TObject;
begin
  Result := FFailure;
  FFailure := nil;
end;

end.
