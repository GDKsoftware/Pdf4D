// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.ClipMask;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Mask;

type
  // What a clip chain comes to on a device of a given size
  TTsClipKind = (
    // Nothing is clipped
    None,
    // The clip is a rectangle of whole pixels: the scan converters clip to it and the draw needs no mask
    Rect,
    // The clip is a mask of the size of the device (and the rectangle that holds all of its pixels)
    Mask,
    // Nothing can show: the chain clips everything away
    Empty);

  // The clip of a device: a chain of clip paths, from the root to the leaf, that is applied as Java2D does (no anti-aliasing, the edges
  // snapped as TPdfStrokeNormalizer.SnapForClip does). Rectangles of the chain are intersected as rectangles of whole pixels; only a path
  // that is not a rectangle makes a mask. The result is built when the chain changes, and the chain is compared by identity.
  //
  // The paths that were applied are kept as a stack of levels, one per link of the chain (as the Skia device keeps its applied list): a new
  // chain applies only the links that are not on the stack, after the deepest one that is, so a long chain costs work in proportion to its
  // length. A level holds the rectangle that the chain up to it comes to and, for a path that is not a rectangle, the mask. A mask is never
  // changed once it is built (the next one is a copy), and only the masks of the last few such levels are kept, so that the memory is bound;
  // a chain that returns to a level that lost its mask is applied again from below it.
  //
  // Must run inside TTsFloatMode: the paths are converted and filled.
  TTsClipMask = class
  private const
    // The number of levels whose mask is kept
    MaxKeptMasks = 8;

  private type
    TClipLevel = record
      Link: IPdfClipPath;
      // The clip rectangle of the chain up to this level
      Left: Integer;
      Top: Integer;
      Right: Integer;
      Bottom: Integer;
      IsEmpty: Boolean;
      // The chain up to this level has a mask; the level at MaskOwner holds it
      HasMask: Boolean;
      MaskOwner: Integer;
      // Only on the level that made the mask: the data (kept unless IsMaskDropped), zero outside of the clean rectangle
      OwnMask: TBytes;
      IsMaskDropped: Boolean;
      CleanLeft: Integer;
      CleanTop: Integer;
      CleanRight: Integer;
      CleanBottom: Integer;
    end;

  private
    FChain: IPdfClipPath;
    FLevels: TArray<TClipLevel>;
    FLevelCount: Integer;
    // The indexes of the levels that hold a mask, from the oldest to the newest
    FMaskOwners: TArray<Integer>;
    FAppliedLinkCount: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FIsBuilt: Boolean;
    FKind: TTsClipKind;
    FLeft: Integer;
    FTop: Integer;
    FRight: Integer;
    FBottom: Integer;
    FMask: TTsMask;
    FBuildCount: Integer;
    FForceMask: Boolean;
    FMaxPathVerbs: Integer;
    // The last combination of the clip with a soft mask: what it was made of (the build of the chain, the geometry and a copy of the values of
    // the mask) and the mask. A new combination is a new mask, so a pointer that was handed out never changes.
    FBuildNumber: Integer;
    FCombined: TTsMask;
    FCombinedBuild: Integer;
    FCombinedLeft: Integer;
    FCombinedTop: Integer;
    FCombinedWidth: Integer;
    FCombinedHeight: Integer;
    FCombinedOutside: Byte;
    FCombinedValues: TBytes;
    FHasCombined: Boolean;

    procedure Build;
    procedure Reset;
    function IsApplied(const Link: IPdfClipPath): Boolean;
    function IsUsableBase(const LevelIndex: Integer): Boolean;
    procedure DropLevels(const KeptCount: Integer);
    procedure PushLevel(const Link: IPdfClipPath);
    procedure ApplyLink(var Level: TClipLevel; const LevelIndex: Integer);
    procedure ApplyPath(var Level: TClipLevel; const LevelIndex: Integer; const Ts: TTsPath; const FillRule: TPdfFillRule);
    procedure KeepMaskOwner(const LevelIndex: Integer);
    procedure FinishBuild;
    function TryIntersectRect(var Level: TClipLevel; const Left, Top, Right, Bottom: Integer): Boolean;
    function TryStartMask: Boolean;
    procedure ClearOutsideRect;
    function IsCombinedFrom(const SoftMask: TPdfAlphaMask): Boolean;
    function ClipValueAt(const X, Y: Integer): Byte;
    procedure SetForceMask(const Value: Boolean);
    function GetRect: TTsScreenIntRect;

  public
    // Takes the clip of the next draws on a device of Width * Height pixels. Nothing is built when the chain and the size are those of the
    // last call.
    constructor Create;

    procedure Update(const Clip: IPdfClipPath; const Width, Height: Integer);

    property Kind: TTsClipKind read FKind;
    // With Kind Rect or Mask: the rectangle inside the device that holds the clip; the whole device for a clip of the whole device
    property Rect: TTsScreenIntRect read GetRect;
    // With Kind Mask: the mask; the data of a mask of another kind is empty
    property Mask: TTsMask read FMask;
    // With Kind Mask: the mask for TTsPainter, which draws through a pointer; nil for the other kinds
    function MaskRef: PTsMask;
    // The clip multiplied with the soft mask: a mask of the size of the device, nil when it cannot be made. Valid until the next call or the next
    // Update that builds another chain. Call it for a clip that is not Empty.
    function Combine(const SoftMask: TPdfAlphaMask): PTsMask;
    // The number of chains that were built (a chain of nil is not built). For the test properties of the device.
    property BuildCount: Integer read FBuildCount;
    // For the test properties of the device: the number of paths of chains that were applied: a path that stays on the stack between two chains is not applied again
    property AppliedLinkCount: Integer read FAppliedLinkCount;
    // A path of the chain with more verbs raises EPdfLimitExceededException when the chain is built, before anything is drawn
    property MaxPathVerbs: Integer read FMaxPathVerbs write FMaxPathVerbs;
    // For the test properties of the device: a rectangle is made into a mask as well, so that a test can compare the two ways to clip
    property ForceMask: Boolean read FForceMask write SetForceMask;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Render.StrokeNormalizer,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Painter,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.Conversion;

