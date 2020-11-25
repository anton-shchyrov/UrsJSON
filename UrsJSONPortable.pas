unit UrsJSONPortable;

{$IF CompilerVersion > 26}  // XE5
  {$MESSAGE WARN 'Delphi version greatest at XE5 don''t needed this unit'}
{$IFEND}

interface

{$IF CompilerVersion <= 26}  // XE5
uses
  System.TypInfo, System.Rtti, System.SysUtils,
  Data.DBXJSON;

type
  TJsonValueBaseHelper = class helper for TJsonValue
  private
    function ObjValue: string;
  end;

  TJsonValueHelper = class helper(TJsonValueBaseHelper) for TJsonValue
  private
    procedure ErrorValueNotFound(const APath: string);
    function Cast<T>: T;
    function AsTValue(ATypeInfo: PTypeInfo; out AValue: TValue): Boolean;
    function FindValue(const APath: string): TJSONValue;
  public
    function TryGetValue<T>(out AValue: T): Boolean; overload;
    function TryGetValue<T>(const APath: string; out AValue: T): Boolean; overload;
    function GetValue<T>(const APath: string = ''): T; overload;
    function GetValue<T>(const APath: string; const ADefaultValue: T): T; overload;
    function Value: string;
  end;

  TJsonArrayHelper = class helper for TJsonArray
  strict private
    function GetCount: Integer;
    function GetItem(const AIndex: Integer): TJSONValue;
  public
    property Count: Integer read GetCount;
    property Items[const AIndex: Integer]: TJSONValue read GetItem;
  end;

  EJSONPathException = class(Exception);
{$IFEND ~CompilerVersion <= 26}  // XE5

implementation

{$IF CompilerVersion <= 26}  // XE5
uses
  System.SysConst,
  System.DateUtils, System.TimeSpan,
  System.Character;

