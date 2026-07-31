program ping;

{$mode delphi}{$H+}
{$CODEPAGE UTF8}
{$DEFINE DEBUG}

{$APPTYPE CONSOLE}

uses
  {$IFDEF DEBUG}
  heaptrc,
  {$ENDIF}
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  SysUtils,
  fphttpserver,
  Horse,
  Horse.CORS,
  WIA_TLB, Helpers, WIAdefs,
  dataobjects,
  controllers.ping,
  controllers.scanner, Services.WiaScanner, options, optvalues, services.storage
  { you can add units after this };

// отключение кэша
procedure NoCacheMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
begin
  // HTTP 1.1: Полный запрет кэширования, повторной валидации и сохранения на диск
  Res.AddHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');

  // HTTP 1.0: Устаревший заголовок для старых клиентов/прокси
  Res.AddHeader('Pragma', 'no-cache');

  // Устанавливаем дату истечения в прошлом, чтобы контент сразу считался устаревшим
  Res.AddHeader('Expires', '0');

  Next; // Передаем управление дальше к обработчикам (маршрутам)
end;

procedure GlobalJsonHeaders(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
begin
  Res.ContentType('application/json; charset=utf-8');
  Next;
end;

begin
  // Настройка heaptrc:
  {$IFDEF DEBUG}
  SetHeapTraceOutput('memory_leaks.log');
  HaltOnNotReleased := False;
  {$ENDIF}

  // Подключаем запрет кэширования глобально
  THorse.Use(THorseCallback(@NoCacheMiddleware));
  // Включаем CORS без ограничений (глобально для всех маршрутов)
  // По умолчанию разрешает: Origin: *, Methods: *, Headers: *
  THorse.Use(THorseCallback(@CORS));
  //THorse.Use(THorseCallback(@GlobalJsonHeaders));

  controllers.ping.Register;
  controllers.scanner.Register;

  THorse.Listen(9000);
end.
