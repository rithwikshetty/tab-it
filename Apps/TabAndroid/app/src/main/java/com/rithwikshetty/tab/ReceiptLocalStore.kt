package com.rithwikshetty.tab

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class PreparedReceipt(
    val localUri: String,
    val remotePath: String,
)

class ReceiptLocalStore(
    private val context: Context,
) {
    suspend fun prepare(source: Uri, tripId: UUID, expenseId: UUID): PreparedReceipt =
        withContext(Dispatchers.IO) {
            val bitmap = decodeScaled(source)
            val bytes = ByteArrayOutputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)) {
                    "Could not encode the receipt."
                }
                output.toByteArray()
            }
            bitmap.recycle()
            require(bytes.size in 1..MAX_RECEIPT_BYTES) {
                "Receipt must be no larger than 10 MB."
            }
            require(bytes.size >= 2 && bytes[0] == JPEG_START_A && bytes[1] == JPEG_START_B) {
                "Receipt must be a JPEG image."
            }
            val directory = File(context.filesDir, "receipts/$tripId").apply { mkdirs() }
            val target = File(directory, "$expenseId.jpg")
            target.outputStream().use { it.write(bytes) }
            PreparedReceipt(
                localUri = target.toURI().toString(),
                remotePath = "$tripId/$expenseId.jpg",
            )
        }

    suspend fun readLocal(localUri: String): ByteArray? = withContext(Dispatchers.IO) {
        runCatching {
            File(java.net.URI(localUri)).takeIf(File::isFile)?.readBytes()
        }.getOrNull()
    }

    private fun decodeScaled(source: Uri): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val imageSource = ImageDecoder.createSource(context.contentResolver, source)
            return ImageDecoder.decodeBitmap(imageSource) { decoder, info, _ ->
                val size = info.size
                val scale = minOf(1f, MAX_DIMENSION.toFloat() / maxOf(size.width, size.height))
                decoder.setTargetSize(
                    (size.width * scale).toInt().coerceAtLeast(1),
                    (size.height * scale).toInt().coerceAtLeast(1),
                )
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(source).use {
            BitmapFactory.decodeStream(checkNotNull(it), null, bounds)
        }
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Could not read the receipt image." }
        var sample = 1
        while (maxOf(bounds.outWidth / sample, bounds.outHeight / sample) > MAX_DIMENSION * 2) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = context.contentResolver.openInputStream(source).use {
            BitmapFactory.decodeStream(checkNotNull(it), null, options)
        } ?: error("Could not read the receipt image.")
        val scale = minOf(1f, MAX_DIMENSION.toFloat() / maxOf(decoded.width, decoded.height))
        if (scale == 1f) return decoded
        val scaled = Bitmap.createScaledBitmap(
            decoded,
            (decoded.width * scale).toInt(),
            (decoded.height * scale).toInt(),
            true,
        )
        decoded.recycle()
        return scaled
    }

    private companion object {
        const val MAX_DIMENSION: Int = 2_200
        const val MAX_RECEIPT_BYTES: Int = 10 * 1024 * 1024
        const val JPEG_QUALITY: Int = 84
        const val JPEG_START_A: Byte = -1
        const val JPEG_START_B: Byte = -40
    }
}
