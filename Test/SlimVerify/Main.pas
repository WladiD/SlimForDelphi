// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Main;

interface

uses

  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,

  Slim.Fixture,
  Slim.Server;

type

  TMainForm = class(TForm)
    LogMemo: TMemo;
  private
    FSlimServer: TSlimServer;
    procedure Log(const AMessage: String);
    procedure ReadRequestHandler(const AValue: String);
    procedure WriteResponseHandler(const AValue: String);
  public
    procedure AfterConstruction; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

{ TMainForm }

procedure TMainForm.AfterConstruction;
begin
  inherited;
  FSlimServer := TSlimServer.Create(Self);
  FSlimServer.DefaultPort := 9000;
  FSlimServer.Active := True;
  FSlimServer.OnReadRequest := ReadRequestHandler;
  FSlimServer.OnWriteResponse := WriteResponseHandler;
end;

procedure TMainForm.Log(const AMessage: String);
begin
  TThread.Synchronize(nil,
    procedure
    begin
      LogMemo.Lines.Add(TimeToStr(Now) + ' - ' + AMessage);
      LogMemo.Lines.Add(sLineBreak + '---' + sLineBreak);
    end);
end;

procedure TMainForm.ReadRequestHandler(const AValue: String);
begin
  Log('Request:' + sLineBreak + AValue);
end;

procedure TMainForm.WriteResponseHandler(const AValue: String);
begin
  Log('Response:' + sLineBreak + AValue);
end;

end.
