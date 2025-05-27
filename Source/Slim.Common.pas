// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Common;

interface

uses

  System.SysUtils;

type

  ESlim = class abstract(Exception)
  protected
    constructor CreateStandardException(const AStandardMessage: String; const AStandardParams: Array of String; const ACustomMessage: String);
  end;

  ESlimStandardException = class(ESlim);

  ESlimNoClass = class(ESlimStandardException) // NO_CLASS <some class>
  public
    constructor Create(const ARequestedClassName: String; const ACustomMessage: String = '');
  end;

  ESlimNoConstructor = class(ESlimStandardException) // NO_CONSTRUCTOR <some class>
  public
    constructor Create(const ARequestedClassName: String; const ACustomMessage: String = '');
  end;

  ESlimCouldNotInvokeConstructor = class(ESlimStandardException) // COULD_NOT_INVOKE_CONSTRUCTOR <some class>
  public
    constructor Create(const ARequestedClassName: String; const ACustomMessage: String = '');
  end;

  ESlimNoInstance = class(ESlimStandardException) // NO_INSTANCE <instance name>
  public
    constructor Create(const ARequestedInstanceName: String; const ACustomMessage: String = '');
  end;

  ESlimNoMethodInClass = class(ESlimStandardException) // NO_METHOD_IN_CLASS <some method> <some class>
  public
    constructor Create(const ARequestedMethod: String);
  end;

  ESlimControlFlow = class abstract(ESlimStandardException);

  ESlimStop = class abstract(ESlimControlFlow);
  ESlimStopTest = class(ESlimStop) // ABORT_SLIM_TEST
  public
    constructor Create(const AReason: String = '');
  end;

  ESlimStopSuite = class(ESlimStop) // ABORT_SLIM_SUITE
  public
    constructor Create(const AReason: String = '');
  end;

  ESlimIgnore = class abstract(ESlimControlFlow);
  ESlimIgnoreScriptTest = class(ESlimIgnore) // IGNORE_SCRIPT_TEST
  public
    constructor Create(const AReason: String = '');
  end;

  ESlimIgnoreAllTests = class(ESlimIgnore) // IGNORE_ALL_TESTS
  public
    constructor Create(const AReason: String = '');
  end;

type

  TSlimConsts = record
  public const
    ScriptTableActor = 'scriptTableActor';
    VoidResponse     = '/__VOID__/';
  end;

implementation

{ ESlim }

constructor ESlim.CreateStandardException(const AStandardMessage: String; const AStandardParams: array of String; const ACustomMessage: String);
var
  ComposedMsg   : String;
  StandardParams: String;
begin
  for var StandardParam in AStandardParams do
  begin
    if StandardParams <> '' then
      StandardParams := StandardParams + ' ';
    StandardParams := StandardParams + StandardParam;
  end;

  ComposedMsg := '__EXCEPTION__:';

  if AStandardMessage <> '' then
  begin
    ComposedMsg := ComposedMsg + AStandardMessage;
    if StandardParams <> '' then
      ComposedMsg := ComposedMsg + ' ' + StandardParams;
    ComposedMsg := ComposedMsg + ':';
  end;

  if ACustomMessage <> '' then
    ComposedMsg := ComposedMsg + ACustomMessage;

  inherited Create(ComposedMsg);
end;

{ ESlimNoInstance }

constructor ESlimNoInstance.Create(const ARequestedInstanceName, ACustomMessage: String);
begin
  CreateStandardException('NO_INSTANCE', [ARequestedInstanceName], ACustomMessage);
end;

{ ESlimNoMethodInClass }

constructor ESlimNoMethodInClass.Create(const ARequestedMethod: String);
begin
  CreateStandardException('NO_METHOD_IN_CLASS', [ARequestedMethod], '');
end;

{ ESlimNoClass }

constructor ESlimNoClass.Create(const ARequestedClassName, ACustomMessage: String);
begin
  CreateStandardException('NO_CLASS', [ARequestedClassName], ACustomMessage);
end;

{ ESlimNoConstructor }

constructor ESlimNoConstructor.Create(const ARequestedClassName, ACustomMessage: String);
begin
  CreateStandardException('NO_CONSTRUCTOR', [ARequestedClassName], ACustomMessage);
end;

{ ESlimCouldNotInvokeConstructor }

constructor ESlimCouldNotInvokeConstructor.Create(const ARequestedClassName, ACustomMessage: String);
begin
  CreateStandardException('COULD_NOT_INVOKE_CONSTRUCTOR', [ARequestedClassName], ACustomMessage);
end;

{ ESlimStopTest }

constructor ESlimStopTest.Create(const AReason: String);
begin
  CreateStandardException('ABORT_SLIM_TEST', [], AReason);
end;

{ ESlimStopSuite }

constructor ESlimStopSuite.Create(const AReason: String);
begin
  CreateStandardException('ABORT_SLIM_SUITE', [], AReason);
end;

{ ESlimIgnoreScriptTest }

constructor ESlimIgnoreScriptTest.Create(const AReason: String);
begin
  CreateStandardException('IGNORE_SCRIPT_TEST', [], AReason);
end;

{ ESlimIgnoreAllTests }

constructor ESlimIgnoreAllTests.Create(const AReason: String);
begin
  CreateStandardException('IGNORE_ALL_TESTS', [], AReason);
end;

end.
