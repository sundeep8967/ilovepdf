import fs from 'fs';
import PDFParser from 'pdf2json';

const pdfPath = '/Users/apple/Desktop/ilovepdf/invoice.pdf';
console.log('Checking valid coordinates...\n');

const pdfParser = new PDFParser();

pdfParser.on('pdfParser_dataReady', (pdfData) => {
    const page = pdfData.Pages[0];

    // Check "Tax Invoice..." and "Order Number"
    page.Texts.forEach((text, i) => {
        const content = text.R.map(r => decodeURIComponent(r.T)).join('');
        if (content.includes('Invoice') || content.includes('Order') || content.includes('Price')) {
            console.log(`[${i}] "${content}"`);
            console.log(`    x: ${text.x}, y: ${text.y}`);
        }
    });
});

pdfParser.loadPDF(pdfPath);
