// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.ViewSupport;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Messaging,
  System.Types,
  FMX.Controls,
  FMX.StdCtrls,
  FMX.Types;

type
  // What the page view and the thumbnails have in common: FMX works in logical units, the controllers in device pixels, so the control
  // knows the scale of the form that shows it, follows its changes and converts lengths and positions.
  TPdfFmxViewControl = class(TControl)
  private
    FScale: Single;
    FScaleChangedId: TMessageSubscriptionId;

    procedure HandleScaleChanged(const Sender: TObject; const Message: System.Messaging.TMessage);

  protected
    // The scale of the form that shows the control; 1 as long as there is none
    function CurrentScale: Single;
    // Takes the scale of the form as the scale of the control
    procedure RefreshScale;
    // True when the form has another scale than the control last used, without a message that reached the control
    function IsScaleStale: Boolean;
    function ToDevice(const LocalPoint: TPointF): TPointF;
    function ToDeviceLength(const LocalLength: Single): Integer;
    // Gives the controller its viewport and scale; called when the scale of the form changes
    procedure UpdateViewport; virtual; abstract;

    // Device pixels per logical unit, as of the last RefreshScale
    property Scale: Single read FScale;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;
  end;

  // The scroll bars of the page view and the thumbnails
  TPdfFmxViewSupport = class
  public
    // A hidden scroll bar that is part of the control, not stored with it; Size is its thickness in logical units
    class function NewScrollBar(const Control: TControl; const Orientation: TOrientation; const Align: TAlignLayout;
                                const Size, SmallChange: Single; const OnChange: TNotifyEvent): TScrollBar; static;
  end;

implementation

uses
  System.Math,
  FMX.Forms;

{ TPdfFmxViewControl }

constructor TPdfFmxViewControl.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FScale := 1;
  FScaleChangedId := TMessageManager.DefaultManager.SubscribeToMessage(TScaleChangedMessage, HandleScaleChanged);
end;

destructor TPdfFmxViewControl.Destroy;
begin
  TMessageManager.DefaultManager.Unsubscribe(TScaleChangedMessage, FScaleChangedId, True);
  inherited;
end;

function TPdfFmxViewControl.CurrentScale: Single;
begin
  Result := 1;
  if Assigned(Scene) then
  begin
    Result := Scene.GetSceneScale;
  end;
  if Result <= 0 then
  begin
    Result := 1;
  end;
end;

procedure TPdfFmxViewControl.RefreshScale;
begin
  FScale := CurrentScale;
end;

function TPdfFmxViewControl.IsScaleStale: Boolean;
begin
  Result := (CurrentScale <> FScale);
end;

function TPdfFmxViewControl.ToDevice(const LocalPoint: TPointF): TPointF;
begin
  Result := TPointF.Create(LocalPoint.X * FScale, LocalPoint.Y * FScale);
end;

function TPdfFmxViewControl.ToDeviceLength(const LocalLength: Single): Integer;
begin
  Result := Max(0, Round(LocalLength * FScale));
end;

procedure TPdfFmxViewControl.HandleScaleChanged(const Sender: TObject; const Message: System.Messaging.TMessage);
begin
  const IsOurForm = Assigned(Root) and (TScaleChangedMessage(Message).Value = Root.GetObject);
  if IsOurForm then
  begin
    UpdateViewport;
    Repaint;
  end;
end;

{ TPdfFmxViewSupport }

class function TPdfFmxViewSupport.NewScrollBar(const Control: TControl; const Orientation: TOrientation; const Align: TAlignLayout;
                                               const Size, SmallChange: Single; const OnChange: TNotifyEvent): TScrollBar;
begin
  Result := TScrollBar.Create(Control);
  Result.Stored := False;
  Result.Locked := True;
  Result.Orientation := Orientation;
  Result.Align := Align;
  if Orientation = TOrientation.Vertical then
  begin
    Result.Width := Size;
  end
  else
  begin
    Result.Height := Size;
  end;
  Result.SmallChange := SmallChange;
  Result.Visible := False;
  Result.OnChange := OnChange;
  Result.Parent := Control;
end;

end.
