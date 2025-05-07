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

  ESlimControlFlow = class abstract(Exception);

  ESlimStop = class abstract(ESlimControlFlow);
  ESlimStopTest = class(ESlimStop);
  ESlimStopSuite = class(ESlimStop);

  ESlimIgnore = class abstract(ESlimControlFlow);
  ESlimIgnoreScriptTest = class(ESlimIgnore);
  ESlimIgnoreAllTests = class(ESlimIgnore);

implementation

end.
