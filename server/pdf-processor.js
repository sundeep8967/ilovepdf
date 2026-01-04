/**
 * PDF Processor Module
 * Converts PDF to JSON (pdf2json) and rebuilds PDF with edits (pdf-lib)
 * 
 * Debug logs prefixed with emoji for easy identification:
 * 🔵 INFO - General progress
 * 🟢 SUCCESS - Operation completed
 * 🔴 ERROR - Error occurred
 * 🟡 DEBUG - Detailed debug info
 */

import PDFParser from 'pdf2json';
import { PDFDocument, rgb, StandardFonts } from 'pdf-lib';
import fs from 'fs/promises';
import path from 'path';

// Debug logger
const log = {
    info: (msg, data = '') => console.log(`🔵 [INFO] ${msg}`, data),
    success: (msg, data = '') => console.log(`🟢 [SUCCESS] ${msg}`, data),
    error: (msg, data = '') => console.log(`🔴 [ERROR] ${msg}`, data),
    debug: (msg, data = '') => console.log(`🟡 [DEBUG] ${msg}`, data),
};

/**
 * Convert PDF file to JSON structure
 * @param {string} pdfPath - Path to PDF file
 * @returns {Promise<Object>} JSON representation of PDF
 */
export async function pdfToJson(pdfPath) {
    log.info('Starting PDF to JSON conversion', pdfPath);

    return new Promise((resolve, reject) => {
        const pdfParser = new PDFParser();

        pdfParser.on('pdfParser_dataError', (errData) => {
            log.error('pdf2json parsing error', errData.parserError);
            reject(new Error(errData.parserError));
        });

        pdfParser.on('pdfParser_dataReady', (pdfData) => {
            log.info('pdf2json parsing complete');
            log.debug('Raw page count', pdfData.Pages?.length || 0);

            // Transform to our format
            const result = transformPdfData(pdfData, pdfPath);
            log.success('JSON transformation complete', `${result.pages.length} pages, ${result.totalElements} elements`);

            resolve(result);
        });

        log.debug('Loading PDF file...');
        pdfParser.loadPDF(pdfPath);
    });
}

/**
 * Transform pdf2json output to our simplified format
 */
function transformPdfData(pdfData, pdfPath) {
    const pages = [];
    let totalElements = 0;
    let elementId = 0;

    for (let pageIndex = 0; pageIndex < pdfData.Pages.length; pageIndex++) {
        const page = pdfData.Pages[pageIndex];
        const pageElements = [];

        log.debug(`Processing page ${pageIndex + 1}`, `${page.Texts?.length || 0} text objects`);

        // Process text elements
        if (page.Texts) {
            for (const text of page.Texts) {
                if (text.R && text.R.length > 0) {
                    // Decode the text content (pdf2json encodes it)
                    const content = text.R.map(r => decodeURIComponent(r.T)).join('');

                    if (content.trim()) {
                        const element = {
                            id: `text_${elementId++}`,
                            type: 'text',
                            content: content,
                            x: text.x * 4.5, // Convert pdf2json units to points (approximate)
                            y: text.y * 4.5,
                            width: text.w || 100,
                            height: text.sw || 12,
                            fontSize: text.R[0]?.TS?.[1] || 12,
                            fontStyle: {
                                bold: text.R[0]?.TS?.[2] === 1,
                                italic: text.R[0]?.TS?.[3] === 1,
                            },
                            pageNumber: pageIndex,
                        };

                        pageElements.push(element);
                        totalElements++;
                    }
                }
            }
        }

        pages.push({
            pageNumber: pageIndex,
            width: page.Width ? page.Width * 4.5 : 612, // Default letter width
            height: page.Height ? page.Height * 4.5 : 792, // Default letter height
            elements: pageElements,
        });
    }

    return {
        path: pdfPath,
        pageCount: pages.length,
        totalElements: totalElements,
        pages: pages,
        metadata: {
            convertedAt: new Date().toISOString(),
            version: '1.0',
        },
    };
}

/**
 * Apply text edits to a PDF using pdf-lib
 * @param {string} pdfPath - Original PDF path
 * @param {Array} edits - Array of edit operations
 * @param {string} outputPath - Output PDF path
 * @returns {Promise<string>} Path to modified PDF
 */
