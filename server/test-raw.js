import fs from 'fs';
import PDFParser from 'pdf2json';

const pdfPath = '/Users/apple/Desktop/ilovepdf/invoice.pdf';
console.log('Extracting RAW text data from invoice.pdf...\n');

const pdfParser = new PDFParser();

pdfParser.on('pdfParser_dataError', (errData) => console.error(errData.parserError));

pdfParser.on('pdfParser_dataReady', (pdfData) => {
    const page = pdfData.Pages[0];
    console.log('=== Page 0 Texts (Raw) ===');

    // Find texts that match our interest
    page.Texts.forEach((text, i) => {
        const content = text.R.map(r => decodeURIComponent(r.T)).join('');
        if (content.includes('PAN') || content.includes('AAE')) {
            console.log(`[${i}] "${content}"`);
            console.log(`    x: ${text.x}, y: ${text.y}, w: ${text.w}, sw: ${text.sw}`);
            console.log(`    Matrix/CLR:`, text.clr);
        }
    });
});

pdfParser.loadPDF(pdfPath);
