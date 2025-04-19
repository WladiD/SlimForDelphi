// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Exec;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,

  Slim.Fixture,
  Slim.List;

type

  TSlimInstruction = (
    siUndefined,
    siImport,        // [<id>, import, <path>]
    siMake,          // [<id>, make, <instance>, <class>, <arg>...]
    siCall,          // [<id>, call, <instance>, <function>, <arg>...]
    siCallAndAssign, // [<id>, callAndAssign, <symbol>, <instance>, <function>, <arg>...]
    siAssign);       // [<id>, assign, <symbol>, <value>]

  TSlimFixtureDictionary = TObjectDictionary<String, TSlimFixture>;
  TSlimFixtureStack = TObjectStack<TSlimFixture>;

  TSlimStatementContext = record
  public
    Resolver    : TSlimFixtureResolver;
    Instances   : TSlimFixtureDictionary;
    LibInstances: TSlimFixtureStack;
  end;

  TSlimStatement = class
  strict private
    FContext: TSlimStatementContext;
    FRawStmt: TSlimList;
  protected
    FArgStartIndex: Integer;
    function GetRawStmtString(AIndex: Integer): String;
    function HasRawArguments(out AStartIndex: Integer): Boolean;
    property Context: TSlimStatementContext read FContext;
    property RawStmt: TSlimList read FRawStmt;
  protected
    function ResponseException(const AMessage: String; const ADefaultMeaning: String = ''): TSlimList;
    function ResponseOk: TSlimList;
    function ResponseString(const AValue: String): TSlimList;
    function ResponseValue(const AValue: TValue): TSlimList;
  public
    constructor Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext); virtual;
    function Execute: TSlimList; virtual;
    property IdParam: String index 0 read GetRawStmtString;
  end;

  TSlimStatementClass = class of TSlimStatement;

  TSlimStmtImport = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property PathParam: String index 2 read GetRawStmtString;
  end;

  TSlimStmtMake = class(TSlimStatement)
  public
    constructor Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext); override;
    function Execute: TSlimList; override;
    property InstanceParam: String index 2 read GetRawStmtString;
    property ClassParam: String index 3 read GetRawStmtString;
  end;

  TSlimStmtCall = class(TSlimStatement)
  public
    constructor Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext); override;
    function Execute: TSlimList; override;
    property InstanceParam: String index 2 read GetRawStmtString;
    property FunctionParam: String index 3 read GetRawStmtString;
  end;

  TSlimStmtCallAndAssign = class(TSlimStatement)
  public
    constructor Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext); override;
    function Execute: TSlimList; override;
    property SymbolParam: String index 2 read GetRawStmtString;
    property InstanceParam: String index 3 read GetRawStmtString;
    property FunctionParam: String index 4 read GetRawStmtString;
  end;

  TSlimStmtAssign = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property SymbolParam: String index 2 read GetRawStmtString;
    property ValueParam: String index 3 read GetRawStmtString;
  end;

  TSlimExecutor = class
  private
    FLibInstances: TSlimFixtureStack;
    function ExecuteStmt(ARawStmt: TSlimList; const AContext: TSlimStatementContext): TSlimList;
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(ARawStmts: TSlimList): TSlimList;
  end;

function StringToSlimInstruction(const AValue: String): TSlimInstruction;
function SlimInstructionToStatementClass(AInstruction: TSlimInstruction): TSlimStatementClass;

implementation

function StringToSlimInstruction(const AValue: String): TSlimInstruction;
begin
  if SameText(AValue, 'call') then
    Result := siCall
  else if SameText(AValue, 'make') then
    Result := siMake
  else if SameText(AValue, 'callAndAssign') then
    Result := siCallAndAssign
  else if SameText(AValue, 'assign') then
    Result := siAssign
  else if SameText(AValue, 'import') then
    Result := siImport
  else
    Result := siUndefined;
end;

