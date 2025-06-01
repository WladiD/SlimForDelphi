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

  Slim.Common,
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
    function ResponseException(AExceptClass: ExceptClass; const AMessage: String): TSlimList;
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
    type
    TFalseReasonGetInstanceAndMember = (
      frUndefined,
      frNoInstanceFound,
      frNoMemberFound);
    function ExecuteInternal(out ASlimMember: TRttiMember; out AInvokeArgs: TArray<TValue>): TValue;
    function ExecuteMember(AInstance: TObject; AMember: TRttiMember; AInvokeArgs: TArray<TValue>): TValue;
    function ExecuteSynchronized(AFixtureInstance: TSlimFixture; AInstance: TObject; ASlimMember: TRttiMember; const AInvokeArgs: TArray<TValue>; var AExecuted: Boolean): TValue;
    function GetFunctionParam: String; virtual; abstract;
    function GetInstanceParam: String; virtual; abstract;
    function ResponseExecute(ASlimMember: TRttiMember; const AMemberResult: TValue): TSlimList;
    function TryGetInstanceAndMember(out AFixtureInstance: TSlimFixture; out AInstance: TObject; out ASlimMember: TRttiMember; out AInvokeArgs: TArray<TValue>; out AFalseReason: TFalseReasonGetInstanceAndMember): Boolean;
    function TryGetMember(AInstance: TObject; out ASlimMember: TRttiMember; out AInvokeArgs: TArray<TValue>): Boolean;
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
    FStopExecute: Boolean;
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

  // Actors: The stack of library objects should be initialized with an instance of a class with
  //         the following 3 methods:
  //         getFixture, pushFixture and popFixture
  if Assigned(FInstances) and Assigned(FLibInstances) and (FLibInstances.Count = 0) then
    FLibInstances.Add(TScriptTableActorStack.Create(FInstances));

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

  if Assigned(Instances) and Assigned(LibInstances) then
  begin
    if (LibInstances.Count > 0) and (LibInstances[0] is TScriptTableActorStack) then
      TScriptTableActorStack(LibInstances[0]).Instances:=Instances
    else if LibInstances.Count = 0 then
      FLibInstances.Add(TScriptTableActorStack.Create(FInstances))
    else if (LibInstances.Count > 0) and not (LibInstances[0] is TScriptTableActorStack) then
      FLibInstances.Insert(0, TScriptTableActorStack.Create(FInstances));
  end;

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

function TSlimStatement.ResponseException(AExceptClass: ExceptClass; const AMessage: String): TSlimList;
var
  LExceptMessage: String;
begin
  if AExceptClass.InheritsFrom(ESlimStandardException) then
    LExceptMessage := AMessage
  else
    LExceptMessage :=Format('%s:%s: %s', [TSlimConsts.ExceptionResponse, AExceptClass.ClassName, AMessage]);

  Result := SlimList([IdParam, LExceptMessage]);
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
    raise ESlimNoClass.Create(ClassParam);

  if not HasRawArguments(ArgStartIndex) then
    ArgStartIndex := -1;

  if not Context.Resolver.TryGetSlimMethod(FixtureClass, '', RawStmt, ArgStartIndex,
    SlimMethod, InvokeArgs) then
    raise ESlimNoConstructor.Create(ClassParam);

  try
    InstanceValue := SlimMethod.Invoke(FixtureClass.MetaclassType,InvokeArgs);
  except
    raise ESlimCouldNotInvokeConstructor.Create(ClassParam);
  end;

  Instance := TSlimFixture(InstanceValue.AsObject);
  if InstanceParam.StartsWith('library', True) then
    Context.LibInstances.Add(Instance)
  else
    Context.Instances.AddOrSetValue(InstanceParam, Instance);
  Result := ResponseOk;
end;

{ TSlimStmtCallBase }

function TSlimStmtCallBase.ExecuteInternal(out ASlimMember: TRttiMember; out AInvokeArgs: TArray<TValue>): TValue;
var
  Executed       : Boolean;
  FalseReason    : TFalseReasonGetInstanceAndMember;
  FixtureInstance: TSlimFixture;
  Instance       : TObject;
begin
  if not TryGetInstanceAndMember(FixtureInstance, Instance, ASlimMember, AInvokeArgs, FalseReason) then
  begin
    Instance := nil;
    ASlimMember := nil;

    case FalseReason of
      frNoInstanceFound:
        raise ESlimNoInstance.Create(InstanceParam);
      frNoMemberFound:
        raise ESlimNoMethodInClass.Create(FunctionParam);
    end;
    Exit(nil);
  end;

  Executed := false;

  if TThread.CurrentThread.ThreadID <> MainThreadID then
    Result := ExecuteSynchronized(FixtureInstance, Instance, ASlimMember, AInvokeArgs, Executed);

  if not Executed then
    Result := ExecuteMember(Instance, ASlimMember, AInvokeArgs);
