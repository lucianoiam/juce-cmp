// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.ipc

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * A Kotlin reimplementation of JUCE's ValueTree with binary-compatible serialization.
 *
 * JuceValueTree is a tree structure where each node has:
 * - A type identifier (String)
 * - Named properties (String -> Var)
 * - Child JuceValueTrees
 *
 * ENDIANNESS: Uses LITTLE-ENDIAN byte order to match JUCE's native format.
 * JUCE uses little-endian on all platforms for ValueTree binary serialization,
 * regardless of the host CPU architecture.
 *
 * Binary format (matches JUCE's ValueTree::writeToStream exactly):
 * - Type: null-terminated UTF-8 string (JUCE writeString)
 * - Property count: compressed int (JUCE writeCompressedInt)
 * - For each property: name (null-terminated UTF-8) + Var (compressed size + marker + data)
 * - Child count: compressed int
 * - For each child: recursive JuceValueTree
 *
 * This format is compatible with juce::ValueTree::readFromData() and writeToStream().
 */
class JuceValueTree(
    val type: String = ""
) {
    private val properties = LinkedHashMap<String, Var>()
    private val children = mutableListOf<JuceValueTree>()

    /**
     * Check if this is a valid (non-empty) tree.
     */
    val isValid: Boolean get() = type.isNotEmpty()

    /**
     * Number of properties.
     */
    val numProperties: Int get() = properties.size

    /**
     * Number of children.
     */
    val numChildren: Int get() = children.size

    // --- Property access ---

    operator fun get(name: String): Var = properties[name] ?: Var.Void

    operator fun set(name: String, value: Var) {
        properties[name] = value
    }

    operator fun set(name: String, value: Int) {
        properties[name] = Var.IntVal(value)
    }

    operator fun set(name: String, value: Long) {
        properties[name] = Var.Int64Val(value)
    }

    operator fun set(name: String, value: Double) {
        properties[name] = Var.DoubleVal(value)
    }

    operator fun set(name: String, value: Float) {
        properties[name] = Var.DoubleVal(value.toDouble())
    }

    operator fun set(name: String, value: Boolean) {
        properties[name] = Var.BoolVal(value)
    }

    operator fun set(name: String, value: String) {
        properties[name] = Var.StrVal(value)
    }

    operator fun set(name: String, value: ByteArray) {
        properties[name] = Var.BinaryVal(value)
    }

    fun hasProperty(name: String): Boolean = properties.containsKey(name)

    fun removeProperty(name: String) {
        properties.remove(name)
    }

    fun getPropertyName(index: Int): String? = properties.keys.elementAtOrNull(index)

    // --- Child access ---

    fun getChild(index: Int): JuceValueTree? = children.getOrNull(index)

    fun getChildWithType(type: String): JuceValueTree? = children.find { it.type == type }

    fun addChild(child: JuceValueTree, index: Int = -1) {
        if (index < 0 || index >= children.size) {
            children.add(child)
        } else {
            children.add(index, child)
        }
    }

    fun removeChild(index: Int): JuceValueTree? {
        return if (index in children.indices) children.removeAt(index) else null
    }

    fun removeChild(child: JuceValueTree): Boolean = children.remove(child)

    fun removeAllChildren() = children.clear()

    // --- Binary serialization (JUCE-compatible, LITTLE-ENDIAN) ---

    /**
     * Serialize to binary format compatible with JUCE's ValueTree::readFromData().
     */
    fun toByteArray(): ByteArray {
        val output = ByteArrayOutputStream()
        writeTo(output)
        return output.toByteArray()
    }

    /**
     * Write to an output stream in JUCE-compatible binary format.
     */
    fun writeTo(output: OutputStream) {
        // Type (null-terminated UTF-8 string)
        JuceIO.writeString(output, type)

        // Property count (compressed int)
        JuceIO.writeCompressedInt(output, properties.size)

        // Properties
        for ((name, value) in properties) {
            JuceIO.writeString(output, name)
            value.writeTo(output)
        }

        // Child count (compressed int)
        JuceIO.writeCompressedInt(output, children.size)

        // Children
        for (child in children) {
            child.writeTo(output)
        }
    }

    companion object {
        /**
         * Invalid/empty tree singleton.
         */
        val invalid = JuceValueTree("")

        /**
         * Deserialize from JUCE-compatible binary format.
         */
        fun fromByteArray(data: ByteArray): JuceValueTree {
            val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            return readFrom(buffer)
        }

        /**
         * Read from an input stream in JUCE-compatible binary format.
         */
        fun readFrom(input: InputStream): JuceValueTree {
            val data = input.readBytes()
            return fromByteArray(data)
        }

        private fun readFrom(buffer: ByteBuffer): JuceValueTree {
            // Type (null-terminated UTF-8 string)
            val type = JuceIO.readString(buffer)
            if (type.isEmpty()) return invalid

            val tree = JuceValueTree(type)

            // Property count (compressed int)
            val numProps = JuceIO.readCompressedInt(buffer)
            repeat(numProps) {
                val name = JuceIO.readString(buffer)
                val value = Var.readFrom(buffer)
                tree.properties[name] = value
            }

            // Child count (compressed int)
            val numChildren = JuceIO.readCompressedInt(buffer)
            repeat(numChildren) {
                tree.children.add(readFrom(buffer))
            }

            return tree
        }
    }

    override fun toString(): String = buildString {
        append("JuceValueTree($type) { ")
        if (properties.isNotEmpty()) {
            append("props: ")
            append(properties.entries.joinToString(", ") { "${it.key}=${it.value}" })
        }
        if (children.isNotEmpty()) {
            if (properties.isNotEmpty()) append(", ")
            append("children: ${children.size}")
        }
        append(" }")
    }
}

/**
 * Utility object for JUCE-compatible binary I/O.
 *
 * Implements JUCE's OutputStream/InputStream binary encoding:
 * - writeString: UTF-8 + null terminator
 * - writeCompressedInt: variable-length int encoding (1-5 bytes)
 * - All multi-byte integers: little-endian
 */
object JuceIO {
    /**
     * Write a null-terminated UTF-8 string (JUCE OutputStream::writeString).
     */
    fun writeString(output: OutputStream, s: String) {
        val bytes = s.toByteArray(Charsets.UTF_8)
        output.write(bytes)
        output.write(0)  // null terminator
    }

    /**
     * Read a null-terminated UTF-8 string (JUCE InputStream::readString).
     */
    fun readString(buffer: ByteBuffer): String {
        val bytes = mutableListOf<Byte>()
        while (buffer.hasRemaining()) {
            val b = buffer.get()
            if (b == 0.toByte()) break
            bytes.add(b)
        }
        return String(bytes.toByteArray(), Charsets.UTF_8)
    }

    /**
     * Write a compressed int (JUCE OutputStream::writeCompressedInt).
     *
     * Format: first byte = number of significant bytes (0-4), followed by
     * that many bytes in little-endian order.
     *
     * Note: JUCE supports negative numbers by using 4 bytes for any negative value.
     */
    fun writeCompressedInt(output: OutputStream, value: Int) {
        val unsigned = value.toUInt()
        val numBytes = when {
            value < 0 -> 4  // Negative numbers always use 4 bytes
            unsigned <= 0xFFu -> 1
            unsigned <= 0xFFFFu -> 2
            unsigned <= 0xFFFFFFu -> 3
            else -> 4
        }
        output.write(numBytes)
        for (i in 0 until numBytes) {
            output.write((value shr (i * 8)) and 0xFF)
        }
    }

    /**
     * Read a compressed int (JUCE InputStream::readCompressedInt).
     */
    fun readCompressedInt(buffer: ByteBuffer): Int {
        val numBytes = buffer.get().toInt() and 0xFF
        if (numBytes == 0) return 0
        var result = 0
        for (i in 0 until numBytes) {
            result = result or ((buffer.get().toInt() and 0xFF) shl (i * 8))
        }
        return result
    }

    /**
     * Write a little-endian 32-bit int.
     */
    fun writeInt(output: OutputStream, value: Int) {
        output.write(value and 0xFF)
        output.write((value shr 8) and 0xFF)
        output.write((value shr 16) and 0xFF)
        output.write((value shr 24) and 0xFF)
    }

    /**
     * Write a little-endian 64-bit long.
     */
    fun writeInt64(output: OutputStream, value: Long) {
        for (i in 0 until 8) {
            output.write(((value shr (i * 8)) and 0xFF).toInt())
        }
    }

    /**
     * Write a little-endian 64-bit double.
     */
    fun writeDouble(output: OutputStream, value: kotlin.Double) {
        writeInt64(output, java.lang.Double.doubleToRawLongBits(value))
    }
}

/**
 * Variant type matching JUCE's var with binary-compatible serialization.
 *
 * Supported types (matching JUCE's VariantStreamMarkers):
 * - varMarker_Int (1): 32-bit int
 * - varMarker_BoolTrue (2): boolean true
 * - varMarker_BoolFalse (3): boolean false
 * - varMarker_Double (4): 64-bit double
 * - varMarker_String (5): UTF-8 string + null terminator
 * - varMarker_Int64 (6): 64-bit int
 * - varMarker_Binary (8): raw bytes
 * - varMarker_Undefined (9): void/undefined
 *
 * ENDIANNESS: All multi-byte values use LITTLE-ENDIAN byte order.
 *
 * Binary format (JUCE var::writeToStream):
 * - writeCompressedInt(dataSize) + type marker byte + type-specific data
 */
sealed class Var {
    abstract fun writeTo(output: OutputStream)

    // --- Type accessors ---
    open fun toInt(): Int = 0
    open fun toLong(): Long = 0L
    open fun toDouble(): kotlin.Double = 0.0
    open fun toBool(): Boolean = false
    open fun toStr(): String = ""
    open fun toBinary(): ByteArray = ByteArray(0)

    /**
     * Void/undefined type.
     * JUCE format: writeCompressedInt(0) - indicates empty/void
     */
    object Void : Var() {
        override fun writeTo(output: OutputStream) {
            // JUCE writes compressedInt(0) for void
            JuceIO.writeCompressedInt(output, 0)
        }
        override fun toString() = "void"
    }

    /**
     * 32-bit integer.
     * JUCE format: writeCompressedInt(5) + varMarker_Int(1) + int32
     */
    data class IntVal(val value: Int) : Var() {
        override fun writeTo(output: OutputStream) {
            JuceIO.writeCompressedInt(output, 5)  // 1 byte marker + 4 bytes int
            output.write(VAR_MARKER_INT)
            JuceIO.writeInt(output, value)
        }
        override fun toInt() = value
        override fun toLong() = value.toLong()
        override fun toDouble() = value.toDouble()
        override fun toBool() = value != 0
        override fun toStr() = value.toString()
        override fun toString() = value.toString()
    }

    /**
     * 64-bit integer.
     * JUCE format: writeCompressedInt(9) + varMarker_Int64(6) + int64
     */
    data class Int64Val(val value: Long) : Var() {
        override fun writeTo(output: OutputStream) {
            JuceIO.writeCompressedInt(output, 9)  // 1 byte marker + 8 bytes long
            output.write(VAR_MARKER_INT64)
            JuceIO.writeInt64(output, value)
        }
        override fun toInt() = value.toInt()
        override fun toLong() = value
        override fun toDouble() = value.toDouble()
        override fun toBool() = value != 0L
        override fun toStr() = value.toString()
        override fun toString() = value.toString()
    }

    /**
     * Boolean.
     * JUCE format: writeCompressedInt(1) + varMarker_BoolTrue(2) or varMarker_BoolFalse(3)
     */
    data class BoolVal(val value: Boolean) : Var() {
        override fun writeTo(output: OutputStream) {
            JuceIO.writeCompressedInt(output, 1)  // 1 byte marker only
            output.write(if (value) VAR_MARKER_BOOL_TRUE else VAR_MARKER_BOOL_FALSE)
        }
        override fun toInt() = if (value) 1 else 0
        override fun toLong() = if (value) 1L else 0L
        override fun toDouble() = if (value) 1.0 else 0.0
        override fun toBool() = value
        override fun toStr() = value.toString()
        override fun toString() = value.toString()
    }

    /**
     * 64-bit double.
     * JUCE format: writeCompressedInt(9) + varMarker_Double(4) + double64
     */
    data class DoubleVal(val value: kotlin.Double) : Var() {
        override fun writeTo(output: OutputStream) {
            JuceIO.writeCompressedInt(output, 9)  // 1 byte marker + 8 bytes double
            output.write(VAR_MARKER_DOUBLE)
            JuceIO.writeDouble(output, value)
        }
        override fun toInt() = value.toInt()
        override fun toLong() = value.toLong()
        override fun toDouble() = value
        override fun toBool() = value != 0.0
        override fun toStr() = value.toString()
        override fun toString() = value.toString()
    }

    /**
     * String.
     * JUCE format: writeCompressedInt(len+2) + varMarker_String(5) + UTF-8 bytes + null terminator
     */
    data class StrVal(val value: String) : Var() {
        private val bytes = value.toByteArray(Charsets.UTF_8)
        override fun writeTo(output: OutputStream) {
            // Size = 1 (marker) + len (UTF-8 bytes) + 1 (null terminator)
            JuceIO.writeCompressedInt(output, 1 + bytes.size + 1)
            output.write(VAR_MARKER_STRING)
            output.write(bytes)
            output.write(0)  // null terminator
        }
        override fun toInt() = value.toIntOrNull() ?: 0
        override fun toLong() = value.toLongOrNull() ?: 0L
        override fun toDouble() = value.toDoubleOrNull() ?: 0.0
        override fun toBool() = value.isNotEmpty() && value != "0" && value.lowercase() != "false"
        override fun toStr() = value
        override fun toString() = "\"$value\""
    }

    /**
     * Binary data.
     * JUCE format: writeCompressedInt(1 + size) + varMarker_Binary(8) + raw bytes
     */
    data class BinaryVal(val value: ByteArray) : Var() {
        override fun writeTo(output: OutputStream) {
            JuceIO.writeCompressedInt(output, 1 + value.size)  // 1 byte marker + data
            output.write(VAR_MARKER_BINARY)
            output.write(value)
        }
        override fun toBinary() = value
        override fun toStr() = "Binary(${value.size} bytes)"
        override fun toString() = toStr()

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is BinaryVal) return false
            return value.contentEquals(other.value)
        }

        override fun hashCode() = value.contentHashCode()
    }

    companion object {
        // JUCE VariantStreamMarkers (from juce_Variant.cpp)
        private const val VAR_MARKER_INT = 1
        private const val VAR_MARKER_BOOL_TRUE = 2
        private const val VAR_MARKER_BOOL_FALSE = 3
        private const val VAR_MARKER_DOUBLE = 4
        private const val VAR_MARKER_STRING = 5
        private const val VAR_MARKER_INT64 = 6
        private const val VAR_MARKER_ARRAY = 7
        private const val VAR_MARKER_BINARY = 8
        private const val VAR_MARKER_UNDEFINED = 9

        /**
         * Read a Var from JUCE-compatible binary format.
         */
        fun readFrom(buffer: ByteBuffer): Var {
            val size = JuceIO.readCompressedInt(buffer)
            if (size == 0) return Void

            val marker = buffer.get().toInt() and 0xFF
            return when (marker) {
                VAR_MARKER_INT -> IntVal(buffer.getInt())
                VAR_MARKER_INT64 -> Int64Val(buffer.getLong())
                VAR_MARKER_BOOL_TRUE -> BoolVal(true)
                VAR_MARKER_BOOL_FALSE -> BoolVal(false)
                VAR_MARKER_DOUBLE -> DoubleVal(buffer.getDouble())
                VAR_MARKER_STRING -> {
                    // size includes marker (1) and null terminator (1)
                    val strLen = size - 2
                    val bytes = ByteArray(strLen)
                    if (strLen > 0) buffer.get(bytes)
                    buffer.get()  // consume null terminator
                    StrVal(String(bytes, Charsets.UTF_8))
                }
                VAR_MARKER_BINARY -> {
                    val dataLen = size - 1  // size includes marker
                    val bytes = ByteArray(dataLen)
                    if (dataLen > 0) buffer.get(bytes)
                    BinaryVal(bytes)
                }
                VAR_MARKER_UNDEFINED -> Void
                else -> {
                    // Unknown type - skip remaining bytes
                    val remaining = size - 1  // already read marker
                    if (remaining > 0) {
                        buffer.position(buffer.position() + remaining)
                    }
                    Void
                }
            }
        }
    }
}
