// ======================================================================
// Copyright (c) 2025 Waldemar Derr. All rights reserved.
//
// Licensed under the MIT license. See included LICENSE file for details.
// ======================================================================

unit Slim.Doc.Generator;

interface

uses

  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.RegularExpressions,
  System.SysUtils,

  mormot.core.base,
  mormot.core.mustache,
  mormot.core.variants,

  Slim.Doc.Model,
  Slim.Doc.Utils,
  Slim.Doc.UsageAnalyzer;

type

  TSlimDocGenerator = class
  private
    function  BuildLink(const APageName, AMemberName: String; AIsMethod: Boolean; AParamCount: Integer): String;
    function  FormatXmlComment(const AXml: String): String;
    function  GenerateMemberData(AFixture: TSlimDocFixture; AMember: TSlimDocMember; AUsageMap: TUsageMap): TDocVariantData;
    function  HasInheritedMembers(AFixture: TSlimDocFixture): Boolean;
    procedure SortFixtures(AFixtures: TList<TSlimDocFixture>);
    procedure SortMembers(AList: TList<TSlimDocMember>);
  public
    function Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const ATemplateContent, AOutputFilePath: String): String;
  end;

implementation

{ TSlimDocGenerator }

function TSlimDocGenerator.HasInheritedMembers(AFixture: TSlimDocFixture): Boolean;
begin
  for var M: TSlimDocMethod in AFixture.Methods do
    if M.IsInherited then
      Exit(True);

  for var P: TSlimDocProperty in AFixture.Properties do
    if P.IsInherited then
      Exit(True);

  Result := False;
end;

procedure TSlimDocGenerator.SortFixtures(AFixtures: TList<TSlimDocFixture>);
begin
  AFixtures.Sort(TComparer<TSlimDocFixture>.Construct(
    function(const L, R: TSlimDocFixture): Integer
    begin
      Result := CompareText(L.Namespace, R.Namespace);
      if Result = 0 then
        Result := CompareText(L.Name, R.Name);
    end));
end;

procedure TSlimDocGenerator.SortMembers(AList: TList<TSlimDocMember>);
begin
  AList.Sort(TComparer<TSlimDocMember>.Construct(
    function(const L, R: TSlimDocMember): Integer
    begin
      Result := CompareText(L.Name, R.Name);
    end));
end;

function TSlimDocGenerator.FormatXmlComment(const AXml: String): String;
begin
  if AXml = '' then
    Exit('');

  Result := AXml;
  // Summary
  Result := TRegEx.Replace(Result, '<summary>\s*(.*?)</summary>', '<div class="xml-summary">$1</div>', [roSingleLine, roIgnoreCase]);

  // Params
  Result := TRegEx.Replace(Result, '<param name="(.*?)">\s*', '<div class="xml-param"><span class="xml-param-name">$1</span>: ', [roIgnoreCase]);
  Result := Result.Replace('</param>', '</div>', [rfReplaceAll, rfIgnoreCase]);

  // Returns
  Result := Result.Replace('<returns>', '<div class="xml-returns"><span class="xml-param-name">Returns:</span> ', [rfReplaceAll, rfIgnoreCase]);
  Result := Result.Replace('</returns>', '</div>', [rfReplaceAll, rfIgnoreCase]);
end;

function TSlimDocGenerator.BuildLink(const APageName, AMemberName: String; AIsMethod: Boolean; AParamCount: Integer): String;
var
  Fragment: String;
  Parts   : TArray<String>;
  Spaced  : String;
begin
  Fragment := 'text=' + AMemberName;
  Spaced := CamelCaseToSpaced(AMemberName);
  if Spaced <> AMemberName then
  begin
    Fragment := Fragment + '&text=' + Spaced.Replace(' ', '%20');
    // Range match for interleaved calls: WriteVarValue -> text=Write,Value
    // Only for methods with at least 2 parameters, as these cause gaps in the HTML cells
    if AIsMethod and (AParamCount >= 2) and Spaced.Contains(' ') then
    begin
      Parts := Spaced.Split([' ']);
      if Length(Parts) >= 2 then
        Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
    end;
  end;

  if AIsMethod and (AMemberName.Length > 3) and AMemberName.StartsWith('Set', True) then
  begin
    var PropName := AMemberName.Substring(3);
    Fragment := Fragment + '&text=' + PropName;

    var SpacedProp := CamelCaseToSpaced(PropName);
    if SpacedProp <> PropName then
    begin
      Fragment := Fragment + '&text=' + SpacedProp.Replace(' ', '%20');
      // Only for methods with at least 2 parameters, as these could potentially cause gaps
      if SpacedProp.Contains(' ') and (AParamCount >= 2) then
      begin
        Parts := SpacedProp.Split([' ']);
        if Length(Parts) >= 2 then
          Fragment := Fragment + '&text=' + Parts[0] + ',' + Parts[High(Parts)];
      end;
    end;
  end;

  Result := Format('../%s#:~:%s', [APageName, Fragment]);
end;

function TSlimDocGenerator.GenerateMemberData(AFixture: TSlimDocFixture; AMember: TSlimDocMember; AUsageMap: TUsageMap): TDocVariantData;
var
  HasDescription: Boolean;
  HasUsage      : Boolean;
  LinkObj       : TDocVariantData;
  LookupKey     : String;
  MemberMethod  : TSlimDocMethod absolute AMember;
  MemberProperty: TSlimDocProperty absolute AMember;
  RowClass      : String;
  UsageLinksArr : TDocVariantData;
  UsageList     : TStringList;
  UsageRowClass : String;
  UsageRowId    : String;
  ParamCount    : Integer;
