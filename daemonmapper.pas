unit daemonmapper;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DaemonApp, daemon;

type
  TDaemonMap = class(TDaemonMapper)
  private

  public

  end;

var
  DaemonMap: TDaemonMap;

implementation

procedure RegisterMapper;
begin
  RegisterDaemonMapper(TDaemonMap)
end;

{$R *.lfm}


initialization
  RegisterMapper;
end.

