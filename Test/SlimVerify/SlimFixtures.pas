// ======================================================================
// Copyright (c) 2026 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit SlimFixtures;

interface

uses

  System.Classes,
  System.StrUtils,
  System.SysUtils,

  Vcl.Forms,

  Slim.Fixture,
  SlimVerify.Pathologies;

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

  /// <summary>
  ///   The counterpart of SlimProxy.Core "Stop Proxy": a suite that launched this
  ///   host through its COMMAND_PATTERN ends it in a SuiteTearDown page, so the
  ///   host does not stay behind and occupy its port for the next run.
  /// </summary>
  [SlimFixture('SlimVerifyControl')]
  TSlimVerifyControlFixture = class(TSlimFixture)
  public
    [SlimMemberSyncMode(smSynchronized)]
    procedure Shutdown;
  end;

  /// <summary>
  ///   Reads the command and never answers. Checks the read timeout of the proxy:
  ///   without one the proxy blocks along with the target, and FitNesse has no
  ///   read timeout of its own either.
  ///   Synchronized on purpose: that is how a real GUI host behaves, its fixture
  ///   calls run on the main thread.
  /// </summary>
  [SlimFixture('BlockForever')]
  TSlimBlockForeverFixture = class(TSlimFixture)
  public
    [SlimMemberSyncMode(smSynchronized)]
    function Block: String;
  end;

  /// <summary>
  ///   Shows a modal window WITH an error wording. The watchdog has to
  ///   capture and dismiss it, so the pending call fails instead of hanging.
  /// </summary>
  [SlimFixture('ShowErrorDialog')]
  TSlimShowErrorDialogFixture = class(TSlimFixture)
  public
    [SlimMemberSyncMode(smSynchronized)]
    function Show: String;
    [SlimMemberSyncMode(smSynchronized)]
    function ShowFor(ATimeoutMs: Integer): String;
  end;

  /// <summary>
  ///   Shows a modal window WITHOUT an error wording. The watchdog must
  ///   report it and must NEVER dismiss it: a yes/no is a decision of the
  ///   application, and a blind "Yes" could let a call run through to a success
  ///   it never had.
  /// </summary>
  [SlimFixture('ShowQuestion')]
  TSlimShowQuestionFixture = class(TSlimFixture)
  public
    [SlimMemberSyncMode(smSynchronized)]
    function Ask: String;
    [SlimMemberSyncMode(smSynchronized)]
    function AskFor(ATimeoutMs: Integer): String;
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

{ TSlimVerifyControlFixture }

procedure TSlimVerifyControlFixture.Shutdown;
begin
  SlimVerifyCloseWindowAfter(Application.MainFormHandle, SlimVerifyShutdownDelayMs);
end;

{ TSlimBlockForeverFixture }

function TSlimBlockForeverFixture.Block: String;
begin
  // Bounded on purpose: an unbounded sleep would leave the simulation target
  // unusable for the rest of the test run. The bound is far above every read
  // timeout a test would set.
  TThread.Sleep(SlimVerifyOptions.BlockMaxMs);
  Result := 'never seen by the caller';
end;

{ TSlimShowErrorDialogFixture }

function TSlimShowErrorDialogFixture.Show: String;
begin
  Result := ShowFor(30000);
end;

function TSlimShowErrorDialogFixture.ShowFor(ATimeoutMs: Integer): String;
begin
  // "Error" in the title is what the configurable error wordings match. The
  // buttons sit on the native class here - the custom control class is exercised
  // by the start up dialog.
  Result := SlimVerifyShowModalWindow(SlimVerifyDialogClass, 'Button',
    'SlimVerify Error', 'An error occurred while processing the request.',
    ['OK'], ATimeoutMs);
  if Result = '' then
    Result := '(closed itself, nobody dismissed it)';
end;

{ TSlimShowQuestionFixture }

function TSlimShowQuestionFixture.Ask: String;
begin
  Result := AskFor(30000);
end;

function TSlimShowQuestionFixture.AskFor(ATimeoutMs: Integer): String;
begin
  // No error wording anywhere: neither in the title nor in the text. The watchdog
  // must leave this window alone.
  Result := SlimVerifyShowModalWindow(SlimVerifyDialogClass, 'Button',
    'SlimVerify Question', 'Continue with the current operation?',
    ['Yes', 'No'], ATimeoutMs);
  if Result = '' then
    Result := '(closed itself, nobody answered it)';
end;

initialization

RegisterSlimFixture(TSlimDivisionFixture);
RegisterSlimFixture(TSlimEchoFixture);
RegisterSlimFixture(TSlimSetUpFixture);
RegisterSlimFixture(TSlimTearDownFixture);
RegisterSlimFixture(TSlimShouldIBuyMilkFixture);
RegisterSlimFixture(TSlimVerifyControlFixture);
RegisterSlimFixture(TSlimBlockForeverFixture);
RegisterSlimFixture(TSlimShowErrorDialogFixture);
RegisterSlimFixture(TSlimShowQuestionFixture);

end.