begin
  Result.InitJson('{}', []);

  LookupKey := Format('%s.%s', [AFixture.Name, AMember.Name]).ToLower;
  HasUsage := Assigned(AUsageMap) and AUsageMap.TryGetValue(LookupKey, UsageList);
  HasDescription := AMember.Description <> '';
  UsageRowId := Format('usage-%s-%s', [AFixture.Id, AMember.Name]).Replace('.', '-');

  RowClass := '';
  if AMember.IsInherited then
    RowClass := 'inherited-member';

  Result.AddValue('Name', AMember.Name);
  if RowClass <> '' then
    Result.AddValue('RowClass', RowClass);

  ParamCount := 0;
  if AMember is TSlimDocMethod then
  begin
    ParamCount := MemberMethod.Parameters.Count;
    Result.AddValue('ParamsString', MemberMethod.GetParamsString);
    Result.AddValue('ReturnType', MemberMethod.ReturnType);
  end
  else if AMember is TSlimDocProperty then
  begin
    Result.AddValue('PropertyType', MemberProperty.PropertyType);
    Result.AddValue('Access', MemberProperty.Access);
    Result.AddValue('ReturnType', ''); // Empty for properties
  end;

  Result.AddValue('SyncMode', AMember.SyncMode);
  if SameText(AMember.SyncMode, 'smUnsynchronized') then
    Result.AddValue('SyncClass', 'unsynchronized-member');
  Result.AddValue('Origin', AMember.Origin);
  Result.AddValue('HasUsageOrDesc', HasUsage or HasDescription);
  Result.AddValue('UsageRowId', UsageRowId);

  UsageRowClass := '';
  if AMember.IsInherited then
    UsageRowClass := 'inherited-member usage-row'
  else
    UsageRowClass := 'usage-row';
  Result.AddValue('UsageRowClass', UsageRowClass);

  if HasDescription then
    Result.AddValue('DescriptionHtml', FormatXmlComment(AMember.Description))
  else
    Result.AddValue('DescriptionHtml', false);

  Result.AddValue('HasUsage', HasUsage);
  if HasUsage then
  begin
    UsageLinksArr.InitJson('[]', []);
    for var U: String in UsageList do
    begin
      LinkObj.InitJson('{}', []);
      LinkObj.AddValue('Link', BuildLink(U, AMember.Name, AMember is TSlimDocMethod, ParamCount));
      LinkObj.AddValue('PageName', U);
      UsageLinksArr.AddItem(Variant(LinkObj));
    end;
    Result.AddValue('UsageLinks', Variant(UsageLinksArr));
  end;
end;

function TSlimDocGenerator.Generate(AFixtures: TList<TSlimDocFixture>; AUsageMap: TUsageMap; const ATemplateContent, AOutputFilePath: String): String;
var
  Doc        : TDocVariantData;
  Fixture    : TSlimDocFixture;
  FixtureObj : TDocVariantData;
  FixturesArr: TDocVariantData;
  Method     : TSlimDocMethod;
  MethodsArr : TDocVariantData;
  Prop       : TSlimDocProperty;
  PropsArr   : TDocVariantData;
begin
  SortFixtures(AFixtures);

  Doc.InitJson('{}', []);
  FixturesArr.InitJson('[]', []);

  for Fixture in AFixtures do
  begin
    FixtureObj.InitJson('{}', []);
    FixtureObj.AddValue('Id', Fixture.Id);
    FixtureObj.AddValue('Name', Fixture.Name);
    FixtureObj.AddValue('Namespace', Fixture.Namespace);
    FixtureObj.AddValue('UnitName', Fixture.UnitName);

    var ClassDecl := Fixture.DelphiClass;
    if (Fixture.InheritanceChain.Count > 0) then
    begin
      ClassDecl := ClassDecl + ' &lt; ' + Fixture.InheritanceChain[0];
      for var I := 1 to Fixture.InheritanceChain.Count - 1 do
        ClassDecl := ClassDecl + ' &lt; ' + Fixture.InheritanceChain[I];
    end;
    FixtureObj.AddValue('DelphiClass', ClassDecl);

    if Fixture.Description <> '' then
      FixtureObj.AddValue('DescriptionHtml', FormatXmlComment(Fixture.Description))
    else
      FixtureObj.AddValue('DescriptionHtml', false);

    FixtureObj.AddValue('HasInherited', HasInheritedMembers(Fixture));

    // Methods
    MethodsArr.InitJson('[]', []);
    SortMembers(TList<TSlimDocMember>(Fixture.Methods));
    for Method in Fixture.Methods do
      MethodsArr.AddItem(Variant(GenerateMemberData(Fixture, Method, AUsageMap)));
    FixtureObj.AddValue('Methods', Variant(MethodsArr));

    // Properties
    if Fixture.Properties.Count > 0 then
    begin
      FixtureObj.AddValue('HasProperties', True);
      PropsArr.InitJson('[]', []);
      SortMembers(TList<TSlimDocMember>(Fixture.Properties));
      for Prop in Fixture.Properties do
        PropsArr.AddItem(Variant(GenerateMemberData(Fixture, Prop, AUsageMap)));
      FixtureObj.AddValue('Properties', Variant(PropsArr));
    end;

    FixturesArr.AddItem(Variant(FixtureObj));
  end;

  Doc.AddValue('Fixtures', Variant(FixturesArr));

  var Rendered: UTF8String := TSynMustache.Parse(RawUtf8(ATemplateContent)).Render(Variant(Doc));
  TFile.WriteAllText(AOutputFilePath, String(Rendered), TEncoding.UTF8);

  var LinkName: String := ExtractFileName(AOutputFilePath);
  Result := Format('<a href="files/%s" target="_blank">Open Documentation</a>', [LinkName]);
end;

end.