export async function applyEdits(pdfPath, edits, outputPath) {
    log.info('Starting PDF edit process', `${edits.length} edit(s) to apply`);

    try {
        // Load the original PDF
        log.debug('Loading original PDF...');
        const pdfBytes = await fs.readFile(pdfPath);
        const pdfDoc = await PDFDocument.load(pdfBytes, {
            ignoreEncryption: true,
            updateMetadata: false
        });

        log.debug('PDF loaded', `${pdfDoc.getPageCount()} pages`);

        // Embed font for text replacement
        const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
        log.debug('Font embedded: Helvetica');

        // Apply each edit
        for (let i = 0; i < edits.length; i++) {
            const edit = edits[i];
            log.info(`Applying edit ${i + 1}/${edits.length}`, `"${edit.oldText}" → "${edit.newText}"`);

            const page = pdfDoc.getPage(edit.pageNumber);
            const { width, height } = page.getSize();
            log.debug('Page size', `${width}x${height}`);

            // For text replacement, we use an overlay approach:
            // 1. Draw a white rectangle over the old text area
            // 2. Draw the new text on top

            // Calculate position (pdf-lib uses bottom-left origin)
            const x = edit.x || 72;
            const y = height - (edit.y || 100) - (edit.height || 14); // Flip Y coordinate
            const fontSize = edit.fontSize || 12;

            log.debug('Drawing at position', `x=${x}, y=${y}, fontSize=${fontSize}`);

            // Draw white background to cover old text
            page.drawRectangle({
                x: x - 2,
                y: y - 2,
                width: edit.width ? edit.width + 4 : font.widthOfTextAtSize(edit.newText, fontSize) + 4,
                height: fontSize + 4,
                color: rgb(1, 1, 1), // White
            });

            // Draw new text
            page.drawText(edit.newText, {
                x: x,
                y: y,
                size: fontSize,
                font: font,
                color: rgb(0, 0, 0), // Black
            });

            log.success(`Edit ${i + 1} applied`);
        }

        // Save the modified PDF
        log.debug('Saving modified PDF...');
        const modifiedPdfBytes = await pdfDoc.save();
        await fs.writeFile(outputPath, modifiedPdfBytes);

        log.success('PDF saved', outputPath);
        return outputPath;

    } catch (error) {
        log.error('Failed to apply edits', error.message);
        throw error;
    }
}

/**
 * Find and replace text in PDF
 * This is a simplified approach - draws new text over the original
 */
export async function replaceText(pdfPath, searchText, newText, pageNumber, outputPath) {
    log.info('Replace text request', { searchText, newText, pageNumber });

    try {
        const pdfBytes = await fs.readFile(pdfPath);
        const pdfDoc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });

        const page = pdfDoc.getPage(pageNumber);
        const { height } = page.getSize();
        const font = await pdfDoc.embedFont(StandardFonts.Helvetica);

        // First, get the JSON to find the text position
        const jsonData = await pdfToJson(pdfPath);
        const targetPage = jsonData.pages[pageNumber];

        if (!targetPage) {
            throw new Error(`Page ${pageNumber} not found`);
        }

        // Find the matching text element
        const matchingElement = targetPage.elements.find(el =>
            el.content.includes(searchText) || searchText.includes(el.content)
        );

        if (matchingElement) {
            log.info('Found matching element', matchingElement);

            // Draw white rectangle and new text
            const x = matchingElement.x;
            const y = height - matchingElement.y - matchingElement.height;
            const fontSize = matchingElement.fontSize || 12;

            page.drawRectangle({
                x: x - 2,
                y: y - 2,
                width: font.widthOfTextAtSize(newText, fontSize) + 8,
                height: fontSize + 6,
                color: rgb(1, 1, 1),
            });

            page.drawText(newText, {
                x: x,
                y: y,
                size: fontSize,
                font: font,
                color: rgb(0, 0, 0),
            });

            log.success('Text replaced successfully');
        } else {
            log.error('Text not found in JSON', searchText);
            // Fallback: just add the text at a default position
            page.drawText(newText, {
                x: 72,
                y: height - 100,
                size: 12,
                font: font,
                color: rgb(0, 0, 0),
            });
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
