package com.rizzog99.personalfinancetracker.domain.receipt

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Invented data shared by parser/recognizer and the editor's photo hand-off tests. */
internal object SyntheticReceiptImage {
    enum class Kind { Clear, Alternate, Ambiguous, AlternateAmbiguous, Unreadable, Angled, Rotated, Dim }

    fun create(context: Context, kind: Kind, date: LocalDate = LocalDate.of(2026, 11, 5)): File {
        val image = Bitmap.createBitmap(1_200, 1_200, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(image)
        canvas.drawColor(if (kind == Kind.Dim) Color.rgb(107, 108, 108) else Color.WHITE)
        when (kind) {
            Kind.Angled -> canvas.rotate(8f, 600f, 600f)
            Kind.Rotated -> canvas.rotate(90f, 600f, 600f)
            else -> Unit
        }
        if (kind != Kind.Unreadable) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = if (kind == Kind.Dim) Color.rgb(63, 64, 64) else Color.BLACK
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
                textSize = 60f
            }
            val merchant = if (kind == Kind.Alternate || kind == Kind.AlternateAmbiguous) "EMPORIO LUMINOSO" else "MERCATO AURORA"
            canvas.drawText(merchant, 120f, 150f, paint)
            paint.typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            paint.textSize = 43f
            canvas.drawText("DOCUMENTO COMMERCIALE", 120f, 237f, paint)
            val receiptDate = date.format(DateTimeFormatter.ofPattern("dd/MM/uuuu", Locale.ROOT))
            canvas.drawText("DATA $receiptDate", 120f, 314f, paint)
            val rows = listOf(
                "PANE" to "4,20",
                "FRUTTA" to "5,80",
                "IVA" to "2,50",
                "TOTALE COMPLESSIVO" to "12,50",
                (if (kind == Kind.Ambiguous || kind == Kind.AlternateAmbiguous) {
                    "TOTALE COMPLESSIVO" to "15,00"
                } else {
                    "CONTANTI" to "20,00"
                }),
                "RESTO" to "7,50",
            )
            rows.forEachIndexed { index, (label, amount) ->
                val baseline = 424f + index * 92f
                canvas.drawText(label, 120f, baseline, paint)
                canvas.drawText(amount, 872f, baseline, paint)
            }
        }
        val file = File.createTempFile("receipt-synthetic-", ".png", context.cacheDir)
        try {
            file.outputStream().use { output -> check(image.compress(Bitmap.CompressFormat.PNG, 100, output)) }
        } finally {
            image.recycle()
        }
        return file
    }
}
