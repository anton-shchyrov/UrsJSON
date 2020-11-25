unit UrsJSONUtils;

interface

uses
  System.SysUtils,
  System.Rtti,
  {$IF CompilerVersion > 26}  // XE5
  System.JSON,
  {$ELSE}
  Data.DBXJSON,
  {$ENDIF}
  System.Classes;

type
  {$IF CompilerVersion > 26}  // XE5
  TJSONValue = System.JSON.TJSONValue;
  TJSONObject = System.JSON.TJSONObject;
  {$ELSE}
  TJSONValue = Data.DBXJSON.TJSONValue;
  TJSONObject = Data.DBXJSON.TJSONObject;
  {$ENDIF}

  TJsonFieldAttribute = class(TCustomAttribute)
  strict private
    FName: string;
  protected
    // Serialize
    function IsDefault(const AValue: TValue): Boolean; virtual;
    function Serialize(const AValue: TValue; out AJson: TJSONValue): Boolean; virtual;
  protected
    // Deserialize
    function GetDefault(out AVal: TValue): Boolean; virtual;
    function Deserialize(AContext, AJson: TJSONValue; out AValue: TValue): Boolean; virtual;
  public
    constructor Create(const AName: string = '');
  public
    property Name: string read FName;
  end;

  TJsonParser = class abstract
  strict private
    class var
      FContext: TRttiContext;
  strict private
    class constructor Create;
    class destructor Destroy;
  strict private
    class function ParseJson(const AJsonBuf: TArray<Byte>; AOffset, ALen: Integer): TJSONValue; overload; static; inline;
    class function ParseJson(const AJsonStr: string): TJSONValue; overload; static; inline;
    class function GetJsonAttribute(AProp: TRttiMember): TJsonFieldAttribute; static;
    class function IsList(AObject: TObject): Boolean; static;
    class function SerializeArray(const AValue: TValue; ALength: Integer): TJSONArray; static;
    class function SerializeStrings(const AStrings: TStrings): TJSONArray; static;
    class function SerializeList(const AObject: TObject): TJSONArray; static;
    class function DeserializeArray(AJson: TJSONArray; AType: TRttiType): TValue; static;
    class procedure DeserializeStrings(AJson: TJSONArray; AStrings: TStrings); static;
    class procedure DeserializeList(AJson: TJSONArray; AObject: TObject); static;
    class procedure MemberToJson(AParent: TJSONObject; AMember: TRttiMember; AInstance: Pointer); static;
    class procedure JsonToMember(AParent: TJSONValue; AMember: TRttiMember; AInstance: Pointer); static;
  strict protected
    procedure WarningAbstract; virtual; abstract;
  public
    class function ToJson(const AValue: TValue): TJSONValue; overload; static;
    class function ToJson(AObject: TObject): TJSONValue; overload; static;
    class function ToJson<T>(const AData: T): TJSONValue; overload; static;
    class function ToJson(AType: TRttiType; AInstance: Pointer): TJSONValue; overload; static;
    class function ToJsonStr<T>(const AData: T): string; static;
    class function FromJson(AJson: TJSONValue; AType: TRttiType): TValue; overload; static;
    class procedure FromJson(const AJsonBuf: TArray<Byte>; AOffset, ALen: Integer; ADst: TObject); overload; static;
    class procedure FromJson(const AJsonStr: string; ADst: TObject); overload; static;
    class procedure FromJson(AJson: TJSONValue; ADst: TObject); overload; static;
    class procedure FromJson<T: IInterface>(const AJsonStr: string; const ADst: T); overload; static;
    class procedure FromJson<T: IInterface>(AJson: TJSONValue; const ADst: T); overload; static;
    class function FromJson<T>(const AJsonBuf: TArray<Byte>; AOffset: Integer = 0;
      ALen: Integer = -1): T; overload; static;
    class function FromJson<T>(const AJsonStr: string): T; overload; static;
    class function FromJson<T>(AJson: TJSONValue): T; overload; static;
    class procedure FromJson(AJson: TJSONValue; AType: TRttiType; AInstance: Pointer); overload; static;
  end;

  TJSONRaw = class(TJSONValue)
  strict private
    const
      CNullData: array[0..3] of Byte = (Ord('n'), Ord('u'), Ord('l'), Ord('l'));
  strict private
    FData: TArray<Byte>;
  protected
    procedure AddDescendant(const ADescendent: TJSONAncestor); override;
    function IsNull: Boolean; override;
  public
    constructor Create; overload;
    constructor Create(const AData: TArray<Byte>); overload;
    function EstimatedByteSize: Integer; override;
    {$IF CompilerVersion < 33}
    function ToBytes(const AData: TBytes; const AOffset: Integer): Integer; override;
    {$ELSE}
    function ToBytes(const AData: TBytes; AOffset: Integer): Integer; override;
    procedure ToChars(ABuilder: TStringBuilder); override;
    {$IFEND}
    function Clone: TJSONAncestor; override;
    function ToString: string; override;
  end;

  TJSONNonUnicodeString = class(TJSONString)
  public
    function EstimatedByteSize: Integer; override;
  end;

  EJsonSerializeDeserializeError = class(Exception);
  EJsonSerializeError = class(EJsonSerializeDeserializeError);
  EJsonDeserializeError = class(EJsonSerializeDeserializeError);

