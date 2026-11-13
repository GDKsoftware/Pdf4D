// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/Filter.java (3.0.8), the decoding part
unit Pdf4D.Filter.Base;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary;

type
  // The caller owns a filter. A filter keeps no state between decodes, so it can decode several streams.
  TPdfFilter = class abstract
  private
    FLog: TPdfLog;
    FEmptyParameters: TCosDictionary;

    function EmptyParameters: TCosDictionary;
    class function TryGetFirstOf(const Dictionary: TCosDictionary; const FirstKey, SecondKey: string; out Value: TCosBase): Boolean; static;

  protected
    // Port of Filter.getDecodeParams. Normalises DecodeParms (or DP) to a dictionary: the one for this filter, or
    // an empty one. The dictionary is not owned by the caller. Dictionary is the dictionary of the stream.
    function GetDecodeParams(const Dictionary: TCosDictionary; const Index: Integer): TCosDictionary;

  public
    destructor Destroy; override;

    // Decodes all of Input into Output. Parameters is the dictionary of the stream, Index the position of this
    // filter in the filter list. Recoverable problems go to the log and keep the data decoded up to there.
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); virtual; abstract;

    // Not owned, may be nil
    property Log: TPdfLog read FLog write FLog;
  end;

implementation

uses
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.PdfArray;

{ TPdfFilter }

destructor TPdfFilter.Destroy;
begin
  FEmptyParameters.Free;
  inherited;
end;

function TPdfFilter.GetDecodeParams(const Dictionary: TCosDictionary; const Index: Integer): TCosDictionary;
begin
  var FilterEntry: TCosBase;
  var ParamsEntry: TCosBase;
  TryGetFirstOf(Dictionary, TCosNames.F, TCosNames.Filter, FilterEntry);
  TryGetFirstOf(Dictionary, TCosNames.DP, TCosNames.DecodeParms, ParamsEntry);

  if (FilterEntry is TCosName) and (ParamsEntry is TCosDictionary) then
  begin
    // PDFBOX-3932: one filter name with a parameter dictionary, as Adobe reads it
    Exit(TCosDictionary(ParamsEntry));
  end;

  if (FilterEntry is TCosArray) and (ParamsEntry is TCosArray) then
  begin
    const ParamsArray = TCosArray(ParamsEntry);
    if Index < ParamsArray.Count then
    begin
      const AtIndex = ParamsArray.GetObject(Index);
      if AtIndex is TCosDictionary then
      begin
        Exit(TCosDictionary(AtIndex));
      end;
    end;
  end
  else if Assigned(ParamsEntry) and not ((FilterEntry is TCosArray) or (ParamsEntry is TCosArray)) and Assigned(FLog) then
  begin
    FLog.Error('Expected DecodeParams to be an Array or Dictionary but found %s', [ParamsEntry.ClassName]);
  end;

  Result := EmptyParameters;
end;

function TPdfFilter.EmptyParameters: TCosDictionary;
begin
  if not Assigned(FEmptyParameters) then
  begin
    FEmptyParameters := TCosDictionary.Create;
  end;
  Result := FEmptyParameters;
end;

class function TPdfFilter.TryGetFirstOf(const Dictionary: TCosDictionary; const FirstKey, SecondKey: string; out Value: TCosBase): Boolean;
begin
  Result := Dictionary.TryGetDictionaryObject(FirstKey, Value) or Dictionary.TryGetDictionaryObject(SecondKey, Value);
end;

end.
