package com.rizzog99.personalfinancetracker.domain.receipt

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

object ReceiptTextRecognizer {
    suspend fun recognize(context: Context, imageUri: Uri): List<String> {
        val image = InputImage.fromFilePath(context, imageUri)
        return suspendCancellableCoroutine { continuation ->
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                .process(image)
                .addOnSuccessListener { result ->
                    if (continuation.isActive) {
                        continuation.resume(result.textBlocks.flatMap { block -> block.lines.map { it.text } })
                    }
                }
                .addOnFailureListener { error ->
                    if (continuation.isActive) continuation.resumeWithException(error)
                }
        }
    }
}
