// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.CffParseOutcome;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils;

type
  // Parses CFF data and reports how that ended, for the tests that feed damaged fonts to the parser
  TCffParseOutcome = record
  public const
    // The longest that parsing a hostile font may take
    MaximumHostileMilliseconds = 1000;

  public
    // The class name of the exception that parsing ends in, or an empty string when it gives fonts
    class function OutcomeOf(const Data: TBytes; out Message: string): string; overload; static;
    class function OutcomeOf(const Data: TBytes): string; overload; static;
    // Parsing must end in an EPdfParseException, in time, with the fragment in its message
    class procedure CheckRaises(const Data: TBytes; const MessageFragment: string = ''); static;
  end;

implementation

uses
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.Common.Defines;

class function TCffParseOutcome.OutcomeOf(const Data: TBytes; out Message: string): string;
begin
  Result := '';
  Message := '';
  const Parser = TCFFParser.Create;
  try
    try
      Parser.Parse(Data).Free;
    except
      on Failure: Exception do
      begin
        Result := Failure.ClassName;
        Message := Failure.Message;
      end;
    end;
  finally
    Parser.Free;
  end;
end;

class function TCffParseOutcome.OutcomeOf(const Data: TBytes): string;
begin
  var Message: string;
  Result := OutcomeOf(Data, Message);
end;

class procedure TCffParseOutcome.CheckRaises(const Data: TBytes; const MessageFragment: string);
begin
  const Stopwatch = TStopwatch.StartNew;
  var Message: string;
  const Outcome = OutcomeOf(Data, Message);
  Assert.AreEqual(EPdfParseException.ClassName, Outcome);
  Assert.IsTrue((MessageFragment = '') or Message.Contains(MessageFragment),
                Format('Message "%s" does not contain "%s"', [Message, MessageFragment]));
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'Parsing took too long');
end;

end.
