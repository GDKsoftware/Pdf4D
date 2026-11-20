// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/DrawObject.java (3.0.8), the image part, and
// pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/graphics/BeginInlineImage.java (3.0.8)
unit Pdf4D.Render.Operators.Image;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Content.Operator,
  Pdf4D.Content.Operators.DrawObject,
  Pdf4D.Cos.Base,
  Pdf4D.Render.GraphicsEngine;

type
  // Do. Forms are run as the core operator does; an image is drawn by the engine.
  TDrawObjectGraphicsOperator = class(TDrawObjectOperator)
  public
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // BI: the image parameters and the data between ID and EI make an inline image, which the engine draws
  TBeginInlineImageOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TImageOperators = record
    // Do for images and forms, and BI
    class procedure Register(const Engine: TPdfGraphicsEngine); static;
  end;

implementation

uses
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Name,
  Pdf4D.Graphics.Image;

{ TImageOperators }

class procedure TImageOperators.Register(const Engine: TPdfGraphicsEngine);
begin
  Engine.AddOperator(TDrawObjectGraphicsOperator.Create(Engine));
  Engine.AddOperator(TBeginInlineImageOperator.Create(Engine));
end;

{ TDrawObjectGraphicsOperator }

procedure TDrawObjectGraphicsOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const IsImage = ((Length(Operands) > 0) and (Operands[0] is TCosName) and Engine.Resources.IsImageXObject(TCosName(Operands[0]).Name));
  if not IsImage then
  begin
    inherited Process(Operator, Operands);
    Exit;
  end;

  var Stream: TCosStream;
  if not Engine.Resources.TryGetXObject(TCosName(Operands[0]).Name, Stream) then
  begin
    Engine.LogError('Missing XObject: %s', [TCosName(Operands[0]).Name]);
    Exit;
  end;

  const Image = TPDImageXObject.Create(Stream, Engine.Resources);
  try
    (Engine as TPdfGraphicsEngine).DrawImage(Image);
  finally
    Image.Free;
  end;
end;

{ TBeginInlineImageOperator }

function TBeginInlineImageOperator.Name: string;
begin
  Result := TOperatorNames.BeginInlineImage;
end;

procedure TBeginInlineImageOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  if not Assigned(Operator.ImageParameters) then
  begin
    Engine.LogWarning('Inline image without parameters is skipped', []);
    Exit;
  end;

  const Image = TPDInlineImage.Create(Operator.ImageParameters, Operator.ImageData, Engine.Resources);
  try
    GraphicsEngine.DrawImage(Image);
  finally
    Image.Free;
  end;
end;

end.
