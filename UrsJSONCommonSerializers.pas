unit UrsJSONCommonSerializers;

interface

uses
  System.Rtti,
  UrsJSONUtils;

type
  TJsonBooleanDefaultAttribute = class(TJsonFieldAttribute)
  protected
    function IsDefault(const AValue: TValue): Boolean; override;
  end;

  TJsonDateTimeAttribute = class(TJsonFieldAttribute)
  strict protected
    function SerializeToString(const AValue: TValue): string; virtual;
    function DeserializeString(const AStr: string): TValue;
  protected
    function Serialize(const AValue: TValue; out AJson: TJSONValue): Boolean; override;
    function Deserialize(AContext, AJson: TJSONValue; out AValue: TValue): Boolean; override;
  end;

  TJsonISODateTimeAttribute = class(TJsonDateTimeAttribute)
  strict private
    const
      CDTDelim = 'T';
  strict protected
    function SerializeToString(const AValue: TValue): string; override;
  protected
    function Deserialize(AContext, AJson: TJSONValue; out AValue: TValue): Boolean; override;
  end;

  TJsonRawAttribute = class(TJsonFieldAttribute)
  protected
    function Serialize(const AValue: TValue; out AJson: TJSONValue): Boolean; override;
  end;

  TJsonStringAttribute = class(TJsonFieldAttribute)
  protected
    function Deserialize(AContext, AJson: TJSONValue; out AValue: TValue): Boolean; override;
  end;

  TJsonStringDefAttribute = class(TJsonStringAttribute)
  protected
    function IsDefault(const AValue: TValue): Boolean; override;
    function GetDefault(out AVal: TValue): Boolean; override;
  end;

  TJsonGUIDAttribute = class(TJsonFieldAttribute)
  strict private
    const
      CNULL_GUID: TGUID = (
        D1: 0;
        D2: 0;
        D3: 0;
        D4: (0, 0, 0, 0, 0, 0, 0, 0);
      );
  protected
    function Serialize(const AValue: TValue; out AJson: TJSONValue): Boolean; override;
    function Deserialize(AContext, AJson: TJSONValue; out AValue: TValue): Boolean; override;
    function IsDefault(const AValue: TValue): Boolean; override;
    function GetDefault(out AVal: TValue): Boolean; override;
  end;

implementation

uses
  {$IF CompilerVersion > 26}  // XE5
  System.JSON,
  {$ELSE}
  Data.DBXJSON, UrsJSONPortable,
  {$ENDIF}
  System.SysUtils;


type
  TDateTimeFormatter = class abstract
  strict private
    const
      CDateFormat = 'yyyy-mm-dd';
      CTimeFormat = 'hh:nn:ss';
    class var
      FFormatSettings: TFormatSettings;
  private
    const
      CDTSepPos = Length(CDateFormat);
  strict private
    class constructor Create;
  public
    class property FormatSettings: TFormatSettings read FFormatSettings;
  end;

{ TDateTimeFormatter }

class constructor TDateTimeFormatter.Create;
begin
  FFormatSettings := TFormatSettings.Create;
  FFormatSettings.DateSeparator := '-';
  FFormatSettings.TimeSeparator := ':';
  FFormatSettings.DecimalSeparator := '.';
  FFormatSettings.ShortDateFormat := CDateFormat;
  FFormatSettings.LongDateFormat := CDateFormat + ' ' + CTimeFormat;
  FFormatSettings.ShortTimeFormat := CTimeFormat;
  FFormatSettings.LongTimeFormat := CTimeFormat;
end;

{ TJsonBooleanDefaultAttribute }

function TJsonBooleanDefaultAttribute.IsDefault(const AValue: TValue): Boolean;
begin
  Result := not AValue.AsBoolean;
end;

{ TJsonDateTimeAttribute }

function TJsonDateTimeAttribute.SerializeToString(const AValue: TValue): string;
begin
  Result := DateTimeToStr(AValue.AsType<TDateTime>, TDateTimeFormatter.FormatSettings);
end;

function TJsonDateTimeAttribute.DeserializeString(
  const AStr: string): TValue;
begin
  Result := TValue.From<TDateTime>(
    StrToDateTime(AStr, TDateTimeFormatter.FormatSettings));
end;

function TJsonDateTimeAttribute.Serialize(const AValue: TValue;
  out AJson: TJSONValue): Boolean;
begin
  AJson := TJSONString.Create(SerializeToString(AValue));
  Result := True;
end;

function TJsonDateTimeAttribute.Deserialize(AContext, AJson: TJSONValue;
  out AValue: TValue): Boolean;
begin
  AValue := DeserializeString(AJson.Value);
  Result := True;
end;

{ TJsonISODateTimeAttribute }

function TJsonISODateTimeAttribute.SerializeToString(
  const AValue: TValue): string;
begin
  Result := inherited SerializeToString(AValue);
  Result[TDateTimeFormatter.CDTSepPos] := CDTDelim;
end;

function TJsonISODateTimeAttribute.Deserialize(AContext, AJson: TJSONValue;
  out AValue: TValue): Boolean;
var
  LStr: string;
  LTPos: Integer;
  LEndPos: Integer;
  Li: Integer;
begin
  LStr := AJson.Value;
  LTPos := -1;
  LEndPos := -1;
  for Li := 1 to Length(LStr) do begin
    case LStr[Li] of
      CDTDelim: LTPos := Li;
      ' ', '+', '-': begin
        if LTPos <> -1 then begin
          LEndPos := Li - 1;
          Break;
        end;
      end;
    end;
  end;
  if LEndPos <> -1 then
    SetLength(LStr, LEndPos);
  if LTPos <> -1 then
    LStr[LTPos] := ' ';
  AValue := DeserializeString(LStr);
  Result := True;
end;

{ TJsonRawAttribute }

function TJsonRawAttribute.Serialize(const AValue: TValue;
  out AJson: TJSONValue): Boolean;
begin
  AJson := TJSONRaw.Create(AValue.AsType<TArray<Byte>>);
  Result := True;
end;

{ TJsonStringAttribute }

function TJsonStringAttribute.Deserialize(AContext, AJson: TJSONValue;
  out AValue: TValue): Boolean;
begin
  AValue := AJson.ToString;
  Result := True;
end;

{ TJsonStringDefAttribute }

function TJsonStringDefAttribute.IsDefault(const AValue: TValue): Boolean;
begin
  Result := AValue.AsString = '';
end;

function TJsonStringDefAttribute.GetDefault(out AVal: TValue): Boolean;
begin
  AVal := TValue.From<string>('');
  Result := True;
end;

{ TJsonGUIDAttribute }

function TJsonGUIDAttribute.Serialize(const AValue: TValue;
  out AJson: TJSONValue): Boolean;
begin
  AJson := TJSONString.Create(GUIDToString(AValue.AsType<TGUID>));
  Result := True;
end;

function TJsonGUIDAttribute.Deserialize(AContext, AJson: TJSONValue;
  out AValue: TValue): Boolean;
begin
  AValue := TValue.From<TGUID>(StringToGUID(AJson.Value));
  Result := True;
end;

function TJsonGUIDAttribute.IsDefault(const AValue: TValue): Boolean;
begin
  Result := IsEqualGUID(AValue.AsType<TGUID>, CNULL_GUID);
end;

function TJsonGUIDAttribute.GetDefault(out AVal: TValue): Boolean;
begin
  AVal := TValue.From<TGUID>(CNULL_GUID);
  Result := True;
end;

end.
