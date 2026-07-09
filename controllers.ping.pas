unit controllers.ping;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Horse;

procedure Register;

implementation

procedure GetPing(Req: THorseRequest; Res: THorseResponse);
begin
  Res.ContentType('text/plain; charset=utf-8');
  Res.Send('OK');
end;

procedure Register;
begin
  // Регистрируем маршруты с приведением типов под требования FPC 3.2.2
  THorse.Get('/ping', THorseCallback(@GetPing));

end;

end.

