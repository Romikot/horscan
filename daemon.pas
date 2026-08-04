unit daemon;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DaemonApp,
  // Подключаем Horse и ваши модули с роутами / контроллерами
  Horse, Horse.CORS,
  controllers.ping, controllers.scanner,
  optvalues;

type
  { Поток для работы сервера Horse, чтобы не блокировать службу }
  THorseThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  { Класс самого Демона }
  THorseDaemon = class(TDaemon)
    procedure DaemonStart(Sender: TCustomDaemon; var OK: Boolean);
    procedure DaemonStop(Sender: TCustomDaemon; var OK: Boolean);
    procedure DaemonShutdown(Sender: TCustomDaemon);
  private
    FHorseThread: THorseThread;
  public
  end;

var
  HorseDaemon: THorseDaemon;

implementation

procedure RegisterDaemon;
begin
  RegisterDaemonClass(THorseDaemon);
end;

{ THorseThread }

procedure THorseThread.Execute;
begin
  THorse.Use(THorseCallback(@CORS));

  controllers.ping.Register;
  controllers.scanner.Register;

  THorse.Listen(9000);
end;

{ THorseDaemon }

// ЗАПУСК СЛУЖБЫ
procedure THorseDaemon.DaemonStart(Sender: TCustomDaemon; var OK: Boolean);
begin
  OK := False;
  try
    // Загрузка глобальных опций, если необходимо
    // optvalues.LoadConfig;

    // Создаем и запускаем фоновый поток с сервером Horse
    FHorseThread := THorseThread.Create(False);
    FHorseThread.FreeOnTerminate := False;

    OK := True; // Успешно сообщили ОС, что служба работает
  except
    OK := False;
  end;
end;

procedure THorseDaemon.DaemonStop(Sender: TCustomDaemon; var OK: Boolean);
begin
  OK := False;
  try
    // Посылаем сигнал серверу Horse на закрытие всех соединений и остановку
    if THorse.IsRunning then
    begin
      THorse.StopListen;
    end;

    // Ждем корректного завершения потока и освобождаем память
    if Assigned(FHorseThread) then
    begin
      FHorseThread.Terminate;
      FHorseThread.WaitFor;
      FreeAndNil(FHorseThread);
    end;

    OK := True; // Успешно остановились
  except
    OK := False;
  end;
end;

// АВАРИЙНОЕ ВЫКЛЮЧЕНИЕ ПК
procedure THorseDaemon.DaemonShutdown(Sender: TCustomDaemon);
var
  Dummy: Boolean;
begin
  DaemonStop(Sender, Dummy);
end;

initialization
  RegisterDaemon;
end.