const
  // The centre of a pixel, as far from its boundary
  HalfPixel: Single = 0.5;

type
  // A path that is one rectangle with its sides along the axes
  TAxisRect = record
    Left: Single;
    Top: Single;
    Right: Single;
    Bottom: Single;
  end;

function TryReadAxisRect(const Path: TTsPath; out Rect: TAxisRect): Boolean;
begin
  Rect := Default(TAxisRect);

  const Verbs = Path.Verbs;
  const Points = Path.Points;

  // Move, three lines and Close; or a fourth line that returns to the start
  var PointCount := 0;
  if (Length(Verbs) = 5) and (Verbs[0] = TTsPathVerb.Move) and (Verbs[1] = TTsPathVerb.Line) and (Verbs[2] = TTsPathVerb.Line) and
     (Verbs[3] = TTsPathVerb.Line) and (Verbs[4] = TTsPathVerb.Close) then
  begin
    PointCount := 4;
  end
  else if (Length(Verbs) = 6) and (Verbs[0] = TTsPathVerb.Move) and (Verbs[1] = TTsPathVerb.Line) and (Verbs[2] = TTsPathVerb.Line) and
          (Verbs[3] = TTsPathVerb.Line) and (Verbs[4] = TTsPathVerb.Line) and (Verbs[5] = TTsPathVerb.Close) then
  begin
    PointCount := 5;
  end;

  if (PointCount = 0) or (Length(Points) <> PointCount) then
  begin
    Exit(False);
  end;

  if PointCount = 5 then
  begin
    const ReturnsToStart = ((Points[4].X = Points[0].X) and (Points[4].Y = Points[0].Y));
    if not ReturnsToStart then
    begin
      Exit(False);
    end;
  end;

  const HorizontalFirst = ((Points[0].Y = Points[1].Y) and (Points[1].X = Points[2].X) and (Points[2].Y = Points[3].Y) and
                           (Points[3].X = Points[0].X));
  const VerticalFirst = ((Points[0].X = Points[1].X) and (Points[1].Y = Points[2].Y) and (Points[2].X = Points[3].X) and
                         (Points[3].Y = Points[0].Y));
  if not (HorizontalFirst or VerticalFirst) then
  begin
    Exit(False);
  end;

  Rect.Left := Points[0].X;
  Rect.Right := Points[0].X;
  Rect.Top := Points[0].Y;
  Rect.Bottom := Points[0].Y;
  for var Index := 1 to 3 do
  begin
    if Points[Index].X < Rect.Left then
    begin
      Rect.Left := Points[Index].X;
    end;
    if Points[Index].X > Rect.Right then
    begin
      Rect.Right := Points[Index].X;
    end;
    if Points[Index].Y < Rect.Top then
    begin
      Rect.Top := Points[Index].Y;
    end;
    if Points[Index].Y > Rect.Bottom then
    begin
      Rect.Bottom := Points[Index].Y;
    end;
  end;

  Result := True;
