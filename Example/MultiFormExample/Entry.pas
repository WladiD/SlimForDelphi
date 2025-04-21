// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Entry;

interface

uses

  Winapi.Messages,
  Winapi.Windows,

  System.Classes,
  System.SysUtils,
  System.Variants,

  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls,

  Data;

type

  TEntryForm = class(TForm)
    CancelButton: TButton;
    EntryDateLabel: TLabel;
    EntryDatePicker: TDateTimePicker;
    IdEdit: TEdit;
    IdLabel: TLabel;
    NameEdit: TEdit;
    NameLabel: TLabel;
    OkButton: TButton;
    procedure EntryDatePickerCloseUp(Sender: TObject);
    procedure EntryDatePickerDropDown(Sender: TObject);
    procedure OkButtonClick(Sender: TObject);
  private
    FEntry: TEntry;
    procedure ApplyFromEntryToForm;
    procedure ApplyFromFormToEntry;
  public
    constructor Create(AOwner: TComponent; AEntry: TEntry);
  end;

implementation

{$R *.dfm}

{ TEntryForm }

constructor TEntryForm.Create(AOwner: TComponent; AEntry: TEntry);
begin
  inherited Create(AOwner);
  FEntry := AEntry;
  ApplyFromEntryToForm;
end;

procedure TEntryForm.EntryDatePickerCloseUp(Sender: TObject);
begin
  OkButton.Default := true;
  CancelButton.Cancel := true;
end;

procedure TEntryForm.OkButtonClick(Sender: TObject);
begin
  ApplyFromFormToEntry;
end;

procedure TEntryForm.ApplyFromEntryToForm;
begin
  IdEdit.Text := FEntry.Id.ToString;
  NameEdit.Text := FEntry.Name;
  EntryDatePicker.Date := FEntry.EntryDate;
end;

procedure TEntryForm.ApplyFromFormToEntry;
begin
  FEntry.Name := NameEdit.Text;
  FEntry.EntryDate := EntryDatePicker.Date;
end;

procedure TEntryForm.EntryDatePickerDropDown(Sender: TObject);
begin
  OkButton.Default := false;
  CancelButton.Cancel := false;
end;

end.
