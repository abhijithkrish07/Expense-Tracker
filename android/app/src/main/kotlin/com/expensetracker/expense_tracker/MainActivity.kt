package com.expensetracker.expense_tracker

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val storagePermissionChannel = "expense_tracker/storage_permission"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storagePermissionChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "requestManageExternalStorageIfNeeded") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                    !Environment.isExternalStorageManager()
                ) {
                    // Opens the system settings page for MANAGE_EXTERNAL_STORAGE.
                    val intent = Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName"),
                    )
                    startActivity(intent)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