end;

// The pixel boundary that a scan conversion without anti-aliasing takes for an edge at Value: the first pixel whose centre lies beyond it
function PixelEdge(const Value: Single): Integer;
begin
  const Shifted: Single = Value + HalfPixel;

  Result := TTsScalar.SaturateFloor(Shifted);
end;

{ TTsClipMask }

constructor TTsClipMask.Create;
begin
  inherited Create;
  FMaxPathVerbs := High(Integer);
end;

procedure TTsClipMask.Update(const Clip: IPdfClipPath; const Width, Height: Integer);
begin
  const IsCurrent = (FIsBuilt and (FWidth = Width) and (FHeight = Height) and (FChain = Clip));
  if IsCurrent then
  begin
    Exit;
  end;

  FChain := Clip;
  FWidth := Width;
  FHeight := Height;
  FIsBuilt := False;
  Build;
  FIsBuilt := True;
end;

function TTsClipMask.MaskRef: PTsMask;
begin
  if FKind <> TTsClipKind.Mask then
  begin
    Exit(nil);
  end;

  Result := @FMask;
end;

function TTsClipMask.ClipValueAt(const X, Y: Integer): Byte;
begin
  case FKind of
    TTsClipKind.Mask:
      begin
        Exit(FMask.Data[Y * FWidth + X]);
      end;
    TTsClipKind.Rect:
      begin
        const IsInside = ((X >= FLeft) and (X < FRight) and (Y >= FTop) and (Y < FBottom));
        if IsInside then
        begin
          Exit(255);
        end;
        Exit(0);
      end;
    TTsClipKind.Empty:
      begin
        Exit(0);
      end;
  end;

  Result := 255;
end;

function TTsClipMask.IsCombinedFrom(const SoftMask: TPdfAlphaMask): Boolean;
begin
  const IsSameMask = (FHasCombined and (FCombinedBuild = FBuildNumber) and (FCombinedLeft = SoftMask.Left) and (FCombinedTop = SoftMask.Top) and
                      (FCombinedWidth = SoftMask.Width) and (FCombinedHeight = SoftMask.Height) and (FCombinedOutside = SoftMask.OutsideValue) and
                      (Length(FCombinedValues) = Length(SoftMask.Values)));
  if not IsSameMask then
  begin
    Exit(False);
  end;

  // The object of a soft mask can be freed and another one made at the same address, so the values are compared as well
  Result := ((Length(FCombinedValues) = 0) or CompareMem(Pointer(FCombinedValues), Pointer(SoftMask.Values), Length(FCombinedValues)));
end;

function TTsClipMask.Combine(const SoftMask: TPdfAlphaMask): PTsMask;
begin
  Result := nil;

  const ValueCount = Int64(SoftMask.Width) * Int64(SoftMask.Height);
  const HasAllValues = ((SoftMask.Width >= 0) and (SoftMask.Height >= 0) and (Int64(Length(SoftMask.Values)) >= ValueCount));
  if not HasAllValues then
  begin
    Exit;
  end;

  if IsCombinedFrom(SoftMask) then
  begin
    Exit(@FCombined);
  end;

  var Combined: TTsMask;
  if not TTsMask.TryCreate(Cardinal(FWidth), Cardinal(FHeight), Combined) then
  begin
    Exit;
  end;

  for var Y := 0 to FHeight - 1 do
  begin
    const RowInMask = Int64(Y) - SoftMask.Top;
    const IsRowInMask = ((RowInMask >= 0) and (RowInMask < SoftMask.Height));
    for var X := 0 to FWidth - 1 do
    begin
      var Value := SoftMask.OutsideValue;
      const ColumnInMask = Int64(X) - SoftMask.Left;
      if IsRowInMask and (ColumnInMask >= 0) and (ColumnInMask < SoftMask.Width) then
      begin
        Value := SoftMask.Values[RowInMask * SoftMask.Width + ColumnInMask];
      end;

      Combined.Data[Y * FWidth + X] := TTsColorMath.PremultiplyU8(ClipValueAt(X, Y), Value);
    end;
  end;

  FCombined := Combined;
  FCombinedBuild := FBuildNumber;
  FCombinedLeft := SoftMask.Left;
  FCombinedTop := SoftMask.Top;
  FCombinedWidth := SoftMask.Width;
  FCombinedHeight := SoftMask.Height;
  FCombinedOutside := SoftMask.OutsideValue;
  FCombinedValues := Copy(SoftMask.Values, 0, Integer(ValueCount));
  FHasCombined := True;
  Result := @FCombined;
