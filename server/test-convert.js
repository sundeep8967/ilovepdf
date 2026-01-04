const fs = require('fs');
const path = require('path');

const pdfPath = '/Users/apple/Desktop/ilovepdf/invoice.pdf';
const pdfBytes = fs.readFileSync(pdfPath);
const pdfBase64 = pdfBytes.toString('base64');

const requestData = JSON.stringify({ pdfBase64 });

// Make HTTP POST request manually
const http = require('http');
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

console.log('Sending PDF to /convert endpoint...\n');

const req = http.request(options, (res) => {
    let data = '';

    res.on('data', (chunk) => {
        data += chunk;
    });

    res.on('end', () => {
        const response = JSON.parse(data);
        if (response.success) {
            const doc = response.data;
            console.log(`Page count: ${doc.pageCount}`);
            console.log(`Total elements: ${doc.pages[0].elements.length}\n`);

            console.log('=== First 30 text elements on page 0 ===');
            doc.pages[0].elements.slice(0, 30).forEach((el, i) => {
                console.log(`[${i}] "${el.content}" at x=${el.x.toFixed(1)}`);
            });

            // Look for PAN number specifically
            console.log('\n=== Elements containing "AAE" or "564" ===');
            doc.pages[0].elements.forEach((el, i) => {
                if (el.content.includes('AAE') || el.content.includes('564') || el.content.includes('PAN')) {
                    console.log(`[${i}] "${el.content}" at x=${el.x.toFixed(1)}`);
                }
            });
        } else {
            console.error('Error:', response.error);
        }
    });
});

req.on('error', (e) => {
    console.error('Request error:', e.message);
});

req.write(requestData);
req.end();
