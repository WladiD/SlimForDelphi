// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Fixture;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.Rtti,
  System.SyncObjs,
  System.SysUtils,

  Slim.Common,
  Slim.List;

type

  /// <summary>
  ///   Determines how method calls should be synchronized
  /// </summary>
  TSyncMode = (
    smUndefined,
    /// <summary>
    ///   Method calls are not synchronized, i.e., they are executed directly from the thread
    ///   where the executor is active.
    /// </summary>
    smUnsynchronized,
    /// <summary>
    ///   The method is executed in a separate Synchronize call.
    /// </summary>
    smSynchronized,
    /// <summary>
    ///   The method call is synchronized from a inner delayed method.
    /// </summary>
    smSynchronizedAndDelayed);

  TDelayedInfo = record
    Owner: TComponent;
    /// <summary>
    ///   If ManualDelayedEvent is false, TSlimFixture.TriggerDelayedEvent is called automatically.
    ///   Otherwise it must be called by the implementing TSlimFixture manually.
    /// </summary>
    ManualDelayedEvent: Boolean;
  end;

  /// <summary>
  ///   Classes with this attribute are automatically considered by the TSlimFixtureResolver
  /// </summary>
  SlimFixtureAttribute = class(TCustomAttribute)
  private
    FName     : String;
    FNamespace: String;
  public
    constructor Create(const AName: String; const ANamespace: String = '');
    property Name: String read FName;
    property Namespace: String read FNamespace;
  end;

  SlimMethodSyncModeAttribute = class(TCustomAttribute)
  private
    FSyncMode: TSyncMode;
  public
    constructor Create(ASyncMode: TSyncMode);
    property SyncMode: TSyncMode read FSyncMode;
  end;

  /// <summary>
  /// Base class for all fixtures
  /// </summary>
  {$RTTI EXPLICIT METHODS([vcPublic, vcPublished]) PROPERTIES([vcPublic, vcPublished]) FIELDS([]) }
  TSlimFixture = class
  protected
    FDelayedEvent: TEvent;
    procedure IgnoreAllTests(const AMessage: String = '');
    procedure IgnoreScriptTest(const AMessage: String = '');
    procedure StopSuite(const AMessage: String = '');
    procedure StopTest(const AMessage: String = '');
  public
    destructor Destroy; override;
    function  HasDelayedInfo(AMethod: TRttiMethod; var AInfo: TDelayedInfo): Boolean; virtual;
    procedure InitDelayedEvent;
    function  SyncMode(AMethod: TRttiMethod): TSyncMode; virtual;
    function  SystemUnderTest: TObject; virtual;
    procedure TriggerDelayedEvent; virtual;
    procedure WaitForDelayedEvent;
  end;

  /// <summary>
  /// Implements the methods of the decision table:
  /// https://fitnesse.org/FitNesse/UserGuide/WritingAcceptanceTests/SliM/DecisionTable.html
  ///
  /// The public methods of this class are called in this order:
  /// 1. Table
  /// 2. Next the BeginTable method is called.
  ///    Use this for initializations if you want to.
  /// Then for each row in the table:
  ///   2.1. The Reset method is called, just in case you want to prepare or clean up.
  ///   2.2. Then all the inputs are loaded by calling the appropriate Set* methods
  ///        (must be implemented in the derived class).
  ///   2.3. Then the Execute method of the fixture is called.
  ///   2.4  Finally all the output functions are called
  /// 3. Finally the EndTable method is called.
  ///    Use this for closedown and cleanup if you want to.
  /// </summary>
  TSlimDecisionTableFixture = class(TSlimFixture)
  public
    procedure Table(AList: TSlimList); virtual;
    procedure BeginTable; virtual;
    procedure Reset; virtual;
    procedure Execute; virtual;
    procedure EndTable; virtual;
  end;

  /// <summary>
  /// Implements the methods of the dynamic decision table:
  /// https://fitnesse.org/FitNesse/UserGuide/WritingAcceptanceTests/SliM/DynamicDecisionTable.html
  /// </summary>
  TSlimDynamicDecisionTableFixture = class(TSlimDecisionTableFixture)
  public
    function  &Get(const AFieldName: String): String; virtual;
    procedure &Set(const AFieldName, AFieldValue: String); virtual;
  end;

  TSlimFixtureClass = class of TSlimFixture;
  TSymbolResolveFunc = function(const AValue: String): String of object;
  TSymbolObjectFunc = function(const AValue: String): TObject of object;

  TSlimFixtureDictionary = TObjectDictionary<String, TSlimFixture>;
  TSlimFixtureList = TObjectList<TSlimFixture>;

  TScriptTableActorStack = class(TSlimFixture)
  private
    FInstances: TSlimFixtureDictionary;
    FList     : TSlimFixtureList;
    procedure RaiseNoScriptTableActorInstances;
  public
    constructor Create(AInstances: TSlimFixtureDictionary);
    destructor  Destroy; override;
    function  GetFixture: TSlimFixture;
    procedure PopFixture;
    procedure PushFixture;
    property  Instances: TSlimFixtureDictionary read FInstances write FInstances;
  end;

  TSlimFixtureResolver = class
  private
    FRttiContext      : TRttiContext;
    FSymbolObjectFunc : TSymbolObjectFunc;
    FSymbolResolveFunc: TSymbolResolveFunc;
  public
    constructor Create;
    destructor Destroy; override;
    function GetParamValue(AParamType: TRttiType; AValueRaw: TSlimEntry): TValue;
    function GetRttiInstanceTypeFromInstance(Instance: TObject): TRttiInstanceType;
    function TryGetSlimFixture(const AFixtureName: String; out AClassType: TRttiInstanceType): Boolean;
    function TryGetSlimMethod(AFixtureClass: TRttiInstanceType; const AName: String; ARawStmt: TSlimList; AArgStartIndex: Integer; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;
    function TryGetSlimProperty(AFixtureClass: TRttiInstanceType; const AName: String; ARawStmt: TSlimList; AArgStartIndex: Integer; out ASlimProperty: TRttiProperty; out AInvokeArg: TValue): Boolean;
    property SymbolObjectFunc: TSymbolObjectFunc read FSymbolObjectFunc write FSymbolObjectFunc;
    property SymbolResolveFunc: TSymbolResolveFunc read FSymbolResolveFunc write FSymbolResolveFunc;
  end;

procedure RegisterSlimFixture(AFixtureClass: TSlimFixtureClass);

implementation

/// <summary>
///   Call this procedure with your fixture class to avoid code elimination for it by the compiler
/// </summary>
procedure RegisterSlimFixture(AFixtureClass: TSlimFixtureClass);
begin
  // Nothing to do
end;

{ SlimFixtureAttribute }

constructor SlimFixtureAttribute.Create(const AName: String; const ANamespace: String);
begin
  inherited Create;
  FName := AName;
  FNamespace := ANamespace;
end;

{ SlimMethodSyncModeAttribute }

constructor SlimMethodSyncModeAttribute.Create(ASyncMode: TSyncMode);
begin
  FSyncMode:=ASyncMode;
end;

{ TSlimFixture }

destructor TSlimFixture.Destroy;
begin
  FDelayedEvent.Free;
  inherited;
end;

function TSlimFixture.HasDelayedInfo(AMethod: TRttiMethod; var AInfo: TDelayedInfo): Boolean;
begin
  AInfo := Default(TDelayedInfo);
  Result := False;
end;

procedure TSlimFixture.InitDelayedEvent;
begin
  if not Assigned(FDelayedEvent) then
    FDelayedEvent := TEvent.Create(nil, True, False, '');
end;

procedure TSlimFixture.IgnoreAllTests(const AMessage: String);
begin
  raise ESlimIgnoreAllTests.Create(AMessage);
end;

procedure TSlimFixture.IgnoreScriptTest(const AMessage: String);
begin
  raise ESlimIgnoreScriptTest.Create(AMessage);
end;

procedure TSlimFixture.StopSuite(const AMessage: String);
begin
  raise ESlimStopSuite.Create(AMessage);
end;

procedure TSlimFixture.StopTest(const AMessage: String);
begin
  raise ESlimStopTest.Create(AMessage);
end;

function TSlimFixture.SyncMode(AMethod: TRttiMethod): TSyncMode;
begin
  Result := smUnsynchronized;
end;

/// <summary>
///   Each fixture may define a particular object, which is used, when the requested method is not
///   exists in the fixture.
/// </summary>
function TSlimFixture.SystemUnderTest: TObject;
begin
  Result := nil;
end;

procedure TSlimFixture.TriggerDelayedEvent;
begin
  if Assigned(FDelayedEvent) then
    FDelayedEvent.SetEvent;
end;

procedure TSlimFixture.WaitForDelayedEvent;
begin
  if Assigned(FDelayedEvent) then
  begin
    FDelayedEvent.WaitFor(INFINITE);
    FreeAndNil(FDelayedEvent);
  end;
end;

{ TSlimDecisionTableFixture }

procedure TSlimDecisionTableFixture.Table(AList: TSlimList);
begin

end;

/// <summary>
///   BeginTable is called once before a table is getting processed
/// </summary>
procedure TSlimDecisionTableFixture.BeginTable;
begin

end;

/// <summary>
///   This method is called before each row
/// </summary>
procedure TSlimDecisionTableFixture.Reset;
begin

end;

/// <summary>
///   EndTable is called after a table is being processed
/// </summary>
procedure TSlimDecisionTableFixture.EndTable;
begin

end;

/// <summary>
///   Execute is executed for each row after all Set* methods are executed
/// </summary>
procedure TSlimDecisionTableFixture.Execute;
begin

end;

{ TSlimDynamicDecisionTableFixture }

function TSlimDynamicDecisionTableFixture.&Get(const AFieldName: String): String;
begin

end;

procedure TSlimDynamicDecisionTableFixture.&Set(const AFieldName, AFieldValue: String);
begin

end;

{ TScriptTableActorStack }

constructor TScriptTableActorStack.Create(AInstances: TSlimFixtureDictionary);
begin
  if not Assigned(AInstances) then
    raise ESlim.Create('AInstances is required');
  FInstances := AInstances;
  FList := TSlimFixtureList.Create(True);
end;

destructor TScriptTableActorStack.Destroy;
begin
  FList.Free;
  inherited;
end;

function TScriptTableActorStack.GetFixture: TSlimFixture;
begin
  if not FInstances.TryGetValue(TSlimConsts.ScriptTableActor, Result) then
    RaiseNoScriptTableActorInstances;
end;

procedure TScriptTableActorStack.PopFixture;
begin
  if FList.Count = 0 then
    raise ESlim.Create('No fixture on stack');
  var Fixture: TSlimFixture:=FList.ExtractAt(FList.Count - 1);
  FInstances.AddOrSetValue(TSlimConsts.ScriptTableActor, Fixture);
end;

procedure TScriptTableActorStack.PushFixture;
begin
  if not ((FInstances.Count > 0) and FInstances.ContainsKey(TSlimConsts.ScriptTableActor)) then
    RaiseNoScriptTableActorInstances;
  var Pair:=FInstances.ExtractPair(TSlimConsts.ScriptTableActor);
  FList.Add(Pair.Value);
end;

procedure TScriptTableActorStack.RaiseNoScriptTableActorInstances;
begin
  raise ESlim.CreateFmt('No fixture with name "%s" found', [TSlimConsts.ScriptTableActor]);
end;

{ TSlimFixtureResolver }

constructor TSlimFixtureResolver.Create;
begin
  FRttiContext := TRttiContext.Create;
end;

destructor TSlimFixtureResolver.Destroy;
begin
  FRttiContext.Free;
  inherited;
end;

function TSlimFixtureResolver.GetParamValue(AParamType: TRttiType; AValueRaw: TSlimEntry): TValue;
var
  ParamClass: TClass;

  function ValueRawToString: String;
  begin
    Result := AValueRaw.ToString;
    if Assigned(FSymbolResolveFunc) then
      Result := FSymbolResolveFunc(Result);
  end;

  function TryValueRawToObject(out AObject: TObject): Boolean;
  begin
    Result := Assigned(FSymbolObjectFunc);
    if Result then
    begin
      AObject := FSymbolObjectFunc(AValueRaw.ToString);
      Result := Assigned(AObject) and (AObject is ParamClass);
    end;
  end;

begin
  var ParamTypeKind: TTypeKind := AParamType.TypeKind;
  ParamClass := nil;
  Result := nil;

  case ParamTypeKind of
    tkInteger:
      Result := StrToInt(ValueRawToString);
    tkEnumeration:
    begin
      var EnumStr: String := ValueRawToString;
      if SameText(EnumStr, 'true') then
        Result := true
      else if SameText(EnumStr, 'false') then
        Result := false
      else
        Result := EnumStr;
    end;
    tkInt64:
      Result := StrToInt64(ValueRawToString);
    tkFloat:
      Result := StrToFloat(ValueRawToString, TFormatSettings.Invariant);
    tkClass:
    begin
      ParamClass := AParamType.AsInstance.MetaclassType;
      var ParamObject: TObject := nil;
      if (AValueRaw is TSlimList) and (ParamClass.InheritsFrom(TSlimList)) then
        Result := AValueRaw
      else if TryValueRawToObject(ParamObject) then
        Result := ParamObject
      else
        Result := nil;
    end;
    tkString,
    tkUString:
      Result := ValueRawToString;
  end;
end;

function TSlimFixtureResolver.GetRttiInstanceTypeFromInstance(Instance: TObject): TRttiInstanceType;
var
  RttiType: TRttiType;
begin
  RttiType := FRttiContext.GetType(Instance.ClassInfo);
  Result := RttiType as TRttiInstanceType;
end;

/// <summary>
///   Try to find a fixture class by name
/// </summary>
/// <remarks>
///   Example:
///   <code>
///     [SlimFixture('Division', 'eg')]
///     TSlimDivisionFixture = class(TSlimFixture)...
///   </code>
///   A fixture can be found by the following namings:
///   - By the name of the SlimFixtureAttribute
///     For the upper example: "Division"
///   - By the combined namespace with the name of the SlimFixtureAttribute separated by "."
///     For the upper example: "eg.Division"
///   - By the class name of the fixture class
///     For the upper example: "TSlimDivisionFixture"
/// </remarks>
function TSlimFixtureResolver.TryGetSlimFixture(const AFixtureName: String; out AClassType: TRttiInstanceType): Boolean;
var
  Attribute: TCustomAttribute;
  LType    : TRttiType;

  function SlimFixtureNameMatch: Boolean;
  begin
    var FixtureAttr: SlimFixtureAttribute := SlimFixtureAttribute(Attribute);
    Result :=
      SameText(FixtureAttr.Name, AFixtureName) or
      (
        (FixtureAttr.Namespace <> '') and
        SameText(FixtureAttr.Namespace + '.' + FixtureAttr.Name, AFixtureName)
      );
  end;

begin
  for LType in FRttiContext.GetTypes do
  begin
    if LType.IsInstance then
    begin
      AClassType := LType.AsInstance;
      for Attribute in AClassType.GetAttributes do
      begin
        if
          (Attribute.ClassType = SlimFixtureAttribute) and
          AClassType.MetaclassType.InheritsFrom(TSlimFixture) and
          (
            SlimFixtureNameMatch or
            AClassType.MetaclassType.ClassNameIs(AFixtureName)
          ) then
          Exit(true);
      end;
    end;
  end;
  Result := false;
  AClassType := nil;
end;

/// <param name="AName">If empty, looks for a constructor</param>
function TSlimFixtureResolver.TryGetSlimMethod(AFixtureClass: TRttiInstanceType; const AName: String; ARawStmt: TSlimList; AArgStartIndex: Integer; out ASlimMethod: TRttiMethod; out AInvokeArgs: TArray<TValue>): Boolean;
var
  ArgsCount        : Integer;
  CheckMethod      : TRttiMethod;
  CheckMethodParams: TArray<TRttiParameter>;
  HasArgs          : Boolean;
  NameIsEmpty      : Boolean;

  function CheckMethodNameMatch: Boolean;
  begin
    Result :=
      (NameIsEmpty and CheckMethod.IsConstructor) or
      (not NameIsEmpty and SameText(AName, CheckMethod.Name));
  end;

  function CheckMethodParamsMatch: Boolean;
  begin
    CheckMethodParams := CheckMethod.GetParameters;
    var ParametersCount: Integer := Length(CheckMethodParams);
    Result :=
      (HasArgs and (ArgsCount = ParametersCount)) or
      (not HasArgs and (ParametersCount = 0));
  end;

begin
  NameIsEmpty := AName = '';
  HasArgs := AArgStartIndex > 0;
  if HasArgs then
    ArgsCount := ARawStmt.Count - AArgStartIndex;

  for CheckMethod in AFixtureClass.GetMethods do
  begin
    if not (CheckMethodNameMatch and CheckMethodParamsMatch) then
      Continue;
    if HasArgs then
    begin
      SetLength(AInvokeArgs, ArgsCount);
      for var ArgLoop := 0 to ArgsCount - 1 do
      begin
        var ArgRawIndex: Integer := AArgStartIndex + ArgLoop;
        var CurValue: TValue := GetParamValue(CheckMethodParams[ArgLoop].ParamType, ARawStmt[ArgRawIndex]);
        AInvokeArgs[ArgLoop] := CurValue;
      end;
    end
    else
      AInvokeArgs := nil;
    ASlimMethod := CheckMethod;
    Exit(true);
  end;

  Result := false;
end;

function TSlimFixtureResolver.TryGetSlimProperty(AFixtureClass: TRttiInstanceType; const AName: String; ARawStmt: TSlimList; AArgStartIndex: Integer; out ASlimProperty: TRttiProperty; out AInvokeArg: TValue): Boolean;
var
  ArgsCount          : Integer;
  CheckProperty      : TRttiProperty;
  CheckPropertyParams: TArray<TRttiParameter>;
  HasArgs            : Boolean;
  RequestedRead      : Boolean;
  RequestedWrite     : Boolean;

  function CheckPropertyNameMatch: Boolean;
  var
    LName: String;
  begin
    LName := AName;
    Result := SameText(LName, CheckProperty.Name);
    if
      not Result and
      (
        (RequestedWrite and LName.StartsWith('set', True)) or
        (RequestedRead and LName.StartsWith('get', True))
      ) then
    begin
      LName := Copy(LName, 4);
      Result := SameText(LName, CheckProperty.Name);
    end;
  end;

  function CheckPropertyAccess: Boolean;
  begin
    Result :=
      (RequestedRead and CheckProperty.IsReadable) or
      (RequestedWrite and CheckProperty.IsWritable);
  end;

begin
  if String.IsNullOrWhiteSpace(AName) then
    Exit(False);

  HasArgs := AArgStartIndex > 0;
  if HasArgs then
    ArgsCount := ARawStmt.Count - AArgStartIndex;

  RequestedRead := not HasArgs;
  RequestedWrite := HasArgs and (ArgsCount = 1);

  if not (RequestedRead or RequestedWrite) then
    Exit(False);

  for CheckProperty in AFixtureClass.GetProperties do
  begin
    if not (CheckPropertyNameMatch and CheckPropertyAccess) then
      Continue;
    if HasArgs then
      AInvokeArg := GetParamValue(CheckProperty.PropertyType, ARawStmt[AArgStartIndex])
    else
      AInvokeArg := nil;
    ASlimProperty := CheckProperty;
    Exit(true);
  end;

  Result := false;
end;

end.
