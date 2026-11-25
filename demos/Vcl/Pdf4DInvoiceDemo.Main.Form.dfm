object FormMain: TFormMain
  Left = 0
  Top = 0
  Caption = 'Pdf4D invoice demo'
  ClientHeight = 640
  ClientWidth = 1000
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnShow = FormShow
  TextHeight = 15
  object PanelFields: TPanel
    Left = 0
    Top = 0
    Width = 260
    Height = 640
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 0
    object ButtonOpen: TButton
      AlignWithMargins = True
      Left = 8
      Top = 8
      Width = 244
      Height = 28
      Margins.Left = 8
      Margins.Top = 8
      Margins.Right = 8
      Margins.Bottom = 8
      Align = alTop
      Caption = 'Open...'
      TabOrder = 0
      OnClick = ButtonOpenClick
    end
    object LabelInvoiceNumber: TLabel
      AlignWithMargins = True
      Left = 8
      Top = 44
      Width = 244
      Height = 15
      Margins.Left = 8
      Margins.Right = 8
      Align = alTop
      Caption = 'Invoice number'
      FocusControl = EditInvoiceNumber
    end
    object EditInvoiceNumber: TEdit
      AlignWithMargins = True
      Left = 8
      Top = 62
      Width = 244
      Height = 23
      Margins.Left = 8
      Margins.Right = 8
      Align = alTop
      TabOrder = 1
      Text = 'INV-2031-0417'
      OnEnter = EditEnter
    end
    object LabelInvoiceDate: TLabel
      AlignWithMargins = True
      Left = 8
      Top = 93
      Width = 244
      Height = 15
      Margins.Left = 8
      Margins.Top = 5
      Margins.Right = 8
      Align = alTop
      Caption = 'Invoice date'
      FocusControl = EditInvoiceDate
    end
    object EditInvoiceDate: TEdit
      AlignWithMargins = True
      Left = 8
      Top = 111
      Width = 244
      Height = 23
      Margins.Left = 8
      Margins.Right = 8
      Align = alTop
      TabOrder = 2
      Text = '2031-03-14'
      OnEnter = EditEnter
    end
    object LabelAmount: TLabel
      AlignWithMargins = True
      Left = 8
      Top = 142
      Width = 244
      Height = 15
      Margins.Left = 8
      Margins.Top = 5
      Margins.Right = 8
      Align = alTop
      Caption = 'Total amount'
      FocusControl = EditAmount
    end
    object EditAmount: TEdit
      AlignWithMargins = True
      Left = 8
      Top = 160
      Width = 244
      Height = 23
      Margins.Left = 8
      Margins.Right = 8
      Align = alTop
      TabOrder = 3
      Text = '1,347.27'
      OnEnter = EditEnter
    end
  end
  object Pdf4DViewer1: TPdf4DViewer
    Left = 260
    Top = 0
    Width = 740
    Height = 640
    Document = Pdf4DDocument1
    Align = alClient
    TabOrder = 1
    OnTextSelected = Pdf4DViewer1TextSelected
  end
  object Pdf4DDocument1: TPdf4DDocument
    Backend = Pdf4DSkiaBackend1
    OnOpened = Pdf4DDocument1Opened
    Left = 24
    Top = 240
  end
  object Pdf4DSkiaBackend1: TPdf4DSkiaBackend
    Left = 24
    Top = 288
  end
  object OpenDialog1: TOpenDialog
    DefaultExt = 'pdf'
    Filter = 'PDF files (*.pdf)|*.pdf'
    Left = 24
    Top = 336
  end
end
