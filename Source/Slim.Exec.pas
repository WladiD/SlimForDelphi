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
  System.SyncObjs,
  System.SysUtils,
  System.TypInfo,

  WDDT.DelayedMethod,

  Slim.Fixture,
  Slim.List,
  Slim.Symbol;

type

  TSlimInstruction = (
    siUndefined,
    siImport,        // [<id>, import, <path>]
    siMake,          // [<id>, make, <instance>, <class>, <arg>...]
    siCall,          // [<id>, call, <instance>, <function>, <arg>...]
    siCallAndAssign, // [<id>, callAndAssign, <symbol>, <instance>, <function>, <arg>...]
    siAssign);       // [<id>, assign, <symbol>, <value>]

  TSlimFixtureDictionary = TObjectDictionary<String, TSlimFixture>;
  TSlimFixtureList = TObjectList<TSlimFixture>;

  TSlimStatementContext = class
  public type
    TContextMember = (cmInstances, cmLibInstances, cmResolver, cmSymbols);
    TContextMembers = set of TContextMember;
  private
    FOwnedMembers: TContextMembers;
    FInstances   : TSlimFixtureDictionary;
    FLibInstances: TSlimFixtureList;
    FResolver    : TSlimFixtureResolver;
    FSymbols     : TSlimSymbolDictionary;
  public
    destructor Destroy; override;
    procedure InitAllMembers;
    procedure InitMembers(AContextMembers: TContextMembers);
    procedure SetInstances(AInstances: TSlimFixtureDictionary; AOwnIt: Boolean);
  public
    property LibInstances: TSlimFixtureList read FLibInstances;
    property Resolver: TSlimFixtureResolver read FResolver;
    property Symbols: TSlimSymbolDictionary read FSymbols;
    property Instances: TSlimFixtureDictionary read FInstances;
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
    constructor Create(ARawStmt: TSlimList; AContext: TSlimStatementContext); virtual;
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
    constructor Create(ARawStmt: TSlimList; AContext: TSlimStatementContext); override;
    function Execute: TSlimList; override;
    property InstanceParam: String index 2 read GetRawStmtString;
    property ClassParam: String index 3 read GetRawStmtString;
  end;

  TSlimStmtCallBase = class(TSlimStatement)
  protected
    function ExecuteInternal(out AInstance: TSlimFixture; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): TValue;
    function ExecuteSynchronized(AInstance: TSlimFixture; ASlimMethod: TRttiMethod; const AInvokeArgs: TArray<TValue>; var AExecuted: Boolean): TValue;
    function GetFunctionParam: String; virtual; abstract;
    function GetInstanceParam: String; virtual; abstract;
    function ResponseExecute(ASlimMethod: TRttiMethod; const AMethodResult: TValue): TSlimList;
    function TryGetInstanceAndMethod(out AInstance: TSlimFixture; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;
    function TryGetMethod(AInstance: TObject; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;
  public
    property InstanceParam: String read GetInstanceParam;
    property FunctionParam: String read GetFunctionParam;
  end;

  TSlimStmtCall = class(TSlimStmtCallBase)
  protected
    function GetFunctionParam: String; override;
    function GetInstanceParam: String; override;
  public
    constructor Create(ARawStmt: TSlimList; AContext: TSlimStatementContext); override;
    function Execute: TSlimList; override;
  end;

  TSlimStmtCallAndAssign = class(TSlimStmtCallBase)
  protected
    function GetFunctionParam: String; override;
    function GetInstanceParam: String; override;
  public
    constructor Create(ARawStmt: TSlimList; AContext: TSlimStatementContext); override;
    function Execute: TSlimList; override;
    property SymbolParam: String index 2 read GetRawStmtString;
  end;

  TSlimStmtAssign = class(TSlimStatement)
  public
    function Execute: TSlimList; override;
    property SymbolParam: String index 2 read GetRawStmtString;
    property ValueParam: String index 3 read GetRawStmtString;
  end;

  TSlimExecutor = class
  private
    FContext: TSlimStatementContext;
    function ExecuteStmt(ARawStmt: TSlimList; AContext: TSlimStatementContext): TSlimList;
  public
    constructor Create(AContext: TSlimStatementContext);
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

{ TSlimStatementContext }

destructor TSlimStatementContext.Destroy;
begin
  if cmInstances in FOwnedMembers then
    FreeAndNil(FInstances);
  if cmLibInstances in FOwnedMembers then
    FreeAndNil(LibInstances);
  if cmResolver in FOwnedMembers then
    FreeAndNil(Resolver);
  if cmSymbols in FOwnedMembers then
    FreeAndNil(Symbols);
  FOwnedMembers := [];
  inherited;
end;

procedure TSlimStatementContext.InitAllMembers;
begin
  InitMembers([cmInstances..cmSymbols]);
end;

procedure TSlimStatementContext.InitMembers(AContextMembers: TContextMembers);
begin
  if not Assigned(FInstances) and (cmInstances in AContextMembers) then
  begin
    FInstances := TSlimFixtureDictionary.Create([doOwnsValues]);
    Include(FOwnedMembers, cmInstances);
  end;
  if not Assigned(FLibInstances) and (cmLibInstances in AContextMembers) then
  begin
    FLibInstances := TSlimFixtureList.Create(True);
    Include(FOwnedMembers, cmLibInstances);
  end;
  if not Assigned(FResolver) and (cmResolver in AContextMembers) then
  begin
    FResolver := TSlimFixtureResolver.Create;
    Include(FOwnedMembers, cmResolver);
  end;
  if not Assigned(FSymbols) and (cmSymbols in AContextMembers) then
  begin
    FSymbols := TSlimSymbolDictionary.Create;
    Include(FOwnedMembers, cmSymbols);
  end;

  if Assigned(FResolver) and Assigned(FSymbols) then
  begin
    if not Assigned(FResolver.SymbolResolveFunc) then
      FResolver.SymbolResolveFunc := FSymbols.EvalSymbols;
    if not Assigned(FResolver.SymbolObjectFunc) then
      FResolver.SymbolObjectFunc := FSymbols.SymbolObject;
  end;
end;

procedure TSlimStatementContext.SetInstances(AInstances: TSlimFixtureDictionary; AOwnIt: Boolean);
begin
  if cmInstances in FOwnedMembers then
    FInstances.Free;
  FInstances := AInstances;
  if AOwnIt then
    Include(FOwnedMembers, cmInstances)
  else
    Exclude(FOwnedMembers, cmInstances);
end;

{ TSlimStatement }

constructor TSlimStatement.Create(ARawStmt: TSlimList; AContext: TSlimStatementContext);
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
  if AValue.IsInstanceOf(TSlimList) then
    Exit(AValue.AsObject as TSlimList);
  case AValue.Kind of
    tkFloat:
    begin
      ValueStr := FloatToStr(AValue.AsExtended, TFormatSettings.Invariant);
      if not ValueStr.Contains('.') then
        ValueStr := ValueStr + '.0'; // Java needs this for truncated floats
    end;
  else
    ValueStr := AValue.ToString;
    if AValue.TypeInfo = System.TypeInfo(Boolean) then
      ValueStr := LowerCase(ValueStr);
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

constructor TSlimStmtMake.Create(ARawStmt: TSlimList; AContext: TSlimStatementContext);
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
    Context.LibInstances.Add(Instance)
  else
    Context.Instances.AddOrSetValue(InstanceParam, Instance);
  Result := ResponseOk;
end;

{ TSlimStmtCallBase }

function TSlimStmtCallBase.ExecuteInternal(out AInstance: TSlimFixture; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): TValue;
var
  Executed: Boolean;
begin
  if not TryGetInstanceAndMethod(AInstance, ASlimMethod, AInvokeArgs) then
    Exit(ResponseException(InstanceParam + '.' + FunctionParam, 'NO_INSTANCE'));

  Executed := false;

  if TThread.CurrentThread.ThreadID <> MainThreadID then
    Result := ExecuteSynchronized(AInstance, ASlimMethod, AInvokeArgs, Executed);

  if not Executed then
    Result := ASlimMethod.Invoke(AInstance, AInvokeArgs);
end;

function TSlimStmtCallBase.ExecuteSynchronized(AInstance: TSlimFixture; ASlimMethod: TRttiMethod; const AInvokeArgs: TArray<TValue>; var AExecuted: Boolean): TValue;
var
  ExceptClassName: String;
  ExceptMessage  : String;
  SyncResult     : TValue;

  function ResponseException: TSlimList;
  begin
    Result := Self.ResponseException(Format('%s: %s', [ExceptClassName, ExceptMessage]));
  end;

begin
  var SyncMode: TFixtureSyncMode := AInstance.SyncMode(ASlimMethod);

  if SyncMode = smSynchronized then
  begin
    TThread.Synchronize(TThread.Current,
      procedure
      begin
        try
          SyncResult := ASlimMethod.Invoke(AInstance, AInvokeArgs);
        except
          on E: Exception do
          begin
            ExceptClassName := E.ClassName;
            ExceptMessage := E.Message;
          end;
        end;
      end);

    AExecuted := true;

    if ExceptClassName <> '' then
      Result := ResponseException
    else
      Result := SyncResult;
  end
  else if SyncMode = smSynchronizedAndDelayed then
  begin
    TThread.Synchronize(TThread.Current,
      procedure
      var
        Info: TDelayedInfo;
      begin
        try
          if AInstance.HasDelayedInfo(ASlimMethod, Info) then
            AInstance.InitDelayedEvent
          else
            raise Exception.CreateFmt('%s.HasDelayedInfo for the method "%s" not defined', [AInstance.ClassName, ASlimMethod.Name]);

          TDelayedMethod.Execute(
            procedure
            begin
              TDelayedMethod.Execute(
                procedure
                begin
                  AInstance.TriggerDelayedEvent;
                end, Info.Owner);
              SyncResult := ASlimMethod.Invoke(AInstance, AInvokeArgs);
            end, Info.Owner);
        except
          on E: Exception do
          begin
            ExceptClassName := E.ClassName;
            ExceptMessage := E.Message;
          end;
        end;
      end);

    AExecuted := true;

    if ExceptClassName <> '' then
      Exit(ResponseException);

    AInstance.WaitForDelayedEvent;
    Result := SyncResult;
  end;
end;

function TSlimStmtCallBase.ResponseExecute(ASlimMethod: TRttiMethod; const AMethodResult: TValue): TSlimList;
begin
  if AMethodResult.IsInstanceOf(TSlimList) then
    Result := AMethodResult.AsObject as TSlimList
  else if ASlimMethod.MethodKind = mkProcedure then
    Result := ResponseString('/__VOID__/')
  else
    Result := ResponseValue(AMethodResult);
end;

function TSlimStmtCallBase.TryGetInstanceAndMethod(out AInstance: TSlimFixture; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;

  function TryGetFromInstances: Boolean;
  begin
    Result := 
      Context.Instances.TryGetValue(InstanceParam, AInstance) and
      TryGetMethod(AInstance, ASlimMethod, AInvokeArgs);  
  end;

  function TryGetFromLibInstances: Boolean;
  begin
    for var Loop: Integer := Context.LibInstances.Count - 1 downto 0 do
    begin
      AInstance := Context.LibInstances[Loop];
      if TryGetMethod(AInstance, ASlimMethod, AInvokeArgs) then
        Exit(True);
    end;
    Result := False;
  end;

begin
  Result :=
    TryGetFromInstances or
    TryGetFromLibInstances;  
end;

function TSlimStmtCallBase.TryGetMethod(AInstance: TObject; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;
var
  ArgStartIndex: Integer;
  RttiClass    : TRttiInstanceType;
begin
  if not HasRawArguments(ArgStartIndex) then
    ArgStartIndex := -1;
  RttiClass := Context.Resolver.GetRttiInstanceTypeFromInstance(AInstance);
  Result := Context.Resolver.TryGetSlimMethod(RttiClass, FunctionParam, RawStmt, ArgStartIndex,
    ASlimMethod, AInvokeArgs)
end;

{ TSlimStmtCall }

constructor TSlimStmtCall.Create(ARawStmt: TSlimList; AContext: TSlimStatementContext);
begin
  inherited;
  FArgStartIndex := 4;
end;

function TSlimStmtCall.Execute: TSlimList;
var
  Instance    : TSlimFixture;
  InvokeArgs  : TArray<TValue>;
  MethodResult: TValue;
  SlimMethod  : TRttiMethod;
begin
  MethodResult := ExecuteInternal(Instance, SlimMethod, InvokeArgs);
  Result := ResponseExecute(SlimMethod, MethodResult);
end;

function TSlimStmtCall.GetFunctionParam: String;
begin
  Result := GetRawStmtString(3);
end;

function TSlimStmtCall.GetInstanceParam: String;
begin
  Result := GetRawStmtString(2);
end;

{ TSlimStmtCallAndAssign }

constructor TSlimStmtCallAndAssign.Create(ARawStmt: TSlimList; AContext: TSlimStatementContext);
begin
  inherited;
  FArgStartIndex := 5;
end;

function TSlimStmtCallAndAssign.Execute: TSlimList;
var
  Instance    : TSlimFixture;
  InvokeArgs  : TArray<TValue>;
  MethodResult: TValue;
  SlimMethod  : TRttiMethod;
begin
  MethodResult := ExecuteInternal(Instance, SlimMethod, InvokeArgs);
  Context.Symbols.AddOrSetValue(SymbolParam, MethodResult);
  Result := ResponseExecute(SlimMethod, MethodResult);
end;

function TSlimStmtCallAndAssign.GetFunctionParam: String;
begin
  Result := GetRawStmtString(4);
end;

function TSlimStmtCallAndAssign.GetInstanceParam: String;
begin
  Result := GetRawStmtString(3);
end;

{ TSlimStmtAssign }

function TSlimStmtAssign.Execute: TSlimList;
begin
  Result := nil;
end;

{ TSlimExecutor }

constructor TSlimExecutor.Create(AContext: TSlimStatementContext);
begin
  FContext := AContext;
end;

function TSlimExecutor.ExecuteStmt(ARawStmt: TSlimList; AContext: TSlimStatementContext): TSlimList;
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
begin
  Result := TSlimList.Create;
  try
    FContext.SetInstances(TSlimFixtureDictionary.Create([doOwnsValues]), True);
    for var Loop := 0 to ARawStmts.Count - 1 do
    begin
      var LRawStmt: TSlimEntry := ARawStmts[Loop];
      if LRawStmt is TSlimList then
      begin
        var LStmtResult: TSlimList := ExecuteStmt(TSlimList(LRawStmt), FContext);
        if Assigned(LStmtResult) then
          Result.Add(LStmtResult);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