function SlimInstructionToStatementClass(AInstruction: TSlimInstruction): TSlimStatementClass;
const
  InstructionClassMap: Array [TSlimInstruction] of TSlimStatementClass = (
    { siUndefined     } TSlimStatement,
    { siImport        } TSlimStmtImport,
    { siMake          } TSlimStmtMake,
    { siCall          } TSlimStmtCall,
    { siCallAndAssign } TSlimStmtCallAndAssign,
    { siAssign        } TSlimStmtAssign);
begin
  Result := InstructionClassMap[AInstruction];
end;

{ TSlimStatement }

constructor TSlimStatement.Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext);
begin
  FRawStmt := ARawStmt;
  FContext := AContext;
  FArgStartIndex := -1;
end;

function TSlimStatement.GetRawStmtString(AIndex: Integer): String;
begin
  if (AIndex < FRawStmt.Count) and (FRawStmt[AIndex] is TSlimString) then
    Result := FRawStmt[AIndex].ToString
  else
    Result := '';
end;

function TSlimStatement.HasRawArguments(out AStartIndex: Integer): Boolean;
begin
  Result := RawStmt.Count > FArgStartIndex;
  if Result then
    AStartIndex := FArgStartIndex;
end;

function TSlimStatement.ResponseException(const AMessage, ADefaultMeaning: String): TSlimList;
var
  LMessage: String;
begin
  if ADefaultMeaning <> '' then
    LMessage := ADefaultMeaning + ' ' + AMessage
  else
    LMessage := AMessage;
  Result := SlimList([IdParam, '__EXCEPTION__:' + LMessage]);
end;

function TSlimStatement.ResponseOk: TSlimList;
begin
  Result := SlimList([IdParam, 'OK']);
end;

function TSlimStatement.ResponseString(const AValue: String): TSlimList;
begin
  Result := SlimList([IdParam, AValue]);
end;

function TSlimStatement.ResponseValue(const AValue: TValue): TSlimList;
var
  ValueStr: String;
begin
  case AValue.Kind of
    tkFloat:
    begin
      ValueStr := FloatToStr(AValue.AsExtended, TFormatSettings.Invariant);
      if not ValueStr.Contains('.') then
        ValueStr := ValueStr + '.0'; // Java needs this for truncated floats
    end;
  else
    ValueStr := AValue.ToString;
  end;
  Result := SlimList([IdParam, ValueStr]);
end;

function TSlimStatement.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtImport }

function TSlimStmtImport.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtMake }

constructor TSlimStmtMake.Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext);
begin
  inherited;
  FArgStartIndex := 4;
end;

function TSlimStmtMake.Execute: TSlimList;
var
  ArgStartIndex: Integer;
  FixtureClass : TRttiInstanceType;
  Instance     : TSlimFixture;
  InstanceValue: TValue;
  Instances    : TSlimFixtureDictionary;
  InvokeArgs   : TArray<TValue>;
  SlimMethod   : TRttiMethod;
begin
  if not Context.Resolver.TryGetSlimFixture(ClassParam, FixtureClass) then
    Exit(ResponseException(ClassParam, 'NO_CLASS'));

  if not HasRawArguments(ArgStartIndex) then
    ArgStartIndex := -1;

  if not Context.Resolver.TryGetSlimMethod(FixtureClass, '', RawStmt, ArgStartIndex,
    SlimMethod, InvokeArgs) then
    Exit(ResponseException(ClassParam, 'NO_CONSTRUCTOR'));

  try
    InstanceValue := SlimMethod.Invoke(FixtureClass.MetaclassType,InvokeArgs);
  except
    Exit(ResponseException(ClassParam, 'COULD_NOT_INVOKE_CONSTRUCTOR'));
  end;

  Instance := TSlimFixture(InstanceValue.AsObject);
  if InstanceParam.StartsWith('library', True) then
    Context.LibInstances.Push(Instance)
  else
    Context.Instances.AddOrSetValue(InstanceParam, Instance);
  Result := ResponseOk;
