/**
 * PDF Editor Server
 * Local HTTP server for PDF processing
 * 
 * Endpoints:
 * - POST /convert     : Convert PDF to JSON
 * - POST /replace     : Replace text in PDF
 * - POST /apply-edits : Apply multiple edits
 * - GET  /health      : Health check
 */

import express from 'express';
import cors from 'cors';
import fs from 'fs/promises';
import path from 'path';
import { pdfToJson, applyEdits, replaceText, log } from './pdf-processor.js';

const app = express();
const PORT = process.env.PORT || 3456;

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Request logging middleware
app.use((req, res, next) => {
    log.info(`${req.method} ${req.path}`);
    next();
});

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

/**
 * Convert PDF to JSON
 * Body: { pdfPath: string } OR { pdfBase64: string }
 */
app.post('/convert', async (req, res) => {
    const startTime = Date.now();

    try {
        let pdfPath = req.body.pdfPath;

        // If base64 is provided, save to temp file first
        if (req.body.pdfBase64) {
            log.info('Received base64 PDF, saving to temp file...');
            const tempPath = path.join('/tmp', `input_${Date.now()}.pdf`);
            const buffer = Buffer.from(req.body.pdfBase64, 'base64');
            await fs.writeFile(tempPath, buffer);
            pdfPath = tempPath;
            log.debug('Temp file created', tempPath);
        }

        if (!pdfPath) {
            return res.status(400).json({
                error: 'Missing pdfPath or pdfBase64',
                logs: ['🔴 [ERROR] No PDF path or base64 data provided']
            });
        }

        log.info('Converting PDF to JSON', pdfPath);
        const result = await pdfToJson(pdfPath);

        const duration = Date.now() - startTime;
        log.success(`Conversion complete in ${duration}ms`);

        res.json({
            success: true,
            data: result,
            duration: duration,
            logs: [
                `🔵 [INFO] Started conversion`,
                `🔵 [INFO] Found ${result.pageCount} pages`,
                `🔵 [INFO] Extracted ${result.totalElements} text elements`,
                `🟢 [SUCCESS] Conversion complete in ${duration}ms`
            ]
        });

    } catch (error) {
        log.error('Conversion failed', error.message);
        res.status(500).json({
            error: error.message,
            logs: [
                `🔴 [ERROR] Conversion failed: ${error.message}`
            ]
        });
    }
});

/**
 * Replace text in PDF
 * Body: { pdfPath, searchText, newText, pageNumber }
 */
app.post('/replace', async (req, res) => {
    const startTime = Date.now();

    try {
        const { pdfPath, pdfBase64, searchText, newText, pageNumber } = req.body;

        let inputPath = pdfPath;

        // Handle base64 input
        if (pdfBase64) {
            inputPath = path.join('/tmp', `input_${Date.now()}.pdf`);
            const buffer = Buffer.from(pdfBase64, 'base64');
            await fs.writeFile(inputPath, buffer);
            log.debug('Input temp file created', inputPath);
        }

        if (!inputPath || !searchText || !newText) {
            return res.status(400).json({
                error: 'Missing required fields: pdfPath/pdfBase64, searchText, newText',
                logs: ['🔴 [ERROR] Missing required fields']
            });
        }

        const outputPath = path.join('/tmp', `output_${Date.now()}.pdf`);

        log.info('Replacing text', { searchText, newText, pageNumber });

        await replaceText(inputPath, searchText, newText, pageNumber || 0, outputPath);

        // Read output as base64
        const outputBytes = await fs.readFile(outputPath);
        const outputBase64 = outputBytes.toString('base64');

        const duration = Date.now() - startTime;
        log.success(`Replace complete in ${duration}ms`);

        res.json({
            success: true,
            outputPath: outputPath,
            outputBase64: outputBase64,
            duration: duration,
            logs: [
                `🔵 [INFO] Loading PDF...`,
                `🔵 [INFO] Searching for "${searchText}"`,
                `🔵 [INFO] Replacing with "${newText}"`,
                `🔵 [INFO] Saving modified PDF...`,
                `🟢 [SUCCESS] Text replaced in ${duration}ms`
            ]
        });

    } catch (error) {
        log.error('Replace failed', error.message);
        res.status(500).json({
            error: error.message,
            logs: [`🔴 [ERROR] Replace failed: ${error.message}`]
        });
    }
});

/**
 * Apply multiple edits to PDF
 * Body: { pdfPath, edits: [{ oldText, newText, x, y, pageNumber, fontSize }] }
 */
app.post('/apply-edits', async (req, res) => {
    const startTime = Date.now();

    try {
        const { pdfPath, pdfBase64, edits } = req.body;

        let inputPath = pdfPath;

        if (pdfBase64) {
            inputPath = path.join('/tmp', `input_${Date.now()}.pdf`);
            const buffer = Buffer.from(pdfBase64, 'base64');
            await fs.writeFile(inputPath, buffer);
        }

        if (!inputPath || !edits || !Array.isArray(edits)) {
            return res.status(400).json({
                error: 'Missing pdfPath/pdfBase64 or edits array',
                logs: ['🔴 [ERROR] Missing required fields']
            });
        }

        const outputPath = path.join('/tmp', `edited_${Date.now()}.pdf`);

        log.info('Applying edits', `${edits.length} edit(s)`);

        await applyEdits(inputPath, edits, outputPath);

        // Read output as base64
        const outputBytes = await fs.readFile(outputPath);
        const outputBase64 = outputBytes.toString('base64');

        const duration = Date.now() - startTime;

        res.json({
            success: true,
            outputPath: outputPath,
            outputBase64: outputBase64,
            duration: duration,
            logs: [
                `🔵 [INFO] Loading PDF...`,
                `🔵 [INFO] Applying ${edits.length} edit(s)...`,
                ...edits.map((e, i) => `🔵 [INFO] Edit ${i + 1}: "${e.oldText}" → "${e.newText}"`),
                `🟢 [SUCCESS] Edits applied in ${duration}ms`
            ]
        });

    } catch (error) {
        log.error('Apply edits failed', error.message);
        res.status(500).json({
            error: error.message,
            logs: [`🔴 [ERROR] Apply edits failed: ${error.message}`]
        });
    }
});

// Start server
app.listen(PORT, () => {
    log.success(`PDF Editor Server running on http://localhost:${PORT}`);
    log.info('Available endpoints:');
    console.log('  GET  /health       - Health check');
    console.log('  POST /convert      - PDF to JSON');
    console.log('  POST /replace      - Replace text');
    console.log('  POST /apply-edits  - Apply multiple edits');
});