const
  SInvalidDateString = 'Invalid date string: %s';
  SInvalidTimeString = 'Invalid time string: %s';
  SInvalidOffsetString = 'Invalid time Offset string: %s';

  SValueNotFound = 'Value ''%s'' not found';

  SJSONPathUnexpectedRootChar = 'Unexpected char for root element: .';
  SJSONPathEndedOpenBracket = 'Path ended with an open bracket';
  SJSONPathEndedOpenString = 'Path ended with an open string';
  SJSONPathInvalidArrayIndex = 'Invalid index for array: %s';
  SJSONPathUnexpectedIndexedChar ='Unexpected character while parsing indexer: %s';
  SJSONPathDotsEmptyName = 'Empty name not allowed in dot notation, use ['''']';

type
  DTErrorCode = (InvDate, InvTime, InvOffset);

  EDateTimeException = class(Exception);

  TJSONPathParser = class
  public type
    TToken = (Undefined, Name, ArrayIndex, Eof, Error);
  private
    FPath: string;
    FPos: Integer;
    FTokenArrayIndex: Integer;
    FToken: TToken;
    FTokenName: string;
    function GetIsEof: Boolean; inline;
    procedure RaiseError(const AMsg: string); overload;
    procedure RaiseErrorFmt(const AMsg: string; const AParams: array of const); overload;
    procedure SetToken(const AToken: TToken); overload;
    procedure SetToken(const AToken: TToken; const AValue); overload;
    procedure ParseName;
    procedure ParseQuotedName(AQuote: Char);
    procedure ParseArrayIndex;
    procedure ParseIndexer;
    function EnsureLength(ALength: Integer): Boolean; inline;
    procedure EatWhiteSpaces;
  public
    constructor Create(const APath: string);
    function NextToken: TToken;
    property IsEof: Boolean read GetIsEof;
    property Token: TToken read FToken;
    property TokenName: string read FTokenName;
    property TokenArrayIndex: Integer read FTokenArrayIndex;
  end;

  TCharHelper = record helper for Char
  public
    function IsDigit: Boolean;
  end;

var
  JSONFormatSettings: TFormatSettings;

{$IF CompilerVersion <= 24} // XE3
function _ValUInt64(const s: string; var code: Integer): UInt64;
var
  i: Integer;
  dig: Integer;
  sign: Boolean;
  empty: Boolean;
begin
  i := 1;
  {$IFNDEF CPUX64} // avoid E1036: Variable 'dig' might not have been initialized
  dig := 0;
  {$ENDIF}
  Result := 0;
  if s = '' then
  begin
    code := 1;
    exit;
  end;
  while s[i] = Char(' ') do
    Inc(i);
  sign := False;
  if s[i] =  Char('-') then
  begin
    sign := True;
    Inc(i);
  end
  else if s[i] =  Char('+') then
    Inc(i);
  empty := True;
  if (s[i] =  Char('$')) or (Upcase(s[i]) =  Char('X'))
    or ((s[i] =  Char('0')) and (I < Length(S)) and (Upcase(s[i+1]) =  Char('X'))) then
  begin
    if s[i] =  Char('0') then
      Inc(i);
    Inc(i);
    while True do
    begin
      case   Char(s[i]) of
       Char('0').. Char('9'): dig := Ord(s[i]) -  Ord('0');
       Char('A').. Char('F'): dig := Ord(s[i]) - (Ord('A') - 10);
       Char('a').. Char('f'): dig := Ord(s[i]) - (Ord('a') - 10);
      else
        break;
      end;
      if Result > (High(UInt64) shr 4) then
        Break;
      if sign and (dig <> 0) then
        Break;
      Result := Result shl 4 + dig;
      Inc(i);
      empty := False;
    end;
  end
  else
  begin
    while True do
    begin
      case  Char(s[i]) of
        Char('0').. Char('9'): dig := Ord(s[i]) - Ord('0');
      else
        break;
      end;
      if Result > (High(UInt64) div 10) then
        Break;
      if sign and (dig <> 0) then
        Break;
      Result := Result*10 + dig;
      Inc(i);
      empty := False;
    end;
  end;
  if (s[i] <> Char(#0)) or empty then
    code := i
  else
    code := 0;
end;
{$IFEND ~CompilerVersion <= 24} // XE3

{$IF CompilerVersion <= 24} // XE3
function TryStrToUInt64(const AStr: string; out AVal: UInt64): Boolean;
var
  LErr: Integer;
begin
  AVal := _ValUInt64(AStr, LErr);
  Result := LErr = 0;
end;
{$IFEND ~CompilerVersion <= 24} // XE3

{$IF CompilerVersion <= 24} // XE3
function StrToUInt64(const AStr: string): UInt64;
begin
  if not TryStrToUInt64(AStr, Result) then
    raise EConvertError.CreateResFmt(@SInvalidInteger, [AStr]);
end;
{$IFEND ~CompilerVersion <= 24} // XE3

function InitJsonFormatSettings: TFormatSettings;
begin
  Result := GetUSFormat;
  Result.CurrencyString := #$00A4;
  Result.CurrencyFormat := 0;
  Result.CurrencyDecimals := 2;
  Result.DateSeparator := '/';
  Result.TimeSeparator := ':';
  Result.ListSeparator := ',';
  Result.ShortDateFormat := 'MM/dd/yyyy';
  Result.LongDateFormat := 'dddd, dd MMMMM yyyy HH:mm:ss';
  Result.TimeAMString := 'AM';
  Result.TimePMString := 'PM';
  Result.ShortTimeFormat := 'HH:mm';
  Result.LongTimeFormat := 'HH:mm:ss';
//  for I := Low(DefShortMonthNames) to High(DefShortMonthNames) do
//  begin
//    Result.ShortMonthNames[I] := LoadResString(DefShortMonthNames[I]);
//    Result.LongMonthNames[I] := LoadResString(DefLongMonthNames[I]);
//  end;
//  for I := Low(DefShortDayNames) to High(DefShortDayNames) do
//  begin
//    Result.ShortDayNames[I] := LoadResString(DefShortDayNames[I]);
//    Result.LongDayNames[I] := LoadResString(DefLongDayNames[I]);
//  end;
  Result.ThousandSeparator := ',';
  Result.DecimalSeparator := '.';
  Result.TwoDigitYearCenturyWindow := 50;
  Result.NegCurrFormat := 0;
end;

procedure DTFmtError(AErrorCode: DTErrorCode; const AValue: string);
const
  Errors: array[DTErrorCode] of string = (SInvalidDateString, SInvalidTimeString, SInvalidOffsetString);
begin
  raise EDateTimeException.CreateFmt(Errors[AErrorCode], [AValue]);
end;

function GetNextDTComp(var P: PChar; const PEnd: PChar;  ErrorCode: DTErrorCode;
  const AValue: string; NumDigits: Integer): string; overload;
var
  LDigits: Integer;
begin
  LDigits := 0;
  Result := '';
  while ((P <= PEnd) and P^.IsDigit and (LDigits < NumDigits)) do
  begin
    Result := Result + P^;
    Inc(P);
    Inc(LDigits);
  end;
  if Result = '' then
    DTFmtError(ErrorCode, AValue);
end;

function GetNextDTComp(var P: PChar; const PEnd: PChar; const DefValue: string; Prefix: Char;
  IsOptional: Boolean; IsDate: Boolean; ErrorCode: DTErrorCode; const AValue: string; NumDigits: Integer): string; overload;
const
  SEmptySeparator: Char = ' ';
var
  LDigits: Integer;
begin
  if (P >= PEnd) then
  begin
    Result := DefValue;
    Exit;
  end;

  Result := '';

  if (Prefix <> SEmptySeparator) and (IsDate or not (Byte(P^) in [Ord('+'), Ord('-')])) then
  begin
    if P^ <> Prefix then
      DTFmtError(ErrorCode, AValue);
    Inc(P);
  end;

  LDigits := 0;
  while ((P <= PEnd) and P^.IsDigit and (LDigits < NumDigits)) do
  begin
    Result := Result + P^;
    Inc(P);
    Inc(LDigits);
  end;

  if Result = '' then
  begin
    if IsOptional then
      Result := DefValue
    else
      DTFmtError(ErrorCode, AValue);
  end;
end;

procedure DecodeISO8601Date(const DateString: string; var AYear, AMonth, ADay: Word);

  procedure ConvertDate(const AValue: string);
  const
    SDateSeparator: Char = '-';
    SEmptySeparator: Char = ' ';
  var
    P, PE: PChar;
  begin
    P := PChar(AValue);
    PE := P + (AValue.Length - 1);
    if AValue.IndexOf(SDateSeparator) < 0 then
    begin
      AYear := StrToInt(GetNextDTComp(P, PE, InvDate, AValue, 4));
      AMonth := StrToInt(GetNextDTComp(P, PE, '00', SEmptySeparator, True, True, InvDate, AValue, 2));
      ADay := StrToInt(GetNextDTComp(P, PE, '00', SEmptySeparator, True, True, InvDate, AValue, 2));
    end
    else
    begin
      AYear := StrToInt(GetNextDTComp(P, PE, InvDate, AValue, 4));
      AMonth := StrToInt(GetNextDTComp(P, PE, '00', SDateSeparator, True, True, InvDate, AValue, 2));
      ADay := StrToInt(GetNextDTComp(P, PE, '00', SDateSeparator, True, True, InvDate, AValue, 2));
    end;
  end;

var
  TempValue: string;
  LNegativeDate: Boolean;
begin
  AYear := 0;
  AMonth := 0;
  ADay := 1;

  LNegativeDate := (DateString <> '') and (DateString[Low(string)] = '-');
  if LNegativeDate then
    TempValue := DateString.Substring(1)
  else
    TempValue := DateString;
  if Length(TempValue) < 4 then
    raise EDateTimeException.CreateFmt(SInvalidDateString, [TempValue]);
  ConvertDate(TempValue);
end;

procedure DecodeISO8601Time(const TimeString: string; var AHour, AMinute, ASecond, AMillisecond: Word;
  var AHourOffset, AMinuteOffset: Integer);
const
  SEmptySeparator: Char = ' ';
  STimeSeparator: Char = ':';
  SMilSecSeparator: Char = '.';
var
  LFractionalSecondString: string;
  P, PE: PChar;
  LOffsetSign: Char;
  LFraction: Double;
begin
  AHour := 0;
  AMinute := 0;
  ASecond := 0;
  AMillisecond := 0;
  AHourOffset := 0;
  AMinuteOffset := 0;
  if TimeString <> '' then
  begin
    P := PChar(TimeString);
    PE := P + (TimeString.Length - 1);
    if TimeString.IndexOf(STimeSeparator) < 0 then
    begin
      AHour := StrToInt(GetNextDTComp(P, PE, InvTime, TimeString, 2));
      AMinute := StrToInt(GetNextDTComp(P, PE, '00', SEmptySeparator, False, False, InvTime, TimeString, 2));
      ASecond := StrToInt(GetNextDTComp(P, PE, '00', SEmptySeparator, True, False, InvTime, TimeString, 2));
      LFractionalSecondString := GetNextDTComp(P, PE, '0', SMilSecSeparator, True, False, InvTime, TimeString, 18);
      if LFractionalSecondString <> '0' then
      begin
        LFractionalSecondString := FormatSettings.DecimalSeparator + LFractionalSecondString;
        LFraction := StrToFloat(LFractionalSecondString);
        AMillisecond := Round(1000 * LFraction);
      end;
    end
    else
    begin
      AHour := StrToInt(GetNextDTComp(P, PE, InvTime, TimeString, 2));
      AMinute := StrToInt(GetNextDTComp(P, PE, '00', STimeSeparator, False, False, InvTime, TimeString, 2));
      ASecond := StrToInt(GetNextDTComp(P, PE, '00', STimeSeparator, True, False, InvTime, TimeString, 2));
      LFractionalSecondString := GetNextDTComp(P, PE, '0', SMilSecSeparator, True, False, InvTime, TimeString, 18);
      if LFractionalSecondString <> '0' then
      begin
        LFractionalSecondString := FormatSettings.DecimalSeparator + LFractionalSecondString;
        LFraction := StrToFloat(LFractionalSecondString);
        AMillisecond := Round(1000 * LFraction);
      end;
    end;

    if CharInSet(P^, ['-', '+']) then
    begin
      LOffsetSign := P^;
      Inc(P);
      if not P^.IsDigit then
        DTFmtError(InvTime, TimeString);
      AHourOffset  := StrToInt(LOffsetSign + GetNextDTComp(P, PE, InvOffset, TimeString, 2));
      AMinuteOffset:= StrToInt(LOffsetSign + GetNextDTComp(P, PE, '00', STimeSeparator, True, True, InvOffset, TimeString, 2));
    end;
  end;
end;

function AdjustDateTime(const ADate: TDateTime; AHourOffset, AMinuteOffset:Integer; IsUTC: Boolean = True): TDateTime;
var
  AdjustDT: TDateTime;
  BiasLocal: Int64;
  BiasTime: Integer;
  BiasHour: Integer;
  BiasMins: Integer;
  BiasDT: TDateTime;
  TZ: TTimeZone;
begin
  Result := ADate;
  if IsUTC then
  begin
    { If we have an offset, adjust time to go back to UTC }
    if (AHourOffset <> 0) or (AMinuteOffset <> 0) then
    begin
      AdjustDT := EncodeTime(Abs(AHourOffset), Abs(AMinuteOffset), 0, 0);
      if ((AHourOffset * MinsPerHour) + AMinuteOffset) > 0 then
        Result := Result - AdjustDT
      else
        Result := Result + AdjustDT;
    end;
  end
  else
  begin
    { Now adjust TDateTime based on any offsets we have and the local bias }
    { There are two possibilities:
        a. The time we have has the same offset as the local bias - nothing to do!!
        b. The time we have and the local bias are different - requiring adjustments }
    TZ := TTimeZone.Local;
    BiasLocal := Trunc(TZ.GetUTCOffset(Result).Negate.TotalMinutes);
    BiasTime  := (AHourOffset * MinsPerHour) + AMinuteOffset;
    if (BiasLocal + BiasTime) = 0 then
      Exit;

    { Here we adjust the Local Bias to make it relative to the Time's own offset
      instead of being relative to GMT }
    BiasLocal := BiasLocal + BiasTime;
    BiasHour := Abs(BiasLocal) div MinsPerHour;
    BiasMins := Abs(BiasLocal) mod MinsPerHour;
    BiasDT := EncodeTime(BiasHour, BiasMins, 0, 0);
    if (BiasLocal > 0) then
      Result := Result - BiasDT
    else
      Result := Result + BiasDT;
  end;
end;

function ISO8601ToDate(const AISODate: string; AReturnUTC: Boolean = True): TDateTime;
const
  STimePrefix: Char = 'T';
var
  TimeString, DateString: string;
  TimePosition: Integer;
  Year, Month, Day, Hour, Minute, Second, Millisecond: Word;
  HourOffset, MinuteOffset: Integer;
  AddDay, AddMinute: Boolean;
begin
  HourOffset := 0;
  MinuteOffset := 0;
  TimePosition := AISODate.IndexOf(STimePrefix);
  if TimePosition >= 0 then
  begin
    DateString := AISODate.Substring(0, TimePosition);
    TimeString := AISODate.Substring(TimePosition + 1);
  end
  else
  begin
    Hour := 0;
    Minute := 0;
    Second := 0;
    Millisecond := 0;
    HourOffset := 0;
    MinuteOffset := 0;
    DateString := AISODate;
    TimeString := '';
  end;
  DecodeISO8601Date(DateString, Year, Month, Day);
  DecodeISO8601Time(TimeString, Hour, Minute, Second, Millisecond, HourOffset, MinuteOffset);

  AddDay := Hour = 24;
  if AddDay then
    Hour := 0;

  AddMinute := Second = 60;
  if AddMinute then
    Second := 0;

  Result := EncodeDateTime(Year, Month, Day, Hour, Minute, Second, Millisecond);

  if AddDay then
    Result := IncDay(Result);
  if AddMinute then
    Result := IncMinute(Result);

  Result := AdjustDateTime(Result, HourOffset, MinuteOffset, AReturnUTC);
end;

function StrToTValue(const Str: string; const TypeInfo: PTypeInfo; out AValue: TValue): Boolean;

  function CheckRange(const Min, Max: Int64; const Value: Int64; const Str: string): Int64;
  begin
    Result := Value;
    if (Value < Min) or (Value > Max) then
      raise EConvertError.CreateFmt(System.SysConst.SInvalidInteger, [Str]);
  end;
var
  TypeData: TTypeData;
  TypeName: string;
begin
  Result := True;
  case TypeInfo.Kind of
    tkInteger:
      case GetTypeData(TypeInfo)^.OrdType of
        otSByte: AValue := CheckRange(Low(Int8), High(Int8), StrToInt(Str), Str);
        otSWord: AValue := CheckRange(Low(Int16), High(Int16), StrToInt(Str), Str);
        otSLong: AValue := StrToInt(Str);
        otUByte: AValue := CheckRange(Low(UInt8), High(UInt8), StrToInt(Str), Str);
        otUWord: AValue := CheckRange(Low(UInt16), High(UInt16), StrToInt(Str), Str);
        otULong: AValue := CheckRange(Low(UInt32), High(UInt32), StrToInt64(Str), Str);
      end;
    tkInt64:
      begin
        TypeData := GetTypeData(TypeInfo)^;
        if TypeData.MinInt64Value > TypeData.MaxInt64Value then
          AValue := StrToUInt64(Str)
        else
          AValue := StrToInt64(Str);
      end;
    tkEnumeration:
      begin
        TypeName := TypeInfo.NameFld.ToString;
        if SameText(TypeName, 'boolean') or SameText(TypeName, 'bool') then
          AValue := StrToBool(Str)
        else
          Result := False;
      end;
    tkFloat:
      case GetTypeData(TypeInfo)^.FloatType of
        ftSingle: AValue := StrToFloat(Str, JSONFormatSettings);
        ftDouble:
        begin
          if TypeInfo = System.TypeInfo(TDate) then
            AValue := ISO8601ToDate(Str)
          else if TypeInfo = System.TypeInfo(TTime) then
            AValue := ISO8601ToDate(Str)
          else if TypeInfo = System.TypeInfo(TDateTime) then
            AValue := ISO8601ToDate(Str)
          else
            AValue := StrToFloat(Str, JSONFormatSettings);
        end;
        ftExtended: AValue := StrToFloat(Str, JSONFormatSettings);
        ftComp: AValue := StrToFloat(Str, JSONFormatSettings);
        ftCurr: AValue := StrToCurr(Str, JSONFormatSettings);
      end;
{$IFNDEF NEXTGEN}
    tkChar,
{$ENDIF !NEXTGEN}
    tkWChar:
      begin
        if Str.Length = 1 then
          AValue := Str[Low(string)]
        else
          Result := False;
      end;
    tkString, tkLString, tkUString, tkWString:
      AValue := Str;
    else
      Result := False;
  end;
end;

function FindJSONValue(const AJSON: TJSONValue; const APath: string): TJsonValue; overload;
var
  LCurrentValue: TJSONValue;
  LParser: TJSONPathParser;
  LPair: TJSONPair;
  LError: Boolean;
begin
  LParser := TJSONPathParser.Create(APath);
  try
    LCurrentValue := AJSON;
    LError := False;
    while (not LParser.IsEof) and (not LError) do
    begin
      case LParser.NextToken of
        TJSONPathParser.TToken.Name:
        begin
          if LCurrentValue is TJSONObject then
          begin
            LPair := TJSONObject(LCurrentValue).Get(LParser.TokenName);
            if LPair <> nil then
              LCurrentValue := LPair.JsonValue
            else
              LCurrentValue := nil;
            if LCurrentValue = nil then
              LError := True;
          end
          else
            LError := True;
        end;
        TJSONPathParser.TToken.ArrayIndex:
        begin
          if LCurrentValue is TJSONArray then
            if LParser.TokenArrayIndex < TJSONArray(LCurrentValue).Count then
              LCurrentValue := TJSONArray(LCurrentValue).Items[LParser.TokenArrayIndex]
            else
              LError := True
          else
            LError := True
        end;
        TJSONPathParser.TToken.Error:
          LError := True;
      else
        Assert(LParser.Token = TJSONPathParser.TToken.Eof); // case statement is not complete
      end;
    end;

    if LParser.IsEof and not LError then
      Result := LCurrentValue
    else
      Result := nil;

  finally
    LParser.Free;
  end;
end;

{ TJSONPathParser }

constructor TJSONPathParser.Create(const APath: string);
begin
  FPath := APath;
end;

procedure TJSONPathParser.EatWhiteSpaces;
begin
  while not IsEof and IsWhiteSpace(FPath.Chars[FPos]) do
    Inc(FPos);
end;

function TJSONPathParser.EnsureLength(ALength: Integer): Boolean;
begin
  Result := (FPos + ALength) < Length(FPath);
end;

function TJSONPathParser.GetIsEof: Boolean;
begin
  Result := FPos >= Length(FPath);
end;

function TJSONPathParser.NextToken: TToken;
var
  IsFirstToken: Boolean;
begin
  IsFirstToken := FPos = 0;
  EatWhiteSpaces;
  if IsEof then
    SetToken(TToken.Eof)
  else
  begin
    case FPath.Chars[FPos] of
      '.':
        // Root element cannot start with a dot
        if IsFirstToken then
          RaiseError(SJSONPathUnexpectedRootChar)
        else
          ParseName;
      '[':
        ParseIndexer;
      else
        // In dot notation all names are prefixed by '.', except the root element
        if IsFirstToken then
          ParseName
        else
          RaiseErrorFmt(SJSONPathUnexpectedIndexedChar, [FPath.Chars[FPos]]);
    end;
    Inc(FPos);
  end;
  Result := FToken;
end;

procedure TJSONPathParser.ParseArrayIndex;
var
  LEndPos: Integer;
  LString: string;
  I: Integer;
begin
  LEndPos := FPath.IndexOf(']', FPos);
  if LEndPos < 0 then
    RaiseError(SJSONPathEndedOpenBracket)
  else
  begin
    LString := Trim(FPath.Substring(FPos, LEndPos - FPos));
    FPos := LEndPos - 1;
    if TryStrToInt(LString, I) then
      SetToken(TToken.ArrayIndex, I)
    else
      RaiseErrorFmt(SJSONPathInvalidArrayIndex, [LString])
  end;
end;

procedure TJSONPathParser.ParseQuotedName(AQuote: Char);
var
  LString: string;
begin
  LString := '';
  Inc(FPos);
  while not IsEof do
  begin
    if (FPath.Chars[FPos] = '\') and  EnsureLength(1) and  (FPath.Chars[FPos + 1] = AQuote) then // \"
    begin
      Inc(FPos);
      LString := LString + AQuote
    end
    else if FPath.Chars[FPos] = AQuote then
    begin
      SetToken(TToken.Name, LString);
      Exit;
    end
    else
      LString := LString + FPath.Chars[FPos];
    Inc(FPos);
  end;
  RaiseError(SJSONPathEndedOpenString);
end;

procedure TJSONPathParser.RaiseError(const AMsg: string);
begin
  RaiseErrorFmt(AMsg, []);
end;

procedure TJSONPathParser.RaiseErrorFmt(const AMsg: string; const AParams: array of const);
begin
  SetToken(TToken.Error);
  raise EJSONPathException.Create(Format(AMsg, AParams));
end;

procedure TJSONPathParser.ParseIndexer;
begin
  Inc(FPos); // [
  EatWhiteSpaces;
  if IsEof then
    RaiseError('Path ended with an open bracket');
  case FPath.Chars[FPos] of
    '"',
    '''':
      ParseQuotedName(FPath.Chars[FPos]);
  else
    ParseArrayIndex;
  end;
  Inc(FPos);
  EatWhiteSpaces;
  if FPath.Chars[FPos] <> ']' then
    RaiseErrorFmt(SJSONPathUnexpectedIndexedChar,[FPath.Chars[FPos]]);
