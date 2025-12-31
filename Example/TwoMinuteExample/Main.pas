// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Main;

interface

uses

  Winapi.Windows,
  Winapi.Messages,

  System.Classes,
  System.SysUtils,
  System.Variants,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls,

  Slim.Fixture,

  Common.LogSlimMain;

type

  TMainForm = class(TLogSlimMainForm)
  end;

  [SlimFixture('Division', 'eg')]
  TSlimDivisionFixture = class(TSlimDecisionTableFixture)
  private
    FNumerator: Double;
    FDenominator: Double;
  public
    property Numerator: Double read FNumerator write FNumerator;
    property Denominator: Double read FDenominator write FDenominator;
    function Quotient: Double;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

{ TSlimDivisionFixture }

function TSlimDivisionFixture.Quotient: Double;
begin
  Result := FNumerator / FDenominator;
end;

initialization

RegisterSlimFixture(TSlimDivisionFixture);

end.
