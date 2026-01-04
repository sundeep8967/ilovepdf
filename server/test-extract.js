import { pdfToJson } from './pdf-processor.js';

const pdfPath = '/Users/apple/Desktop/ilovepdf/invoice.pdf';

console.log('Extracting text from invoice.pdf...\n');

pdfToJson(pdfPath).then(result => {
    console.log(`Page count: ${result.pageCount}`);
    console.log(`Total elements: ${result.totalElements}\n`);

    // Show all text elements on page 0
    const page = result.pages[0];
    console.log('=== Page 0 Text Elements ===');
    page.elements.forEach((el, i) => {
        console.log(`[${i}] "${el.content}" at (${el.x.toFixed(1)}, ${el.y.toFixed(1)})`);
    });
}).catch(err => {
    console.error('Error:', err.message);
});