end;

procedure TJSONPathParser.ParseName;
var
  LEndPos: Integer;
  LString: string;
begin
  if FPath.Chars[FPos] = '.' then
  begin
    Inc(FPos);
    if IsEof then
    begin
      SetToken(TToken.Error);
      Exit;
    end;
  end;
  LEndPos := FPath.IndexOfAny(['.', '['], FPos);
  if LEndPos < 0 then
  begin
    LString := FPath.Substring(FPos);
    FPos := Length(FPath) - 1;
  end
  else
  begin
    LString := Trim(FPath.Substring(FPos, LEndPos - FPos));
    FPos := LEndPos - 1;
  end;
  if LString = '' then
    RaiseError(SJSONPathDotsEmptyName)
  else
    SetToken(TToken.Name, LString);
end;

procedure TJSONPathParser.SetToken(const AToken: TToken);
var
  P: Pointer;
begin
  SetToken(AToken, P);
end;

procedure TJSONPathParser.SetToken(const AToken: TToken; const AValue);
begin
  FToken := AToken;
  case FToken of
    TToken.Name:
      FTokenName := string(AValue);
    TToken.ArrayIndex:
      FTokenArrayIndex := Integer(AValue);
  end;
end;

{ TCharHelper }

function TCharHelper.IsDigit: Boolean;
begin
  Result := System.Character.IsDigit(Self)
