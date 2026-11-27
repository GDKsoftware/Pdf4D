// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The render fuzz tests on the native backend: the mutated corpus, the generated graphics streams and the hostile documents of the shared
// base class, each drawn at 36 DPI with TPdfNativeBackend and the default limits. Only success or an EPdfException passes, within the time
// of the worker.
unit Pdf4D.Tests.RenderRobustness.Native.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.Fuzz,
  Pdf4D.Tests.RenderRobustness.Base;

type
  [TestFixture]
  TNativeRenderRobustnessTests = class(TRenderRobustnessTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
    // A path of 5 000 000 segments and a dash of a million pieces, each within the time of the worker (10 s)
    procedure RunExtraHostile(const Campaign: TFuzzCampaign); override;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Render.Native.Backend;

{ TNativeRenderRobustnessTests }

function TNativeRenderRobustnessTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
end;

procedure TNativeRenderRobustnessTests.RunExtraHostile(const Campaign: TFuzzCampaign);
const
  Pair = '100 100 l 0 0 l ';
  PairCount = 2500000;
  Mark = '0 0 1 rg 0 0 20 20 re f';
  // The time of the path of 5 000 000 segments in seconds; 0 is the general limit of 10 s. Win32 runs the f32 code on the x87 unit and needs
  // 12.0 s for this path (measured, Release, one run), so its limit is 20 s: the measured time with a
  // margin of two thirds, far below the 60 s hang guard of the device contract tests.
  {$IFDEF CPUX86}
  LongPathSeconds = 20;
  {$ELSE}
  LongPathSeconds = 0;
  {$ENDIF}
begin
  const Builder = TStringBuilder.Create(Length(Pair) * PairCount + 64);
  try
    Builder.Append('0 0 m ');
    for var Index := 1 to PairCount do
    begin
      Builder.Append(Pair);
    end;
    Builder.Append('f ').Append(Mark);
    RunHostileContent(Campaign, 'path of 5 000 000 segments', Builder.ToString, LongPathSeconds);
  finally
    Builder.Free;
  end;

  RunHostileContent(Campaign, 'dash of a million pieces', '[0.001 0.001] 0 d 1 w 0 100 m 2000 100 l S ' + Mark);
end;

end.
