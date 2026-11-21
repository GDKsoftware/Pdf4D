# Helper of generate-invoices.ps1: opens an HTML file in Microsoft Word through COM and writes it as a PDF twice,
# with Document.ExportAsFixedFormat (-ExportPath) and printed to the "Microsoft Print to PDF" printer with PrintToFile (-PrintPath).
# Prints the Word version. Word is always closed at the end; it runs in a process of its own so that the caller can end it on a time-out.
param([Parameter(Mandatory)][string]$Html, [string]$ExportPath = '', [string]$PrintPath = '')
$ErrorActionPreference = 'Stop'
$word = New-Object -ComObject Word.Application
$doc = $null
try {
    $word.Visible = $true
    $word.DisplayAlerts = 0
    $missing = [Type]::Missing
    # Open(FileName, ConfirmConversions, ReadOnly, AddToRecentFiles, PasswordDocument, PasswordTemplate, Revert, WritePasswordDocument,
    #      WritePasswordTemplate, Format, Encoding, Visible)
    $doc = $word.Documents.Open($Html, $false, $true, $false, $missing, $missing, $true, $missing, $missing, $missing, $missing, $true)
    Write-Output $word.Version
    if ($ExportPath) {
        # ExportFormat 17 is wdExportFormatPDF; IncludeDocProperties is false, so Author and the like stay out of the file
        $doc.ExportAsFixedFormat($ExportPath, 17, $false, 0, 0, 1, 1, 0, $false, $false, 0, $true, $true, $false)
    }
    if ($PrintPath) {
        $word.ActivePrinter = 'Microsoft Print to PDF'
        # Document.PrintOut(Background, Append, Range, OutputFileName, From, To, Item, Copies, Pages, PageType, PrintToFile)
        $printArguments = @($false, $false, 0, $PrintPath, $missing, $missing, $missing, 1, $missing, 0, $true)
        [void][System.__ComObject].InvokeMember('PrintOut', [Reflection.BindingFlags]::InvokeMethod, $null, $doc, $printArguments)
    }
} finally {
    if ($doc) { $doc.Close([ref]$false) }
    $word.Quit([ref]$false)
}
