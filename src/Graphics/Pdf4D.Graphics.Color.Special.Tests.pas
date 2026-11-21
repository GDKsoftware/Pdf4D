// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for the Indexed, Separation and DeviceN colour spaces of PDFBox (PDIndexed, PDSeparation, PDDeviceN,
// PDDeviceNAttributes and PDDeviceNProcess, 3.0.8); the reference values (tests/reference/color-spaces/colorspaces.txt) come from PDFBox itself
unit Pdf4D.Graphics.Color.Special.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color,
  Pdf4D.Tests.ColorBuilder,
  Pdf4D.Tests.ColorSpaceReferences;

type
  [TestFixture]
  TSpecialColorSpaceTests = class
  private
    FBuilder: TColorTestBuilder;
    FReferences: TColorSpaceReferences;

    function NewNames(const Names: array of string): TCosArray;
    function NewIndexedArray(const Base: TCosBase; const Hival: Integer; const Lookup: TBytes): TCosArray;
    function SpaceOf(const Name: string; const Items: TCosArray): TPDColorSpace;
    function NewDeviceNArray(const Colorants: TCosArray; const Alternate: TCosBase; const TintTransform: TCosBase): TCosArray;
    function NewGrayTint: TCosBase;
    class function Lookup(const Values: array of Byte): TBytes; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestIndexedLookup;

    [Test]
    procedure TestIndexedMatchesPdfBox;

    [Test]
    procedure TestShortIndexedLookupClamps;

    [Test]
    procedure TestIndexedHivalIsLimitedTo255;

    [Test]
    procedure TestIndexedInitialColorDefaultDecodeAndName;

    [Test]
    procedure TestIndexedWithoutLookupRaises;

    [Test]
    procedure TestIndexedWithHivalThatIsNoNumberRaises;

    [Test]
    procedure TestIndexedWithBaseWithoutComponentsRaises;

    [Test]
    procedure TestIndexedImageToRgb;

    [Test]
    procedure TestSeparationMatchesPdfBox;

    [Test]
    procedure TestSeparationAllIsGray;

    [Test]
    procedure TestSeparationNoneStillConvertsLikePdfBox;

    [Test]
    procedure TestSeparationTintTransform;

    [Test]
    procedure TestSeparationInitialColorDefaultDecodeAndName;

    [Test]
    procedure TestSeparationWithTooFewTintOutputsRaises;

    [Test]
    procedure TestDeviceNWithType4Function;

    [Test]
    procedure TestDeviceNWithAttributesMatchesPdfBox;

    [Test]
    procedure TestDeviceNInitialColorAndDefaultDecode;

    [Test]
    procedure TestDeviceNWithoutOrWithTooManyColorantsRaises;

    [Test]
    procedure TestDeviceNProcessWithoutColorSpaceFallsBackToTheTintTransform;

    [Test]
    procedure TestRecursiveColorSpaceStops;

    [Test]
    procedure TestIndexedThatIsItsOwnBaseRaises;

    [Test]
    procedure TestSpacesAreSharedPerArray;

    [Test]
    procedure TestSeparationTintOverOneWrapsLikeJava;

    [Test]
    procedure TestDeviceNWithHugeColorantListRaisesQuickly;

    [Test]
    procedure TestDictionaryWithColorSpaceEntryIsTheSpaceOfTheEntry;

    [Test]
    procedure TestDictionaryWithColorSpaceEntryThatIsItselfRaises;
  end;

implementation

uses
  System.Diagnostics,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfString,
  Pdf4D.Graphics.Image,
  Pdf4D.Render.Bitmap;

const
  ExactColor = 0.000001;
  ColorTolerance = 1.0 / 255.0;
  RedLevel = 255;
  MaxDeviceNColorants = 32;
  HugeColorantCount = 100000;
  HugeColorantLimitMilliseconds = 500;

{ TSpecialColorSpaceTests }

procedure TSpecialColorSpaceTests.Setup;
begin
  FBuilder := TColorTestBuilder.Create;
  FReferences := TColorSpaceReferences.Create;
end;

