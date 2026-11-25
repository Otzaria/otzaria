const installedPdfDarwinSymbols = {
  'pdfium': ['FPDF_LoadDocument', 'FPDF_RenderPageBitmap'],
  'printing': ['CGPDFDocumentCreateWithProvider', 'CGContextDrawPDFPage'],
};
const installedPdfDarwinSource = 'dyld image list + dladdr of process symbols';
const installedPdfDarwinPrinting = 'CoreGraphics (CGPDFDocument/CGContext)';
