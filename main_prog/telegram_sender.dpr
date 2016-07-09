program telegram_sender;

{$APPTYPE CONSOLE}

{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{ $SetPEFlags 1}  { <- $SetPEFlags IMAGE_FILE_RELOCS_STRIPPED}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils, System.StrUtils, System.Classes,
  cHTTPUtils,
  cHTTPClient,
  JwaWinNT;

{$SetPEFlags IMAGE_FILE_RELOCS_STRIPPED or IMAGE_FILE_DEBUG_STRIPPED or IMAGE_FILE_LINE_NUMS_STRIPPED or IMAGE_FILE_LOCAL_SYMS_STRIPPED}



const
  PROGRAMM_NAME          = 'Telegram Sender';
  WEB_SERVICE_HOST       = 'api.telegram.org';
  HTTP_CLIENT_USER_AGENT = 'telegram_sender';

  SEND_ITERATION_COUNT   = 5;



type
  TMacro = record
    MacroName: String;
    MacroValue: RawByteString;
  end;

const
  MACRO_COUNT = 10;

  // http://www.utf8-chartable.de/unicode-utf8-table.pl
  MacroArray: array[1..MACRO_COUNT] of TMacro = (
    (MacroName: '.WHITE_HEAVY_CHECK_MARK.'; MacroValue: #$E2#$9C#$85),
    (MacroName: '.LARGE_RED_CIRCLE.';       MacroValue: #$F0#$9F#$94#$B4),
    (MacroName: '.LARGE_BLUE_CIRCLE.';      MacroValue: #$F0#$9F#$94#$B5),
    (MacroName: '.CROSS_MARK.';             MacroValue: #$E2#$9D#$8C),
    (MacroName: '.WARNING_SIGN.';           MacroValue: #$E2#$9A#$A0),
    (MacroName: '.NO_ENTRY.';               MacroValue: #$E2#$9B#$94),
    (MacroName: '.ALARM_CLOCK.';            MacroValue: #$E2#$8F#$B0),
    (MacroName: '.HOURGLASS.';              MacroValue: #$E2#$8F#$B3),
    (MacroName: '.TELEPHONE.';              MacroValue: #$E2#$98#$8E),
    (MacroName: '.SKULL.';                  MacroValue: #$E2#$98#$A0)
  );






type

  PMacro_Block = ^TMacro_Block;
  TMacro_Block = record
    Macro_Pos: integer;
    Macro_Len: integer;
    Macro_Idx: integer;
  end;


//==================================================================================================
function Macro_Pos_Compare(Item1, Item2: Pointer): Integer;
begin
  if PMacro_Block(Item1)^.Macro_Pos > PMacro_Block(Item2)^.Macro_Pos then Result := 1
  else if PMacro_Block(Item1)^.Macro_Pos < PMacro_Block(Item2)^.Macro_Pos then Result := -1
  else Result := 0;
end;


//==================================================================================================
function Encode_Text(Text: String): RawByteString;
var
  i, Len: integer;
  Byte_Ptr: PByte;
  b: Byte;
  Ch_Lo, Ch_Hi: AnsiChar;
  Result_Ch_Ptr: PByte;
  UpperText: RawByteString;
  UTF8Text: RawByteString;
  SubstrPos: integer;
  Macro_Block_List: TList;
  Macro_Block_Ptr: PMacro_Block;
  Text_Block_Start: integer;

begin
  Result := '';

  Macro_Block_List := TList.Create;
  try

    // составление списка всех макроподстановок, обнаруженных в тексте
    UpperText := UpperCase(Text);
    for i := 1 to MACRO_COUNT do
    begin
      SubstrPos := PosEx(MacroArray[i].MacroName, UpperText, 1);
      while SubstrPos > 0 do
      begin
        Macro_Block_Ptr := AllocMem(SizeOf(TMacro_Block));
        Macro_Block_List.Add(Macro_Block_Ptr);
        Macro_Block_Ptr^.Macro_Pos := SubstrPos;
        Macro_Block_Ptr^.Macro_Len := Length(MacroArray[i].MacroName);
        Macro_Block_Ptr^.Macro_Idx := i;
        SubstrPos := PosEx(MacroArray[i].MacroName, UpperText, Macro_Block_Ptr.Macro_Pos + Macro_Block_Ptr.Macro_Len);
      end;
    end;

    // сортировка списка макроподстановок по позиции в тексте
    Macro_Block_List.Sort(@Macro_Pos_Compare);

    // замещение макроподстановок своими значениями
    UTF8Text := '';
    Text_Block_Start := 1;
    for i := 0 to Macro_Block_List.Count - 1 do
    begin
      Macro_Block_Ptr := Macro_Block_List[i];
      // копирование текста перед текущей макроподстановкой
      UTF8Text := UTF8Text + UTF8Encode(System.Copy(Text, Text_Block_Start, Macro_Block_Ptr^.Macro_Pos - Text_Block_Start));
      // добавление значение текущей макроподстановки
      UTF8Text := UTF8Text + MacroArray[Macro_Block_Ptr^.Macro_Idx].MacroValue;
      // сдвиг дальше по тексту
      Text_Block_Start := Macro_Block_Ptr^.Macro_Pos + Macro_Block_Ptr^.Macro_Len;
    end;
    UTF8Text := UTF8Text + UTF8Encode(System.Copy(Text, Text_Block_Start, Length(Text) - Text_Block_Start + 1));


  finally
    for i := 0 to Macro_Block_List.Count - 1 do FreeMem(Macro_Block_List[i]);
    Macro_Block_List.Free;
  end;

  // кодирование в url
  Len := Length(UTF8Text);
  Byte_Ptr := pointer(UTF8Text);
  SetLength(Result, Len * 3);
  Result_Ch_Ptr := pointer(Result);
  for i := 1 to Len do
  begin
    b := Byte_Ptr^ and $f;
    if b > 9 then Ch_Lo := AnsiChar(b - 10 + byte('A')) else Ch_Lo := AnsiChar(b + byte('0'));
    b := Byte_Ptr^ shr 4 and $f;
    if b > 9 then Ch_Hi := AnsiChar(b - 10 + byte('A')) else Ch_Hi := AnsiChar(b + byte('0'));
    Result_Ch_Ptr^ := byte('%');
    inc(Result_Ch_Ptr);
    Result_Ch_Ptr^ := byte(Ch_Hi);
    inc(Result_Ch_Ptr);
    Result_Ch_Ptr^ := byte(Ch_Lo);
    inc(Result_Ch_Ptr);
    inc(Byte_Ptr);
  end;

end;





//==================================================================================================
procedure Log_Sys_Error_Message(Message: String);
var
  P: Pointer;
  EventLog: Integer;
begin
  EventLog := RegisterEventSource(nil, PROGRAMM_NAME);
  if EventLog <> 0 then
  try
    P := PChar(Message);
    ReportEvent(EventLog, EVENTLOG_ERROR_TYPE, 0, 0, nil, 1, 0, @P, nil);
  finally
    DeregisterEventSource(EventLog);
  end;
end;



//==================================================================================================
var
  Authentication_Token: RawByteString;
  Chat_ID: RawByteString;
  Text_To_Send: String;

  HTTP_Client: TF4HTTPClient;
  Web_Service_URI: RawByteString;
  i: integer;
  Is_Success: boolean;
  Web_Service_Response: RawByteString;
  Web_Service_ResponseCode: integer;
  Sleep_Time: DWORD;
  _Error_Msg: String;
  Str1: string;


const
  HTTP4ClientState_Closed = [
    hcsInit,
    hcsStopped,
    hcsConnectFailed,
    hcsResponseCompleteAndClosed,
    hcsRequestInterruptedAndClosed,
    hcsRequestFailed
  ];


begin
  {$IFDEF DEBUG}ReportMemoryLeaksOnShutdown := true;{$ENDIF}

  ExitCode := 0;
  try

    Authentication_Token := AnsiDequotedStr(ParamStr(1), '"');
    Chat_ID := AnsiDequotedStr(ParamStr(2), '"');
    Text_To_Send := AnsiDequotedStr(ParamStr(3), '"');
//                                                Authentication_Token := '1111111111';
//                                                Chat_ID := '2222222222';
//                                                Text_To_Send := 'привет бла бла бла я123';
//                                                Text_To_Send := '  .WHITE_HEAVY_CHECK_MARK.  .LARGE_RED_CIRCLE.  .LARGE_BLUE_CIRCLE.  .CROSS_MARK.  .WARNING_SIGN.  .NO_ENTRY.  .ALARM_CLOCK.  .HOURGLASS.  .TELEPHONE. .SKULL.';

    if (Authentication_Token <> '') and (Chat_ID <> '') and (Text_To_Send <> '') then
    begin

      Is_Success := false;
      Web_Service_Response := '';

      Web_Service_URI := '/bot' + Authentication_Token + '/sendMessage?chat_id=' + Chat_ID + '&text=' + Encode_Text(Text_To_Send);
      //Web_Service_URI := '/bot' + Authentication_Token + '/getMe';
      //Web_Service_URI := '/bot' + Authentication_Token + '/getUpdates';

      HTTP_Client := TF4HTTPClient.Create(nil);
      try
        with HTTP_Client do
        begin
          UseHTTPS := true;
          PortInt := 443;
          AddressFamily := cafIP4;
          Method := cmGET;
          Host := WEB_SERVICE_HOST;
          URI := Web_Service_URI;
          UserAgent := HTTP_CLIENT_USER_AGENT;
          KeepAlive := kaClose;
          //RequestContentMechanism := hctmString;
          ResponseContentMechanism := hcrmString;

          CustomHeader['Accept'] := 'text/html';
          CustomHeader['Pragma'] := 'no-cache';
          //CustomHeader['Accept-Language'] := 'ru';
          CustomHeader['Accept-Encoding'] := '';
          CustomHeader['Cache-Control'] := 'no-store, no-cache, must-revalidate';
          CustomHeader['Range'] := 'bytes=0-8000';
          CustomHeader['DNT'] := '1';

          Sleep_Time := 0;
          for i := 1 to SEND_ITERATION_COUNT do
          begin

            Writeln;
            Writeln('Attempt #' + IntToStr(i) + ' to send the message...');
            _Error_Msg := '';

            Request;

            Sleep(500);
            while not (State in HTTP4ClientState_Closed) do Sleep(500);

            Web_Service_ResponseCode := ResponseCode;
            Web_Service_Response := ResponseContentStr;
            Active := false;

            if ((Web_Service_ResponseCode = 200) or (Web_Service_ResponseCode = 206) or (Web_Service_ResponseCode = 304)) and
               (ResponseContentStr <> '') then
            begin
              Is_Success := true;
              Break;
            end;

            _Error_Msg := ErrorMsg;
            Writeln('Error of sending message. ' + _Error_Msg);
            if Web_Service_ResponseCode <> 0 then
            begin
              Writeln('HHTP response code: ' + IntToStr(Web_Service_ResponseCode));
              Writeln('Telegram API response:');
              Writeln(Web_Service_Response);
            end;

            if i < SEND_ITERATION_COUNT then
            begin
              inc(Sleep_Time, 3);
              Writeln('Pause ' + IntToStr(Sleep_Time) + ' second...');
              Sleep(Sleep_Time * 1000);
            end;
          end;

        end;
      finally
        FreeAndNil(HTTP_Client);
      end;

      if Is_Success then
      begin
        Writeln('The message was sent successfully.');
        Writeln('HHTP response code: ' + IntToStr(Web_Service_ResponseCode));
        Writeln('Telegram API response:');
        Writeln(Web_Service_Response);
      end
      else
      begin
        ExitCode := 1;
        if Web_Service_ResponseCode <> 0 then
          _Error_Msg := 'HHTP response code: ' + IntToStr(Web_Service_ResponseCode) + #13'Telegram API response:'#13 + Web_Service_Response;
        Log_Sys_Error_Message('Error of sending message.'#13 + _Error_Msg);
      end;

    end
    else
    begin
      Writeln('Command options:');
      Writeln('  telegram_sender.exe <authentication token> <chat id> <text to send>');
    end;

  except
    on E: Exception do
    begin
      ExitCode := 2;
      Str1 := 'Exception: ' + E.ClassName + '.'#13#10'Error message: ' + E.Message + '.';
      Log_Sys_Error_Message(Str1);
      Writeln(ErrOutput, Str1);
    end;
  end;

  {$IFDEF DEBUG}Writeln('[done. press "enter"]'); ReadLn;{$ENDIF}
end.