procedure TSpecialColorSpaceTests.TearDown;
begin
  FReferences.Free;
  FBuilder.Free;
end;

class function TSpecialColorSpaceTests.Lookup(const Values: array of Byte): TBytes;
begin
  SetLength(Result, Length(Values));
  for var Index := 0 to High(Values) do
  begin
    Result[Index] := Values[Index];
  end;
end;

function TSpecialColorSpaceTests.NewNames(const Names: array of string): TCosArray;
begin
  Result := TCosArray.Create;
  for var Name in Names do
  begin
    Result.Add(TCosName.Create(Name));
  end;
end;

function TSpecialColorSpaceTests.NewIndexedArray(const Base: TCosBase; const Hival: Integer; const Lookup: TBytes): TCosArray;
begin
  Result := TCosArray.Create;
  Result.Add(TCosName.Create(TCosNames.Indexed));
  Result.Add(Base);
  Result.Add(TCosInteger.Create(Hival));
  Result.Add(TCosString.Create(Lookup, True));
end;

// Registers Items under Name in the resources and makes the colour space through that name
function TSpecialColorSpaceTests.SpaceOf(const Name: string; const Items: TCosArray): TPDColorSpace;
begin
  FBuilder.AddColorSpace(Name, Items);
  Result := FBuilder.CreateSpace(FBuilder.NewName(Name));
end;

function TSpecialColorSpaceTests.NewGrayTint: TCosBase;
begin
  Result := FBuilder.Functions.Detach(FBuilder.Functions.NewType2('0 1', '1', '0', 1));
end;

function TSpecialColorSpaceTests.NewDeviceNArray(const Colorants: TCosArray; const Alternate: TCosBase; const TintTransform: TCosBase): TCosArray;
begin
  Result := TCosArray.Create;
  Result.Add(TCosName.Create(TCosNames.DeviceN));
  Result.Add(Colorants);
  Result.Add(Alternate);
  Result.Add(TintTransform);
end;

procedure TSpecialColorSpaceTests.TestIndexedLookup;
begin
  const Items = NewIndexedArray(TCosName.Create(TCosNames.DeviceRGB), 1, Lookup([$FF, $00, $00, $00, $00, $FF]));

  const Space = SpaceOf('IndexedLookup', Items);

  Assert.AreEqual('Indexed', Space.Name);
  Assert.AreEqual(1, Space.NumberOfComponents);
  const First = Space.ToRgb([0]);
  Assert.AreEqual(Single(1), First.R, ExactColor);
  Assert.AreEqual(Single(0), First.B, ExactColor);
  const Second = Space.ToRgb([1]);
  Assert.AreEqual(Single(0), Second.R, ExactColor);
  Assert.AreEqual(Single(0), Second.G, ExactColor);
  Assert.AreEqual(Single(1), Second.B, ExactColor);
end;

procedure TSpecialColorSpaceTests.TestIndexedMatchesPdfBox;
begin
  for var SpaceName in ['Idx', 'IdxGray', 'IdxCmyk', 'IdxLab', 'IdxStream', 'IdxCal'] do
  begin
    FReferences.CheckColors(SpaceName, ColorTolerance);
    FReferences.CheckImages(SpaceName, 1);
  end;

  FReferences.CheckColors('Idx', ExactColor);
  FReferences.CheckImages('Idx', 0);
end;

procedure TSpecialColorSpaceTests.TestShortIndexedLookupClamps;
begin
  // 7 bytes for hival 3: two complete entries, the index is clamped to the last of them
  FReferences.CheckColors('IdxShort', ExactColor);
  FReferences.CheckImages('IdxShort', 0);
  // 4 bytes for hival 3: one complete entry
  FReferences.CheckColors('IdxShortOne', ExactColor);
  FReferences.CheckImages('IdxShortOne', 0);

  const Last = FReferences.SpaceOf('IdxShort').ToRgb([3]);
  Assert.AreEqual(Single(0), Last.R, ExactColor);
  Assert.AreEqual(Single(1), Last.B, ExactColor);
end;