end;

procedure TTsClipMask.SetForceMask(const Value: Boolean);
begin
  if FForceMask = Value then
  begin
    Exit;
  end;

  FForceMask := Value;
  FIsBuilt := False;
end;

function TTsClipMask.GetRect: TTsScreenIntRect;
begin
  if not TTsScreenIntRect.TryFromXYWH(Cardinal(FLeft), Cardinal(FTop), Cardinal(FRight - FLeft), Cardinal(FBottom - FTop), Result) then
  begin
    Result := Default(TTsScreenIntRect);
  end;
end;

procedure TTsClipMask.Reset;
begin
  FKind := TTsClipKind.None;
  FLeft := 0;
  FTop := 0;
  FRight := FWidth;
  FBottom := FHeight;
  FMask := Default(TTsMask);
end;

function TTsClipMask.IsApplied(const Link: IPdfClipPath): Boolean;
begin
  const Depth = Link.Depth;
  Result := ((Depth >= 1) and (Depth <= FLevelCount) and (FLevels[Depth - 1].Link = Link));
end;

// A level can be built on when the mask of its chain is still kept
function TTsClipMask.IsUsableBase(const LevelIndex: Integer): Boolean;
begin
  const Level = FLevels[LevelIndex];
  Result := ((not Level.HasMask) or (not FLevels[Level.MaskOwner].IsMaskDropped));
end;

// The levels from KeptCount on are removed
procedure TTsClipMask.DropLevels(const KeptCount: Integer);
begin
  for var Index := KeptCount to FLevelCount - 1 do
  begin
    FLevels[Index] := Default(TClipLevel);
  end;
  FLevelCount := KeptCount;

  var OwnerCount := Length(FMaskOwners);
  while (OwnerCount > 0) and (FMaskOwners[OwnerCount - 1] >= KeptCount) do
  begin
    Dec(OwnerCount);
  end;
  SetLength(FMaskOwners, OwnerCount);
end;

// A level whose mask is new: the oldest masks beyond the last few are let go
procedure TTsClipMask.KeepMaskOwner(const LevelIndex: Integer);
begin
  SetLength(FMaskOwners, Length(FMaskOwners) + 1);
  FMaskOwners[High(FMaskOwners)] := LevelIndex;

  if Length(FMaskOwners) > MaxKeptMasks then
  begin
    const Oldest = FMaskOwners[0];
    FLevels[Oldest].OwnMask := nil;
    FLevels[Oldest].IsMaskDropped := True;
    Move(FMaskOwners[1], FMaskOwners[0], (Length(FMaskOwners) - 1) * SizeOf(Integer));
    SetLength(FMaskOwners, Length(FMaskOwners) - 1);
  end;
end;

