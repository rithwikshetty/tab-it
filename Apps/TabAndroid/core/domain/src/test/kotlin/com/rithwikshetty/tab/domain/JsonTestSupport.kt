package com.rithwikshetty.tab.domain

internal class JsonValue private constructor(
    private val value: Any?,
) {
    @Suppress("UNCHECKED_CAST")
    val objectValue: Map<String, JsonValue>
        get() = value as Map<String, JsonValue>
    @Suppress("UNCHECKED_CAST")
    val arrayValue: List<JsonValue>
        get() = value as List<JsonValue>
    val stringValue: String
        get() = value as String
    val booleanValue: Boolean
        get() = value as Boolean

    operator fun get(key: String): JsonValue = objectValue.getValue(key)

    companion object {
        fun parse(text: String): JsonValue = Parser(text).parse()
    }

    private class Parser(private val text: String) {
        private var index = 0

        fun parse(): JsonValue {
            val result = readValue()
            skipWhitespace()
            check(index == text.length)
            return result
        }

        private fun readValue(): JsonValue {
            skipWhitespace()
            return when (text[index]) {
                '{' -> readObject()
                '[' -> readArray()
                '"' -> JsonValue(readString())
                't' -> {
                    expect("true")
                    JsonValue(true)
                }
                'f' -> {
                    expect("false")
                    JsonValue(false)
                }
                'n' -> {
                    expect("null")
                    JsonValue(null)
                }
                else -> JsonValue(readNumber())
            }
        }

        private fun readObject(): JsonValue {
            index++
            val entries = mutableMapOf<String, JsonValue>()
            skipWhitespace()
            while (text[index] != '}') {
                val key = readString()
                skipWhitespace()
                check(text[index++] == ':')
                entries[key] = readValue()
                skipWhitespace()
                if (text[index] == ',') {
                    index++
                    skipWhitespace()
                } else {
                    break
                }
            }
            check(text[index++] == '}')
            return JsonValue(entries)
        }

        private fun readArray(): JsonValue {
            index++
            val values = mutableListOf<JsonValue>()
            skipWhitespace()
            while (text[index] != ']') {
                values += readValue()
                skipWhitespace()
                if (text[index] == ',') {
                    index++
                    skipWhitespace()
                } else {
                    break
                }
            }
            check(text[index++] == ']')
            return JsonValue(values)
        }

        private fun readString(): String {
            skipWhitespace()
            check(text[index++] == '"')
            val result = StringBuilder()
            while (text[index] != '"') {
                val character = text[index++]
                if (character == '\\') {
                    result.append(
                        when (val escaped = text[index++]) {
                            '"' -> '"'
                            '\\' -> '\\'
                            '/' -> '/'
                            'b' -> '\b'
                            'f' -> '\u000C'
                            'n' -> '\n'
                            'r' -> '\r'
                            't' -> '\t'
                            else -> error("Unsupported JSON escape: $escaped")
                        },
                    )
                } else {
                    result.append(character)
                }
            }
            index++
            return result.toString()
        }

        private fun readNumber(): String {
            val start = index
            while (index < text.length && text[index] in "-+0123456789.eE") index++
            return text.substring(start, index)
        }

        private fun expect(expected: String) {
            check(text.startsWith(expected, index))
            index += expected.length
        }

        private fun skipWhitespace() {
            while (index < text.length && text[index].isWhitespace()) index++
        }
    }
}
