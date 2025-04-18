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

  TSlimStatementContext = record
  public
    Resolver : TSlimFixtureResolver;
    Instances: TSlimFixtureDictionary;
  end;

  TSlimStatement = class
  strict private
    FContext: TSlimStatementContext;
    FRawStmt: TSlimList;
  protected
    function GetRawStmtString(AIndex: Integer): String;
    function HasRawArguments(out AStartIndex: Integer): Boolean; virtual;
    property Context: TSlimStatementContext read FContext;
    property RawStmt: TSlimList read FRawStmt;
  protected
    function ResponseException(const AMessage: String; const ASlimExceptionType: String = '__EXCEPTION__'): TSlimList;
    function ResponseOk: TSlimList;
    function ResponseString(const AValue: String): TSlimList;
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
  protected
    function HasRawArguments(out AStartIndex: Integer): Boolean; override;
  public
    function Execute: TSlimList; override;
    property InstanceParam: String index 2 read GetRawStmtString;
    property ClassParam: String index 3 read GetRawStmtString;
  end;

  TSlimStmtCall = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property InstanceParam: String index 2 read GetRawStmtString;
    property FunctionParam: String index 3 read GetRawStmtString;
  end;

  TSlimStmtCallAndAssign = class(TSlimStatement)
  public
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
    FInstances: TSlimFixtureDictionary;
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
  Result := false;
end;

function TSlimStatement.ResponseException(const AMessage, ASlimExceptionType: String): TSlimList;
begin
  Result := SlimList([IdParam, Format('%s:%s', [AMessage, ASlimExceptionType])]);
end;

function TSlimStatement.ResponseOk: TSlimList;
begin
  Result := SlimList([IdParam, 'OK']);
end;

function TSlimStatement.ResponseString(const AValue: String): TSlimList;
begin
  Result := SlimList([IdParam, AValue]);
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

function TSlimStmtMake.Execute: TSlimList;
var
  ArgsCount        : Integer;
  ArgStartIndex    : Integer;
  CheckMethod      : TRttiMethod;
  CheckMethodParams: TArray<TRttiParameter>;
  FixtureClass     : TRttiInstanceType;
  HasArgs          : Boolean;
  Instance         : TSlimFixture;
  InstanceValue    : TValue;
  InvokeArgs       : TArray<TValue>;

  function CheckMethodParamsMatch: Boolean;
  var
    ParametersCount: Integer;
  begin
    CheckMethodParams := CheckMethod.GetParameters;
    ParametersCount := Length(CheckMethodParams);
    Result :=
      (HasArgs and (ArgsCount = ParametersCount)) or
      (not HasArgs and (ParametersCount = 0));
  end;

begin
  Result := nil;
  if not Context.Resolver.TryGetSlimFixture(ClassParam, FixtureClass) then
    raise Exception.CreateFmt('Fixture class "%s" not found', [ClassParam]);

  Instance := nil;
  HasArgs := HasRawArguments(ArgStartIndex);
  if HasArgs then
    ArgsCount := RawStmt.Count - ArgStartIndex;

  for CheckMethod in FixtureClass.GetMethods do
  begin
    if CheckMethod.IsConstructor and CheckMethodParamsMatch then
    begin
      if HasArgs then
      begin
        // TODO: Hier die Parameter in InvokeArgs packen
//        for var LCheckParam: TRttiParameter in CheckMethodParams do
//        begin
//          var LFlags: TParamFlags := LCheckParam.Flags;
//          var LParamType: TRttiType := LCheckParam.ParamType;
//          var LParamKind: TTypeKind := LParamType.TypeKind;
//          var LParamIsInstance: Boolean := LParamType.IsInstance;
//        end;
      end
      else
        InvokeArgs := nil;

      try
        InstanceValue := CheckMethod.Invoke(FixtureClass.MetaclassType,InvokeArgs);
      except
        Result := ResponseException(ClassParam, 'COULD_NOT_INVOKE_CONSTRUCTOR');
        Exit;
      end;
      Instance := TSlimFixture(InstanceValue.AsObject);
      Context.Instances.Add(InstanceParam, Instance);
      Result := ResponseOk;
      Exit;
    end;
  end;
  Result := ResponseException(ClassParam, 'NO_CLASS');
end;

function TSlimStmtMake.HasRawArguments(out AStartIndex: Integer): Boolean;
const
  ArgStartIndex = 4;
begin
  Result := RawStmt.Count > ArgStartIndex;
  if Result then
    AStartIndex := ArgStartIndex;
end;

{ TSlimStmtCall }

function TSlimStmtCall.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimStmtCallAndAssign }

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
  FInstances := TSlimFixtureDictionary.Create([doOwnsValues]);
end;

destructor TSlimExecutor.Destroy;
begin
  FInstances.Free;
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
    Result := Stmt.Execute;
  finally
    Stmt.Free;
  end;
end;

function TSlimExecutor.Execute(ARawStmts: TSlimList): TSlimList;
var
  Context : TSlimStatementContext;
  Resolver: TSlimFixtureResolver;
begin
  Resolver := nil;
  Result := TSlimList.Create;
  try
    try
      Resolver := TSlimFixtureResolver.Create;

      Context := Default(TSlimStatementContext);
      Context.Resolver := Resolver;
      Context.Instances := FInstances;

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
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
