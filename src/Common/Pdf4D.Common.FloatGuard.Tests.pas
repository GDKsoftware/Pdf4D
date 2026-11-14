// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.FloatGuard.Tests;

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Common.FloatGuard;

type
  [TestFixture]
  TFloatGuardTests = class
  private
    function Divide(const Dividend, Divisor: Single): Single;
    function Multiply(const Left, Right: Single): Single;

  public
    [Test]
    procedure TestOverflowGivesInfinityInsideTheGuard;

    [Test]
    procedure TestDivisionByZeroGivesInfinityInsideTheGuard;

    [Test]
    procedure TestInvalidOperationGivesNaNInsideTheGuard;

    [Test]
    procedure TestMaskIsRestoredAfterRun;

    [Test]
    procedure TestMaskIsRestoredWhenWorkRaises;

    [Test]
    procedure TestEnterAndLeaveRestoreTheMask;
  end;

implementation

{ TFloatGuardTests }

function TFloatGuardTests.Divide(const Dividend, Divisor: Single): Single;
begin
  Result := Dividend / Divisor;
end;

function TFloatGuardTests.Multiply(const Left, Right: Single): Single;
begin
  Result := Left * Right;
end;

procedure TFloatGuardTests.TestOverflowGivesInfinityInsideTheGuard;
begin
  var Product: Single := 0;

  TPdfFloatGuard.Run(
    procedure
    begin
      Product := Multiply(3E38, 3E38);
    end);

  Assert.IsTrue(IsInfinite(Product));
end;

procedure TFloatGuardTests.TestDivisionByZeroGivesInfinityInsideTheGuard;
begin
  var Quotient: Single := 0;

  TPdfFloatGuard.Run(
    procedure
    begin
      Quotient := Divide(1000, 0);
    end);

  Assert.IsTrue(IsInfinite(Quotient));
end;

procedure TFloatGuardTests.TestInvalidOperationGivesNaNInsideTheGuard;
begin
  var Quotient: Single := 0;

  TPdfFloatGuard.Run(
    procedure
    begin
      Quotient := Divide(0, 0);
    end);

  Assert.IsTrue(IsNan(Quotient));
end;

procedure TFloatGuardTests.TestMaskIsRestoredAfterRun;
begin
  const Before = GetExceptionMask;

  TPdfFloatGuard.Run(
    procedure
    begin
    end);

  Assert.IsTrue(Before = GetExceptionMask);
end;

procedure TFloatGuardTests.TestMaskIsRestoredWhenWorkRaises;
begin
  const Before = GetExceptionMask;

  Assert.WillRaise(
    procedure
    begin
      TPdfFloatGuard.Run(
        procedure
        begin
          raise EAbort.Create('stop');
        end);
    end, EAbort);

  Assert.IsTrue(Before = GetExceptionMask);
end;

procedure TFloatGuardTests.TestEnterAndLeaveRestoreTheMask;
begin
  const Before = GetExceptionMask;

  const Previous = TPdfFloatGuard.Enter;
  const Inside = GetExceptionMask;
  TPdfFloatGuard.Leave(Previous);

  Assert.IsTrue(exOverflow in Inside);
  Assert.IsTrue(Before = GetExceptionMask);
end;

end.