end;

{ TSlimStmtCall }

constructor TSlimStmtCall.Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext);
begin
  inherited;
  FArgStartIndex := 4;
end;

function TSlimStmtCall.Execute: TSlimList;
var
  ArgStartIndex: Integer;
  FixtureClass : TRttiInstanceType;
  Instance     : TSlimFixture;
  InvokeArgs   : TArray<TValue>;
  SlimMethod   : TRttiMethod;
  MethodResult : TValue;
begin
  if not Context.Instances.TryGetValue(InstanceParam, Instance) then
    Exit(ResponseException(InstanceParam, 'NO_INSTANCE'));

  FixtureClass := Context.Resolver.GetRttiInstanceTypeFromInstance(Instance);
  if not Assigned(FixtureClass) then
    Exit(ResponseException(Format('RTTI-Error for Instance "%s"', [InstanceParam])));

  if not HasRawArguments(ArgStartIndex) then
    ArgStartIndex := -1;

  if not Context.Resolver.TryGetSlimMethod(FixtureClass, FunctionParam, RawStmt, ArgStartIndex,
    SlimMethod, InvokeArgs) then
    Exit(nil);

  MethodResult := SlimMethod.Invoke(Instance, InvokeArgs);

  if SlimMethod.MethodKind = mkProcedure then
    Result := ResponseString('/__VOID__/')
  else
    Result := ResponseValue(MethodResult);
end;

{ TSlimStmtCallAndAssign }

constructor TSlimStmtCallAndAssign.Create(ARawStmt: TSlimList; const AContext: TSlimStatementContext);
begin
  inherited;
  FArgStartIndex := 5;
end;

function TSlimStmtCallAndAssign.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtAssign }

function TSlimStmtAssign.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimExecutor }

constructor TSlimExecutor.Create;
begin
  FLibInstances := TSlimFixtureStack.Create(True);
end;

destructor TSlimExecutor.Destroy;
begin
  FLibInstances.Free;
  inherited;
end;

function TSlimExecutor.ExecuteStmt(ARawStmt: TSlimList; const AContext: TSlimStatementContext): TSlimList;
var
  Stmt     : TSlimStatement;
  StmtClass: TSlimStatementClass;
  Instr    : TSlimInstruction;
  InstrStr : String;
begin
  InstrStr := ARawStmt[1].ToString;
  Instr := StringToSlimInstruction(InstrStr);
  StmtClass := SlimInstructionToStatementClass(Instr);
  Stmt := StmtClass.Create(ARawStmt, AContext);
  try
    try
      Result := Stmt.Execute;
    except
      on E: Exception do
        Exit(Stmt.ResponseException(Format('%s: %s', [E.ClassName, E.Message])));
    end;
  finally
    Stmt.Free;
  end;
end;

function TSlimExecutor.Execute(ARawStmts: TSlimList): TSlimList;
var
  Context  : TSlimStatementContext;
  Instances: TSlimFixtureDictionary;
  Resolver : TSlimFixtureResolver;
begin
  Resolver := nil;
  Instances := nil;
  Result := TSlimList.Create;
  try
    try
      Resolver := TSlimFixtureResolver.Create;
      Instances := TSlimFixtureDictionary.Create([doOwnsValues]);

      Context := Default(TSlimStatementContext);
      Context.Resolver := Resolver;
      Context.Instances := Instances;
      Context.LibInstances := FLibInstances;

      for var Loop := 0 to ARawStmts.Count - 1 do
      begin
        var LRawStmt: TSlimEntry := ARawStmts[Loop];
        if LRawStmt is TSlimList then
        begin
          var LStmtResult: TSlimList := ExecuteStmt(TSlimList(LRawStmt), Context);
          if Assigned(LStmtResult) then
            Result.Add(LStmtResult);
        end;
      end;
    finally
      Resolver.Free;
      Instances.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
