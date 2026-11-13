unit Pdf4D.Parser.Security.Interfaces;

interface

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary;

type
  // The part of PDFBox' SecurityHandler that the parser uses. The handler is set before objects are loaded.
  ISecurityHandler = interface
    ['{2F0E7B64-7D0B-4B5C-9A55-6C5E8B1D3F21}']
    procedure DecryptStream(const Stream: TCosStream; const ObjectNumber: Int64; const Generation: Integer);
    // Value may be nil: the object was empty
    procedure Decrypt(const Value: TCosBase; const ObjectNumber: Int64; const Generation: Integer);
  end;

  // Reads the encryption of the document from its trailer and gives the handler, or nil for a document that is not encrypted
  TDecryptionPreparer = reference to function: ISecurityHandler;

implementation

end.
