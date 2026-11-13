// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/FontMapper.java, FontMapping.java, CIDFontMapping.java and
// FontMappers.java (3.0.8)
unit Pdf4D.Font.Mapper;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Provider;

type
  // The mapped font is shared: the mapper owns it and the caller must not free it. It stays valid until the process ends.
  TFontMapping<T: class> = record
    Font: T;
    IsFallback: Boolean;
  end;

  // Font is the OpenType font of a CID font (nil when there is none), TrueTypeFont the substitute when it is not a CID font
  TCIDFontMapping = record
    Font: TFontBoxFont;
    TrueTypeFont: TTrueTypeFont;
    IsFallback: Boolean;

    function IsCIDFont: Boolean;
  end;

  // Finds fonts that are not embedded. The fonts are shared: the mapper keeps them and the caller does not free them. The
  // descriptor may be nil.
  IPdfFontMapper = interface
    ['{B1A3C7E5-84D2-4F6B-9E10-2D7A5C3F8B64}']
    function GetTrueTypeFont(const BaseFont: string; const Descriptor: TPDFontDescriptor): TFontMapping<TTrueTypeFont>;
    function GetFontBoxFont(const BaseFont: string; const Descriptor: TPDFontDescriptor): TFontMapping<TFontBoxFont>;
    function GetCIDFont(const BaseFont: string; const Descriptor: TPDFontDescriptor; const HasCIDSystemInfo: Boolean;
                        const CIDSystemInfo: TPDCIDSystemInfo): TCIDFontMapping;
  end;

  // The process-wide font mapper, like FontMappers in PDFBox. Instance and SetInstance are thread-safe.
  // SetInstance can be called at any time, but a mapper that has been in use is never freed before the process ends: fonts
  // that it gave out are borrowed from it and a thread may still use them. SetInstance is therefore meant for start up and
  // tests, and each different mapper that is replaced stays in memory until shutdown. SetInstance(nil) goes back to the
  // default mapper. The default mapper is made when Instance is first called and reads the font folders of the machine when the
  // first font is asked for, so a process that sets its own mapper first never scans the file system.
  TPdfFontMappers = record
  private
    class var FLock: TLightweightMREW;
    class var FCurrent: IPdfFontMapper;
    class var FDefault: IPdfFontMapper;
    class var FRetired: TList<IPdfFontMapper>;
    class var FDefaultProvider: IPdfFontProvider;
    class var FLogLock: TLightweightMREW;
    class var FLogEvent: TPdfLogEvent;
    class var FLog: TPdfLog;

    class destructor Destroy;

    class function CreateDefault: IPdfFontMapper; static;
    class procedure DispatchLog(const Level: TPdfLogLevel; const Message: string); static;
    class procedure Retire(const Mapper: IPdfFontMapper); static;

  public
    class function Instance: IPdfFontMapper; static;
    class procedure SetInstance(const Mapper: IPdfFontMapper); static;
    // The font provider of the default mapper, instead of the file system provider; nil goes back to that. Meant for tests, and only
    // useful before the default mapper is first made, which is when Instance is first called without SetInstance having been called.
    class procedure SetDefaultProvider(const Provider: IPdfFontProvider); static;
    // Sets the process-wide log callback for font discovery: a font file or folder that is skipped, and the limits of the scan, get a
    // warning. Nil by default, which means silent. The callback can be set or cleared at any time and is called from whichever thread
    // scans the fonts, so it must be thread-safe. Pass nil to switch the log off.
    class procedure SetLog(const OnLog: TPdfLogEvent); static;
    // The log that goes to the callback of SetLog. It lives until the process ends; the default provider uses it, and so can others.
    class function Log: TPdfLog; static;
  end;

implementation

uses
  Pdf4D.Font.FileSystemProvider,
  Pdf4D.Font.MapperImpl;

{ TCIDFontMapping }

function TCIDFontMapping.IsCIDFont: Boolean;
begin
  Result := Assigned(Font);
end;

{ TPdfFontMappers }

class destructor TPdfFontMappers.Destroy;
begin
  FCurrent := nil;
  FDefault := nil;
  FDefaultProvider := nil;
  FreeAndNil(FRetired);
  FreeAndNil(FLog);
  FLogEvent := nil;
end;

class function TPdfFontMappers.CreateDefault: IPdfFontMapper;
begin
  var Provider := FDefaultProvider;
  if not Assigned(Provider) then
  begin
    Provider := TFileSystemFontProvider.CreateDefault(Log);
  end;
  Result := TFontMapperImpl.Create(Provider);
end;

class procedure TPdfFontMappers.DispatchLog(const Level: TPdfLogLevel; const Message: string);
begin
  FLogLock.BeginRead;
  var OnLog: TPdfLogEvent;
  try
    OnLog := FLogEvent;
  finally
    FLogLock.EndRead;
  end;

  if Assigned(OnLog) then
  begin
    OnLog(Level, Message);
  end;
end;

class procedure TPdfFontMappers.SetLog(const OnLog: TPdfLogEvent);
begin
  FLogLock.BeginWrite;
  try
    FLogEvent := OnLog;
  finally
    FLogLock.EndWrite;
  end;
end;

class function TPdfFontMappers.Log: TPdfLog;
begin
  FLogLock.BeginWrite;
  try
    if not Assigned(FLog) then
    begin
      FLog := TPdfLog.Create(DispatchLog);
    end;
    Result := FLog;
  finally
    FLogLock.EndWrite;
  end;
end;

class function TPdfFontMappers.Instance: IPdfFontMapper;
begin
  FLock.BeginRead;
  try
    Result := FCurrent;
    if not Assigned(Result) then
    begin
      Result := FDefault;
    end;
  finally
    FLock.EndRead;
  end;
  if Assigned(Result) then
  begin
    Exit;
  end;

  FLock.BeginWrite;
  try
    if not Assigned(FDefault) then
    begin
      FDefault := CreateDefault;
    end;
    Result := FCurrent;
    if not Assigned(Result) then
    begin
      Result := FDefault;
    end;
  finally
    FLock.EndWrite;
  end;
end;

class procedure TPdfFontMappers.Retire(const Mapper: IPdfFontMapper);
begin
  if not Assigned(Mapper) then
  begin
    Exit;
  end;

  if not Assigned(FRetired) then
  begin
    FRetired := TList<IPdfFontMapper>.Create;
  end;

  const IsKnown = FRetired.Contains(Mapper);
  if not IsKnown then
  begin
    FRetired.Add(Mapper);
  end;
end;

class procedure TPdfFontMappers.SetDefaultProvider(const Provider: IPdfFontProvider);
begin
  FLock.BeginWrite;
  try
    FDefaultProvider := Provider;
  finally
    FLock.EndWrite;
  end;
end;

class procedure TPdfFontMappers.SetInstance(const Mapper: IPdfFontMapper);
begin
  FLock.BeginWrite;
  try
    Retire(FCurrent);
    FCurrent := Mapper;
  finally
    FLock.EndWrite;
  end;
end;

end.
