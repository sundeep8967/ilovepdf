package com.sundeep.ilovepdf

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.sundeep.ilovepdf/pdf_bridge"
    private lateinit var pdfBridge: PdfBridgePlugin
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize PDFBox
        PDFBoxResourceLoader.init(applicationContext)
        
        pdfBridge = PdfBridgePlugin(applicationContext)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractTextElements" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val json = pdfBridge.extractTextElements(path)
                                withContext(Dispatchers.Main) {
                                    result.success(json)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("EXTRACTION_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "Path is required", null)
                    }
                }
                "replaceText" -> {
                    val path = call.argument<String>("path")
                    val searchText = call.argument<String>("searchText")
                    val newText = call.argument<String>("newText")
                    val pageNumber = call.argument<Int>("pageNumber") ?: 0
                    
                    if (path != null && searchText != null && newText != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val outputPath = pdfBridge.replaceText(path, searchText, newText, pageNumber)
                                withContext(Dispatchers.Main) {
                                    result.success(outputPath)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("REPLACE_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "path, searchText, newText are required", null)
                    }
                }
                "inspectText" -> {
                    val path = call.argument<String>("path")
                    val searchText = call.argument<String>("searchText")
                    val pageNumber = call.argument<Int>("pageNumber") ?: 0
                    
                    if (path != null && searchText != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val json = pdfBridge.inspectText(path, searchText, pageNumber)
                                withContext(Dispatchers.Main) {
                                    result.success(json)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("INSPECT_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "path and searchText are required", null)
                    }
                }
                "replaceTextAdvanced" -> {
                    val path = call.argument<String>("path")
                    val searchText = call.argument<String>("searchText")
                    val newText = call.argument<String>("newText")
                    val pageNumber = call.argument<Int>("pageNumber") ?: 0
                    val fontSize = call.argument<Double>("fontSize")?.toFloat() ?: 0f
                    val isBold = call.argument<Boolean>("isBold") ?: false
                    val isItalic = call.argument<Boolean>("isItalic") ?: false
                    val xOffset = call.argument<Double>("xOffset")?.toFloat() ?: 0f
                    val yOffset = call.argument<Double>("yOffset")?.toFloat() ?: 0f
                    
                    if (path != null && searchText != null && newText != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val outputPath = pdfBridge.replaceTextAdvanced(
                                    path, searchText, newText, pageNumber, 
                                    fontSize, isBold, isItalic, xOffset, yOffset
                                )
                                withContext(Dispatchers.Main) {
                                    result.success(outputPath)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("REPLACE_ADV_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "path, searchText, newText are required", null)
                    }
                }
                "saveDocument" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    
                    if (inputPath != null && outputPath != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val success = pdfBridge.saveDocument(inputPath, outputPath)
                                withContext(Dispatchers.Main) {
                                    result.success(success)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("SAVE_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "inputPath and outputPath are required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
