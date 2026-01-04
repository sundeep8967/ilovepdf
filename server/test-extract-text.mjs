import fs from 'fs';
import http from 'http';

const pdfPath = '/Users/apple/Desktop/ilovepdf/invoice.pdf';
const pdfBytes = fs.readFileSync(pdfPath);
const pdfBase64 = pdfBytes.toString('base64');

const requestData = JSON.stringify({ pdfBase64 });

const options = {
    hostname: 'localhost',
    port: 3456,
    path: '/convert',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(requestData)
    }
};

console.log('Testing PDF text extraction...\n');

const req = http.request(options, (res) => {
    let data = '';
    res.on('data', (chunk) => { data += chunk; });
    res.on('end', () => {
        const response = JSON.parse(data);
        if (response.success) {
            const doc = response.data;
            const page0 = doc.pages[0];
            console.log(`Total elements: ${page0.elements.length}\n`);
            console.log('=== First 30 elements ===');
            page0.elements.slice(0, 30).forEach((el, i) => {
                console.log(`[${i}] "${el.content}"`);
            });
            console.log('\n=== Elements with "AAE", "564", or "PAN" ===');
            page0.elements.forEach((el, i) => {
                const c = el.content;
                if (c.includes('AAE') || c.includes('564') || c.includes('PAN')) {
                    console.log(`[${i}] "${c}" at (${el.x.toFixed(0)}, ${el.y.toFixed(0)})`);
                }
            });
        } else {
            console.error('Error:', response.error);
        }
    });
});

req.on('error', (e) => console.error('Error:', e.message));
req.write(requestData);
req.end();
