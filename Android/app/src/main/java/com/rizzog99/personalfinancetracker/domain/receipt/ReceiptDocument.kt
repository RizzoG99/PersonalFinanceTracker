package com.rizzog99.personalfinancetracker.domain.receipt

/** OCR observations with geometry in a common, deskewed image coordinate system. */
data class ReceiptDocument(val lines: List<ReceiptLine>)

data class ReceiptLine(
    val text: String,
    val bounds: ReceiptBounds? = null,
    val confidence: Float? = null,
)

data class ReceiptBounds(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val centerY: Float get() = (top + bottom) / 2f
    val height: Float get() = bottom - top
}
