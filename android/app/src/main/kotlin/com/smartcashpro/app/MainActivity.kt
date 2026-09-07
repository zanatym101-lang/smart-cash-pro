package com.smartcashpro.app

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val smsChannelName = "com.smartcashpro.app/sms_inbox"
    private val integrityChannelName = "com.smartcashpro.app/app_integrity"
    private val readSmsRequestCode = 44021
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            smsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionStatus" -> result.success(permissionStatus())
                "requestPermission" -> handleRequestPermission(result)
                "fetchRecentMessages" -> handleFetchRecentMessages(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            integrityChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSignatureFingerprint" -> result.success(getSignatureFingerprint())
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != readSmsRequestCode) return
        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(if (granted) "granted" else "denied")
        pendingPermissionResult = null
    }

    private fun handleRequestPermission(result: MethodChannel.Result) {
        if (permissionStatus() == "granted") {
            result.success("granted")
            return
        }
        if (pendingPermissionResult != null) {
            result.success("denied")
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.READ_SMS), readSmsRequestCode)
    }

    private fun handleFetchRecentMessages(call: MethodCall, result: MethodChannel.Result) {
        if (permissionStatus() != "granted") {
            result.error("permission_denied", "READ_SMS not granted", null)
            return
        }

        val limit = call.argument<Int>("limit") ?: 100
        val uri = Uri.parse("content://sms/inbox")
        val projection = arrayOf("_id", "address", "body", "date")
        val rows = mutableListOf<Map<String, Any?>>()

        contentResolver.query(
            uri,
            projection,
            null,
            null,
            "date DESC"
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndex("_id")
            val addressIndex = cursor.getColumnIndex("address")
            val bodyIndex = cursor.getColumnIndex("body")
            val dateIndex = cursor.getColumnIndex("date")

            while (cursor.moveToNext() && rows.size < limit) {
                val id = if (idIndex >= 0) cursor.getLong(idIndex) else 0L
                val address = if (addressIndex >= 0) cursor.getString(addressIndex) else ""
                val body = if (bodyIndex >= 0) cursor.getString(bodyIndex) else ""
                val date = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                rows.add(
                    mapOf(
                        "id" to id.toString(),
                        "address" to address,
                        "sender" to address,
                        "body" to body,
                        "receivedAt" to date
                    )
                )
            }
        }

        result.success(rows)
    }

    private fun permissionStatus(): String {
        return if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            "granted"
        } else if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_SMS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            "granted"
        } else {
            "denied"
        }
    }
    private fun getSignatureFingerprint(): String? {
        return try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
                val signingInfo = packageInfo.signingInfo ?: return null
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }

            if (signatures.isNullOrEmpty()) return null

            val cert = signatures[0].toByteArray()
            val md = java.security.MessageDigest.getInstance("SHA-256")
            val digest = md.digest(cert)
            digest.joinToString(":") { String.format("%02X", it) }
        } catch (e: Exception) {
            null
        }
    }
}
