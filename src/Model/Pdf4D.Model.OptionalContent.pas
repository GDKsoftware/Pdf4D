// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/optionalcontent/PDOptionalContentProperties.java (3.0.8), the read side:
// getBaseState and isGroupEnabled
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/optionalcontent/PDOptionalContentGroup.java (3.0.8), getRenderState
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/optionalcontent/PDOptionalContentMembershipDictionary.java (3.0.8), getOCGs
// and getVisibilityPolicy
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/documentinterchange/markedcontent/PDPropertyList.java (3.0.8), create (as KindOf)
unit Pdf4D.Model.OptionalContent;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray;

type
  {$SCOPEDENUMS ON}
  // What PDPropertyList.create makes of a dictionary: an optional content group, a membership dictionary, or a plain property list
  TPDOptionalContentKind = (Group, Membership, Other);

  // The usage dictionaries that decide the state of a group for a destination
  TPDOptionalContentUsage = (Export, View, Print);
  {$SCOPEDENUMS OFF}

  // The configuration /OCProperties /D of a document: the base state and the groups that are on or off. It does not own the
  // dictionary and reads the lists of groups once, on first use.
  TPDOptionalContentProperties = class
  private
    FDictionary: TCosDictionary;
    FIsLoaded: Boolean;
    FIsBaseStateOff: Boolean;
    FGroupsOn: TDictionary<TCosDictionary, Boolean>;
    FGroupsOff: TDictionary<TCosDictionary, Boolean>;

    procedure Load;
    procedure LoadBaseState(const Configuration: TCosDictionary);
    procedure LoadGroups(const Configuration: TCosDictionary; const Key: string; const Target: TDictionary<TCosDictionary, Boolean>);

  public
    constructor Create(const Dictionary: TCosDictionary);
    destructor Destroy; override;

    // PDOptionalContentProperties.isGroupEnabled: a group in /ON is on, one in /OFF is off, any other group has the base state
    // (/BaseState is ON unless it says OFF). Group is compared by identity; nil has the base state.
    function IsGroupEnabled(const Group: TCosDictionary): Boolean;

    property CosObject: TCosDictionary read FDictionary;
  end;

  TPDPropertyList = record
    // /Type OCG and /Type OCMD, like PDPropertyList.create
    class function KindOf(const Dictionary: TCosDictionary): TPDOptionalContentKind; static;
  end;

  TPDOptionalContentGroup = record
  private
    // COSDictionary.getCOSName: the name of the entry in capitals, empty when the entry is missing or no name
    class function StateName(const Dictionary: TCosDictionary; const Key: string): string; static;

  public
    // PDOptionalContentGroup.getRenderState: the state that the usage dictionary of Destination gives, View and Print falling back
    // to the export state. False when the group says nothing about it. A state that is neither ON nor OFF counts as no state (PDFBox
    // raises an IllegalArgumentException there).
    class function TryGetRenderState(const Group: TCosDictionary; const Usage: TPDOptionalContentUsage; out IsOn: Boolean): Boolean; static;
  end;

  TPDOptionalContentMembership = record
    // PDOptionalContentMembershipDictionary.getOCGs: the dictionary of /OCGs or the dictionaries in it; other entries are left out
    class function Groups(const Membership: TCosDictionary): TArray<TCosDictionary>; static;
    // The name in /P, AnyOn when there is none
    class function VisibilityPolicy(const Membership: TCosDictionary): string; static;
    // The visibility expression /VE; False when it is missing, no array or empty
    class function TryGetVisibilityExpression(const Membership: TCosDictionary; out Expression: TCosArray): Boolean; static;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names;

{ TPDOptionalContentProperties }

constructor TPDOptionalContentProperties.Create(const Dictionary: TCosDictionary);
begin
  if not Assigned(Dictionary) then
  begin
    raise EArgumentNilException.Create('Dictionary');
  end;

  inherited Create;
  FDictionary := Dictionary;
  FGroupsOn := TDictionary<TCosDictionary, Boolean>.Create;
  FGroupsOff := TDictionary<TCosDictionary, Boolean>.Create;
end;

destructor TPDOptionalContentProperties.Destroy;
begin
  FGroupsOff.Free;
  FGroupsOn.Free;
  inherited;
end;

procedure TPDOptionalContentProperties.LoadBaseState(const Configuration: TCosDictionary);
begin
  var State: TCosBase;
  // BaseState.valueOf: no name is ON, and so is Unchanged; PDFBox raises for a name it does not know, this takes it as ON
  FIsBaseStateOff := (Configuration.TryGetDictionaryObject(TCosNames.BaseState, State) and (State is TCosName) and
                      SameText(TCosName(State).Name, TCosNames.OffOcg));
end;

procedure TPDOptionalContentProperties.LoadGroups(const Configuration: TCosDictionary; const Key: string;
                                                  const Target: TDictionary<TCosDictionary, Boolean>);
