package com.rizzog99.personalfinancetracker.domain.receipt

import android.content.Context
import android.graphics.Point
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

object ReceiptTextRecognizer {
    suspend fun recognize(context: Context, imageUri: Uri): ReceiptDocument {
        val image = withContext(Dispatchers.IO) { InputImage.fromFilePath(context, imageUri) }
        val result = recognize(image)
        return withContext(Dispatchers.Default) { result.toReceiptDocument() }
    }

    private suspend fun recognize(image: InputImage): Text = suspendCancellableCoroutine { continuation ->
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            recognizer.process(image).addOnCompleteListener { result ->
                try {
                    if (continuation.isActive) {
                        if (result.isSuccessful) {
                            continuation.resume(result.result)
                        } else {
                            continuation.resumeWithException(result.exception ?: IllegalStateException("Receipt OCR was interrupted"))
                        }
                    }
                } finally {
                    recognizer.close()
                }
            }
        } catch (error: Exception) {
            recognizer.close()
            if (continuation.isActive) continuation.resumeWithException(error)
        }
    }

    private fun Text.toReceiptDocument(): ReceiptDocument {
        val lines = textBlocks.flatMap { it.lines }.filter { it.text.isNotBlank() }
        // Use a common top edge for every row. Independent axis-aligned boxes would make a
        // tilted merchant heading appear taller and put horizontally paired prices on other rows.
        val horizontal = lines.sumOf { cos(Math.toRadians(it.angle.toDouble())) * it.text.length }
        val vertical = lines.sumOf { sin(Math.toRadians(it.angle.toDouble())) * it.text.length }
        val deskew = atan2(vertical, horizontal)
        return ReceiptDocument(lines.map { line ->
            ReceiptLine(line.text, line.deskewedBounds(cos(deskew), sin(deskew)), line.confidence)
        })
    }

    private fun Text.Line.deskewedBounds(cosine: Double, sine: Double): ReceiptBounds? {
        val points = cornerPoints?.takeIf { it.size == 4 } ?: boundingBox?.let { rect ->
            arrayOf(Point(rect.left, rect.top), Point(rect.right, rect.top), Point(rect.right, rect.bottom), Point(rect.left, rect.bottom))
        } ?: return null
        val x = points.map { (it.x * cosine + it.y * sine).toFloat() }
        val y = points.map { (-it.x * sine + it.y * cosine).toFloat() }
        val left = x.min()
        val right = x.max()
        val top = y.min()
        val bottom = y.max()
        return if (left < right && top < bottom) ReceiptBounds(left, top, right, bottom) else null
    }
}
