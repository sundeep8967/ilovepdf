import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs';
import fs from 'fs';

// Node.js support for PDF.js
const CMAP_URL = './node_modules/pdfjs-dist/cmaps/';
const CMAP_PACKED = true;

const pdfPath = '/Users/apple/Desktop/ilovepdf/invoice.pdf';
console.log('Testing PDF.js extraction on invoice.pdf...');

async function run() {
    try {
        const data = new Uint8Array(fs.readFileSync(pdfPath));
        const loadingTask = pdfjsLib.getDocument({
            data: data,
            cMapUrl: CMAP_URL,
            cMapPacked: CMAP_PACKED,
            standardFontDataUrl: './node_modules/pdfjs-dist/standard_fonts/'
        });

        const doc = await loadingTask.promise;
        console.log(`Document loaded: ${doc.numPages} pages`);

        const page = await doc.getPage(1);
        console.log(`Page 1 loaded`);

        const content = await page.getTextContent();
        console.log(`Extracted ${content.items.length} text items`);

        console.log('\n=== First 20 items ===');
        content.items.slice(0, 20).forEach((item, i) => {
            console.log(`[${i}] "${item.str}"`);
            console.log(`    Transform: [${item.transform.join(', ')}]`);
            // transform[4] is x, transform[5] is y
            console.log(`    x: ${item.transform[4]}, y: ${item.transform[5]}`);
        });

        console.log('\n=== Items with "PAN" or "AAE" ===');
        content.items.forEach((item, i) => {
            if (item.str.includes('PAN') || item.str.includes('AAE')) {
                console.log(`[${i}] "${item.str}"`);
                console.log(`    x: ${item.transform[4]}, y: ${item.transform[5]}`);
            }
        });

    } catch (e) {
        console.error('Error:', e);
    }
}

run();