end;

function TSlimStmtCallBase.ExecuteMember(AInstance: TObject; AMember: TRttiMember; AInvokeArgs: TArray<TValue>): TValue;
begin
  if AMember is TRttiMethod then
    Result := TRttiMethod(AMember).Invoke(AInstance, AInvokeArgs)
  else if AMember is TRttiProperty then
  begin
    case Length(AInvokeArgs) of
      0:
      begin
        Result := TRttiProperty(AMember).GetValue(AInstance);
      end;
      1:
      begin
        TRttiProperty(AMember).SetValue(AInstance, AInvokeArgs[0]);
        Result := TSlimConsts.VoidResponse;
      end;
    end;
  end;
end;

function TSlimStmtCallBase.ExecuteSynchronized(AFixtureInstance: TSlimFixture; AInstance: TObject; ASlimMember: TRttiMember; const AInvokeArgs: TArray<TValue>; var AExecuted: Boolean): TValue;
var
  CatchedExceptClass: ExceptClass;
  ExceptMessage     : String;
  SyncResult        : TValue;

  procedure HandleSyncException;
  begin
    if CatchedExceptClass.InheritsFrom(ESlimControlFlow) then
      raise CatchedExceptClass.Create(ExceptMessage);
  end;

  function GetSyncMode: TSyncMode;
  begin
    var SyncAttrCustom: TCustomAttribute := ASlimMember.GetAttribute(SlimMemberSyncModeAttribute);
    if Assigned(SyncAttrCustom) then
      Result := SlimMemberSyncModeAttribute(SyncAttrCustom).SyncMode
    else
      Result := AFixtureInstance.SyncMode(ASlimMember);
  end;

begin
  var SyncMode: TSyncMode := GetSyncMode;
  CatchedExceptClass := nil;

  if SyncMode = smSynchronized then
  begin
    TThread.Synchronize(TThread.Current,
      procedure
      begin
        try
          SyncResult := ExecuteMember(AInstance, ASlimMember, AInvokeArgs);
        except
          on E: Exception do
          begin
            CatchedExceptClass := ExceptClass(E.ClassType);
            ExceptMessage := E.Message;
          end;
        end;
      end);

    AExecuted := true;

    if Assigned(CatchedExceptClass) then
    begin
      HandleSyncException;
      Result := ResponseException(CatchedExceptClass, ExceptMessage);
    end
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
          if AFixtureInstance.HasDelayedInfo(ASlimMember, Info) then
            AFixtureInstance.InitDelayedEvent
          else
            raise Exception.CreateFmt('%s.HasDelayedInfo for the method "%s" not defined', [AInstance.ClassName, ASlimMember.Name]);

          TDelayedMethod.Execute(
            procedure
            begin
              if not Info.ManualDelayedEvent then
              begin
                TDelayedMethod.Execute(
                  procedure
                  begin
                    AFixtureInstance.TriggerDelayedEvent;
                  end, Info.Owner);
              end;

              SyncResult := ExecuteMember(AInstance, ASlimMember, AInvokeArgs);
            end, Info.Owner);
        except
          on E: Exception do
          begin
            CatchedExceptClass := ExceptClass(E.ClassType);
            ExceptMessage := E.Message;
          end;
        end;
      end);

    AExecuted := true;

    if Assigned(CatchedExceptClass) then
    begin
      HandleSyncException;
      Exit(ResponseException(CatchedExceptClass, ExceptMessage));
    end;

    AFixtureInstance.WaitForDelayedEvent;
    Result := SyncResult;
  end;
end;

function TSlimStmtCallBase.ResponseExecute(ASlimMember: TRttiMember; const AMemberResult: TValue): TSlimList;
var
  SlimMethod  : TRttiMethod absolute ASlimMember;
  SlimProperty: TRttiProperty absolute ASlimMember;
begin
  Result := nil;
  if ASlimMember is TRttiMethod then
  begin
    if AMemberResult.IsInstanceOf(TSlimList) then
      Result := AMemberResult.AsObject as TSlimList
    else if SlimMethod.MethodKind = mkProcedure then
      Result := ResponseString(TSlimConsts.VoidResponse)
    else
      Result := ResponseValue(AMemberResult);
  end
  else if ASlimMember is TRttiProperty then
  begin
    Result := ResponseValue(AMemberResult);
  end;
end;