begin
  var Items: TCosArray;
  if not Configuration.TryGetCosArray(Key, Items) then
  begin
    Exit;
  end;

  for var Index := 0 to Items.Count - 1 do
  begin
    const Item = Items.GetObject(Index);
    if Item is TCosDictionary then
    begin
      Target.AddOrSetValue(TCosDictionary(Item), True);
    end;
  end;
end;

procedure TPDOptionalContentProperties.Load;
begin
  FIsLoaded := True;
  var Configuration: TCosDictionary;
  if FDictionary.TryGetCosDictionary(TCosNames.D, Configuration) then
  begin
    LoadBaseState(Configuration);
    LoadGroups(Configuration, TCosNames.ON_, FGroupsOn);
    LoadGroups(Configuration, TCosNames.OffOcg, FGroupsOff);
  end;
end;

function TPDOptionalContentProperties.IsGroupEnabled(const Group: TCosDictionary): Boolean;
begin
  if not FIsLoaded then
  begin
    Load;
  end;

  Result := (not FIsBaseStateOff);
  if Assigned(Group) then
  begin
    if FGroupsOn.ContainsKey(Group) then
    begin
      Result := True;
    end
    else if FGroupsOff.ContainsKey(Group) then
    begin
      Result := False;
    end;
  end;
end;

{ TPDPropertyList }

class function TPDPropertyList.KindOf(const Dictionary: TCosDictionary): TPDOptionalContentKind;
begin
  Result := TPDOptionalContentKind.Other;
  const TypeValue = Dictionary.GetItem(TCosNames.Type_);
  if TypeValue is TCosName then
  begin
    const TypeName = TCosName(TypeValue).Name;
    if TypeName = TCosNames.OCG then
    begin
      Result := TPDOptionalContentKind.Group;
    end
    else if TypeName = TCosNames.OCMD then
    begin
      Result := TPDOptionalContentKind.Membership;
    end;
  end;
end;

{ TPDOptionalContentGroup }

class function TPDOptionalContentGroup.StateName(const Dictionary: TCosDictionary; const Key: string): string;
begin
  Result := '';
  var Value: TCosBase;
  if Dictionary.TryGetDictionaryObject(Key, Value) and (Value is TCosName) then
  begin
    Result := UpperCase(TCosName(Value).Name);
  end;
end;

class function TPDOptionalContentGroup.TryGetRenderState(const Group: TCosDictionary; const Usage: TPDOptionalContentUsage; out IsOn: Boolean): Boolean;
begin
  IsOn := False;
  var UsageDictionary: TCosDictionary;
  if not Group.TryGetCosDictionary(TCosNames.Usage, UsageDictionary) then
  begin
    Exit(False);
  end;

  var State := '';
  var Entry: TCosDictionary;
  case Usage of
    TPDOptionalContentUsage.Print:
      begin
        if UsageDictionary.TryGetCosDictionary(TCosNames.Print, Entry) then
        begin
          State := StateName(Entry, TCosNames.PrintState);
        end;
      end;
    TPDOptionalContentUsage.View:
      begin
        if UsageDictionary.TryGetCosDictionary(TCosNames.View, Entry) then
        begin
          State := StateName(Entry, TCosNames.ViewState);
        end;
      end;
    TPDOptionalContentUsage.Export:
      begin
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported optional content usage: %d', [Ord(Usage)]);
  end;

  const IsDefined = ((State = TCosNames.ON_) or (State = TCosNames.OffOcg));
  if (not IsDefined) and UsageDictionary.TryGetCosDictionary(TCosNames.Export, Entry) then
  begin
    State := StateName(Entry, TCosNames.ExportState);
  end;

  IsOn := (State = TCosNames.ON_);
  Result := (IsOn or (State = TCosNames.OffOcg));
end;

{ TPDOptionalContentMembership }

class function TPDOptionalContentMembership.Groups(const Membership: TCosDictionary): TArray<TCosDictionary>;
begin
  Result := nil;
  var Value: TCosBase;
  if not Membership.TryGetDictionaryObject(TCosNames.OCGs, Value) then
  begin
    Exit;
  end;

  if Value is TCosDictionary then
  begin
    SetLength(Result, 1);
    Result[0] := TCosDictionary(Value);
    Exit;
  end;

  if Value is TCosArray then
  begin
    const Items = TCosArray(Value);
    for var Index := 0 to Items.Count - 1 do
    begin
      const Item = Items.GetObject(Index);
      if Item is TCosDictionary then
      begin
        Result := Result + [TCosDictionary(Item)];
      end;
    end;
  end;
end;

class function TPDOptionalContentMembership.VisibilityPolicy(const Membership: TCosDictionary): string;
begin
  Result := TCosNames.AnyOn;
  var Value: TCosBase;
  if Membership.TryGetDictionaryObject(TCosNames.P, Value) and (Value is TCosName) then
  begin
    Result := TCosName(Value).Name;
  end;
end;

class function TPDOptionalContentMembership.TryGetVisibilityExpression(const Membership: TCosDictionary; out Expression: TCosArray): Boolean;
begin
  Result := (Membership.TryGetCosArray(TCosNames.VE, Expression) and (Expression.Count > 0));
end;

end.