implementation

uses
  System.TypInfo,
  {$IF CompilerVersion <= 26}  // XE5
  UrsJSONPortable,
  {$IFEND}
  System.Generics.Collections;

{ TJsonFieldAttribute }

constructor TJsonFieldAttribute.Create(const AName: string);
begin
  inherited Create;
  FName := AName
end;

// Serialize
function TJsonFieldAttribute.IsDefault(const AValue: TValue): Boolean;
begin
  Result := False;
end;

function TJsonFieldAttribute.Serialize(const AValue: TValue;
  out AJson: TJSONValue): Boolean;
begin
  Result := False;
end;

// Deserialize
function TJsonFieldAttribute.GetDefault(out AVal: TValue): Boolean;
begin
  Result := False;
end;

function TJsonFieldAttribute.Deserialize(AContext, AJson: TJSONValue;
  out AValue: TValue): Boolean;
begin
  Result := False;
end;

{ TJsonParser }

class constructor TJsonParser.Create;
begin
  FContext := TRttiContext.Create;
end;

class destructor TJsonParser.Destroy;
begin
  FContext.Free;
end;

class function TJsonParser.ParseJson(const AJsonBuf: TArray<Byte>; AOffset,
  ALen: Integer): TJSONValue;
begin
  if ALen < 0 then
    ALen := Length(AJsonBuf) - AOffset;
  Result := TJSONObject.ParseJSONValue(
    AJsonBuf,
    AOffset,
    ALen,
    {$IF CompilerVersion > 26}  // XE5
    [
      TJSONObject.TJSONParseOption.IsUTF8,
      TJSONObject.TJSONParseOption.UseBool,
      TJSONObject.TJSONParseOption.RaiseExc
    ]
    {$ELSE}
    True
    {$IFEND}
  );
end;

