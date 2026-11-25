// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PageDrawer.java (3.0.8): isHiddenOCG, isHiddenOCMD and the visibility
// expressions (isHiddenVisibilityExpression, isHiddenAndVisibilityExpression, isHiddenOrVisibilityExpression and
// isHiddenNotVisibilityExpression)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PDFRenderer.java (3.0.8): isGroupEnabled
unit Pdf4D.Render.OptionalContent;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.OptionalContent,
  Pdf4D.Render.Options;

type
  // Decides whether the optional content of a page is hidden, for a destination. The decision about a dictionary or an expression does
  // not change while a page is drawn, so each one is worked out once: a file cannot make the work explode by letting expressions share
  // their parts. A cycle counts as visible where it is met again, and expressions are not followed deeper than MaxDepth.
  TPdfOptionalContentVisibility = class
  public
    const MaxDepth = 64;

  private
    FProperties: TPDOptionalContentProperties;
    FUsage: TPDOptionalContentUsage;
    FLog: TPdfLog;
    FDecisions: TDictionary<TCosBase, Boolean>;
    FDepth: Integer;
    FHasLoggedDepth: Boolean;

    class function UsageOf(const Destination: TPdfRenderDestination): TPDOptionalContentUsage; static;
    procedure LogDepthReached;
    function IsItemHidden(const Item: TCosBase): Boolean;
    function ComputeHidden(const Item: TCosBase): Boolean;
    function IsGroupHidden(const Group: TCosDictionary): Boolean;
    function IsMembershipHidden(const Membership: TCosDictionary): Boolean;
    function AreGroupsHidden(const Groups: TArray<TCosDictionary>; const Policy: string): Boolean;
    function IsExpressionHidden(const Expression: TCosArray): Boolean;
    function TryGetOperandHidden(const Operand: TCosBase; out IsHidden: Boolean): Boolean;
    function IsAndHidden(const Expression: TCosArray): Boolean;
    function IsOrHidden(const Expression: TCosArray): Boolean;
    function IsNotHidden(const Expression: TCosArray): Boolean;

  public
    // Properties is not owned and may be nil: a document without optional content properties has every group enabled. Log may be nil.
    constructor Create(const Properties: TPDOptionalContentProperties; const Destination: TPdfRenderDestination; const Log: TPdfLog);
    destructor Destroy; override;

    // PageDrawer.isHiddenOCG: PropertyList is the dictionary of /OC or of a property list of a marked-content sequence. Nil, and a
    // dictionary that is no group and no membership dictionary, are not hidden.
    function IsHidden(const PropertyList: TCosDictionary): Boolean;
  end;

implementation

uses
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names;

const
  AndOperator = 'And';
  OrOperator = 'Or';
  NotOperator = 'Not';
  NotLength = 2;

{ TPdfOptionalContentVisibility }

constructor TPdfOptionalContentVisibility.Create(const Properties: TPDOptionalContentProperties; const Destination: TPdfRenderDestination;
                                                 const Log: TPdfLog);
begin
  inherited Create;
  FProperties := Properties;
  FUsage := UsageOf(Destination);
  FLog := Log;
  FDecisions := TDictionary<TCosBase, Boolean>.Create;
end;

destructor TPdfOptionalContentVisibility.Destroy;
begin
  FDecisions.Free;
  inherited;
end;

class function TPdfOptionalContentVisibility.UsageOf(const Destination: TPdfRenderDestination): TPDOptionalContentUsage;
begin
  case Destination of
    TPdfRenderDestination.Export : Result := TPDOptionalContentUsage.Export;
    TPdfRenderDestination.View   : Result := TPDOptionalContentUsage.View;
    TPdfRenderDestination.Print  : Result := TPDOptionalContentUsage.Print;
  else
    raise ENotSupportedException.CreateFmt('Unsupported render destination: %d', [Ord(Destination)]);
  end;
end;

procedure TPdfOptionalContentVisibility.LogDepthReached;
begin
  if (not FHasLoggedDepth) and Assigned(FLog) then
  begin
    FHasLoggedDepth := True;
    FLog.Warning('Visibility expressions are nested as deep as the limit of %d, the rest counts as visible', [MaxDepth]);
  end;
end;

function TPdfOptionalContentVisibility.IsHidden(const PropertyList: TCosDictionary): Boolean;
begin
  Result := (Assigned(PropertyList) and IsItemHidden(PropertyList));
end;

function TPdfOptionalContentVisibility.IsItemHidden(const Item: TCosBase): Boolean;
begin
  if FDecisions.TryGetValue(Item, Result) then
  begin
    Exit;
  end;

  // Until it is known, an item that is met again (a cycle) counts as visible
  FDecisions.AddOrSetValue(Item, False);
  Result := ComputeHidden(Item);
  FDecisions.AddOrSetValue(Item, Result);
end;

