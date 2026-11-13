// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Tests.MemoryCheck;

interface

type
  // Counts outstanding allocations on every platform. The Linux RTL has no GetMemoryManagerState
  // and ReportMemoryLeaksOnShutdown only exists for the Windows memory manager.
  TMemoryCheck = class
  private
    class var FOriginal: TMemoryManagerEx;
    class var FOutstandingBlocks: NativeInt;

    class function CountedGetMem(Size: NativeInt): Pointer; static;
    class function CountedFreeMem(P: Pointer): Integer; static;
    class function CountedReallocMem(P: Pointer; Size: NativeInt): Pointer; static;
    class function CountedAllocMem(Size: NativeInt): Pointer; static;

  public
    class procedure Install; static;
    class function OutstandingBlocks: NativeInt; static;
  end;

implementation

{ TMemoryCheck }

class procedure TMemoryCheck.Install;
begin
  var Counting: TMemoryManagerEx;
  GetMemoryManager(FOriginal);
  Counting := FOriginal;
  Counting.GetMem     := CountedGetMem;
  Counting.FreeMem    := CountedFreeMem;
  Counting.ReallocMem := CountedReallocMem;
  Counting.AllocMem   := CountedAllocMem;
  SetMemoryManager(Counting);
end;

class function TMemoryCheck.OutstandingBlocks: NativeInt;
begin
  Result := FOutstandingBlocks;
end;

class function TMemoryCheck.CountedGetMem(Size: NativeInt): Pointer;
begin
  Result := FOriginal.GetMem(Size);
  AtomicIncrement(FOutstandingBlocks);
end;

class function TMemoryCheck.CountedFreeMem(P: Pointer): Integer;
begin
  Result := FOriginal.FreeMem(P);
  AtomicDecrement(FOutstandingBlocks);
end;

class function TMemoryCheck.CountedReallocMem(P: Pointer; Size: NativeInt): Pointer;
begin
  const IsNewBlock = (P = nil);
  Result := FOriginal.ReallocMem(P, Size);
  if IsNewBlock then
  begin
    AtomicIncrement(FOutstandingBlocks);
  end;
end;

class function TMemoryCheck.CountedAllocMem(Size: NativeInt): Pointer;
begin
  Result := FOriginal.AllocMem(Size);
  AtomicIncrement(FOutstandingBlocks);
end;

end.
