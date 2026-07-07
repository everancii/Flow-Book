package com.everancii.audiobookflow

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UpdateHelper(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> {
                try {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath != null) {
                        val installStatus = installApk(apkPath)
                        result.success(installStatus)
                    } else {
                        result.error("INVALID_PATH", "APK path is null", null)
                    }
                } catch (e: UpdateInstallException) {
                    result.error(e.code, e.message, null)
                } catch (e: Exception) {
                    result.error("INSTALL_ERROR", e.message, null)
                }
            }
            "canInstallApk" -> {
                try {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath != null) {
                        validateApkForInstall(apkPath)
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "APK path is null", null)
                    }
                } catch (e: UpdateInstallException) {
                    result.error(e.code, e.message, null)
                } catch (e: Exception) {
                    result.error("VALIDATION_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun installApk(apkPath: String): Map<String, Any> {
        val apkFile = validateApkForInstall(apkPath)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(settingsIntent)
            throw UpdateInstallException(
                "INSTALL_PERMISSION_REQUIRED",
                "Allow Flow Book to install updates, then try again."
            )
        }

        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.provider",
            apkFile
        )

        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)

        return mapOf("started" to true)
    }

    private fun validateApkForInstall(apkPath: String): File {
        val apkFile = File(apkPath)
        if (!apkFile.exists() || !apkFile.isFile) {
            throw UpdateInstallException("INVALID_PATH", "APK file does not exist: $apkPath")
        }
        if (!apkFile.canRead()) {
            throw UpdateInstallException("INVALID_PATH", "APK file cannot be read: $apkPath")
        }

        val archiveInfo = context.packageManager.getPackageArchiveInfo(apkPath, 0)
            ?: throw UpdateInstallException("INVALID_APK", "APK package information could not be read.")

        if (archiveInfo.packageName != context.packageName) {
            throw UpdateInstallException(
                "PACKAGE_MISMATCH",
                "APK package ${archiveInfo.packageName} does not match installed app ${context.packageName}."
            )
        }

        val installedInfo = getInstalledPackageInfo(context.packageName)
        if (installedInfo != null && archiveInfo.versionCodeLong() <= installedInfo.versionCodeLong()) {
            throw UpdateInstallException(
                "ALREADY_INSTALLED",
                "Flow Book ${installedInfo.versionName} is already installed. Download a newer APK before updating."
            )
        }

        return apkFile
    }

    private fun getInstalledPackageInfo(packageName: String): PackageInfo? {
        return try {
            context.packageManager.getPackageInfo(packageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun PackageInfo.versionCodeLong(): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            longVersionCode
        } else {
            @Suppress("DEPRECATION")
            versionCode.toLong()
        }
    }
}

private class UpdateInstallException(
    val code: String,
    override val message: String
) : Exception(message)
