package com.example.impresion_termica

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pending: String? = null

    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private var socket: BluetoothSocket? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val r = block()
                main.post { result.success(r) }
            } catch (e: Exception) {
                main.post { result.error("BT", e.message ?: e.toString(), null) }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val ch = MethodChannel(messenger, "app/share")
        shareChannel = ch
        ch.setMethodCallHandler { call, result ->
            if (call.method == "getInitial") {
                result.success(pending); pending = null
            } else result.notImplemented()
        }

        MethodChannel(messenger, "app/bt").setMethodCallHandler { call, result ->
            when (call.method) {
                "paired" -> async(result) {
                    val ad = BluetoothAdapter.getDefaultAdapter()
                        ?: throw Exception("Sin Bluetooth")
                    ad.bondedDevices.map {
                        mapOf("name" to (it.name ?: it.address), "mac" to it.address)
                    }
                }
                "isConnected" -> result.success(socket?.isConnected == true)
                "connect" -> {
                    val mac = call.argument<String>("mac")!!
                    async(result) {
                        val ad = BluetoothAdapter.getDefaultAdapter()
                            ?: throw Exception("Sin Bluetooth")
                        try { socket?.close() } catch (_: Exception) {}
                        ad.cancelDiscovery()
                        val s = ad.getRemoteDevice(mac).createRfcommSocketToServiceRecord(sppUuid)
                        s.connect()
                        socket = s
                        true
                    }
                }
                "write" -> {
                    val data = call.argument<ByteArray>("data")!!
                    async(result) {
                        val s = socket ?: throw Exception("No conectado")
                        s.outputStream.write(data)
                        s.outputStream.flush()
                        true
                    }
                }
                "disconnect" -> async(result) {
                    try { socket?.close() } catch (_: Exception) {}
                    socket = null
                    true
                }
                else -> result.notImplemented()
            }
        }
        handle(intent, false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent, true)
    }

    @Suppress("DEPRECATION")
    private fun handle(intent: Intent?, live: Boolean) {
        if (intent == null) return
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            else -> null
        } ?: return
        try {
            var name = "shared_file"
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (i >= 0 && c.moveToFirst()) name = c.getString(i)
            }
            if (!name.contains('.')) {
                val t = contentResolver.getType(uri) ?: ""
                name += when {
                    t.contains("pdf") -> ".pdf"
                    t.contains("zip") -> ".zip"
                    else -> ".xml"
                }
            }
            val out = File(cacheDir, "shared_" + name.replace(Regex("[^A-Za-z0-9._-]"), "_"))
            contentResolver.openInputStream(uri)?.use { i -> out.outputStream().use { o -> i.copyTo(o) } }
            if (live) shareChannel?.invokeMethod("onFile", out.absolutePath) else pending = out.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