function TPdfOptionalContentVisibility.ComputeHidden(const Item: TCosBase): Boolean;
begin
  Result := False;
  if FDepth >= MaxDepth then
  begin
    LogDepthReached;
    Exit;
  end;

  Inc(FDepth);
  try
    if Item is TCosArray then
    begin
      Result := IsExpressionHidden(TCosArray(Item));
    end
    else
    begin
      const PropertyList = TCosDictionary(Item);
      case TPDPropertyList.KindOf(PropertyList) of
        TPDOptionalContentKind.Group      : Result := IsGroupHidden(PropertyList);
        TPDOptionalContentKind.Membership : Result := IsMembershipHidden(PropertyList);
        TPDOptionalContentKind.Other      : Result := False;
      else
        raise ENotSupportedException.Create('Unsupported kind of property list');
      end;
    end;
  finally
    Dec(FDepth);
  end;
end;

// The state in the usage dictionary of the destination wins; without one the configuration of the document says (PDFRenderer.isGroupEnabled)
function TPdfOptionalContentVisibility.IsGroupHidden(const Group: TCosDictionary): Boolean;
begin
  var IsOn: Boolean;
  if TPDOptionalContentGroup.TryGetRenderState(Group, FUsage, IsOn) then
  begin
    Exit(not IsOn);
  end;

  Result := (Assigned(FProperties) and (not FProperties.IsGroupEnabled(Group)));
end;

function TPdfOptionalContentVisibility.IsMembershipHidden(const Membership: TCosDictionary): Boolean;
begin
  var Expression: TCosArray;
  if TPDOptionalContentMembership.TryGetVisibilityExpression(Membership, Expression) then
  begin
    Exit(IsItemHidden(Expression));
  end;

  const Groups = TPDOptionalContentMembership.Groups(Membership);
  const HasGroups = (Length(Groups) > 0);
  Result := (HasGroups and AreGroupsHidden(Groups, TPDOptionalContentMembership.VisibilityPolicy(Membership)));
end;

function TPdfOptionalContentVisibility.AreGroupsHidden(const Groups: TArray<TCosDictionary>; const Policy: string): Boolean;
begin
  var VisibleCount := 0;
  for var Group in Groups do
  begin
    if not IsItemHidden(Group) then
    begin
      Inc(VisibleCount);
    end;
  end;
  const HiddenCount = Length(Groups) - VisibleCount;

  if Policy = TCosNames.AnyOff then
  begin
    // Visible if any of the groups is off
    Result := (HiddenCount = 0);
  end
  else if Policy = TCosNames.AllOn then
  begin
    // Visible only if all groups are on
    Result := (HiddenCount > 0);
  end
  else if Policy = TCosNames.AllOff then
  begin
    // Visible only if all groups are off
    Result := (VisibleCount > 0);
  end
  else
  begin
    // AnyOn, which is also what a policy that is not known gets: visible if any of the groups is on
    Result := (VisibleCount = 0);
  end;
end;

function TPdfOptionalContentVisibility.IsExpressionHidden(const Expression: TCosArray): Boolean;
begin
  Result := False;
  const IsEmpty = (Expression.Count = 0);
  if IsEmpty then
  begin
    Exit;
  end;

  const First = Expression.GetObject(0);
  if not (First is TCosName) then
  begin
    Exit;
  end;

  const OperatorName = TCosName(First).Name;
  if OperatorName = AndOperator then
  begin
    Result := IsAndHidden(Expression);
  end
  else if OperatorName = OrOperator then
  begin
    Result := IsOrHidden(Expression);
  end
  else if OperatorName = NotOperator then
  begin
    Result := IsNotHidden(Expression);
  end;
end;

// An operand is another expression or a group; anything else does not count
function TPdfOptionalContentVisibility.TryGetOperandHidden(const Operand: TCosBase; out IsHidden: Boolean): Boolean;
begin
  Result := ((Operand is TCosArray) or (Operand is TCosDictionary));
  IsHidden := (Result and IsItemHidden(Operand));
end;

// Hidden if at least one operand is hidden
function TPdfOptionalContentVisibility.IsAndHidden(const Expression: TCosArray): Boolean;
begin
  Result := False;
  for var Index := 1 to Expression.Count - 1 do
  begin
    var IsOperandHidden := False;
    if TryGetOperandHidden(Expression.GetObject(Index), IsOperandHidden) and IsOperandHidden then
    begin
      Exit(True);
    end;
  end;
end;

// Hidden only if all operands are hidden
function TPdfOptionalContentVisibility.IsOrHidden(const Expression: TCosArray): Boolean;
begin
  Result := True;
  for var Index := 1 to Expression.Count - 1 do
  begin
    var IsOperandHidden := False;
    if TryGetOperandHidden(Expression.GetObject(Index), IsOperandHidden) and (not IsOperandHidden) then
    begin
      Exit(False);
    end;
  end;
end;

function TPdfOptionalContentVisibility.IsNotHidden(const Expression: TCosArray): Boolean;
begin
  Result := False;
  if Expression.Count <> NotLength then
  begin
    Exit;
  end;

  var IsOperandHidden := False;
  if TryGetOperandHidden(Expression.GetObject(1), IsOperandHidden) then
  begin
    Result := (not IsOperandHidden);
  end;
end;

end.