end;

{ TJsonValueBaseHelper }

function TJsonValueBaseHelper.ObjValue: string;
begin
  Result := Value;
end;

{ TJsonValueHelper }

procedure TJsonValueHelper.ErrorValueNotFound(const APath: string);
begin
  raise TJSONException.Create(Format(SValueNotFound, [APath]));
end;

function TJsonValueHelper.Cast<T>: T;
var
  LTypeInfo: PTypeInfo;
  LValue: TValue;
begin
  LTypeInfo := System.TypeInfo(T);
  if not AsTValue(LTypeInfo, LValue) then
    raise TJSONException.CreateFmt('Conversion from %0:s to %1:s is not supported', [Self.ClassName, LTypeInfo.Name]);
  Result := LValue.AsType<T>;
end;

function TJsonValueHelper.AsTValue(ATypeInfo: PTypeInfo; out AValue: TValue): Boolean;
var
  LNeedBase: Boolean;
  LBool: Boolean;
begin
  Result := False;
  LNeedBase := False;
  if (Self is TJSONTrue) or (Self is TJSONFalse) then begin
    LBool := Self is TJSONTrue;
    case ATypeInfo.Kind of
      tkEnumeration: begin
        AValue := TValue.FromOrdinal(ATypeInfo, Ord(LBool));
        Result :=
          AValue.IsType<Boolean> or
          AValue.IsType<ByteBool> or
          AValue.IsType<WordBool> or
          AValue.IsType<LongBool>;
      end;
      tkInteger, tkInt64, tkFloat: begin
        AValue := Ord(LBool);
        Result := True;
      end;
      tkString, tkLString, tkWString, tkUString: begin
        AValue := Value;
        Result := True;
      end
      else
        LNeedBase := True;
    end;
  end else if Self is TJSONNull then begin
    case ATypeInfo.Kind of
      tkString, tkLString, tkUString, TkWString: begin
        AValue := '';
        Result := True;
      end
      else
        LNeedBase := True;
    end;
  end else if Self is TJSONString then begin
    case ATypeInfo.Kind of
      tkInteger, tkInt64, tkFloat,
      tkString, tkLString, tkWString, tkUString,
      {$IFNDEF NEXTGEN}
      tkChar,
      {$ENDIF !NEXTGEN}
      tkWChar,
      tkEnumeration:
        Result := StrToTValue(Value, ATypeInfo, AValue)
      else
        LNeedBase := True;
    end;
  end else
    LNeedBase := True;
  if LNeedBase then begin
    case ATypeInfo^.Kind of
      tkClass: begin
        AValue := Self;
        Result := True;
      end
    end;
  end;