// The new links of the chain are applied on top of the deepest link that is on the stack. Iterative, because a file can chain very many
// clips.
procedure TTsClipMask.Build;
begin
  Inc(FBuildNumber);
  Reset;

  const HasClip = Assigned(FChain);
  if not HasClip then
  begin
    DropLevels(0);
    Exit;
  end;

  Inc(FBuildCount);

  const IsDeviceUsable = ((FWidth > 0) and (FHeight > 0));
  if not IsDeviceUsable then
  begin
    DropLevels(0);
    FKind := TTsClipKind.Empty;
    Exit;
  end;

  var Link := FChain;
  while Assigned(Link) and (not IsApplied(Link)) do
  begin
    Link := Link.Parent;
  end;

  var KeptCount := 0;
  if Assigned(Link) then
  begin
    KeptCount := Link.Depth;
  end;

  while (KeptCount > 0) and (not IsUsableBase(KeptCount - 1)) do
  begin
    Dec(KeptCount);
  end;
  DropLevels(KeptCount);

  const Missing = FChain.Depth - KeptCount;
  var Pending: TArray<IPdfClipPath>;
  SetLength(Pending, Missing);
  Link := FChain;
  for var Index := Missing - 1 downto 0 do
  begin
    Pending[Index] := Link;
    Link := Link.Parent;
  end;

  if FLevelCount + Missing > Length(FLevels) then
  begin
    SetLength(FLevels, FLevelCount + Missing);
  end;

  for var Item in Pending do
  begin
    PushLevel(Item);
  end;

  FinishBuild;
end;

procedure TTsClipMask.PushLevel(const Link: IPdfClipPath);
begin
  var Level := Default(TClipLevel);
  if FLevelCount > 0 then
  begin
    Level := FLevels[FLevelCount - 1];
    Level.OwnMask := nil;
    Level.IsMaskDropped := False;
  end
  else
  begin
    Level.Right := FWidth;
    Level.Bottom := FHeight;
    Level.MaskOwner := -1;
  end;
  Level.Link := Link;

  Inc(FAppliedLinkCount);
  if not Level.IsEmpty then
  begin
    ApplyLink(Level, FLevelCount);
  end;

  FLevels[FLevelCount] := Level;
  Inc(FLevelCount);
  if Length(Level.OwnMask) > 0 then
  begin
    KeepMaskOwner(FLevelCount - 1);
  end;
end;

procedure TTsClipMask.ApplyLink(var Level: TClipLevel; const LevelIndex: Integer);
begin
  const Link = Level.Link;

  // Java2D moves the vertices of a clip before it takes the pixels, so the path goes on in device pixels
  if Link.Path.VerbCount > FMaxPathVerbs then
  begin
    raise EPdfLimitExceededException.CreateFmt('A clip path has %d verbs, more than the limit of %d', [Link.Path.VerbCount, FMaxPathVerbs]);
  end;

  // A point that is not a number clips everything away: it must not be snapped into a finite one first
  if not TTsConversion.HasFinitePoints(Link.Path) then
  begin
    Level.IsEmpty := True;
    Exit;
  end;

  const Snapped = TPdfStrokeNormalizer.SnapForClip(Link.Path, Link.Transform);
  var Ts: TTsPath;
  var IsConverted: Boolean;
  try
    IsConverted := TTsConversion.TryToPath(Snapped, Ts);
  finally
    Snapped.Free;
  end;

  // A path without a segment, or with a point that is not a number, clips everything away
  if not IsConverted then
  begin
    Level.IsEmpty := True;
    Exit;
  end;

  ApplyPath(Level, LevelIndex, Ts, Link.FillRule);
end;

procedure TTsClipMask.ApplyPath(var Level: TClipLevel; const LevelIndex: Integer; const Ts: TTsPath; const FillRule: TPdfFillRule);
begin
  var Edges: TAxisRect;
  const IsRect = TryReadAxisRect(Ts, Edges);
  if IsRect then
  begin
    Level.IsEmpty := not TryIntersectRect(Level, PixelEdge(Edges.Left), PixelEdge(Edges.Top), PixelEdge(Edges.Right), PixelEdge(Edges.Bottom));
    Exit;
  end;

  // The mask of the chain so far is copied, never changed: the levels above and the clip of the last build may still use it
  var Mask: TTsMask;
  if not TTsMask.TryCreate(Cardinal(FWidth), Cardinal(FHeight), Mask) then
  begin
    Level.IsEmpty := True;
    Exit;
  end;

  if Level.HasMask then
  begin
    const Owner = FLevels[Level.MaskOwner];
    Move(Owner.OwnMask[0], Mask.Data[0], Length(Mask.Data));
    Level.CleanLeft := Owner.CleanLeft;
    Level.CleanTop := Owner.CleanTop;
    Level.CleanRight := Owner.CleanRight;
    Level.CleanBottom := Owner.CleanBottom;
  end
  else
  begin
    for var Y := Level.Top to Level.Bottom - 1 do
    begin
      FillChar(Mask.Data[Y * FWidth + Level.Left], Level.Right - Level.Left, 255);
    end;
    Level.CleanLeft := Level.Left;
    Level.CleanTop := Level.Top;
    Level.CleanRight := Level.Right;
    Level.CleanBottom := Level.Bottom;
  end;

  Mask.IntersectPath(Ts, TTsConversion.ToFillRule(FillRule), False, TTsTransform.Identity);
  Level.OwnMask := Mask.Data;
  Level.HasMask := True;
  Level.MaskOwner := LevelIndex;
