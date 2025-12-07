// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Proxy.Base;

interface

uses

  Slim.Fixture,
  Slim.Proxy.Interfaces;

type

  TSlimProxyBaseFixture = class(TSlimFixture)
  protected
    FExecutor: ISlimProxyExecutor;
  public
    property Executor: ISlimProxyExecutor read FExecutor write FExecutor;
  end;

implementation

end.
