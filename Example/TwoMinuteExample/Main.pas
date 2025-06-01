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
    class constructor Create;
    procedure Log(const AMessage: String);
    procedure ReadRequestHandler(const AValue: String);
    procedure WriteResponseHandler(const AValue: String);
  public
    procedure AfterConstruction; override;
  end;

  [SlimFixture('Division', 'eg')]
  TSlimDivisionFixture = class(TSlimDecisionTableFixture)
  private
    FNumerator: Double;
    FDenominator: Double;
  public
    constructor Create;
    property Numerator: Double read FNumerator write FNumerator;
    property Denominator: Double read FDenominator write FDenominator;
    function Quotient: Double;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

{ TMainForm }

class constructor TMainForm.Create;
begin
  RegisterSlimFixture(TSlimDivisionFixture);
end;

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

{ TSlimDivisionFixture }

constructor TSlimDivisionFixture.Create;
begin
//  raise Exception.Create('I''m not in the mood today.');
end;

function TSlimDivisionFixture.Quotient: Double;
begin
  Result := FNumerator / FDenominator;
end;

end.
