object EntryForm: TEntryForm
  Left = 0
  Top = 0
  Caption = 'EntryForm'
  ClientHeight = 238
  ClientWidth = 237
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  DesignSize = (
    237
    238)
  TextHeight = 15
  object NameLabel: TLabel
    Left = 10
    Top = 40
    Width = 40
    Height = 15
    Caption = 'Name'
  end
  object EntryDateLabel: TLabel
    Left = 10
    Top = 70
    Width = 53
    Height = 15
    Caption = 'Entry date'
  end
  object IdLabel: TLabel
    Left = 10
    Top = 10
    Width = 11
    Height = 15
    Caption = 'ID'
  end
  object NameEdit: TEdit
    Left = 100
    Top = 40
    Width = 121
    Height = 23
    TabOrder = 1
  end
  object EntryDatePicker: TDateTimePicker
    Left = 100
    Top = 70
    Width = 121
    Height = 23
    Date = 45767.000000000000000000
    Time = 0.363822060186066700
    TabOrder = 2
    OnCloseUp = EntryDatePickerCloseUp
    OnDropDown = EntryDatePickerDropDown
  end
  object IdEdit: TEdit
    Left = 100
    Top = 10
    Width = 121
    Height = 23
    Enabled = False
    ReadOnly = True
    TabOrder = 0
  end
  object CancelButton: TButton
    Left = 157
    Top = 206
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 4
  end
  object OkButton: TButton
    Left = 77
    Top = 206
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 3
    OnClick = OkButtonClick
  end
end