procedure TSpecialColorSpaceTests.TestIndexedHivalIsLimitedTo255;
begin
  var Table: TBytes;
  SetLength(Table, 300 * 3);
  for var Entry := 0 to 299 do
  begin
    Table[Entry * 3] := Byte(Entry);
  end;
  const Items = NewIndexedArray(TCosName.Create(TCosNames.DeviceRGB), 1000, Table);

  const Space = SpaceOf('IndexedHuge', Items);

  Assert.AreEqual(Single(255 / 255), Space.ToRgb([255]).R, ExactColor);
  Assert.AreEqual(Single(255 / 255), Space.ToRgb([300]).R, ExactColor, 'an index over 255 uses the last entry');
  Assert.AreEqual(Single(7 / 255), Space.ToRgb([7]).R, ExactColor);
end;

procedure TSpecialColorSpaceTests.TestIndexedInitialColorDefaultDecodeAndName;
begin
  const Space = FReferences.SpaceOf('Idx');

  Assert.AreEqual<Integer>(1, Length(Space.InitialColor.Components));
  Assert.AreEqual(Single(0), Space.InitialColor.Components[0], 0.0);
  const Decode = Space.GetDefaultDecode(2);
  Assert.AreEqual<Integer>(2, Length(Decode));
  Assert.AreEqual(Single(0), Decode[0], 0.0);
  Assert.AreEqual(Single(3), Decode[1], 0.0);
  Assert.AreEqual(Single(255), Space.GetDefaultDecode(8)[1], 0.0);
end;

procedure TSpecialColorSpaceTests.TestIndexedWithoutLookupRaises;
begin
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create(TCosNames.Indexed));
  Items.Add(TCosName.Create(TCosNames.DeviceRGB));
  Items.Add(TCosInteger.Create(1));
  FBuilder.AddColorSpace('IndexedNoLookup', Items);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('IndexedNoLookup'));
    end,
    EPdfParseException,
    'an empty lookup leaves no colour');

  const WrongLookup = TCosArray.Create;
  WrongLookup.Add(TCosName.Create(TCosNames.Indexed));
  WrongLookup.Add(TCosName.Create(TCosNames.DeviceRGB));
  WrongLookup.Add(TCosInteger.Create(1));
  WrongLookup.Add(TCosName.Create('NoTable'));
  FBuilder.AddColorSpace('IndexedWrongLookup', WrongLookup);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('IndexedWrongLookup'));
    end,
    EPdfParseException,
    'a lookup that is no string or stream');
end;

procedure TSpecialColorSpaceTests.TestIndexedWithHivalThatIsNoNumberRaises;
begin
  const Replacement = TCosArray.Create;
  Replacement.Add(TCosName.Create(TCosNames.Indexed));
  Replacement.Add(TCosName.Create(TCosNames.DeviceRGB));
  Replacement.Add(TCosName.Create('NoNumber'));
  Replacement.Add(TCosString.Create(Lookup([1, 2, 3]), True));
  FBuilder.AddColorSpace('IndexedBadHival', Replacement);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('IndexedBadHival'));
    end,
    EPdfParseException);
end;

procedure TSpecialColorSpaceTests.TestIndexedWithBaseWithoutComponentsRaises;
begin
  const Items = NewIndexedArray(TCosName.Create(TCosNames.Pattern), 1, Lookup([1, 2, 3, 4]));
  FBuilder.AddColorSpace('IndexedPattern', Items);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('IndexedPattern'));
    end,
    EPdfParseException);
end;

