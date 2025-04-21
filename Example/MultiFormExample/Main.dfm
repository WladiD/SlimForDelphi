object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'MainForm'
  ClientHeight = 398
  ClientWidth = 703
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 15
  object MainGrid: TStringGrid
    Left = 0
    Top = 0
    Width = 703
    Height = 363
    Align = alClient
    TabOrder = 0
  end
  object BottomPanel: TPanel
    Left = 0
    Top = 363
    Width = 703
    Height = 35
    Align = alBottom
    BevelEdges = [beTop]
    BevelKind = bkSoft
    BevelOuter = bvNone
    TabOrder = 1
    object AddButton: TButton
      Left = 5
      Top = 5
      Width = 75
      Height = 25
      Caption = '&Add'
      TabOrder = 0
      OnClick = AddButtonClick
    end
  end
end
