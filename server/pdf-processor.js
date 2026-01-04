/**
 * PDF Processor Module
 * Extracts text with coordinates (pdfjs-dist) and rebuilds PDF with edits (pdf-lib)
 */

import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs';
import { PDFDocument, rgb, StandardFonts } from 'pdf-lib';
import fs from 'fs/promises';
import { readFileSync } from 'fs';

// Node.js support for PDF.js
const CMAP_URL = './node_modules/pdfjs-dist/cmaps/';
const CMAP_PACKED = true;
const STANDARD_FONT_DATA_URL = './node_modules/pdfjs-dist/standard_fonts/';

// Debug logger
const log = {
    info: (msg, data = '') => console.log(`🔵 [INFO] ${msg}`, data),
    success: (msg, data = '') => console.log(`🟢 [SUCCESS] ${msg}`, data),
    error: (msg, data = '') => console.log(`🔴 [ERROR] ${msg}`, data),
    debug: (msg, data = '') => console.log(`🟡 [DEBUG] ${msg}`, data),
};

/**
 * Extract text elements with positions using PDF.js
 * @param {string} pdfPath - Path to PDF file
 * @returns {Promise<Object>} JSON representation with pages and elements
 */
export async function pdfToJson(pdfPath) {
    log.info('Starting PDF text extraction (pdfjs-dist)', pdfPath);

    try {
        const data = new Uint8Array(readFileSync(pdfPath));
        const loadingTask = pdfjsLib.getDocument({
            data: data,
            cMapUrl: CMAP_URL,
            cMapPacked: CMAP_PACKED,
            standardFontDataUrl: STANDARD_FONT_DATA_URL
        });

        const doc = await loadingTask.promise;
        const numPages = doc.numPages;
        log.debug('Document loaded', `${numPages} pages`);

        const pages = [];
        let totalElements = 0;

        for (let i = 1; i <= numPages; i++) {
            const page = await doc.getPage(i);
            const viewport = page.getViewport({ scale: 1.0 });
            const content = await page.getTextContent();

            const elements = content.items.map(item => {
                // transform[4] is x, transform[5] is y (from bottom-left in PDF usually)
                return {
                    content: item.str,
                    x: item.transform[4],
                    y: item.transform[5],
                    width: item.width,
                    height: item.height,
                    fontSize: item.transform[0], // approximate font size from scaling factor
                    fontName: item.fontName,
                    hasEOL: item.hasEOL
                };
            }).filter(el => el.content.trim().length > 0);

            log.debug(`Page ${i}`, `${elements.length} text elements`);
            totalElements += elements.length;

            pages.push({
                pageNumber: i - 1, // 0-indexed for our API
                width: viewport.width,
                height: viewport.height,
                elements: elements
            });
        }

        return {
            path: pdfPath,
            pageCount: numPages,
            totalElements: totalElements,
            pages: pages
        };

    } catch (error) {
        log.error('Extraction failed', error);
        throw error;
    }
}

/**
 * Apply text edits to a PDF using pdf-lib
 */
export async function applyEdits(pdfPath, edits, outputPath) {
    if (!edits || edits.length === 0) return pdfPath;
    return replaceText(pdfPath, edits[0].oldText, edits[0].newText, edits[0].pageNumber, outputPath);
}

/**
 * Find and replace text in PDF
 */
