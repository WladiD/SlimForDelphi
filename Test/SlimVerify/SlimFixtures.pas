// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit SlimFixtures;

interface

uses

  System.StrUtils,
  System.SysUtils,

  Slim.Fixture;

type

  [SlimFixture('EchoFixture')]
  TSlimEchoFixture = class(TSlimFixture)
  public
    function Echo(const AValue: String): String;
    function EchoInt(const AValue: Integer): Integer;
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

  [SlimFixture('SetUp')]
  TSlimSetUpFixture = class(TSlimDecisionTableFixture)
  public
    constructor Create(const AConfig: String);
  end;

  [SlimFixture('TearDown')]
  TSlimTearDownFixture = class(TSlimDecisionTableFixture)
  end;

  [SlimFixture('ShouldIBuyMilk')]
  TSlimShouldIBuyMilkFixture = class(TSlimDecisionTableFixture)
  private
    FDollars: Integer;
    FPints: Integer;
    FCreditCard: Boolean;
  public
    procedure SetCreditCard(const AValid: String);
    function  GoToStore: String;
    property CashInWallet: Integer read FDollars write FDollars;
    property PintsOfMilkRemaining: Integer read FPints write FPints;
  end;

implementation

{ TSlimEchoFixture }

function TSlimEchoFixture.Echo(const AValue: String): String;
begin
  Result := AValue;
end;

function TSlimEchoFixture.EchoInt(const AValue: Integer): Integer;
begin
  Result := AValue;
end;

{ TSlimDivisionFixture }

function TSlimDivisionFixture.Quotient: Double;
begin
  Result := FNumerator / FDenominator;
end;


{ TSlimSetUpFixture }

constructor TSlimSetUpFixture.Create(const AConfig: String);
begin

end;

{ TSlimShouldIBuyMilkFixture }

function TSlimShouldIBuyMilkFixture.GoToStore: String;
begin
  if (FPints = 0) and ((FDollars > 2) or FCreditCard) then
    Result := 'yes'
  else
    Result := 'no';
end;

procedure TSlimShouldIBuyMilkFixture.SetCreditCard(const AValid: String);
begin
  FCreditCard := SameText(AValid, 'yes');
end;

initialization

RegisterSlimFixture(TSlimDivisionFixture);
RegisterSlimFixture(TSlimEchoFixture);
RegisterSlimFixture(TSlimSetUpFixture);
RegisterSlimFixture(TSlimTearDownFixture);
RegisterSlimFixture(TSlimShouldIBuyMilkFixture);

end.