end;

function TJsonValueHelper.FindValue(const APath: string): TJSONValue;
begin
  if (Self is TJSONArray) or (Self is TJSONObject) then
    Result := FindJSONValue(Self, APath)
  else begin
    if APath = '' then
      Result := Self
    else
      Result := nil;
  end;
end;

function TJsonValueHelper.TryGetValue<T>(out AValue: T): Boolean;
begin
  Result := TryGetValue<T>('', AValue);
end;

function TJsonValueHelper.TryGetValue<T>(const APath: string; out AValue: T): Boolean;
var
  LJSONValue: TJSONValue;
begin
  LJSONValue := FindValue(APath);
  Result := LJSONValue <> nil;
  if Result then
  begin
    try
      AValue := LJSONValue.Cast<T>;
    except
      Result := False;
    end;
  end;
end;

function TJsonValueHelper.GetValue<T>(const APath: string = ''): T;
var
  LValue: T;
  LJSONValue: TJSONValue;
begin
  LJSONValue := FindValue(APath);
  if LJSONValue = nil then
    ErrorValueNotFound(APath);
  Result := LJSONValue.Cast<T>;
end;

function TJsonValueHelper.GetValue<T>(const APath: string; const ADefaultValue: T): T;
var
  LValue: T;
  LJSONValue: TJSONValue;
  LTypeInfo: PTypeInfo;
  LReturnDefault: Boolean;
begin
  LJSONValue := FindValue(APath);
  LReturnDefault := LJSONValue = nil;

  // Treat JSONNull as nil
  if LJSONValue is TJSONNull then
  begin
    LTypeInfo := System.TypeInfo(T);
    if LTypeInfo.TypeData.ClassType <> nil then
      LJSONValue := nil;
  end;

  if LJSONValue <> nil then
    Result := LJSONValue.Cast<T>
  else
    Result := ADefaultValue
end;

function TJsonValueHelper.Value: string;
begin
  if (Self is TJSONTrue) or (Self is TJSONFalse) then
    Result := ToString
  else
    Result := ObjValue;
end;

{ TJsonArrayHelper }

function TJsonArrayHelper.GetCount: Integer;
begin
  Result := Size;
end;

function TJsonArrayHelper.GetItem(const AIndex: Integer): TJSONValue;
begin
  Result := Get(AIndex);
end;

initialization
  JSONFormatSettings := InitJsonFormatSettings;
{$IFEND ~CompilerVersion <= 26}  // XE5

end.