export async function replaceText(pdfPath, searchText, newText, pageNumber, outputPath) {
    log.info('Replace text request', { searchText, newText, pageNumber });

    try {
        const pdfBytes = await fs.readFile(pdfPath);
        const pdfDoc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });

        const page = pdfDoc.getPage(pageNumber);
        const { height } = page.getSize();
        const font = await pdfDoc.embedFont(StandardFonts.Helvetica);

        // Get text positions using PDF.js
        const jsonData = await pdfToJson(pdfPath);
        const targetPage = jsonData.pages[pageNumber];

        if (!targetPage) {
            throw new Error(`Page ${pageNumber} not found`);
        }

        // --- Improved Text Matching (4-Tier Strategy) ---
        let matchingElement = null;

        // Strategy 1: Exact substring match
        matchingElement = targetPage.elements.find(el =>
            el.content.includes(searchText)
        );

        // Strategy 2: Partial match (search text contains element content)
        if (!matchingElement) {
            matchingElement = targetPage.elements.find(el =>
                searchText.includes(el.content) && el.content.length > 2
            );
        }

        // Strategy 3: Prefix match
        if (!matchingElement) {
            const searchStart = searchText.substring(0, Math.min(4, searchText.length));
            matchingElement = targetPage.elements.find(el =>
                el.content.startsWith(searchStart)
            );
        }

        // Strategy 4: Fuzzy match
        if (!matchingElement && targetPage.elements.length > 0) {
            let bestMatch = null;
            let bestScore = 0;

            for (const el of targetPage.elements) {
                let score = 0;
                for (const char of searchText) {
                    if (el.content.includes(char)) score++;
                }
                if (score > bestScore && score >= Math.min(searchText.length * 0.5, el.content.length * 0.8)) {
                    bestScore = score;
                    bestMatch = el;
                }
            }
            matchingElement = bestMatch;
        }

        if (matchingElement) {
            log.info('Found matching element', JSON.stringify(matchingElement));

            // Coordinates:
            // PDF.js gives Y from bottom-left (typically).
            // pdf-lib drawText also uses Y from bottom-left.
            // So matchingElement.y should be correct directly.

            const x = matchingElement.x;
            const y = matchingElement.y;
            const fontSize = matchingElement.fontSize || 12;

            log.debug(`Writing at x=${x}, y=${y}`);

            // Calculate width o cover: use the width of the ORIGINAL element content to ensure full erasure
            // We use the embedded font to measure it to match the scale we are drawing with
            const originalTextWidth = font.widthOfTextAtSize(matchingElement.content, fontSize);
            const newTextWidth = font.widthOfTextAtSize(newText, fontSize);

            // Width should be enough to cover original text. 
            // We add a bit of padding (+4) to be safe.
            const coverWidth = Math.max(originalTextWidth, newTextWidth) + 4;

            // Draw white rectangle to cover old text
            // Need to cover slightly below baseline (for descenders like 'g', 'p', 'y')
            page.drawRectangle({
                x: x - 2,
                y: y - 2,
                width: coverWidth,
                height: fontSize + 4,
                color: rgb(1, 1, 1),
            });

            // Draw new text
            page.drawText(newText, {
                x: x,
                y: y,
                size: fontSize,
                font: font,
                color: rgb(0, 0, 0),
            });

            log.success('Text replaced successfully');
        } else {
            log.error('Text not found after all strategies', searchText);
            throw new Error(`Could not find text "${searchText}" on page ${pageNumber}`);
        }

        const modifiedBytes = await pdfDoc.save();
        await fs.writeFile(outputPath, modifiedBytes);

        return outputPath;
    } catch (error) {
        log.error('Replace text failed', error.message);
        throw error;
    }
}


export { log };

/**
 * Write text at specific coordinates (Manual Add Text)
 * @param {string} pdfPath - Path to input PDF
 * @param {string} text - Text to write
 * @param {number} pageNumber - 0-indexed page number
 * @param {number} x - X coordinate
 * @param {number} y - Y coordinate (from top, will be converted)
 * @param {string} outputPath - Path for output PDF
 */
export async function writeTextAt(pdfPath, text, pageNumber, x, y, outputPath) {
    log.info('Writing text at coordinates', `"${text}" at (${x}, ${y}) on page ${pageNumber}`);

    try {
        const pdfBytes = await fs.readFile(pdfPath);
        const pdfDoc = await PDFDocument.load(pdfBytes);
        const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
        const pages = pdfDoc.getPages();

        if (pageNumber < 0 || pageNumber >= pages.length) {
            throw new Error(`Invalid page number: ${pageNumber}`);
        }

        const page = pages[pageNumber];
        const { height } = page.getSize();

        // Convert Y from top-left (Flutter) to bottom-left (PDF)
        const pdfY = height - y;

        const fontSize = 14; // Default font size

        // Draw the text
        page.drawText(text, {
            x: x,
            y: pdfY,
            size: fontSize,
            font: font,
            color: rgb(0, 0, 0),
        });

        log.success('Text written successfully');

        const modifiedBytes = await pdfDoc.save();
        await fs.writeFile(outputPath, modifiedBytes);

        return outputPath;
    } catch (error) {
        log.error('Write text failed', error.message);
        throw error;
    }
}

/**
 * Erase text by drawing white rectangle (Manual Eraser)
 * @param {string} pdfPath - Path to input PDF
 * @param {number} pageNumber - 0-indexed page number
 * @param {number} x - X coordinate
 * @param {number} y - Y coordinate (from top)
 * @param {number} width - Width of rectangle
 * @param {number} height - Height of rectangle
 * @param {string} outputPath - Path for output PDF
 */
export async function eraseArea(pdfPath, pageNumber, x, y, width, rectHeight, outputPath) {
    log.info('Erasing area', `(${x}, ${y}) size ${width}x${rectHeight} on page ${pageNumber}`);

    try {
        const pdfBytes = await fs.readFile(pdfPath);
        const pdfDoc = await PDFDocument.load(pdfBytes);
        const pages = pdfDoc.getPages();

        if (pageNumber < 0 || pageNumber >= pages.length) {
            throw new Error(`Invalid page number: ${pageNumber}`);
        }

        const page = pages[pageNumber];
        const { height: pageHeight } = page.getSize();

        // Convert Y from top-left to bottom-left
        const pdfY = pageHeight - y - rectHeight;

        // Draw white rectangle
        page.drawRectangle({
            x: x,
            y: pdfY,
            width: width,
            height: rectHeight,
            color: rgb(1, 1, 1),
        });

        log.success('Area erased successfully');

        const modifiedBytes = await pdfDoc.save();
        await fs.writeFile(outputPath, modifiedBytes);

        return outputPath;
    } catch (error) {
        log.error('Erase area failed', error.message);
        throw error;
    }
}