// Two bits per pixel: the samples are the indexes, which the colour space turns into the colours of the table
procedure TSpecialColorSpaceTests.TestIndexedImageToRgb;
begin
  const Items = NewIndexedArray(TCosName.Create(TCosNames.DeviceRGB), 3, Lookup([$FF, 0, 0, 0, $FF, 0, 0, 0, $FF, $80, $80, $80]));
  FBuilder.AddColorSpace('IndexedImage', Items);
  const Stream = TCosStream.Create;
  try
    Stream.SetRawData(Lookup([$1B]));
    Stream.SetItem(TCosNames.Width, TCosInteger.Create(4));
    Stream.SetItem(TCosNames.Height, TCosInteger.Create(1));
    Stream.SetItem(TCosNames.BitsPerComponent, TCosInteger.Create(2));
    Stream.SetItem(TCosNames.ColorSpace, TCosName.Create('IndexedImage'));
    const Image = TPDImageXObject.Create(Stream, FBuilder.Resources);
    try
      var Bitmap: TPdfBitmap;
      Assert.IsTrue(Image.TryGetImage(MaxInt, Bitmap), 'the image decodes');
      try
        Assert.AreEqual<Integer>(4, Bitmap.Width);
        Assert.AreEqual<Integer>(RedLevel, Bitmap.GetPixel(0, 0).R);
        Assert.AreEqual<Integer>(RedLevel, Bitmap.GetPixel(1, 0).G);
        Assert.AreEqual<Integer>(RedLevel, Bitmap.GetPixel(2, 0).B);
        Assert.AreEqual<Integer>($80, Bitmap.GetPixel(3, 0).R);
        Assert.AreEqual<Integer>(RedLevel, Bitmap.GetPixel(3, 0).A);
      finally
        Bitmap.Free;
      end;
    finally
      Image.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TSpecialColorSpaceTests.TestSeparationMatchesPdfBox;
begin
  for var SpaceName in ['Sep', 'SepType4', 'SepAll', 'SepNone', 'SepGray', 'SepLab'] do
  begin
    FReferences.CheckColors(SpaceName, ColorTolerance);
    FReferences.CheckImages(SpaceName, 1);
  end;
end;

procedure TSpecialColorSpaceTests.TestSeparationAllIsGray;
begin
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create(TCosNames.Separation));
  Items.Add(TCosName.Create(TCosNames.All));
  Items.Add(TCosName.Create(TCosNames.DeviceGray));
  Items.Add(NewGrayTint);

  const Space = SpaceOf('SepAllGray', Items);

  const Rgb = Space.ToRgb([0.25]);
  Assert.AreEqual(Single(0.75), Rgb.R, ExactColor);
  Assert.AreEqual(Rgb.R, Rgb.G, ExactColor);
  Assert.AreEqual(Rgb.R, Rgb.B, ExactColor);
end;

procedure TSpecialColorSpaceTests.TestSeparationNoneStillConvertsLikePdfBox;
begin
  // The conversion is that of the tint transform; the renderer paints nothing for /None (see the PageDrawer tests)
  FReferences.CheckColors('SepNone', ColorTolerance);
  Assert.AreEqual('Separation', FReferences.SpaceOf('SepNone').Name);
end;

procedure TSpecialColorSpaceTests.TestSeparationTintTransform;
begin
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create(TCosNames.Separation));
  Items.Add(TCosName.Create('Spot'));
  Items.Add(TCosName.Create(TCosNames.DeviceRGB));
  Items.Add(FBuilder.Functions.Detach(FBuilder.Functions.NewType2('0 1', '1 1 1', '1 0 0', 1)));

  const Space = SpaceOf('SepTint', Items);

  const Half = Space.ToRgb([0.5]);
  Assert.AreEqual(Single(1), Half.R, ExactColor);
  Assert.AreEqual(Single(0.5), Half.G, ExactColor);
  Assert.AreEqual(Single(0.5), Half.B, ExactColor);
  const Full = Space.ToRgb([1]);
  Assert.AreEqual(Single(0), Full.G, ExactColor);
  FReferences.CheckColors('Sep', ColorTolerance);
  FReferences.CheckColors('SepType4', ColorTolerance);
end;

procedure TSpecialColorSpaceTests.TestSeparationInitialColorDefaultDecodeAndName;
begin
  const Space = FReferences.SpaceOf('Sep');

  Assert.AreEqual('Separation', Space.Name);
  Assert.AreEqual(1, Space.NumberOfComponents);
  Assert.AreEqual(Single(1), Space.InitialColor.Components[0], 0.0);
  const Decode = Space.GetDefaultDecode(8);
  Assert.AreEqual(Single(0), Decode[0], 0.0);
  Assert.AreEqual(Single(1), Decode[1], 0.0);
end;

