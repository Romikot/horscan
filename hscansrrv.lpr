Program hscansrrv;

Uses
{$IFDEF UNIX}{$IFDEF UseCThreads}
  CThreads,
{$ENDIF}{$ENDIF}
  DaemonApp, lazdaemonapp, daemonmapper, daemon, controllers.ping,
  controllers.scanner, DataObjects, options, optvalues, services.storage,
  Services.WiaScanner, Helpers, WIA_TLB, WIAdefs
  { add your units here };

begin
  Application.Initialize;
  Application.Run;
end.