function TSlimStmtCallBase.TryGetInstanceAndMember(out AFixtureInstance: TSlimFixture; out AInstance: TObject; out ASlimMember: TRttiMember; out AInvokeArgs: TArray<TValue>; out AFalseReason: TFalseReasonGetInstanceAndMember): Boolean;
var
  InstanceFound: Boolean;
  MemberFound  : Boolean;

  function TryGetFromInstances: Boolean;
  begin
    InstanceFound := Context.Instances.TryGetValue(InstanceParam, AFixtureInstance);
    Result := InstanceFound;
    if Result then
    begin
      MemberFound := TryGetMember(AFixtureInstance, ASlimMember, AInvokeArgs);
      Result := MemberFound;
      if MemberFound then
        AInstance := AFixtureInstance;
    end;
  end;

  function TryGetFromSystemUnderTest: Boolean;
  var
    Sut: TObject;
  begin
    Result := InstanceFound;
    if Result then
    begin
      Sut := AFixtureInstance.SystemUnderTest;
      Result := Assigned(Sut) and TryGetMember(Sut, ASlimMember, AInvokeArgs);
      if Result then
        AInstance := Sut;
    end;
  end;

  function TryGetFromLibInstances: Boolean;
  begin
    for var Loop: Integer := Context.LibInstances.Count - 1 downto 0 do
    begin
      AFixtureInstance := Context.LibInstances[Loop];
      if TryGetMember(AFixtureInstance, ASlimMember, AInvokeArgs) then
      begin
        AInstance := AFixtureInstance;
        Exit(True);
      end
      else if TryGetFromSystemUnderTest then
        Exit(True);
    end;
    Result := False;
  end;

begin
  AFixtureInstance := nil;
  InstanceFound := False;
  MemberFound := False;
  Result :=
    TryGetFromInstances or
    TryGetFromSystemUnderTest or
    TryGetFromLibInstances;
  if not Result then
  begin
    if not InstanceFound then
      AFalseReason := frNoInstanceFound
    else if not MemberFound then
      AFalseReason := frNoMemberFound
    else
      AFalseReason := frUndefined;
  end;
end;

function TSlimStmtCallBase.TryGetMember(AInstance: TObject; out ASlimMember: TRttiMember; out AInvokeArgs: TArray<TValue>): Boolean;
var
  ArgStartIndex: Integer;
  RttiClass    : TRttiInstanceType;
  SlimMethod   : TRttiMethod;
  SlimProperty : TRttiProperty;
begin
  if not HasRawArguments(ArgStartIndex) then
    ArgStartIndex := -1;
  RttiClass := Context.Resolver.GetRttiInstanceTypeFromInstance(AInstance);
  Result := Context.Resolver.TryGetSlimMethod(RttiClass, FunctionParam, RawStmt, ArgStartIndex,
    SlimMethod, AInvokeArgs);
  if Result then
  begin
    ASlimMember := SlimMethod;
  end
  else
  begin
    var InvokeArg: TValue := nil;
    Result := Context.Resolver.TryGetSlimProperty(RttiClass, FunctionParam, RawStmt, ArgStartIndex,
      SlimProperty, InvokeArg);
    if Result then
    begin
      ASlimMember := SlimProperty;
      if InvokeArg.ToString = TSlimConsts.VoidResponse then
        AInvokeArgs := nil
      else
      begin
        SetLength(AInvokeArgs, 1);
        AInvokeArgs[0] := InvokeArg;
      end;
    end;
  end;
end;

{ TSlimStmtCall }

constructor TSlimStmtCall.Create(ARawStmt: TSlimList; AContext: TSlimStatementContext);
begin
  inherited;
  FArgStartIndex := 4;
end;

function TSlimStmtCall.Execute: TSlimList;
var
  InvokeArgs  : TArray<TValue>;
  MemberResult: TValue;
  SlimMember  : TRttiMember;
begin
  MemberResult := ExecuteInternal(SlimMember, InvokeArgs);
  Result := ResponseExecute(SlimMember, MemberResult);
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
  InvokeArgs  : TArray<TValue>;
  MemberResult: TValue;
  SlimMember  : TRttiMember;
begin
  MemberResult := ExecuteInternal(SlimMember, InvokeArgs);
  Context.Symbols.AddOrSetValue(SymbolParam, MemberResult);
  Result := ResponseExecute(SlimMember, MemberResult);
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
  Context.Symbols.AddOrSetValue(SymbolParam, ValueParam);
  Result := ResponseOk;
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
      on E: ESlimControlFlow do
      begin
        FStopExecute := true;
        Exit(Stmt.ResponseException(ExceptClass(E.ClassType), E.Message));
      end;
      on E: Exception do
        Exit(Stmt.ResponseException(ExceptClass(E.ClassType), E.Message));
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
      if FStopExecute then
        Break;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
