// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Common.LogSlimMain;

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
  Slim.Server,
  Slim.CmdUtils;

type

  TLogSlimMainForm = class(TForm)
    LogMemo: TMemo;
  private
    procedure ReadRequestHandler(const AValue: String);
    procedure WriteResponseHandler(const AValue: String);
  protected
    FSlimServer: TSlimServer;
    function  AutoStartSlimServer: Boolean; virtual;
    procedure Log(const AMessage: String);
  public
    procedure AfterConstruction; override;
    procedure StartSlimServer;
    property SlimServer: TSlimServer read FSlimServer;
  end;

implementation

{$R *.dfm}

{ TMainForm }

procedure TLogSlimMainForm.AfterConstruction;
var
  LPort: Integer;
begin
  inherited;
  FSlimServer := TSlimServer.Create(Self);

  if not HasSlimPortParam(LPort) then
    LPort := 9000;

  FSlimServer.DefaultPort := LPort;
  FSlimServer.OnReadRequest := ReadRequestHandler;
  FSlimServer.OnWriteResponse := WriteResponseHandler;

  if AutoStartSlimServer then
    StartSlimServer;
end;

/// <summary>
///   False lets a descendant activate the server later - that is what makes
///   a delayed start up simulable.
/// </summary>
function TLogSlimMainForm.AutoStartSlimServer: Boolean;
begin
  Result := True;
end;

/// <summary>Activates the Slim server. Idempotent.</summary>
procedure TLogSlimMainForm.StartSlimServer;
begin
  if not FSlimServer.Active then
    FSlimServer.Active := True;
end;

procedure TLogSlimMainForm.Log(const AMessage: String);
begin
  TThread.Synchronize(nil,
    procedure
    begin
      LogMemo.Lines.Add(TimeToStr(Now) + ' - ' + AMessage);
      LogMemo.Lines.Add(sLineBreak + '---' + sLineBreak);
    end);
end;

procedure TLogSlimMainForm.ReadRequestHandler(const AValue: String);
begin
  Log('Request:' + sLineBreak + AValue);
end;

procedure TLogSlimMainForm.WriteResponseHandler(const AValue: String);
begin
  Log('Response:' + sLineBreak + AValue);
end;

end.