class function TJsonParser.ParseJson(const AJsonStr: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(
    AJsonStr
    {$IF CompilerVersion > 26}  // XE5
    , True,
    True
    {$IFEND}
  );
end;

class function TJsonParser.GetJsonAttribute(AProp: TRttiMember): TJsonFieldAttribute;
var
  LAttr: TCustomAttribute;
begin
  Result := nil;
  for LAttr in AProp.GetAttributes do begin
    if LAttr is TJsonFieldAttribute then begin
      {$IFOPT D+}
      if Result <> nil then
        raise EJsonSerializeDeserializeError.CreateFmt('Duplicate JSON attribute for %s', [AProp.Name]);
      {$ENDIF}
      Result := TJsonFieldAttribute(LAttr);
      {$IFOPT D-}
      Exit;
      {$ENDIF}
    end;
  end;
end;

class function TJsonParser.IsList(AObject: TObject): Boolean;
var
  LClass: TClass;
  LUnit: string;
  LName: string;
begin
  LClass := AObject.ClassType;
  LUnit := TList<Byte>.UnitName;
  while LClass <> nil do begin
    LName := LClass.ClassName;
    if
      (LName[Length(LName)] = '>') and
      (LClass.UnitName = LUnit) and
      LName.StartsWith('TList<')
    then
      Exit(True);
    LClass := LClass.ClassParent;
  end;
  Result := False;
end;

class function TJsonParser.SerializeArray(const AValue: TValue; ALength: Integer): TJSONArray;
var
  Li: Integer;
begin
  Result := TJSONArray.Create;
  try
    for Li := 0 to ALength - 1 do
      Result.AddElement(ToJson(AValue.GetArrayElement(Li)));
  except
    Result.Free;
    raise;
  end;
end;

class function TJsonParser.SerializeStrings(const AStrings: TStrings): TJSONArray;
var
  Li: Integer;
begin
  Result := TJSONArray.Create;
  try
    for Li := 0 to AStrings.Count - 1 do
      Result.AddElement(TJSONString.Create(AStrings[Li]));
  except
    Result.Free;
    raise;
  end;
end;

class function TJsonParser.SerializeList(const AObject: TObject): TJSONArray;
var
  LType: TRttiType;
  LProp: TRttiProperty;
  LVal: TValue;
begin
  LType := FContext.GetType(AObject.ClassType);
  LProp := LType.GetProperty('List');
  LVal := LProp.GetValue(AObject);
  LProp := LType.GetProperty('Count');
  Result := SerializeArray(LVal, LProp.GetValue(AObject).AsInteger);
end;

class function TJsonParser.DeserializeArray(AJson: TJSONArray; AType: TRttiType): TValue;
var
  LCnt: Integer;
  Li: Integer;
  LRes: array of TValue;
  LElemType: TRttiType;
begin
  LCnt := AJson.Count;
  SetLength(LRes, LCnt);
  case AType.TypeKind of
    tkDynArray: LElemType := TRttiDynamicArrayType(AType).ElementType;
    tkArray: LElemType := TRttiArrayType(AType).ElementType;
  else
    raise EJsonDeserializeError.Create('Invalid type for array');
  end;
  for Li := 0 to LCnt - 1 do
    LRes[Li] := FromJson(AJson.Items[Li], LElemType);
  Result := TValue.FromArray(AType.Handle, LRes);
end;

class procedure TJsonParser.DeserializeStrings(AJson: TJSONArray; AStrings: TStrings);
var
  LJsonVal: TJSONValue;
begin
  AStrings.BeginUpdate;
  try
    AStrings.Clear;
    for LJsonVal in AJson do
      AStrings.Add(LJsonVal.Value);
  finally
    AStrings.EndUpdate;
  end;
end;

class procedure TJsonParser.DeserializeList(AJson: TJSONArray; AObject: TObject);
var
  LType: TRttiType;
  LProp: TRttiProperty;
  LIdxProp: TRttiIndexedProperty;
  Li: Integer;
begin
  LType := FContext.GetType(AObject.ClassType);
  LProp := LType.GetProperty('Count');
  LProp.SetValue(AObject, AJson.Count);
  LIdxProp := LType.GetIndexedProperty('Items');
  for Li := 0 to AJson.Count - 1 do
    LIdxProp.SetValue(AObject, [Li], FromJson(AJson.Items[Li], LIdxProp.PropertyType));
end;

class procedure TJsonParser.MemberToJson(AParent: TJSONObject; AMember: TRttiMember;
  AInstance: Pointer);
var
  LAttr: TJsonFieldAttribute;
  LVal: TValue;
  LJsonVal: TJSONValue;
  LName: string;
begin
  LAttr := GetJsonAttribute(AMember);
  if LAttr = nil then
    Exit;
  if AMember is TRttiProperty then begin
    if not TRttiProperty(AMember).IsReadable then
      Exit;
    LVal := TRttiProperty(AMember).GetValue(AInstance);
  end else if AMember is TRttiField then
    LVal := TRttiField(AMember).GetValue(AInstance)
  else
    raise EJsonSerializeError.Create('Invalid member type');
  if not LAttr.IsDefault(LVal) then begin
    if not LAttr.Serialize(LVal, LJsonVal) then
      LJsonVal := ToJson(LVal);
    if LJsonVal <> nil then begin
      LName := LAttr.Name;
      if LName = '' then
        LName := AMember.Name;
      AParent.AddPair(TJSONNonUnicodeString.Create(LName), LJsonVal);
    end;
  end;
end;

class procedure TJsonParser.JsonToMember(AParent: TJSONValue; AMember: TRttiMember;
  AInstance: Pointer);
var
  LAttr: TJsonFieldAttribute;
  LName: string;
  LVal: TValue;
  LNewVal: TValue;
  LJsonVal: TJSONValue;
  LProp: TRttiProperty;
  LField: TRttiField;
  LType: TRttiType;
begin
  LAttr := GetJsonAttribute(AMember);
  if LAttr = nil then
    Exit;

  LName := LAttr.Name;
  if LName = '' then
    LName := AMember.Name;
  LVal := TValue.Empty;
  if AMember is TRttiProperty then begin
    LProp := TRttiProperty(AMember);
    LType := LProp.PropertyType;
    LField := nil;
  end else if AMember is TRttiField then begin
    LField := TRttiField(AMember);
    LType := LField.FieldType;
    LProp := nil;
  end else
    raise EJsonDeserializeError.Create('Member type not supported');

  if not AParent.TryGetValue<TJSONValue>(LName, LJsonVal) then begin
    if LAttr.GetDefault(LNewVal) then
      LVal := LNewVal;
  end else begin
    if LAttr.Deserialize(AParent, LJsonVal, LNewVal) then
      LVal := LNewVal
    else begin
      case LType.TypeKind of
        tkClass: begin
          if LProp <> nil then
            LVal := LProp.GetValue(AInstance)
          else
            LVal := LField.GetValue(AInstance);
          FromJson(LJsonVal, LVal.AsObject);
        end;
        tkInterface: begin
          LVal := LProp.GetValue(AInstance);
          FromJson(LJsonVal, LType, Pointer(LVal.AsInterface));
        end
      else
        LVal := FromJson(LJsonVal, LType);
      end;
    end;
  end;
  if LVal.TypeInfo <> nil then begin
    if LProp <> nil then begin
      if LProp.IsWritable then
        LProp.SetValue(AInstance, LVal);
    end else
      LField.SetValue(AInstance, LVal);
  end;
end;

class function TJsonParser.ToJson(const AValue: TValue): TJSONValue;
begin
  case AValue.Kind of
    tkInteger: Result := TJSONNumber.Create(AValue.AsInteger);
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString:
      Result := TJSONString.Create(AValue.AsString);
    tkEnumeration: begin
      if
        AValue.IsType<Boolean> or
        AValue.IsType<ByteBool> or
        AValue.IsType<WordBool> or
        AValue.IsType<LongBool>
      then begin
        if AValue.AsBoolean then
          Result := TJSONTrue.Create
        else
          Result := TJSONFalse.Create;
      end else
        Result := TJSONNonUnicodeString.Create(GetEnumName(AValue.TypeInfo, AValue.AsOrdinal));
    end;
    tkFloat: Result := TJSONNumber.Create(AValue.AsExtended);
//    tkSet:;
    tkClass: Result := ToJson(AValue.AsObject);
    tkInterface: Result := ToJson(AValue.AsInterface);
    tkArray, tkDynArray: Result := SerializeArray(AValue, AValue.GetArrayLength);
    tkRecord: Result := ToJson(FContext.GetType(AValue.TypeInfo), AValue.GetReferenceToRawData);
    tkInt64: Result := TJSONNumber.Create(AValue.AsInt64);
  else
    raise EJsonSerializeError.Create('Type not supported');
  end;
end;

class function TJsonParser.ToJson(AObject: TObject): TJSONValue;
begin
  if AObject is TStrings then
    Result := SerializeStrings(TStrings(AObject))
  else if IsList(AObject) then
    Result := SerializeList(AObject)
  else
    Result := ToJson(FContext.GetType(AObject.ClassType), AObject);
end;

class function TJsonParser.ToJson<T>(const AData: T): TJSONValue;
var
  LType: PTypeInfo;
  LVal: TValue;
  LObj: TObject;
begin
  LType := TypeInfo(T);
  case LType.Kind of
    tkClass: begin
      LObj := PPointer(@AData)^;
      Result := ToJson(LObj);
    end;
    tkInterface: Result := ToJson(FContext.GetType(LType), PPointer(@AData)^);
    tkRecord: Result := ToJson(FContext.GetType(LType), @AData);
  else
    LVal := TValue.From<T>(AData);
    Result := ToJson(LVal);
  end;
end;

class function TJsonParser.ToJson(AType: TRttiType; AInstance: Pointer): TJSONValue;
var
  LMember: TRttiMember;
begin
  if AInstance = nil then
    Exit(TJSONNull.Create);
  Result := TJSONObject.Create;
  try
    for LMember in AType.GetFields do
      MemberToJson(TJSONObject(Result), LMember, AInstance);
    for LMember in AType.GetProperties do
      MemberToJson(TJSONObject(Result), LMember, AInstance);
  except
    Result.Free;
    raise;
  end;
end;

class function TJsonParser.ToJsonStr<T>(const AData: T): string;
var
  LJson: TJSONValue;
begin
  LJson := ToJson<T>(AData);
  try
    Result := LJson.ToString;
  finally
    LJson.Free;
  end;
end;

class function TJsonParser.FromJson(AJson: TJSONValue; AType: TRttiType): TValue;
var
  LEnum: Integer;
  LBuf: Pointer;
begin
  case AType.TypeKind of
    tkInteger: Result := StrToInt(AJson.Value);
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString:
      Result := AJson.Value;
    tkEnumeration: begin
      LEnum := GetEnumValue(AType.Handle, AJson.Value);
      if LEnum = -1 then
        raise EJsonDeserializeError.Create('Unknown enumeration name: ' + AJson.Value);
      Result := TValue.FromOrdinal(AType.Handle, LEnum);
    end;
    tkFloat: Result := StrToFloat(AJson.Value);
//    tkSet:;
//    tkClass: Result := ToJson(AValue.AsObject);
    tkRecord: begin
      GetMem(LBuf, AType.AsRecord.TypeSize);
      try
        FillChar(LBuf^, AType.AsRecord.TypeSize, 0);
        FromJson(AJson, AType, LBuf);
        TValue.MakeWithoutCopy(LBuf, AType.Handle, Result);
      finally
        FreeMem(LBuf);
      end;
    end;
    tkArray, tkDynArray: Result := DeserializeArray(AJson as TJSONArray, AType);
    tkInt64: Result := StrToInt64(AJson.Value);
  else
    raise EJsonDeserializeError.Create('Type not supported');
  end;
end;

class procedure TJsonParser.FromJson(const AJsonBuf: TArray<Byte>; AOffset,
  ALen: Integer; ADst: TObject);
var
  LJson: TJSONValue;
begin
  LJson := ParseJson(AJsonBuf, AOffset, ALen);
  try
    FromJson(LJson, ADst);
  finally
    LJson.Free;
  end;
end;

class procedure TJsonParser.FromJson(const AJsonStr: string; ADst: TObject);
var
  LJson: TJSONValue;
begin
  LJson := ParseJson(AJsonStr);
  try
    FromJson(LJson, ADst);
  finally
    LJson.Free;
  end;
end;

class procedure TJsonParser.FromJson(AJson: TJSONValue; ADst: TObject);
var
  LType: TRttiType;
begin
  if ADst is TStrings then
    DeserializeStrings(AJson as TJSONArray, TStrings(ADst))
  else if IsList(ADst) then
    DeserializeList(AJson as TJSONArray, ADst)
  else begin
    LType := FContext.GetType(ADst.ClassType);
    FromJson(AJson, LType, ADst);
  end;
end;

class procedure TJsonParser.FromJson<T>(const AJsonStr: string; const ADst: T);
var
  LJson: TJSONValue;
begin
  LJson := ParseJson(AJsonStr);
  try
    FromJson<T>(LJson, ADst);
  finally
    LJson.Free;
  end;
end;

class procedure TJsonParser.FromJson<T>(AJson: TJSONValue; const ADst: T);
begin
  FromJson(AJson, FContext.GetType(TypeInfo(T)), PPointer(@ADst)^);
end;

class function TJsonParser.FromJson<T>(const AJsonBuf: TArray<Byte>; AOffset,
  ALen: Integer): T;
var
  LJson: TJSONValue;
begin
  LJson := ParseJson(AJsonBuf, AOffset, ALen);
  try
    Result := FromJson<T>(LJson);
  finally
    LJson.Free;
  end;
end;

class function TJsonParser.FromJson<T>(const AJsonStr: string): T;
var
  LJson: TJSONValue;
begin
  LJson := ParseJson(AJsonStr);
  try
    Result := FromJson<T>(LJson);
  finally
    LJson.Free;
  end;
end;

class function TJsonParser.FromJson<T>(AJson: TJSONValue): T;
var
  LType: PTypeInfo;
begin
  LType := TypeInfo(T);
  Result := Default(T);
  case LType.Kind of
    tkClass, tkInterface: raise EJsonDeserializeError.Create('Return type not supported');
    tkRecord: FromJson(AJson, FContext.GetType(LType), @Result);
  else
    Result := FromJson(AJson, FContext.GetType(LType)).AsType<T>;
  end;
end;

class procedure TJsonParser.FromJson(AJson: TJSONValue; AType: TRttiType;
  AInstance: Pointer);
var
  LMember: TRttiMember;
begin
  for LMember in AType.GetFields do
    JsonToMember(AJson, LMember, AInstance);
  for LMember in AType.GetProperties do
    JsonToMember(AJson, LMember, AInstance);
end;

{ TJSONRaw }

constructor TJSONRaw.Create;
begin
  inherited Create;
end;

constructor TJSONRaw.Create(const AData: TArray<Byte>);
begin
  Create;
  FData := AData;
end;

procedure TJSONRaw.AddDescendant(const ADescendent: TJSONAncestor);
begin
  // Descedant not supported
end;

function TJSONRaw.IsNull: Boolean;
begin
  Result := Length(FData) = 0;
end;

function TJSONRaw.EstimatedByteSize: Integer;
begin
  if IsNull then
    Result := Length(CNullData)
  else
    Result := Length(FData);
end;

{$IF CompilerVersion < 33}
function TJSONRaw.ToBytes(const AData: TBytes;
  const AOffset: Integer): Integer;
{$ELSE}
function TJSONRaw.ToBytes(const AData: TBytes;
  AOffset: Integer): Integer;
{$IFEND}
begin
  if Null then begin
    Move(CNullData[0], AData[AOffset], Length(CNullData));
    Result := AOffset + Length(CNullData);
  end else begin
    Move(FData[0], AData[AOffset], Length(FData));
    Result := AOffset + Length(FData);
  end;
end;

{$IF CompilerVersion >= 33}
procedure TJSONRaw.ToChars(ABuilder: TStringBuilder);
begin
  ABuilder.Append(ToString);
end;
{$IFEND}

function TJSONRaw.Clone: TJSONAncestor;
begin
  Result := TJSONRaw.Create(FData);
end;

function TJSONRaw.ToString: string;
begin
  if IsNull then
    Result := 'null'
  else
    Result := TEncoding.UTF8.GetString(FData);
end;

{ TJSONNonUnicodeString }

function TJSONNonUnicodeString.EstimatedByteSize: Integer;
begin
  if IsNull then
    Result := 4
  else
    Result := Length(Value) + 2;
end;

end.
