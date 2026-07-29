package com.rithwikshetty.tab

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DataTransferStore(
    private val context: Context,
) {
    suspend fun readCsv(uri: Uri): String = withContext(Dispatchers.IO) {
        context.contentResolver.openInputStream(uri).use { input ->
            val stream = checkNotNull(input) { "Could not open the selected CSV file." }
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8 * 1024)
            var totalBytes = 0
            while (totalBytes <= MAX_IMPORT_BYTES) {
                val read = stream.read(buffer, 0, minOf(buffer.size, MAX_IMPORT_BYTES + 1 - totalBytes))
                if (read == -1) break
                output.write(buffer, 0, read)
                totalBytes += read
            }
            val bytes = output.toByteArray()
            require(bytes.size <= MAX_IMPORT_BYTES) { "CSV imports must be 5 MB or smaller." }
            bytes.toString(Charsets.UTF_8)
        }
    }

    suspend fun writeCsv(fileName: String, content: String): Uri = withContext(Dispatchers.IO) {
        val directory = File(context.cacheDir, "exports").apply { mkdirs() }
        val safeName = fileName
            .lowercase()
            .replace(Regex("[^a-z0-9]+"), "-")
            .trim('-')
            .ifEmpty { "tab-trip" }
        val file = File(directory, "$safeName.csv")
        file.writeText(content, Charsets.UTF_8)
        FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    }

    private companion object {
        const val MAX_IMPORT_BYTES: Int = 5 * 1024 * 1024
    }
}