procedure TSpecialColorSpaceTests.TestSeparationWithTooFewTintOutputsRaises;
begin
  // A type 2 function with one output for DeviceRGB, which needs three
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create(TCosNames.Separation));
  Items.Add(TCosName.Create('Spot'));
  Items.Add(TCosName.Create(TCosNames.DeviceRGB));
  Items.Add(NewGrayTint);
  FBuilder.AddColorSpace('SepShortTint', Items);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('SepShortTint'));
    end,
    EPdfParseException);
end;

procedure TSpecialColorSpaceTests.TestDeviceNWithType4Function;
begin
  FReferences.CheckColors('DevN', ColorTolerance);
  FReferences.CheckImages('DevN', 1);
  FReferences.CheckColors('DevNMissingSpot', ColorTolerance);
  FReferences.CheckImages('DevNMissingSpot', 1);

  const Space = FReferences.SpaceOf('DevN');
  Assert.AreEqual('DeviceN', Space.Name);
  Assert.AreEqual(2, Space.NumberOfComponents);
end;

procedure TSpecialColorSpaceTests.TestDeviceNWithAttributesMatchesPdfBox;
begin
  for var SpaceName in ['DevNAttr', 'DevNSpotWins', 'DevNProcessRgb'] do
  begin
    FReferences.CheckColors(SpaceName, ColorTolerance);
    FReferences.CheckImages(SpaceName, 1);
  end;
end;

procedure TSpecialColorSpaceTests.TestDeviceNInitialColorAndDefaultDecode;
begin
  const Space = FReferences.SpaceOf('DevNAttr');

  Assert.AreEqual<Integer>(3, Length(Space.InitialColor.Components));
  Assert.AreEqual(Single(1), Space.InitialColor.Components[2], 0.0);
  const Decode = Space.GetDefaultDecode(8);
  Assert.AreEqual<Integer>(6, Length(Decode));
  Assert.AreEqual(Single(0), Decode[4], 0.0);
  Assert.AreEqual(Single(1), Decode[5], 0.0);
end;

procedure TSpecialColorSpaceTests.TestDeviceNWithoutOrWithTooManyColorantsRaises;
begin
  const NoColorants = NewDeviceNArray(TCosArray.Create, TCosName.Create(TCosNames.DeviceRGB), FBuilder.Functions.Detach(FBuilder.Functions.NewType2('0 1', '0 0 0', '1 1 1', 1)));
  FBuilder.AddColorSpace('DevNNone', NoColorants);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('DevNNone'));
    end,
    EPdfParseException,
    'no colorants');

  const Names = TCosArray.Create;
  for var Index := 0 to MaxDeviceNColorants do
  begin
    Names.Add(TCosName.Create(Format('C%d', [Index])));
  end;
  const TooMany = NewDeviceNArray(Names, TCosName.Create(TCosNames.DeviceRGB), FBuilder.Functions.Detach(FBuilder.Functions.NewType2('0 1', '0 0 0', '1 1 1', 1)));
  FBuilder.AddColorSpace('DevNMany', TooMany);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('DevNMany'));
    end,
    EPdfParseException,
    'more colorants than a raster has components');
end;

procedure TSpecialColorSpaceTests.TestDeviceNProcessWithoutColorSpaceFallsBackToTheTintTransform;
begin
  // /Process without /ColorSpace: PDFBox has no space to convert the process colorants with
  const Items = NewDeviceNArray(NewNames(['Cyan', 'Magenta']), TCosName.Create(TCosNames.DeviceRGB), FBuilder.Functions.Detach(FBuilder.Functions.NewType2('0 1', '1 1 1', '0 0 0', 1)));
  const Process = TCosDictionary.Create;
  Process.SetItem(TCosNames.Components, NewNames(['Cyan', 'Magenta']));
  const Attributes = TCosDictionary.Create;
  Attributes.SetItem(TCosNames.Process, Process);
  Items.Add(Attributes);

  const Space = SpaceOf('DevNNoProcessSpace', Items);

  Assert.AreEqual(2, Space.NumberOfComponents);
  const Rgb = Space.ToRgb([0.5, 0.5]);
  Assert.IsFalse(IsNan(Rgb.R));