end;

// The clip of the whole chain, from its top level
procedure TTsClipMask.FinishBuild;
begin
  const Top = FLevels[FLevelCount - 1];
  if Top.IsEmpty then
  begin
    Reset;
    FKind := TTsClipKind.Empty;
    Exit;
  end;

  FLeft := Top.Left;
  FTop := Top.Top;
  FRight := Top.Right;
  FBottom := Top.Bottom;

  const IsWholeDevice = ((FLeft = 0) and (FTop = 0) and (FRight = FWidth) and (FBottom = FHeight));
  if (not Top.HasMask) and IsWholeDevice then
  begin
    Exit;
  end;

  const NeedsMask = (Top.HasMask or FForceMask);
  if not NeedsMask then
  begin
    FKind := TTsClipKind.Rect;
    Exit;
  end;

  if Top.HasMask then
  begin
    // The mask alone is the clip; the rectangle only tells where it can be other than 0. A mask that is clean outside of the rectangle is
    // taken as it is, else a copy is cleared.
    const Owner = FLevels[Top.MaskOwner];
    FMask.Width := Cardinal(FWidth);
    FMask.Height := Cardinal(FHeight);
    const IsClean = ((Owner.CleanLeft = FLeft) and (Owner.CleanTop = FTop) and (Owner.CleanRight = FRight) and (Owner.CleanBottom = FBottom));
    if IsClean then
    begin
      FMask.Data := Owner.OwnMask;
    end
    else
    begin
      FMask.Data := Copy(Owner.OwnMask);
      ClearOutsideRect;
    end;
  end
  else if not TryStartMask then
  begin
    Reset;
    FKind := TTsClipKind.Empty;
    Exit;
  end;

  if FForceMask then
  begin
    FLeft := 0;
    FTop := 0;
    FRight := FWidth;
    FBottom := FHeight;
  end;

  FKind := TTsClipKind.Mask;
end;

// The rectangle of whole pixels, taken into the clip rectangle of the level; False when nothing is left of it
function TTsClipMask.TryIntersectRect(var Level: TClipLevel; const Left, Top, Right, Bottom: Integer): Boolean;
begin
  if Left > Level.Left then
  begin
    Level.Left := Left;
  end;
  if Top > Level.Top then
  begin
    Level.Top := Top;
  end;
  if Right < Level.Right then
  begin
    Level.Right := Right;
  end;
  if Bottom < Level.Bottom then
  begin
    Level.Bottom := Bottom;
  end;

  Result := ((Level.Left < Level.Right) and (Level.Top < Level.Bottom));
end;

// A mask that lets through what the clip rectangle holds so far
function TTsClipMask.TryStartMask: Boolean;
begin
  if not TTsMask.TryCreate(Cardinal(FWidth), Cardinal(FHeight), FMask) then
  begin
    Exit(False);
  end;

  for var Y := FTop to FBottom - 1 do
  begin
    FillChar(FMask.Data[Y * FWidth + FLeft], FRight - FLeft, 255);
  end;

  Result := True;
end;

procedure TTsClipMask.ClearOutsideRect;
begin
  for var Y := 0 to FHeight - 1 do
  begin
    const RowStart = Y * FWidth;
    const IsRowInside = ((Y >= FTop) and (Y < FBottom));
    if not IsRowInside then
    begin
      FillChar(FMask.Data[RowStart], FWidth, 0);
      Continue;
    end;

    if FLeft > 0 then
    begin
      FillChar(FMask.Data[RowStart], FLeft, 0);
    end;
    if FRight < FWidth then
    begin
      FillChar(FMask.Data[RowStart + FRight], FWidth - FRight, 0);
    end;
  end;
end;

end.