end;

procedure TSpecialColorSpaceTests.TestRecursiveColorSpaceStops;
begin
  // Indexed spaces in each other, deeper than the limit
  var Nested: TCosBase := TCosName.Create(TCosNames.DeviceRGB);
  for var Level := 1 to 12 do
  begin
    Nested := NewIndexedArray(Nested, 0, Lookup([0, 0, 0]));
  end;
  FBuilder.AddColorSpace('DeepIndexed', Nested);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('DeepIndexed'));
    end,
    EPdfParseException,
    'twelve levels');

  // An alternate that is the space itself
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create(TCosNames.Separation));
  Items.Add(TCosName.Create('Spot'));
  Items.Add(FBuilder.NewReference(Items, 21));
  Items.Add(NewGrayTint);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(Items);
    end,
    EPdfParseException,
    'an alternate that refers to its own array');
end;

procedure TSpecialColorSpaceTests.TestIndexedThatIsItsOwnBaseRaises;
begin
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create(TCosNames.Indexed));
  Items.Add(FBuilder.NewReference(Items, 22));
  Items.Add(TCosInteger.Create(0));
  Items.Add(TCosString.Create(Lookup([0]), True));

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(Items);
    end,
    EPdfParseException);
end;

procedure TSpecialColorSpaceTests.TestSpacesAreSharedPerArray;
begin
  Assert.AreSame(FReferences.SpaceOf('Idx'), FReferences.SpaceOf('Idx'));
  Assert.AreSame(FReferences.SpaceOf('Sep'), FReferences.SpaceOf('Sep'));
  Assert.AreSame(FReferences.SpaceOf('DevNAttr'), FReferences.SpaceOf('DevNAttr'));
end;

// DeviceCMYK through ICC_ColorSpace.toRGB: a tint over 1 does not clamp, the 16-bit value wraps
procedure TSpecialColorSpaceTests.TestSeparationTintOverOneWrapsLikeJava;
begin
  FReferences.CheckColors('SepOverOne', ColorTolerance);
  FReferences.CheckImages('SepOverOne', 1);
end;

// The count is checked before anything else is made: the alternate here does not exist, and the message must still be about the colorants
procedure TSpecialColorSpaceTests.TestDeviceNWithHugeColorantListRaisesQuickly;
begin
  const Names = TCosArray.Create;
  for var Index := 1 to HugeColorantCount do
  begin
    Names.Add(TCosName.Create(Format('C%d', [Index])));
  end;
  const Items = NewDeviceNArray(Names, TCosName.Create('NoSuchSpace'), NewGrayTint);
  FBuilder.AddColorSpace('DevNHuge', Items);
  const Stopwatch = TStopwatch.StartNew;
  var Message := '';

  try
    FBuilder.CreateSpace(FBuilder.NewName('DevNHuge'));
  except
    on Failure: EPdfParseException do
    begin
      Message := Failure.Message;
    end;
  end;

  Assert.IsTrue(Message.Contains('colorants'), Message);
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < HugeColorantLimitMilliseconds, Format('Took %d ms', [Stopwatch.ElapsedMilliseconds]));
end;

// PDColorSpace.create: PDFBOX-4833
procedure TSpecialColorSpaceTests.TestDictionaryWithColorSpaceEntryIsTheSpaceOfTheEntry;
begin
  const Wrapper = TCosDictionary.Create;
  Wrapper.SetItem(TCosNames.ColorSpace, TCosName.Create(TCosNames.DeviceRGB));
  FBuilder.AddColorSpace('Wrapped', Wrapper);

  const Space = FBuilder.CreateSpace(FBuilder.NewName('Wrapped'));

  Assert.AreEqual('DeviceRGB', Space.Name);
end;

// PDFBOX-5315
procedure TSpecialColorSpaceTests.TestDictionaryWithColorSpaceEntryThatIsItselfRaises;
begin
  const Wrapper = TCosDictionary.Create;
  Wrapper.SetItem(TCosNames.ColorSpace, FBuilder.NewReference(Wrapper, 23));

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(Wrapper);
    end,
    EPdfParseException);
end;

end.
