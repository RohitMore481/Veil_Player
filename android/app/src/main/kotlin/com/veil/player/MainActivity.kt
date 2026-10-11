package com.veil.player

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Size
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.provider.Settings
import java.io.File
import java.io.FileOutputStream
import java.util.LinkedHashSet
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        var activeChannel: MethodChannel? = null
            private set

        fun sendMediaCommand(method: String, args: Any?) {
            activeChannel?.let { ch ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try {
                        ch.invokeMethod(method, args)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
    }

    private val CHANNEL = "veil_player/media"
    private val PERMISSION_REQUEST_CODE = 4567
    private var mediaSession: MediaSession? = null
    private var channel: MethodChannel? = null
    private val NOTIFICATION_ID = 101
    private val CHANNEL_ID = "veil_player_channel"
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var originalInterruptionFilter: Int? = null
    private val PICK_SUBTITLE_REQUEST_CODE = 4568
    private val SETTINGS_REQUEST_CODE = 4573
    private var permissionResult: MethodChannel.Result? = null
    private var pendingSettingsResult: MethodChannel.Result? = null
    private var subtitleResult: MethodChannel.Result? = null
    private val AUDIO_PERMISSION_REQUEST_CODE = 4574
    private var audioPermissionResult: MethodChannel.Result? = null
    private var isPipEnabled = false
    private var pipAspectRatioNumerator = 16
    private var pipAspectRatioDenominator = 9

    // Transaction tables for thread-safe asynchronous results
    private val pendingDeleteResults = HashMap<Int, MethodChannel.Result>()
    private val pendingDeleteFolderPaths = HashMap<Int, String>()
    private var nextRequestCode = 10000

    private data class PendingRenameAction(
        val videoId: String,
        val oldPath: String,
        val newName: String,
        val result: MethodChannel.Result
    )
    private val pendingRenameActions = HashMap<Int, PendingRenameAction>()
    private val pendingWriteResults = HashMap<Int, MethodChannel.Result>()

    private fun getNextRequestCode(): Int {
        synchronized(this) {
            val code = nextRequestCode++
            if (nextRequestCode > 20000) {
                nextRequestCode = 10000
            }
            return code
        }
    }

    private data class FolderInfo(
        val name: String,
        val path: String,
        var count: Int,
        var newVideosCount: Int,
        var containsMovies: Boolean,
        var shortClipsCount: Int
    )

    private data class AudioFolderInfo(
        val name: String,
        val path: String,
        var count: Int,
        var totalDuration: Long,
        var totalSize: Long
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Install safe native uncaught exception handler preserving system crash semantics
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val crashMarkerFile = File(filesDir, "native_crash_marker.txt")
                crashMarkerFile.writeText("NATIVE_CRASH:${System.currentTimeMillis()}:${throwable.javaClass.simpleName}")
            } catch (_: Exception) {}
            defaultHandler?.uncaughtException(thread, throwable)
        }

        // Request high refresh rate (120Hz)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val lp = window.attributes
            lp.preferredRefreshRate = 120.0f
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val display = display
                if (display != null) {
                    val maxRefreshRateMode = display.supportedModes.maxByOrNull { it.refreshRate }
                    if (maxRefreshRateMode != null) {
                        lp.preferredDisplayModeId = maxRefreshRateMode.modeId
                    }
                }
            }
            window.attributes = lp
        }

        // Trim thumbnail cache on startup
        thread {
            trimThumbnailCache()
        }

        // Register BroadcastReceiver for notification controls
        val filter = IntentFilter().apply {
            addAction("action_prev")
            addAction("action_play_pause")
            addAction("action_next")
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(notificationReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(notificationReceiver, filter)
        }

        // Initialize MediaSession for Media Output Switcher compatibility
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                mediaSession = MediaSession(this, "VeilPlayerMediaSession").apply {
                    setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
                    setCallback(mediaSessionCallback)
                    val state = PlaybackState.Builder()
                        .setActions(
                            PlaybackState.ACTION_PLAY or
                            PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_PLAY_PAUSE or
                            PlaybackState.ACTION_SKIP_TO_NEXT or
                            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                            PlaybackState.ACTION_SEEK_TO
                        )
                        .setState(PlaybackState.STATE_STOPPED, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 0.0f)
                        .build()
                    setPlaybackState(state)
                    isActive = false
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val mChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = mChannel
        activeChannel = mChannel
        mChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(getPermissionStatus())
                }
                "requestPermission" -> {
                    requestPermissions(result)
                }
                "needsSystemConfirmationForWrite" -> {
                    result.success(needsSystemConfirmationForWrite())
                }
                "isStorageManager" -> {
                    result.success(isExternalStorageManager())
                }
                "requestManageStoragePermission" -> {
                    requestManageStoragePermission(result)
                }
                "hasSafPermission" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(hasSafPermissionForPath(path))
                }
                "requestSafPermission" -> {
                    val path = call.argument<String>("path") ?: ""
                    requestSafPermission(path, result)
                }
                "openSettings" -> {
                    openSettings(result)
                }
                "getVideos" -> {
                    val limit = call.argument<Int>("limit") ?: 50
                    val offset = call.argument<Int>("offset") ?: 0
                    val folderName = call.argument<String>("folderName")
                    val folderPath = call.argument<String>("folderPath")
                    getVideos(limit, offset, folderName, folderPath, result)
                }
                "getFolders" -> {
                    getFolders(result)
                }
                "checkAudioPermission" -> {
                    result.success(getAudioPermissionStatus())
                }
                "requestAudioPermission" -> {
                    requestAudioPermissions(result)
                }
                "getAudioTracks" -> {
                    val limit = call.argument<Int>("limit") ?: 50
                    val offset = call.argument<Int>("offset") ?: 0
                    val folderName = call.argument<String>("folderName")
                    val folderPath = call.argument<String>("folderPath")
                    getAudioTracks(limit, offset, folderName, folderPath, result)
                }
                "getAudioFolders" -> {
                    getAudioFolders(result)
                }
                "renameAudio" -> {
                    val id = call.argument<String>("id")
                    val path = call.argument<String>("path") ?: ""
                    val newName = call.argument<String>("newName") ?: ""
                    if (id != null && path.isNotEmpty() && newName.isNotEmpty()) {
                        renameAudio(id, path, newName, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "id, path, and newName are required", null)
                    }
                }
                "deleteAudio" -> {
                    val id = call.argument<String>("id")
                    val path = call.argument<String>("path") ?: ""
                    if (id != null && path.isNotEmpty()) {
                        deleteAudio(id, path, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "id and path are required", null)
                    }
                }
                "copyAudio" -> {
                    val path = call.argument<String>("path") ?: ""
                    val targetFolder = call.argument<String>("targetFolder") ?: ""
                    if (path.isNotEmpty() && targetFolder.isNotEmpty()) {
                        copyVideo(path, targetFolder, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path and targetFolder are required", null)
                    }
                }
                "moveAudio" -> {
                    val id = call.argument<String>("id") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    val targetFolder = call.argument<String>("targetFolder") ?: ""
                    if (path.isNotEmpty() && targetFolder.isNotEmpty()) {
                        moveAudio(id, path, targetFolder, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path and targetFolder are required", null)
                    }
                }
                "renameVideo" -> {
                    val id = call.argument<String>("id")
                    val path = call.argument<String>("path") ?: ""
                    val newName = call.argument<String>("newName") ?: ""
                    if (id != null && path.isNotEmpty() && newName.isNotEmpty()) {
                        renameVideo(id, path, newName, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "id, path, and newName are required", null)
                    }
                }
                "deleteVideo" -> {
                    val id = call.argument<String>("id")
                    val path = call.argument<String>("path") ?: ""
                    if (id != null && path.isNotEmpty()) {
                        deleteVideo(id, path, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "id and path are required", null)
                    }
                }
                "deleteVideosBatch" -> {
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    if (ids.isNotEmpty() && paths.isNotEmpty() && ids.size == paths.size) {
                        deleteVideosBatch(ids, paths, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "ids and paths are required and must be of same length", null)
                    }
                }
                "copyVideo" -> {
                    val path = call.argument<String>("path") ?: ""
                    val targetFolder = call.argument<String>("targetFolder") ?: ""
                    if (path.isNotEmpty() && targetFolder.isNotEmpty()) {
                        copyVideo(path, targetFolder, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path and targetFolder are required", null)
                    }
                }
                "moveVideo" -> {
                    val id = call.argument<String>("id") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    val targetFolder = call.argument<String>("targetFolder") ?: ""
                    if (id.isNotEmpty() && path.isNotEmpty() && targetFolder.isNotEmpty()) {
                        moveVideo(id, path, targetFolder, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "id, path, and targetFolder are required", null)
                    }
                }
                "copyVideosBatch" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val targetFolder = call.argument<String>("targetFolder") ?: ""
                    if (paths.isNotEmpty() && targetFolder.isNotEmpty()) {
                        copyVideosBatch(paths, targetFolder, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "paths and targetFolder are required", null)
                    }
                }
                "moveVideosBatch" -> {
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val targetFolder = call.argument<String>("targetFolder") ?: ""
                    if (ids.isNotEmpty() && paths.isNotEmpty() && targetFolder.isNotEmpty()) {
                        moveVideosBatch(ids, paths, targetFolder, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "ids, paths, and targetFolder are required", null)
                    }
                }
                "renameFolder" -> {
                    val path = call.argument<String>("path") ?: ""
                    val newName = call.argument<String>("newName") ?: ""
                    if (path.isNotEmpty() && newName.isNotEmpty()) {
                        renameFolder(path, newName, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path and newName are required", null)
                    }
                }
                "deleteFolder" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isNotEmpty()) {
                        deleteFolder(path, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path is required", null)
                    }
                }
                "hideFolder" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isNotEmpty()) {
                        hideFolder(path, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path is required", null)
                    }
                }
                "refreshFolder" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isNotEmpty()) {
                        refreshFolder(path, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path is required", null)
                    }
                }
                "shareVideo" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isNotEmpty()) {
                        shareVideo(path, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "path is required", null)
                    }
                }
                "clearThumbnailCache" -> {
                    clearThumbnailCache(result)
                }
                "generateThumbnail" -> {
                    val idStr = call.argument<String>("id")
                    val path = call.argument<String>("path")
                    if (idStr != null && path != null) {
                        val id = idStr.toLongOrNull()
                        if (id != null) {
                            generateThumbnail(id, path, result)
                        } else {
                            result.error("INVALID_ID", "Video ID is not a long integer", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "ID and path are required", null)
                    }
                }
                "savePlaybackPosition" -> {
                    val id = call.argument<String>("id")
                    val position = call.argument<Number>("position")?.toLong()
                    val duration = call.argument<Number>("duration")?.toLong()
                    val title = call.argument<String>("title") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    if (id != null && position != null && duration != null) {
                        savePlaybackPosition(id, position, duration, title, path, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "ID, position and duration are required", null)
                    }
                }
                "getPlaybackPosition" -> {
                    val id = call.argument<String>("id")
                    if (id != null) {
                        getPlaybackPosition(id, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "ID is required", null)
                    }
                }
                "getAllPlaybackPositions" -> {
                    getAllPlaybackPositions(result)
                }
                "clearPlaybackPosition" -> {
                    val id = call.argument<String>("id")
                    if (id != null) {
                        clearPlaybackPosition(id, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "ID is required", null)
                    }
                }
                "getVolume" -> {
                    getVolume(result)
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")
                    setVolume(volume, result)
                }
                "getBrightness" -> {
                    getBrightness(result)
                }
                "setBrightness" -> {
                    val brightness = call.argument<Double>("brightness")
                    setBrightness(brightness, result)
                }
                "getVideoMetadata" -> {
                    val path = call.argument<String>("path")
                    getVideoMetadata(path, result)
                }
                "savePlayerSetting" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<Any>("value")
                    if (key != null && value != null) {
                        savePlayerSetting(key, value, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Key and value are required", null)
                    }
                }
                "getPlayerSetting" -> {
                    val key = call.argument<String>("key")
                    val type = call.argument<String>("type")
                    if (key != null && type != null) {
                        getPlayerSetting(key, type, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Key and type are required", null)
                    }
                }
                "getAllPlayerSettings" -> {
                    getAllPlayerSettings(result)
                }
                "setPipEnabled" -> {
                    isPipEnabled = call.argument<Boolean>("enabled") ?: false
                    pipAspectRatioNumerator = call.argument<Int>("numerator") ?: 16
                    pipAspectRatioDenominator = call.argument<Int>("denominator") ?: 9
                    result.success(true)
                }
                "enterPip" -> {
                    val success = enterPipMode()
                    result.success(success)
                }
                "saveScreenshotToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val title = call.argument<String>("title") ?: ""
                    if (bytes != null) {
                        saveScreenshotToGallery(bytes, title, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Bytes are required", null)
                    }
                }
                "openScreenshotFolder" -> {
                    openScreenshotFolder(result)
                }
                "searchVideos" -> {
                    val query = call.argument<String>("query") ?: ""
                    val limit = call.argument<Int>("limit") ?: 100
                    searchVideos(query, limit, result)
                }
                "pickSubtitleFile" -> {
                    pickSubtitleFile(result)
                }
                "requestAudioFocus" -> {
                    result.success(requestAudioFocus())
                }
                "abandonAudioFocus" -> {
                    abandonAudioFocus()
                    result.success(true)
                }
                "updateActiveMediaSession" -> {
                    val title = call.argument<String>("title") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val position = call.argument<Number>("position")?.toLong() ?: 0L
                    val duration = call.argument<Number>("duration")?.toLong() ?: 0L
                    updateActiveMediaSession(title, isPlaying, position, duration)
                    result.success(true)
                }
                "startAudioService", "updateAudioService" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val position = call.argument<Number>("position")?.toLong() ?: 0L
                    val duration = call.argument<Number>("duration")?.toLong() ?: 0L

                    val intent = Intent(this, VeilAudioService::class.java).apply {
                        action = VeilAudioService.ACTION_UPDATE
                        putExtra(VeilAudioService.EXTRA_TITLE, title)
                        putExtra(VeilAudioService.EXTRA_ARTIST, artist)
                        putExtra(VeilAudioService.EXTRA_IS_PLAYING, isPlaying)
                        putExtra(VeilAudioService.EXTRA_POSITION, position)
                        putExtra(VeilAudioService.EXTRA_DURATION, duration)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopAudioService" -> {
                    val intent = Intent(this, VeilAudioService::class.java).apply {
                        action = VeilAudioService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "getNativeCrashMarker" -> {
                    val file = File(filesDir, "native_crash_marker.txt")
                    if (file.exists()) {
                        result.success(file.readText())
                    } else {
                        result.success(null)
                    }
                }
                "clearNativeCrashMarker" -> {
                    val file = File(filesDir, "native_crash_marker.txt")
                    if (file.exists()) {
                        file.delete()
                    }
                    result.success(true)
                }
                "isNotificationPolicyAccessGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(notificationManager.isNotificationPolicyAccessGranted)
                    } else {
                        result.success(true)
                    }
                }
                "openNotificationPolicySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "setFocusModeEnabled" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    setFocusModeEnabled(enable)
                    result.success(true)
                }
                "saveCrashLog" -> {
                    val log = call.argument<String>("log") ?: ""
                    saveCrashLog(log, result)
                }
                "getAppPrivateDirectory" -> {
                    result.success(filesDir.absolutePath)
                }
                "getDeviceInfo" -> {
                    getDeviceInfo(result)
                }
                "shareReportFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val title = call.argument<String>("title") ?: "Share Diagnostic Report"
                    shareReportFile(path, title, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getPermissionStatus(): String {
        val context = this
        val sharedPrefs = getSharedPreferences("veil_player_prefs", Context.MODE_PRIVATE)
        val hasRequested = sharedPrefs.getBoolean("has_requested_permissions", false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && android.os.Environment.isExternalStorageManager()) {
            return "granted"
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) { // Android 14+
            val hasVideo = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
            val hasSelected = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED

            when {
                hasVideo -> "granted"
                hasSelected -> "partial"
                else -> {
                    val shouldShowVideo = ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_MEDIA_VIDEO)
                    val shouldShowSelected = ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                    if (!shouldShowVideo && !shouldShowSelected && hasRequested) {
                        "permanently_denied"
                    } else {
                        "denied"
                    }
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // Android 13
            val hasVideo = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
            when {
                hasVideo -> "granted"
                else -> {
                    if (!ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_MEDIA_VIDEO) && hasRequested) {
                        "permanently_denied"
                    } else {
                        "denied"
                    }
                }
            }
        } else { // Android 12 and below
            val hasStorage = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
            when {
                hasStorage -> "granted"
                else -> {
                    if (!ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_EXTERNAL_STORAGE) && hasRequested) {
                        "permanently_denied"
                    } else {
                        "denied"
                    }
                }
            }
        }
    }

    private fun needsSystemConfirmationForWrite(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return !android.os.Environment.isExternalStorageManager()
        }
        if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
            val hasWrite = ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
            return !hasWrite
        }
        return true
    }

    private fun isExternalStorageManager(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            android.os.Environment.isExternalStorageManager()
        } else {
            true // On older Android, direct file access is always allowed
        }
    }

    private val MANAGE_STORAGE_REQUEST_CODE = 4572
    private var pendingManageStorageResult: MethodChannel.Result? = null

    private fun requestManageStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (android.os.Environment.isExternalStorageManager()) {
                result.success(true)
                return
            }
            pendingManageStorageResult = result
            try {
                val intent = Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
                startActivityForResult(intent, MANAGE_STORAGE_REQUEST_CODE)
            } catch (e: Exception) {
                // Fallback to the general manage all files settings
                try {
                    val intent = Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    startActivityForResult(intent, MANAGE_STORAGE_REQUEST_CODE)
                } catch (ex: Exception) {
                    pendingManageStorageResult = null
                    result.success(false)
                }
            }
        } else {
            result.success(true) // Not needed on older Android
        }
    }

    private fun scanFiles(paths: Array<String>, callback: (() -> Unit)? = null) {
        if (paths.isEmpty()) {
            callback?.invoke()
            return
        }
        var completed = 0
        var callbackCalled = false

        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val runnable = Runnable {
            if (!callbackCalled) {
                callbackCalled = true
                callback?.invoke()
            }
        }
        handler.postDelayed(runnable, 2000)

        android.media.MediaScannerConnection.scanFile(
            this,
            paths,
            null
        ) { path, uri ->
            completed++
            if (completed >= paths.size) {
                handler.removeCallbacks(runnable)
                if (!callbackCalled) {
                    callbackCalled = true
                    callback?.invoke()
                }
            }
        }
    }

    private val SAF_TREE_REQUEST_CODE = 4571
    private var pendingPermissionResult: MethodChannel.Result? = null

    private fun getPhysicalPathFromTreeUri(treeUri: Uri): String? {
        if (treeUri.authority != "com.android.externalstorage.documents") {
            return null
        }
        val docId = android.provider.DocumentsContract.getTreeDocumentId(treeUri) ?: return null
        val parts = docId.split(":")
        if (parts.isNotEmpty()) {
            val volumeId = parts[0]
            val relativePath = if (parts.size > 1) parts[1] else ""
            return if (volumeId == "primary") {
                val primaryRoot = android.os.Environment.getExternalStorageDirectory().absolutePath
                if (relativePath.isEmpty()) primaryRoot else "$primaryRoot/$relativePath"
            } else {
                val sdRoot = "/storage/$volumeId"
                if (relativePath.isEmpty()) sdRoot else "$sdRoot/$relativePath"
            }
        }
        return null
    }

    private fun getDocumentIdForPath(path: String): String? {
        val primaryRoot = android.os.Environment.getExternalStorageDirectory().absolutePath
        if (path.startsWith(primaryRoot)) {
            val relative = path.substring(primaryRoot.length).removePrefix("/")
            return "primary:$relative"
        }
        val pathParts = path.split("/")
        if (pathParts.size >= 3 && pathParts[1] == "storage") {
            val volumeId = pathParts[2]
            if (volumeId != "emulated" && volumeId != "self") {
                val sdRoot = "/storage/$volumeId"
                if (path.startsWith(sdRoot)) {
                    val relative = path.substring(sdRoot.length).removePrefix("/")
                    return "$volumeId:$relative"
                }
            }
        }
        return null
    }

    private fun getDocumentUriForPath(path: String): Uri? {
        val sharedPrefs = getSharedPreferences("veil_saf_prefs", Context.MODE_PRIVATE)
        val allPrefs = sharedPrefs.all
        val persistedUris = contentResolver.persistedUriPermissions.map { it.uri.toString() }
        for ((treeUriStr, savedPathStr) in allPrefs) {
            val savedPath = savedPathStr as? String ?: continue
            if (persistedUris.contains(treeUriStr) && path.startsWith(savedPath)) {
                val treeUri = Uri.parse(treeUriStr)
                val docId = getDocumentIdForPath(path) ?: continue
                return android.provider.DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
            }
        }
        return null
    }

    private fun hasSafPermissionForPath(path: String): Boolean {
        return getDocumentUriForPath(path) != null
    }

    private fun deleteDocFile(documentUri: Uri): Boolean {
        return try {
            android.provider.DocumentsContract.deleteDocument(contentResolver, documentUri)
        } catch (e: Exception) {
            false
        }
    }

    private fun renameDocFile(documentUri: Uri, newName: String): Uri? {
        return try {
            android.provider.DocumentsContract.renameDocument(contentResolver, documentUri, newName)
        } catch (e: Exception) {
            null
        }
    }

    private fun requestSafPermission(path: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            pendingPermissionResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val docId = getDocumentIdForPath(path)
                    if (docId != null) {
                        val documentUri = android.provider.DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", docId)
                        putExtra(android.provider.DocumentsContract.EXTRA_INITIAL_URI, documentUri)
                    }
                }
            }
            runOnUiThread {
                try {
                    startActivityForResult(intent, SAF_TREE_REQUEST_CODE)
                } catch (e: Exception) {
                    pendingPermissionResult = null
                    result.error("SAF_REQUEST_FAILED", e.message, null)
                }
            }
        } else {
            result.success(true)
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("ALREADY_REQUESTING", "Permission request already in progress", null)
            return
        }
        permissionResult = result

        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                Manifest.permission.POST_NOTIFICATIONS
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.POST_NOTIFICATIONS
            )
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        ActivityCompat.requestPermissions(this, permissions, PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val sharedPrefs = getSharedPreferences("veil_player_prefs", Context.MODE_PRIVATE)
            sharedPrefs.edit()
                .putBoolean("has_requested_permissions", true)
                .putBoolean("has_requested_audio_permissions", true)
                .apply()

            val status = getPermissionStatus()
            permissionResult?.success(status)
            permissionResult = null
        } else if (requestCode == AUDIO_PERMISSION_REQUEST_CODE) {
            val sharedPrefs = getSharedPreferences("veil_player_prefs", Context.MODE_PRIVATE)
            sharedPrefs.edit().putBoolean("has_requested_audio_permissions", true).apply()

            val status = getAudioPermissionStatus()
            audioPermissionResult?.success(status)
            audioPermissionResult = null
        }
    }

    private fun getAudioPermissionStatus(): String {
        val context = this
        val sharedPrefs = getSharedPreferences("veil_player_prefs", Context.MODE_PRIVATE)
        val hasRequested = sharedPrefs.getBoolean("has_requested_audio_permissions", false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && android.os.Environment.isExternalStorageManager()) {
            return "granted"
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) { // Android 14+
            val hasAudio = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED
            when {
                hasAudio -> "granted"
                else -> {
                    val shouldShowAudio = ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_MEDIA_AUDIO)
                    if (!shouldShowAudio && hasRequested) {
                        "permanently_denied"
                    } else {
                        "denied"
                    }
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // Android 13
            val hasAudio = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED
            when {
                hasAudio -> "granted"
                else -> {
                    if (!ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_MEDIA_AUDIO) && hasRequested) {
                        "permanently_denied"
                    } else {
                        "denied"
                    }
                }
            }
        } else { // Android 12 and below
            val hasStorage = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
            when {
                hasStorage -> "granted"
                else -> {
                    if (!ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_EXTERNAL_STORAGE) && hasRequested) {
                        "permanently_denied"
                    } else {
                        "denied"
                    }
                }
            }
        }
    }

    private fun requestAudioPermissions(result: MethodChannel.Result) {
        if (audioPermissionResult != null) {
            result.error("ALREADY_REQUESTING", "Audio permission request already in progress", null)
            return
        }
        audioPermissionResult = result

        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        ActivityCompat.requestPermissions(this, permissions, AUDIO_PERMISSION_REQUEST_CODE)
    }

    private fun openSettings(result: MethodChannel.Result) {
        if (pendingSettingsResult != null) {
            val old = pendingSettingsResult
            pendingSettingsResult = null
            try { old?.success(true) } catch (_: Exception) {}
        }
        pendingSettingsResult = result
        try {
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
            startActivityForResult(intent, SETTINGS_REQUEST_CODE)
        } catch (e: Exception) {
            pendingSettingsResult = null
            result.error("OPEN_SETTINGS_FAILED", e.message, null)
        }
    }

    private fun getVideos(limit: Int, offset: Int, folderName: String?, folderPath: String?, result: MethodChannel.Result) {
        thread {
            try {
                val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
                val watchedIds = prefs.getStringSet("watched_ids", emptySet()) ?: emptySet()

                val videoList = ArrayList<Map<String, Any?>>()
                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI

                val projection = arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                    MediaStore.Video.Media.DATE_ADDED,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Video.Media.BUCKET_DISPLAY_NAME
                    } else {
                        "bucket_display_name"
                    }
                )

                var selection: String? = null
                var selectionArgs: Array<String>? = null
                var canonicalFolder: String? = null
                if (folderPath != null) {
                    try {
                        canonicalFolder = File(folderPath).canonicalPath
                    } catch (e: Exception) {
                        canonicalFolder = folderPath
                    }
                    val fName = File(folderPath).name
                    if (fName.isNotEmpty()) {
                        selection = "${MediaStore.Video.Media.DATA} LIKE ?"
                        selectionArgs = arrayOf("%/$fName/%")
                    }
                } else if (folderName != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        selection = "${MediaStore.Video.Media.BUCKET_DISPLAY_NAME} LIKE ?"
                        selectionArgs = arrayOf(folderName)
                    } else {
                        selection = "${MediaStore.Video.Media.DATA} LIKE ?"
                        selectionArgs = arrayOf("%/$folderName/%")
                    }
                }

                val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val queryArgs = Bundle().apply {
                        putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                        putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
                        if (folderPath != null || folderName != null) {
                            putStringArray(
                                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                                arrayOf(MediaStore.Video.Media.DISPLAY_NAME)
                            )
                            putInt(
                                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                                ContentResolver.QUERY_SORT_DIRECTION_ASCENDING
                            )
                        } else {
                            putStringArray(
                                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                                arrayOf(MediaStore.Video.Media.DATE_ADDED)
                            )
                            putInt(
                                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                                ContentResolver.QUERY_SORT_DIRECTION_DESCENDING
                            )
                        }
                        if (selection != null) {
                            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                        }
                    }
                    contentResolver.query(uri, projection, queryArgs, null)
                } else {
                    val sortOrder = if (folderPath != null || folderName != null) {
                        "${MediaStore.Video.Media.DISPLAY_NAME} ASC LIMIT $limit OFFSET $offset"
                    } else {
                        "${MediaStore.Video.Media.DATE_ADDED} DESC LIMIT $limit OFFSET $offset"
                    }
                    contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
                }

                cursor?.use {
                    val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                    val nameCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                    val pathCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                    val durationCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                    val sizeCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                    val dateCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                    val bucketCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        it.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                    } else {
                        it.getColumnIndex("bucket_display_name")
                    }

                    while (it.moveToNext()) {
                        val id = it.getLong(idCol)
                        val title = it.getString(nameCol) ?: ""
                        val path = it.getString(pathCol) ?: ""
                        val duration = it.getLong(durationCol)
                        val size = it.getLong(sizeCol)
                        val dateAdded = it.getLong(dateCol)

                        var folder = ""
                        if (bucketCol != -1) {
                            folder = it.getString(bucketCol) ?: ""
                        }
                        if (folder.isEmpty() && path.isNotEmpty()) {
                            try {
                                val file = File(path)
                                folder = file.parentFile?.name ?: ""
                            } catch (e: Exception) {
                                // ignore
                            }
                        }

                        // Filter by exact parent path if folderPath is specified
                        if (canonicalFolder != null && path.isNotEmpty()) {
                            val normFolder = canonicalFolder.replace("\\", "/").lowercase()
                            try {
                                val parentCanonical = File(path).parentFile?.canonicalPath ?: ""
                                val normParent = parentCanonical.replace("\\", "/").lowercase()
                                if (normParent != normFolder) {
                                    continue
                                }
                            } catch (e: Exception) {
                                val parentAbsolute = File(path).parentFile?.absolutePath ?: ""
                                val normParent = parentAbsolute.replace("\\", "/").lowercase()
                                val normFolderPath = (folderPath ?: "").replace("\\", "/").lowercase()
                                if (normParent != normFolderPath) {
                                    continue
                                }
                            }
                        }
                        if (folder.isEmpty()) {
                            folder = "Storage"
                        }

                        val videoItem = HashMap<String, Any?>()
                        videoItem["id"] = id.toString()
                        videoItem["title"] = title
                        videoItem["path"] = path
                        videoItem["duration"] = duration
                        videoItem["size"] = size
                        videoItem["dateAdded"] = dateAdded
                        videoItem["folderName"] = folder
                        videoItem["isWatched"] = watchedIds.contains(id.toString())

                        videoList.add(videoItem)
                    }
                }

                runOnUiThread {
                    result.success(videoList)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("QUERY_FAILED", e.message, null)
                }
            }
        }
    }

    private fun getFolders(result: MethodChannel.Result) {
        thread {
            try {
                val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
                val watchedIds = prefs.getStringSet("watched_ids", emptySet()) ?: emptySet()

                val foldersMap = LinkedHashMap<String, FolderInfo>()
                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                val projection = arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DURATION,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Video.Media.BUCKET_DISPLAY_NAME
                    } else {
                        "bucket_display_name"
                    }
                )

                val cursor = contentResolver.query(uri, projection, null, null, null)
                cursor?.use {
                    val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                    val pathCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                    val durationCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                    val bucketCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        it.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                    } else {
                        it.getColumnIndex("bucket_display_name")
                    }

                    while (it.moveToNext()) {
                        val idStr = it.getLong(idCol).toString()
                        val isWatched = watchedIds.contains(idStr)
                        val path = it.getString(pathCol) ?: ""
                        val duration = it.getLong(durationCol)
                        if (path.isEmpty()) continue

                        val file = File(path)
                        val parentFile = file.parentFile
                        val folderPath = parentFile?.absolutePath ?: ""
                        if (folderPath.isEmpty()) continue

                        var folderName = ""
                        if (bucketCol != -1) {
                            folderName = it.getString(bucketCol) ?: ""
                        }
                        if (folderName.isEmpty()) {
                            folderName = parentFile.name ?: ""
                        }
                        if (folderName.isEmpty()) {
                            folderName = "Storage"
                        }

                        val nameLower = folderName.lowercase()
                        val pathLower = folderPath.lowercase()
                        
                        // Ignore hidden folders, cache, temp, thumbnail, android/data, gif, sticker
                        if (nameLower.startsWith(".") || pathLower.contains("/.") || 
                            nameLower.contains("cache") || pathLower.contains("/cache/") ||
                            nameLower.contains("temp") || pathLower.contains("/temp/") ||
                            nameLower.contains("thumbnail") || pathLower.contains("/thumbnail/") ||
                            pathLower.contains("/android/data/") ||
                            nameLower.contains("gif") || pathLower.contains("/gif/") ||
                            nameLower.contains("sticker") || pathLower.contains("/sticker/")) {
                            continue
                        }

                        val isMovieName = nameLower.contains("movie") || nameLower.contains("film") || nameLower.contains("cinema")
                        val isLongVideo = duration > 60 * 60 * 1000 // > 60 minutes
                        val isShortClip = duration > 0 && duration < 3500 // less than 3.5 seconds

                        val existing = foldersMap[folderPath]
                        if (existing == null) {
                            foldersMap[folderPath] = FolderInfo(
                                name = folderName,
                                path = folderPath,
                                count = 1,
                                newVideosCount = if (isWatched) 0 else 1,
                                containsMovies = isMovieName || isLongVideo,
                                shortClipsCount = if (isShortClip) 1 else 0
                            )
                        } else {
                            existing.count += 1
                            if (!isWatched) {
                                existing.newVideosCount += 1
                            }
                            if (isMovieName || isLongVideo) {
                                existing.containsMovies = true
                            }
                            if (isShortClip) {
                                existing.shortClipsCount += 1
                            }
                        }
                    }
                }

                val folderList = ArrayList<Map<String, Any>>()
                for (info in foldersMap.values) {
                    if (info.count > 0 && info.count == info.shortClipsCount) {
                        // Exclude folders that ONLY contain short clips (GIFs)
                        continue
                    }
                    val item = HashMap<String, Any>()
                    item["name"] = info.name
                    item["path"] = info.path
                    item["count"] = info.count
                    item["newVideosCount"] = info.newVideosCount
                    item["containsMovies"] = info.containsMovies
                    folderList.add(item)
                }

                runOnUiThread {
                    result.success(folderList)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("QUERY_FAILED", e.message, null)
                }
            }
        }
    }

    private fun getAudioTracks(
        limit: Int,
        offset: Int,
        folderName: String?,
        folderPath: String?,
        result: MethodChannel.Result
    ) {
        thread {
            try {
                val audioList = ArrayList<Map<String, Any?>>()
                val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

                val projection = arrayOf(
                    MediaStore.Audio.Media._ID,
                    MediaStore.Audio.Media.TITLE,
                    MediaStore.Audio.Media.ARTIST,
                    MediaStore.Audio.Media.ALBUM,
                    MediaStore.Audio.Media.ALBUM_ID,
                    MediaStore.Audio.Media.DATA,
                    MediaStore.Audio.Media.DURATION,
                    MediaStore.Audio.Media.SIZE,
                    MediaStore.Audio.Media.DATE_ADDED,
                    MediaStore.Audio.Media.TRACK,
                    MediaStore.Audio.Media.DISPLAY_NAME,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Audio.Media.BUCKET_DISPLAY_NAME
                    } else {
                        "bucket_display_name"
                    }
                )

                val baseSelection = "${MediaStore.Audio.Media.DURATION} > 0 AND ${MediaStore.Audio.Media.SIZE} > 0"
                var selection = baseSelection
                var selectionArgs: Array<String>? = null
                var canonicalFolder: String? = null

                if (folderPath != null) {
                    try {
                        canonicalFolder = File(folderPath).canonicalPath
                    } catch (e: Exception) {
                        canonicalFolder = folderPath
                    }
                    val fName = File(folderPath).name
                    if (fName.isNotEmpty()) {
                        selection = "$baseSelection AND ${MediaStore.Audio.Media.DATA} LIKE ?"
                        selectionArgs = arrayOf("%/$fName/%")
                    }
                } else if (folderName != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        selection = "$baseSelection AND ${MediaStore.Audio.Media.BUCKET_DISPLAY_NAME} = ?"
                        selectionArgs = arrayOf(folderName)
                    } else {
                        selection = "$baseSelection AND ${MediaStore.Audio.Media.DATA} LIKE ?"
                        selectionArgs = arrayOf("%/$folderName/%")
                    }
                }

                val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val queryArgs = Bundle().apply {
                        putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                        putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
                        if (folderPath != null || folderName != null) {
                            putStringArray(
                                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                                arrayOf(MediaStore.Audio.Media.TITLE)
                            )
                            putInt(
                                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                                ContentResolver.QUERY_SORT_DIRECTION_ASCENDING
                            )
                        } else {
                            putStringArray(
                                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                                arrayOf(MediaStore.Audio.Media.DATE_ADDED)
                            )
                            putInt(
                                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                                ContentResolver.QUERY_SORT_DIRECTION_DESCENDING
                            )
                        }
                        putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                        if (selectionArgs != null) {
                            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                        }
                    }
                    contentResolver.query(uri, projection, queryArgs, null)
                } else {
                    val sortOrder = if (folderPath != null || folderName != null) {
                        "${MediaStore.Audio.Media.TITLE} ASC LIMIT $limit OFFSET $offset"
                    } else {
                        "${MediaStore.Audio.Media.DATE_ADDED} DESC LIMIT $limit OFFSET $offset"
                    }
                    contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
                }

                cursor?.use {
                    val idCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                    val titleCol = it.getColumnIndex(MediaStore.Audio.Media.TITLE)
                    val artistCol = it.getColumnIndex(MediaStore.Audio.Media.ARTIST)
                    val albumCol = it.getColumnIndex(MediaStore.Audio.Media.ALBUM)
                    val albumIdCol = it.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID)
                    val pathCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    val durationCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                    val sizeCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                    val dateCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                    val trackCol = it.getColumnIndex(MediaStore.Audio.Media.TRACK)
                    val nameCol = it.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                    val bucketCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        it.getColumnIndex(MediaStore.Audio.Media.BUCKET_DISPLAY_NAME)
                    } else {
                        it.getColumnIndex("bucket_display_name")
                    }

                    while (it.moveToNext()) {
                        val id = it.getLong(idCol)
                        val path = it.getString(pathCol) ?: ""
                        if (path.isEmpty()) continue

                        val pathLower = path.lowercase()
                        // Exclude hidden files and directories, cache, temp, Android system app data
                        if (pathLower.contains("/.") ||
                            pathLower.contains("/cache/") ||
                            pathLower.contains("/temp/") ||
                            pathLower.contains("/android/data/") ||
                            pathLower.contains("/android/obb/")) {
                            continue
                        }

                        // Filter by exact parent folder if folderPath is specified
                        if (canonicalFolder != null) {
                            val normFolder = canonicalFolder.replace("\\", "/").lowercase()
                            try {
                                val parentCanonical = File(path).parentFile?.canonicalPath ?: ""
                                val normParent = parentCanonical.replace("\\", "/").lowercase()
                                if (normParent != normFolder) {
                                    continue
                                }
                            } catch (e: Exception) {
                                val parentAbsolute = File(path).parentFile?.absolutePath ?: ""
                                val normParent = parentAbsolute.replace("\\", "/").lowercase()
                                val normFolderPath = (folderPath ?: "").replace("\\", "/").lowercase()
                                if (normParent != normFolderPath) {
                                    continue
                                }
                            }
                        }

                        val file = File(path)
                        val parentFile = file.parentFile
                        val actualFolderPath = parentFile?.absolutePath ?: ""

                        var folderNameStr = ""
                        if (bucketCol != -1) {
                            folderNameStr = it.getString(bucketCol) ?: ""
                        }
                        if (folderNameStr.isEmpty()) {
                            folderNameStr = parentFile?.name ?: ""
                        }
                        if (folderNameStr.isEmpty()) {
                            folderNameStr = "Music"
                        }

                        val rawTitle = if (titleCol != -1) it.getString(titleCol) else null
                        val displayName = if (nameCol != -1) it.getString(nameCol) else null
                        val title = when {
                            !rawTitle.isNullOrBlank() -> rawTitle.trim()
                            !displayName.isNullOrBlank() -> displayName.substringBeforeLast('.').trim()
                            else -> file.nameWithoutExtension.ifBlank { "Unknown Track" }
                        }

                        val rawArtist = if (artistCol != -1) it.getString(artistCol) else null
                        val artist = if (rawArtist.isNullOrBlank() || rawArtist.equals("<unknown>", ignoreCase = true)) {
                            "Unknown Artist"
                        } else {
                            rawArtist.trim()
                        }

                        val rawAlbum = if (albumCol != -1) it.getString(albumCol) else null
                        val album = if (rawAlbum.isNullOrBlank() || rawAlbum.equals("<unknown>", ignoreCase = true)) {
                            "Unknown Album"
                        } else {
                            rawAlbum.trim()
                        }

                        val albumId = if (albumIdCol != -1) it.getLong(albumIdCol) else -1L
                        val albumArtUri = if (albumId > 0) {
                            "content://media/external/audio/albumart/$albumId"
                        } else {
                            null
                        }

                        val duration = it.getLong(durationCol)
                        val size = it.getLong(sizeCol)
                        val dateAdded = it.getLong(dateCol)

                        val rawTrack = if (trackCol != -1) it.getInt(trackCol) else 0
                        val trackNumber = when {
                            rawTrack >= 1000 -> rawTrack % 1000
                            rawTrack > 0 -> rawTrack
                            else -> null
                        }

                        val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id).toString()

                        val audioItem = HashMap<String, Any?>()
                        audioItem["id"] = id.toString()
                        audioItem["title"] = title
                        audioItem["artist"] = artist
                        audioItem["album"] = album
                        audioItem["albumId"] = if (albumId > 0) albumId.toString() else null
                        audioItem["albumArtUri"] = albumArtUri
                        audioItem["path"] = path
                        audioItem["contentUri"] = contentUri
                        audioItem["duration"] = duration
                        audioItem["size"] = size
                        audioItem["dateAdded"] = dateAdded
                        audioItem["trackNumber"] = trackNumber
                        audioItem["folderName"] = folderNameStr
                        audioItem["folderPath"] = actualFolderPath

                        audioList.add(audioItem)
                    }
                }

                runOnUiThread {
                    result.success(audioList)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("AUDIO_QUERY_FAILED", e.message, null)
                }
            }
        }
    }

    private fun getAudioFolders(result: MethodChannel.Result) {
        thread {
            try {
                val foldersMap = LinkedHashMap<String, AudioFolderInfo>()
                val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                val projection = arrayOf(
                    MediaStore.Audio.Media._ID,
                    MediaStore.Audio.Media.DATA,
                    MediaStore.Audio.Media.DURATION,
                    MediaStore.Audio.Media.SIZE,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Audio.Media.BUCKET_DISPLAY_NAME
                    } else {
                        "bucket_display_name"
                    }
                )

                val selection = "${MediaStore.Audio.Media.DURATION} > 0 AND ${MediaStore.Audio.Media.SIZE} > 0"
                val cursor = contentResolver.query(uri, projection, selection, null, null)

                cursor?.use {
                    val pathCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    val durationCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                    val sizeCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                    val bucketCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        it.getColumnIndex(MediaStore.Audio.Media.BUCKET_DISPLAY_NAME)
                    } else {
                        it.getColumnIndex("bucket_display_name")
                    }

                    while (it.moveToNext()) {
                        val path = it.getString(pathCol) ?: ""
                        if (path.isEmpty()) continue

                        val duration = it.getLong(durationCol)
                        val size = it.getLong(sizeCol)

                        val file = File(path)
                        val parentFile = file.parentFile
                        val folderPath = parentFile?.absolutePath ?: ""
                        if (folderPath.isEmpty()) continue

                        var folderName = ""
                        if (bucketCol != -1) {
                            folderName = it.getString(bucketCol) ?: ""
                        }
                        if (folderName.isEmpty()) {
                            folderName = parentFile?.name ?: ""
                        }
                        if (folderName.isEmpty()) {
                            folderName = "Music"
                        }

                        val nameLower = folderName.lowercase()
                        val pathLower = folderPath.lowercase()

                        // Ignore hidden folders, cache, temp, thumbnail, android/data
                        if (nameLower.startsWith(".") || pathLower.contains("/.") ||
                            nameLower.contains("cache") || pathLower.contains("/cache/") ||
                            nameLower.contains("temp") || pathLower.contains("/temp/") ||
                            pathLower.contains("/android/data/") ||
                            pathLower.contains("/android/obb/")) {
                            continue
                        }

                        val existing = foldersMap[folderPath]
                        if (existing == null) {
                            foldersMap[folderPath] = AudioFolderInfo(
                                name = folderName,
                                path = folderPath,
                                count = 1,
                                totalDuration = duration,
                                totalSize = size
                            )
                        } else {
                            existing.count += 1
                            existing.totalDuration += duration
                            existing.totalSize += size
                        }
                    }
                }

                val folderList = ArrayList<Map<String, Any>>()
                for (info in foldersMap.values) {
                    val item = HashMap<String, Any>()
                    item["name"] = info.name
                    item["path"] = info.path
                    item["count"] = info.count
                    item["totalDuration"] = info.totalDuration
                    item["totalSize"] = info.totalSize
                    folderList.add(item)
                }

                runOnUiThread {
                    result.success(folderList)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("AUDIO_FOLDERS_QUERY_FAILED", e.message, null)
                }
            }
        }
    }

    private fun generateThumbnail(videoId: Long, path: String, result: MethodChannel.Result) {
        thread {
            try {
                val thumbDir = File(cacheDir, "veil_thumbnails")
                if (!thumbDir.exists()) {
                    thumbDir.mkdirs()
                }
                val destFile = File(thumbDir, "$videoId.jpg")
                if (destFile.exists()) {
                    runOnUiThread {
                        result.success(destFile.absolutePath)
                    }
                    return@thread
                }

                val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val videoUri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, videoId)
                    try {
                        contentResolver.loadThumbnail(videoUri, Size(320, 240), null)
                    } catch (e: Exception) {
                        null
                    }
                } else {
                    @Suppress("DEPRECATION")
                    MediaStore.Video.Thumbnails.getThumbnail(
                        contentResolver,
                        videoId,
                        MediaStore.Video.Thumbnails.MINI_KIND,
                        null
                    )
                }

                if (bitmap != null) {
                    FileOutputStream(destFile).use { out ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
                    }
                    runOnUiThread {
                        result.success(destFile.absolutePath)
                    }
                } else {
                    runOnUiThread {
                        result.success(null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("THUMBNAIL_FAILED", e.message, null)
                }
            }
        }
    }

    private fun savePlaybackPosition(
        videoId: String,
        positionMs: Long,
        durationMs: Long,
        title: String,
        path: String,
        result: MethodChannel.Result
    ) {
        thread {
            try {
                val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
                val editor = prefs.edit()

                editor.putLong("${videoId}_position", positionMs)
                editor.putLong("${videoId}_duration", durationMs)
                editor.putString("${videoId}_title", title)
                editor.putString("${videoId}_path", path)
                editor.putLong("${videoId}_timestamp", System.currentTimeMillis())

                val watchedIds = prefs.getStringSet("watched_ids", LinkedHashSet()) ?: LinkedHashSet()
                val newIds = LinkedHashSet<String>(watchedIds)
                newIds.add(videoId)
                editor.putStringSet("watched_ids", newIds)

                editor.commit()
                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SAVE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun getPlaybackPosition(videoId: String, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
            if (prefs.contains("${videoId}_position")) {
                val map = HashMap<String, Any>()
                map["position"] = prefs.getLong("${videoId}_position", 0L)
                map["duration"] = prefs.getLong("${videoId}_duration", 0L)
                result.success(map)
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("GET_FAILED", e.message, null)
        }
    }

    private fun getAllPlaybackPositions(result: MethodChannel.Result) {
        thread {
            try {
                val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
                val watchedIds = prefs.getStringSet("watched_ids", emptySet()) ?: emptySet()

                val list = ArrayList<Map<String, Any>>()
                for (id in watchedIds) {
                    if (prefs.contains("${id}_position")) {
                        val pos = prefs.getLong("${id}_position", 0L)
                        val dur = prefs.getLong("${id}_duration", 0L)
                        val title = prefs.getString("${id}_title", "") ?: ""
                        val path = prefs.getString("${id}_path", "") ?: ""
                        val ts = prefs.getLong("${id}_timestamp", 0L)

                        val progress = if (dur > 0) pos.toDouble() / dur else 0.0
                        if (progress < 0.95 && pos >= 0) {
                            val map = HashMap<String, Any>()
                            map["id"] = id
                            map["position"] = pos
                            map["duration"] = dur
                            map["title"] = title
                            map["path"] = path
                            map["timestamp"] = ts
                            list.add(map)
                        }
                    }
                }

                list.sortByDescending { it["timestamp"] as Long }

                runOnUiThread {
                    result.success(list)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("GET_ALL_FAILED", e.message, null)
                }
            }
        }
    }

    private fun clearPlaybackPosition(videoId: String, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
            val editor = prefs.edit()
            editor.remove("${videoId}_position")
            editor.remove("${videoId}_duration")
            editor.remove("${videoId}_title")
            editor.remove("${videoId}_path")
            editor.remove("${videoId}_timestamp")

            val watchedIds = prefs.getStringSet("watched_ids", emptySet()) ?: emptySet()
            val newIds = LinkedHashSet<String>(watchedIds)
            newIds.remove(videoId)
            editor.putStringSet("watched_ids", newIds)

            editor.apply()
            result.success(true)
        } catch (e: Exception) {
            result.error("CLEAR_FAILED", e.message, null)
        }
    }

    private fun getBrightness(result: MethodChannel.Result) {
        val lp = window.attributes
        result.success(lp.screenBrightness.toDouble())
    }

    private fun setBrightness(brightness: Double?, result: MethodChannel.Result) {
        if (brightness != null) {
            val lp = window.attributes
            lp.screenBrightness = brightness.toFloat().coerceIn(0f, 1f)
            window.attributes = lp
            result.success(true)
        } else {
            result.error("INVALID_ARGUMENT", "Brightness value is required", null)
        }
    }

    private fun getVolume(result: MethodChannel.Result) {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val current = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            result.success(if (max > 0) current.toDouble() / max else 0.0)
        } catch (e: Exception) {
            result.error("VOLUME_ERROR", e.message, null)
        }
    }

    private fun setVolume(volume: Double?, result: MethodChannel.Result) {
        if (volume != null) {
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val target = (volume * max).toInt().coerceIn(0, max)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                result.success(true)
            } catch (e: Exception) {
                result.error("VOLUME_ERROR", e.message, null)
            }
        } else {
            result.error("INVALID_ARGUMENT", "Volume value is required", null)
        }
    }

    private fun getVideoMetadata(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("INVALID_ARGUMENT", "Path is required", null)
            return
        }
        thread {
            val retriever = android.media.MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                val width = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                val height = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                val bitrateStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE)
                val durationStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                val frameRateStr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                } else null

                val map = HashMap<String, Any?>()
                map["width"] = width
                map["height"] = height
                map["bitrate"] = bitrateStr
                map["duration"] = durationStr
                map["frameRate"] = frameRateStr

                val file = File(path)
                map["size"] = file.length()
                map["extension"] = file.extension

                runOnUiThread {
                    result.success(map)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("METADATA_FAILED", e.message, null)
                }
            } finally {
                try {
                    retriever.release()
                } catch (e: Exception) {
                    // ignore
                }
            }
        }
    }

    private fun savePlayerSetting(key: String, value: Any, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("veil_player_settings", Context.MODE_PRIVATE)
            val editor = prefs.edit()
            when (value) {
                is Boolean -> editor.putBoolean(key, value)
                is Float -> editor.putFloat(key, value)
                is Double -> editor.putFloat(key, value.toFloat())
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is String -> editor.putString(key, value)
                else -> {
                    result.error("UNSUPPORTED_TYPE", "Type not supported for saving", null)
                    return
                }
            }
            editor.apply()
            result.success(true)
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    private fun getPlayerSetting(key: String, type: String, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("veil_player_settings", Context.MODE_PRIVATE)
            if (!prefs.contains(key)) {
                result.success(null)
                return
            }
            val value = when (type) {
                "bool" -> prefs.getBoolean(key, false)
                "float" -> prefs.getFloat(key, 0f).toDouble()
                "int" -> prefs.getInt(key, 0)
                "long" -> prefs.getLong(key, 0L)
                "string" -> prefs.getString(key, null)
                else -> {
                    result.error("UNSUPPORTED_TYPE", "Type not supported for retrieving", null)
                    return
                }
            }
            result.success(value)
        } catch (e: Exception) {
            result.error("GET_FAILED", e.message, null)
        }
    }

    private fun getAllPlayerSettings(result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("veil_player_settings", Context.MODE_PRIVATE)
            result.success(prefs.all)
        } catch (e: Exception) {
            result.error("GET_ALL_FAILED", e.message, null)
        }
    }

    private fun pickSubtitleFile(result: MethodChannel.Result) {
        if (subtitleResult != null) {
            result.error("ALREADY_PICKING", "Subtitle selection already in progress", null)
            return
        }
        subtitleResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            }
            startActivityForResult(intent, PICK_SUBTITLE_REQUEST_CODE)
        } catch (e: Exception) {
            subtitleResult = null
            result.error("PICK_INTENT_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_SUBTITLE_REQUEST_CODE) {
            val result = subtitleResult
            subtitleResult = null
            if (resultCode == RESULT_OK && data != null && data.data != null) {
                val uri = data.data!!
                thread {
                    try {
                        var name = "subtitle.srt"
                        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                            val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (nameIndex != -1 && cursor.moveToFirst()) {
                                name = cursor.getString(nameIndex)
                            }
                        }
                        val cacheDirFile = File(cacheDir, "picked_subtitles")
                        if (!cacheDirFile.exists()) {
                            cacheDirFile.mkdirs()
                        }
                        val destFile = File(cacheDirFile, name)
                        contentResolver.openInputStream(uri)?.use { input ->
                            FileOutputStream(destFile).use { output ->
                                input.copyTo(output)
                            }
                        }
                        runOnUiThread {
                            result?.success(destFile.absolutePath)
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result?.error("PICK_FAILED", e.message, null)
                        }
                    }
                }
            } else {
                result?.success(null)
            }
        } else if (pendingDeleteResults.containsKey(requestCode)) {
            val res = pendingDeleteResults.remove(requestCode)
            val folderPath = pendingDeleteFolderPaths.remove(requestCode)
            if (res != null) {
                if (resultCode == RESULT_OK) {
                    thread {
                        if (folderPath != null) {
                            try {
                                File(folderPath).deleteRecursively()
                            } catch (e: Exception) {}
                        }
                        runOnUiThread {
                            res.success("success")
                        }
                    }
                } else {
                    res.success("cancelled")
                }
            }
        } else if (pendingRenameActions.containsKey(requestCode)) {
            val action = pendingRenameActions.remove(requestCode)
            val res = pendingWriteResults.remove(requestCode)
            if (action != null) {
                if (resultCode == RESULT_OK) {
                    renameVideo(action.videoId, action.oldPath, action.newName, action.result)
                } else {
                    action.result.success("cancelled")
                }
            }
        } else if (requestCode == MANAGE_STORAGE_REQUEST_CODE) {
            val res = pendingManageStorageResult
            pendingManageStorageResult = null
            if (res != null) {
                val granted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                    android.os.Environment.isExternalStorageManager()
                runOnUiThread { res.success(granted) }
            }
        } else if (requestCode == SAF_TREE_REQUEST_CODE) {
            val res = pendingPermissionResult
            pendingPermissionResult = null
            if (res != null) {
                val treeUri = data?.data
                if (resultCode == RESULT_OK && treeUri != null) {
                    try {
                        val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                        val physicalPath = getPhysicalPathFromTreeUri(treeUri)
                        if (physicalPath != null) {
                            val sharedPrefs = getSharedPreferences("veil_saf_prefs", Context.MODE_PRIVATE)
                            sharedPrefs.edit().putString(treeUri.toString(), physicalPath).apply()
                            runOnUiThread { res.success(true) }
                        } else {
                            runOnUiThread { res.success(false) }
                        }
                    } catch (e: Exception) {
                        runOnUiThread { res.error("SAF_GRANT_FAILED", e.message, null) }
                    }
                } else {
                    runOnUiThread { res.success(false) }
                }
            }
        } else if (requestCode == SETTINGS_REQUEST_CODE) {
            val res = pendingSettingsResult
            pendingSettingsResult = null
            if (res != null) {
                runOnUiThread { res.success(true) }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (pendingSettingsResult != null) {
            val res = pendingSettingsResult
            pendingSettingsResult = null
            runOnUiThread {
                try {
                    res?.success(true)
                } catch (_: Exception) {}
            }
        }
        if (pendingManageStorageResult != null) {
            val res = pendingManageStorageResult
            pendingManageStorageResult = null
            val granted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                android.os.Environment.isExternalStorageManager()
            runOnUiThread {
                try {
                    res?.success(granted)
                } catch (_: Exception) {}
            }
        }
    }

    private fun enterPipMode(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val builder = android.app.PictureInPictureParams.Builder()
            try {
                val ratio = android.util.Rational(pipAspectRatioNumerator, pipAspectRatioDenominator)
                val floatRatio = ratio.toFloat()
                if (floatRatio in 0.4184f..2.39f) {
                    builder.setAspectRatio(ratio)
                }
            } catch (e: Exception) {
                // ignore
            }
            enterPictureInPictureMode(builder.build())
        } else {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isPipEnabled) {
            enterPipMode()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        }
    }

    private fun saveScreenshotToGallery(bytes: ByteArray, title: String, result: MethodChannel.Result) {
        thread {
            try {
                val resolver = contentResolver
                val contentValues = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, "$title.jpg")
                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Veil")
                        put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                }

                val imageUri = resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                if (imageUri != null) {
                    resolver.openOutputStream(imageUri).use { out ->
                        out?.write(bytes)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        contentValues.clear()
                        contentValues.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                        resolver.update(imageUri, contentValues, null, null)
                    }
                    runOnUiThread {
                        result.success(imageUri.toString())
                    }
                } else {
                    runOnUiThread {
                        result.error("INSERT_FAILED", "Failed to insert MediaStore entry", null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SAVE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun openScreenshotFolder(result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "image/*")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    private fun searchVideos(query: String, limit: Int, result: MethodChannel.Result) {
        thread {
            try {
                val videoList = ArrayList<Map<String, Any?>>()
                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI

                val projection = arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                    MediaStore.Video.Media.DATE_ADDED,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Video.Media.BUCKET_DISPLAY_NAME
                    } else {
                        "bucket_display_name"
                    }
                )

                val bucketColName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaStore.Video.Media.BUCKET_DISPLAY_NAME
                } else {
                    "bucket_display_name"
                }

                val cleanQuery = query.trim()
                val flexQuery = "%" + cleanQuery.replace(Regex("[._\\-\\s]+"), "%") + "%"
                val literalQuery = "%$cleanQuery%"

                val selection = "${MediaStore.Video.Media.DISPLAY_NAME} LIKE ? OR $bucketColName LIKE ? OR ${MediaStore.Video.Media.DATA} LIKE ? OR ${MediaStore.Video.Media.DISPLAY_NAME} LIKE ?"
                val selectionArgs = arrayOf(literalQuery, literalQuery, flexQuery, flexQuery)

                val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val queryArgs = Bundle().apply {
                        putInt(ContentResolver.QUERY_ARG_LIMIT, limit * 2)
                        putStringArray(
                            ContentResolver.QUERY_ARG_SORT_COLUMNS,
                            arrayOf(MediaStore.Video.Media.DATE_ADDED)
                        )
                        putInt(
                            ContentResolver.QUERY_ARG_SORT_DIRECTION,
                            ContentResolver.QUERY_SORT_DIRECTION_DESCENDING
                        )
                        putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                        putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                    }
                    contentResolver.query(uri, projection, queryArgs, null)
                } else {
                    val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC LIMIT ${limit * 2}"
                    contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
                }

                val normQuery = cleanQuery.replace(Regex("[._\\-\\s]+"), "").lowercase()

                cursor?.use {
                    val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                    val nameCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                    val pathCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                    val durationCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                    val sizeCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                    val dateCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                    val bucketCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        it.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                    } else {
                        it.getColumnIndex("bucket_display_name")
                    }

                    while (it.moveToNext()) {
                        if (videoList.size >= limit) break

                        val id = it.getLong(idCol)
                        val title = it.getString(nameCol) ?: ""
                        val path = it.getString(pathCol) ?: ""
                        val duration = it.getLong(durationCol)
                        val size = it.getLong(sizeCol)
                        val dateAdded = it.getLong(dateCol)

                        if (path.isEmpty()) continue
                        val pathLower = path.lowercase()

                        // Ignore junk folders during search
                        if (pathLower.contains("/.") || 
                            pathLower.contains("/cache/") ||
                            pathLower.contains("/temp/") || pathLower.contains("/tmp/") ||
                            pathLower.contains("/thumbnail/") || pathLower.contains("/.thumbnails/") ||
                            pathLower.contains("/android/data/") ||
                            pathLower.contains("whatsapp animated gifs") ||
                            pathLower.contains("whatsapp stickers")) {
                            continue
                        }

                        var folder = ""
                        if (bucketCol != -1) {
                            folder = it.getString(bucketCol) ?: ""
                        }
                        if (folder.isEmpty() && path.isNotEmpty()) {
                            try {
                                val file = File(path)
                                folder = file.parentFile?.name ?: ""
                            } catch (e: Exception) {
                                // ignore
                            }
                        }
                        if (folder.isEmpty()) {
                            folder = "Storage"
                        }

                        // Normalized fuzzy match check
                        if (normQuery.isNotEmpty()) {
                            val normTitle = title.replace(Regex("[._\\-\\s]+"), "").lowercase()
                            val normPath = path.replace(Regex("[._\\-\\s]+"), "").lowercase()
                            val normFolder = folder.replace(Regex("[._\\-\\s]+"), "").lowercase()

                            if (!normTitle.contains(normQuery) && !normPath.contains(normQuery) && !normFolder.contains(normQuery)) {
                                continue
                            }
                        }

                        val videoItem = HashMap<String, Any?>()
                        videoItem["id"] = id.toString()
                        videoItem["title"] = title
                        videoItem["path"] = path
                        videoItem["duration"] = duration
                        videoItem["size"] = size
                        videoItem["dateAdded"] = dateAdded
                        videoItem["folderName"] = folder

                        videoList.add(videoItem)
                    }
                }

                runOnUiThread {
                    result.success(videoList)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("QUERY_FAILED", e.message, null)
                }
            }
        }
    }

    private fun deleteVideo(videoId: String, path: String, result: MethodChannel.Result) {
        thread {
            try {
                // Delete cached thumbnail if it exists
                try {
                    val thumbFile = File(File(cacheDir, "veil_thumbnails"), "$videoId.jpg")
                    if (thumbFile.exists()) {
                        thumbFile.delete()
                    }
                } catch (e: Exception) {}

                val file = File(path)
                val videoUri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, videoId.toLong())

                // Strategy 1: Direct file.delete() — works on older Android or when MANAGE_EXTERNAL_STORAGE is granted
                var physicallyDeleted = false
                try {
                    if (file.exists()) {
                        physicallyDeleted = file.delete()
                    } else {
                        physicallyDeleted = true // Already gone, clean up MediaStore
                    }
                } catch (e: Exception) {}

                if (physicallyDeleted) {
                    try { contentResolver.delete(videoUri, null, null) } catch (e: Exception) {}
                    runOnUiThread { result.success("success") }
                    return@thread
                }

                // Strategy 2: SAF (Storage Access Framework) — if user granted folder access
                val docUri = getDocumentUriForPath(path)
                if (docUri != null) {
                    val safDeleted = deleteDocFile(docUri)
                    if (safDeleted) {
                        try { contentResolver.delete(videoUri, null, null) } catch (e: Exception) {}
                        runOnUiThread { result.success("success") }
                        return@thread
                    }
                }

                // Strategy 3: MediaStore delete (Android 10+) — may require system confirmation dialog
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // On Android 11+, use createDeleteRequest which shows a one-time system dialog.
                    // If MANAGE_EXTERNAL_STORAGE is granted, file.delete() above would have worked already.
                    val uris = listOf(videoUri)
                    val pendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
                    val code = getNextRequestCode()
                    pendingDeleteResults[code] = result
                    runOnUiThread {
                        try {
                            startIntentSenderForResult(
                                pendingIntent.intentSender,
                                code,
                                null, 0, 0, 0
                            )
                        } catch (e: Exception) {
                            pendingDeleteResults.remove(code)
                            result.error("DELETE_FAILED", e.message, null)
                        }
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        contentResolver.delete(videoUri, null, null)
                        runOnUiThread { result.success("success") }
                    } catch (e: SecurityException) {
                        val recoverableSecurityException = e as? android.app.RecoverableSecurityException
                        if (recoverableSecurityException != null) {
                            val code = getNextRequestCode()
                            pendingDeleteResults[code] = result
                            runOnUiThread {
                                try {
                                    startIntentSenderForResult(
                                        recoverableSecurityException.userAction.actionIntent.intentSender,
                                        code,
                                        null, 0, 0, 0
                                    )
                                } catch (ex: Exception) {
                                    pendingDeleteResults.remove(code)
                                    result.error("DELETE_FAILED", ex.message, null)
                                }
                            }
                        } else {
                            runOnUiThread { result.success("permission_required") }
                        }
                    }
                } else {
                    contentResolver.delete(videoUri, null, null)
                    runOnUiThread { result.success("success") }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("DELETE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun deleteVideosBatch(videoIds: List<String>, paths: List<String>, result: MethodChannel.Result) {
        thread {
            try {
                // Delete cached thumbnails if they exist
                for (id in videoIds) {
                    try {
                        val thumbFile = File(File(cacheDir, "veil_thumbnails"), "$id.jpg")
                        if (thumbFile.exists()) {
                            thumbFile.delete()
                        }
                    } catch (e: Exception) {}
                }

                val urisToSystemDelete = ArrayList<Uri>()
                val videoUris = videoIds.map { ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, it.toLong()) }
                
                var successCount = 0
                for (i in paths.indices) {
                    val file = File(paths[i])
                    var physicallyDeleted = false
                    try {
                        if (file.exists()) {
                            physicallyDeleted = file.delete()
                        } else {
                            physicallyDeleted = true
                        }
                    } catch (e: Exception) {}

                    if (physicallyDeleted) {
                        try {
                            contentResolver.delete(videoUris[i], null, null)
                            successCount++
                        } catch (e: Exception) {}
                        continue
                    }

                    val docUri = getDocumentUriForPath(paths[i])
                    if (docUri != null) {
                        val safDeleted = deleteDocFile(docUri)
                        if (safDeleted) {
                            try {
                                contentResolver.delete(videoUris[i], null, null)
                                successCount++
                            } catch (e: Exception) {}
                            continue
                        }
                    }
                    
                    urisToSystemDelete.add(videoUris[i])
                }

                if (urisToSystemDelete.isEmpty()) {
                    runOnUiThread { result.success("success") }
                    return@thread
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val pendingIntent = MediaStore.createDeleteRequest(contentResolver, urisToSystemDelete)
                    val code = getNextRequestCode()
                    pendingDeleteResults[code] = result
                    runOnUiThread {
                        try {
                            startIntentSenderForResult(
                                pendingIntent.intentSender,
                                code,
                                null, 0, 0, 0
                            )
                        } catch (e: Exception) {
                            pendingDeleteResults.remove(code)
                            result.error("BATCH_DELETE_FAILED", e.message, null)
                        }
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        for (uri in urisToSystemDelete) {
                            contentResolver.delete(uri, null, null)
                        }
                        runOnUiThread { result.success("success") }
                    } catch (e: SecurityException) {
                        val recoverableSecurityException = e as? android.app.RecoverableSecurityException
                        if (recoverableSecurityException != null) {
                            val code = getNextRequestCode()
                            pendingDeleteResults[code] = result
                            runOnUiThread {
                                try {
                                    startIntentSenderForResult(
                                        recoverableSecurityException.userAction.actionIntent.intentSender,
                                        code,
                                        null, 0, 0, 0
                                    )
                                } catch (ex: Exception) {
                                    pendingDeleteResults.remove(code)
                                    result.error("BATCH_DELETE_FAILED", ex.message, null)
                                }
                            }
                        } else {
                            runOnUiThread { result.success("permission_required") }
                        }
                    }
                } else {
                    for (uri in urisToSystemDelete) {
                        contentResolver.delete(uri, null, null)
                    }
                    runOnUiThread { result.success("success") }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("BATCH_DELETE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun getUniqueFile(dir: File, fileName: String): File {
        var file = File(dir, fileName)
        if (!file.exists()) return file
        val dotIndex = fileName.lastIndexOf('.')
        val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        var counter = 1
        while (file.exists()) {
            file = File(dir, "$baseName ($counter)$extension")
            counter++
        }
        return file
    }

    private fun copyVideoFileInternal(sourceFile: File, targetFile: File): Boolean {
        return try {
            sourceFile.inputStream().channel.use { inChannel ->
                targetFile.outputStream().channel.use { outChannel ->
                    inChannel.transferTo(0, inChannel.size(), outChannel)
                }
            }
            true
        } catch (e: Exception) {
            try {
                sourceFile.inputStream().use { input ->
                    targetFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                true
            } catch (ex: Exception) {
                false
            }
        }
    }

    private fun copyVideo(sourcePath: String, targetFolder: String, result: MethodChannel.Result) {
        thread {
            try {
                val sourceFile = File(sourcePath)
                if (!sourceFile.exists() || !sourceFile.isFile) {
                    runOnUiThread { result.error("FILE_NOT_FOUND", "Source video does not exist", null) }
                    return@thread
                }
                val targetDir = File(targetFolder)
                if (!targetDir.exists()) {
                    targetDir.mkdirs()
                }
                val targetFile = getUniqueFile(targetDir, sourceFile.name)
                val copied = copyVideoFileInternal(sourceFile, targetFile)
                if (copied) {
                    scanFiles(arrayOf(targetFile.absolutePath)) {
                        runOnUiThread { result.success("success") }
                    }
                } else {
                    runOnUiThread { result.error("COPY_FAILED", "Failed to copy video", null) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("COPY_FAILED", e.message, null) }
            }
        }
    }

    private fun moveVideo(videoId: String, sourcePath: String, targetFolder: String, result: MethodChannel.Result) {
        thread {
            try {
                val sourceFile = File(sourcePath)
                if (!sourceFile.exists() || !sourceFile.isFile) {
                    runOnUiThread { result.error("FILE_NOT_FOUND", "Source video does not exist", null) }
                    return@thread
                }
                val targetDir = File(targetFolder)
                if (!targetDir.exists()) {
                    targetDir.mkdirs()
                }

                if (sourceFile.parentFile?.canonicalPath == targetDir.canonicalPath) {
                    runOnUiThread { result.error("SAME_FOLDER", "Source and destination are the same folder", null) }
                    return@thread
                }

                val targetFile = getUniqueFile(targetDir, sourceFile.name)
                var moved = false
                try {
                    moved = sourceFile.renameTo(targetFile)
                } catch (e: Exception) {}

                if (!moved) {
                    if (copyVideoFileInternal(sourceFile, targetFile)) {
                        try {
                            sourceFile.delete()
                        } catch (e: Exception) {}
                        moved = true
                    }
                }

                if (moved) {
                    try {
                        val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
                        if (prefs.contains("${videoId}_path")) {
                            prefs.edit().putString("${videoId}_path", targetFile.absolutePath).commit()
                        }
                    } catch (e: Exception) {}

                    scanFiles(arrayOf(sourcePath, targetFile.absolutePath)) {
                        runOnUiThread { result.success("success") }
                    }
                } else {
                    runOnUiThread { result.error("MOVE_FAILED", "Failed to move video", null) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("MOVE_FAILED", e.message, null) }
            }
        }
    }

    private fun copyVideosBatch(paths: List<String>, targetFolder: String, result: MethodChannel.Result) {
        thread {
            try {
                val targetDir = File(targetFolder)
                if (!targetDir.exists()) {
                    targetDir.mkdirs()
                }
                val scannedPaths = ArrayList<String>()
                for (path in paths) {
                    val sourceFile = File(path)
                    if (sourceFile.exists() && sourceFile.isFile) {
                        val targetFile = getUniqueFile(targetDir, sourceFile.name)
                        if (copyVideoFileInternal(sourceFile, targetFile)) {
                            scannedPaths.add(targetFile.absolutePath)
                        }
                    }
                }
                if (scannedPaths.isNotEmpty()) {
                    scanFiles(scannedPaths.toTypedArray()) {
                        runOnUiThread { result.success("success") }
                    }
                } else {
                    runOnUiThread {
                        if (paths.isEmpty()) result.success("success")
                        else result.error("COPY_FAILED", "No files were copied", null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("COPY_FAILED", e.message, null) }
            }
        }
    }

    private fun moveVideosBatch(videoIds: List<String>, paths: List<String>, targetFolder: String, result: MethodChannel.Result) {
        thread {
            try {
                val targetDir = File(targetFolder)
                if (!targetDir.exists()) {
                    targetDir.mkdirs()
                }
                val scannedPaths = ArrayList<String>()
                val prefs = getSharedPreferences("veil_playback_history", Context.MODE_PRIVATE)
                val editor = prefs.edit()

                for (i in paths.indices) {
                    val path = paths[i]
                    val id = if (i < videoIds.size) videoIds[i] else ""
                    val sourceFile = File(path)
                    if (sourceFile.exists() && sourceFile.isFile) {
                        if (sourceFile.parentFile?.canonicalPath == targetDir.canonicalPath) {
                            continue
                        }
                        val targetFile = getUniqueFile(targetDir, sourceFile.name)
                        var moved = false
                        try {
                            moved = sourceFile.renameTo(targetFile)
                        } catch (e: Exception) {}

                        if (!moved) {
                            if (copyVideoFileInternal(sourceFile, targetFile)) {
                                try {
                                    sourceFile.delete()
                                } catch (e: Exception) {}
                                moved = true
                            }
                        }

                        if (moved) {
                            scannedPaths.add(path)
                            scannedPaths.add(targetFile.absolutePath)
                            if (id.isNotEmpty() && prefs.contains("${id}_path")) {
                                editor.putString("${id}_path", targetFile.absolutePath)
                            }
                        }
                    }
                }
                try {
                    editor.commit()
                } catch (e: Exception) {}

                if (scannedPaths.isNotEmpty()) {
                    scanFiles(scannedPaths.toTypedArray()) {
                        runOnUiThread { result.success("success") }
                    }
                } else {
                    runOnUiThread {
                        if (paths.isEmpty()) result.success("success")
                        else result.error("MOVE_FAILED", "No files were moved", null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("MOVE_FAILED", e.message, null) }
            }
        }
    }

    private fun renameVideo(videoId: String, oldPath: String, newName: String, result: MethodChannel.Result) {
        thread {
            try {
                val oldFile = File(oldPath)
                val ext = oldFile.extension
                var finalNewName = newName
                if (ext.isNotEmpty() && !newName.endsWith(".$ext", ignoreCase = true)) {
                    finalNewName = "$newName.$ext"
                }

                val parent = oldFile.parentFile
                val newFile = File(parent, finalNewName)

                var renameSuccess = false
                try {
                    renameSuccess = oldFile.renameTo(newFile)
                } catch (e: Exception) {}

                val videoUri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, videoId.toLong())
                val values = android.content.ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, finalNewName)
                }

                if (renameSuccess) {
                    values.put(MediaStore.Video.Media.DATA, newFile.absolutePath)
                    try {
                        contentResolver.update(videoUri, values, null, null)
                    } catch (e: Exception) {}
                    scanFiles(arrayOf(oldFile.absolutePath, newFile.absolutePath)) {
                        runOnUiThread { result.success("success") }
                    }
                    return@thread
                }

                val docUri = getDocumentUriForPath(oldPath)
                if (docUri != null) {
                    val newDocUri = renameDocFile(docUri, finalNewName)
                    if (newDocUri != null) {
                        values.put(MediaStore.Video.Media.DATA, newFile.absolutePath)
                        try {
                            contentResolver.update(videoUri, values, null, null)
                        } catch (e: Exception) {}
                        scanFiles(arrayOf(oldFile.absolutePath, newFile.absolutePath)) {
                            runOnUiThread { result.success("success") }
                        }
                        return@thread
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        val updatedRows = contentResolver.update(videoUri, values, null, null)
                        if (updatedRows > 0) {
                            val newPathEstim = oldFile.parentFile?.let { File(it, finalNewName).absolutePath }
                            if (newPathEstim != null) {
                                scanFiles(arrayOf(oldFile.absolutePath, newPathEstim)) {
                                    runOnUiThread { result.success("success") }
                                }
                            } else {
                                runOnUiThread { result.success("success") }
                            }
                        } else {
                            runOnUiThread { result.success("permission_required") }
                        }
                    } catch (e: SecurityException) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val uris = listOf(videoUri)
                            val pendingIntent = MediaStore.createWriteRequest(contentResolver, uris)
                            val code = getNextRequestCode()
                            pendingRenameActions[code] = PendingRenameAction(videoId, oldPath, finalNewName, result)
                            pendingWriteResults[code] = result
                            runOnUiThread {
                                try {
                                    startIntentSenderForResult(
                                        pendingIntent.intentSender,
                                        code,
                                        null, 0, 0, 0
                                    )
                                } catch (ex: Exception) {
                                    pendingWriteResults.remove(code)
                                    pendingRenameActions.remove(code)
                                    result.error("RENAME_FAILED", ex.message, null)
                                }
                            }
                        } else {
                            val recoverableSecurityException = e as? android.app.RecoverableSecurityException
                            if (recoverableSecurityException != null) {
                                val code = getNextRequestCode()
                                pendingRenameActions[code] = PendingRenameAction(videoId, oldPath, finalNewName, result)
                                pendingWriteResults[code] = result
                                runOnUiThread {
                                    try {
                                        startIntentSenderForResult(
                                            recoverableSecurityException.userAction.actionIntent.intentSender,
                                            code,
                                            null, 0, 0, 0
                                        )
                                    } catch (ex: Exception) {
                                        pendingWriteResults.remove(code)
                                        pendingRenameActions.remove(code)
                                        result.error("RENAME_FAILED", ex.message, null)
                                    }
                                }
                            } else {
                                runOnUiThread { result.success("permission_required") }
                            }
                        }
                    }
                } else {
                    runOnUiThread { result.success("permission_required") }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("RENAME_FAILED", e.message, null)
                }
            }
        }
    }

    private fun renameAudio(audioId: String, oldPath: String, newName: String, result: MethodChannel.Result) {
        thread {
            try {
                val oldFile = File(oldPath)
                val ext = oldFile.extension
                var finalNewName = newName
                if (ext.isNotEmpty() && !newName.endsWith(".$ext", ignoreCase = true)) {
                    finalNewName = "$newName.$ext"
                }

                val parent = oldFile.parentFile
                val newFile = File(parent, finalNewName)

                var renameSuccess = false
                try {
                    renameSuccess = oldFile.renameTo(newFile)
                } catch (e: Exception) {}

                val values = android.content.ContentValues().apply {
                    put(MediaStore.Audio.Media.DISPLAY_NAME, finalNewName)
                    val titleWithoutExt = if (finalNewName.contains(".")) finalNewName.substringBeforeLast(".") else finalNewName
                    put(MediaStore.Audio.Media.TITLE, titleWithoutExt)
                }

                val audioIdLong = audioId.toLongOrNull()
                val audioUri = if (audioIdLong != null) {
                    ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, audioIdLong)
                } else null

                if (renameSuccess) {
                    if (audioUri != null) {
                        values.put(MediaStore.Audio.Media.DATA, newFile.absolutePath)
                        try {
                            contentResolver.update(audioUri, values, null, null)
                        } catch (e: Exception) {}
                    }
                    scanFiles(arrayOf(oldFile.absolutePath, newFile.absolutePath)) {
                        runOnUiThread { result.success("success") }
                    }
                    return@thread
                }

                val docUri = getDocumentUriForPath(oldPath)
                if (docUri != null) {
                    val newDocUri = renameDocFile(docUri, finalNewName)
                    if (newDocUri != null) {
                        if (audioUri != null) {
                            values.put(MediaStore.Audio.Media.DATA, newFile.absolutePath)
                            try {
                                contentResolver.update(audioUri, values, null, null)
                            } catch (e: Exception) {}
                        }
                        scanFiles(arrayOf(oldFile.absolutePath, newFile.absolutePath)) {
                            runOnUiThread { result.success("success") }
                        }
                        return@thread
                    }
                }

                if (audioUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        val updatedRows = contentResolver.update(audioUri, values, null, null)
                        if (updatedRows > 0) {
                            val newPathEstim = oldFile.parentFile?.let { File(it, finalNewName).absolutePath }
                            if (newPathEstim != null) {
                                scanFiles(arrayOf(oldFile.absolutePath, newPathEstim)) {
                                    runOnUiThread { result.success("success") }
                                }
                            } else {
                                runOnUiThread { result.success("success") }
                            }
                        } else {
                            runOnUiThread { result.success("permission_required") }
                        }
                    } catch (e: SecurityException) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val uris = listOf(audioUri)
                            val pendingIntent = MediaStore.createWriteRequest(contentResolver, uris)
                            val code = getNextRequestCode()
                            pendingRenameActions[code] = PendingRenameAction(audioId, oldPath, finalNewName, result)
                            pendingWriteResults[code] = result
                            runOnUiThread {
                                try {
                                    startIntentSenderForResult(
                                        pendingIntent.intentSender,
                                        code,
                                        null, 0, 0, 0
                                    )
                                } catch (ex: Exception) {
                                    pendingWriteResults.remove(code)
                                    pendingRenameActions.remove(code)
                                    result.error("RENAME_FAILED", ex.message, null)
                                }
                            }
                        } else {
                            runOnUiThread { result.success("permission_required") }
                        }
                    }
                } else {
                    runOnUiThread { result.success("permission_required") }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("RENAME_FAILED", e.message, null)
                }
            }
        }
    }

    private fun deleteAudio(audioId: String, path: String, result: MethodChannel.Result) {
        thread {
            try {
                val file = File(path)
                val audioIdLong = audioId.toLongOrNull()
                val audioUri = if (audioIdLong != null) {
                    ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, audioIdLong)
                } else null

                var physicallyDeleted = false
                try {
                    if (file.exists()) {
                        physicallyDeleted = file.delete()
                    } else {
                        physicallyDeleted = true
                    }
                } catch (e: Exception) {}

                if (physicallyDeleted) {
                    if (audioUri != null) {
                        try { contentResolver.delete(audioUri, null, null) } catch (e: Exception) {}
                    }
                    scanFiles(arrayOf(path)) {
                        runOnUiThread { result.success("success") }
                    }
                    return@thread
                }

                val docUri = getDocumentUriForPath(path)
                if (docUri != null) {
                    val safDeleted = deleteDocFile(docUri)
                    if (safDeleted) {
                        if (audioUri != null) {
                            try { contentResolver.delete(audioUri, null, null) } catch (e: Exception) {}
                        }
                        scanFiles(arrayOf(path)) {
                            runOnUiThread { result.success("success") }
                        }
                        return@thread
                    }
                }

                if (audioUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val uris = listOf(audioUri)
                    val pendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
                    val code = getNextRequestCode()
                    pendingDeleteResults[code] = result
                    runOnUiThread {
                        try {
                            startIntentSenderForResult(
                                pendingIntent.intentSender,
                                code,
                                null, 0, 0, 0
                            )
                        } catch (ex: Exception) {
                            pendingDeleteResults.remove(code)
                            result.error("DELETE_FAILED", ex.message, null)
                        }
                    }
                } else {
                    runOnUiThread { result.success("permission_required") }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("DELETE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun moveAudio(audioId: String, sourcePath: String, targetFolder: String, result: MethodChannel.Result) {
        thread {
            try {
                val sourceFile = File(sourcePath)
                if (!sourceFile.exists() || !sourceFile.isFile) {
                    runOnUiThread { result.error("FILE_NOT_FOUND", "Source audio does not exist", null) }
                    return@thread
                }
                val targetDir = File(targetFolder)
                if (!targetDir.exists()) {
                    targetDir.mkdirs()
                }

                if (sourceFile.parentFile?.canonicalPath == targetDir.canonicalPath) {
                    runOnUiThread { result.error("SAME_FOLDER", "Source and destination are the same folder", null) }
                    return@thread
                }

                val targetFile = getUniqueFile(targetDir, sourceFile.name)
                var moved = false
                try {
                    moved = sourceFile.renameTo(targetFile)
                } catch (e: Exception) {}

                if (!moved) {
                    if (copyVideoFileInternal(sourceFile, targetFile)) {
                        try {
                            sourceFile.delete()
                        } catch (e: Exception) {}
                        moved = true
                    }
                }

                if (moved) {
                    scanFiles(arrayOf(sourcePath, targetFile.absolutePath)) {
                        runOnUiThread { result.success("success") }
                    }
                } else {
                    runOnUiThread { result.error("MOVE_FAILED", "Failed to move audio", null) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("MOVE_FAILED", e.message, null) }
            }
        }
    }

    private fun renameFolder(oldPath: String, newName: String, result: MethodChannel.Result) {
        thread {
            try {
                val oldDir = File(oldPath)
                if (!oldDir.exists() || !oldDir.isDirectory) {
                    runOnUiThread { result.error("INVALID_PATH", "Folder does not exist", null) }
                    return@thread
                }

                // Query all video file paths in MediaStore under oldPath before renaming
                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                val projection = arrayOf(MediaStore.Video.Media.DATA)
                val selection = "${MediaStore.Video.Media.DATA} LIKE ?"
                val selectionArgs = arrayOf("$oldPath/%")
                val oldPaths = ArrayList<String>()

                val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
                cursor?.use {
                    val dataCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                    while (it.moveToNext()) {
                        val path = it.getString(dataCol) ?: ""
                        if (path.isNotEmpty()) {
                            oldPaths.add(path)
                        }
                    }
                }

                val parent = oldDir.parentFile
                val newDir = File(parent, newName)
                val newPath = newDir.absolutePath

                var renameSuccess = false
                try {
                    renameSuccess = oldDir.renameTo(newDir)
                } catch (e: Exception) {}

                if (!renameSuccess) {
                    val docUri = getDocumentUriForPath(oldPath)
                    if (docUri != null) {
                        val newDocUri = renameDocFile(docUri, newName)
                        renameSuccess = newDocUri != null
                    }
                }

                if (renameSuccess) {
                    val newPaths = oldPaths.map { it.replace(oldPath, newPath) }
                    val allPathsToScan = ArrayList<String>()
                    allPathsToScan.add(oldPath)
                    allPathsToScan.add(newPath)
                    allPathsToScan.addAll(oldPaths)
                    allPathsToScan.addAll(newPaths)

                    scanFiles(allPathsToScan.toTypedArray()) {
                        runOnUiThread { result.success("success") }
                    }
                } else {
                    runOnUiThread { result.success("permission_required") }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("RENAME_FOLDER_FAILED", e.message, null) }
            }
        }
    }

    private fun scanDirectoryRecursively(dir: File) {
        val files = dir.listFiles() ?: return
        val pathsToScan = ArrayList<String>()
        for (file in files) {
            if (file.isDirectory) {
                scanDirectoryRecursively(file)
            } else if (file.isFile) {
                pathsToScan.add(file.absolutePath)
            }
        }
        if (pathsToScan.isNotEmpty()) {
            android.media.MediaScannerConnection.scanFile(
                this,
                pathsToScan.toTypedArray(),
                null,
                null
            )
        }
    }

    private fun deleteFolder(folderPath: String, result: MethodChannel.Result) {
        thread {
            try {
                val dir = File(folderPath)
                if (!dir.exists() || !dir.isDirectory) {
                    runOnUiThread { result.error("INVALID_PATH", "Folder does not exist", null) }
                    return@thread
                }

                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                val projection = arrayOf(MediaStore.Video.Media._ID, MediaStore.Video.Media.DATA)
                val selection = "${MediaStore.Video.Media.DATA} LIKE ?"
                val selectionArgs = arrayOf("$folderPath/%")

                val videoUrisMap = HashMap<String, Uri>()
                val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
                cursor?.use {
                    val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                    val dataCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                    while (it.moveToNext()) {
                        val id = it.getLong(idCol)
                        val path = it.getString(dataCol) ?: ""
                        if (path.isNotEmpty()) {
                            val videoUri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                            videoUrisMap[path] = videoUri
                        }
                    }
                }

                var physicallyDeleted = false
                try {
                    physicallyDeleted = dir.deleteRecursively()
                } catch (e: Exception) {}

                if (physicallyDeleted) {
                    for ((path, videoUri) in videoUrisMap) {
                        try {
                            contentResolver.delete(videoUri, null, null)
                        } catch (e: Exception) {}
                    }
                    runOnUiThread { result.success("success") }
                    return@thread
                }

                val docUri = getDocumentUriForPath(folderPath)
                if (docUri != null) {
                    val safDeleted = deleteDocFile(docUri)
                    if (safDeleted) {
                        for ((path, videoUri) in videoUrisMap) {
                            try {
                                contentResolver.delete(videoUri, null, null)
                            } catch (e: Exception) {}
                        }
                        runOnUiThread { result.success("success") }
                        return@thread
                    }
                }

                runOnUiThread {
                    result.success("permission_required")
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("DELETE_FOLDER_FAILED", e.message, null) }
            }
        }
    }

    private fun hideFolder(folderPath: String, result: MethodChannel.Result) {
        thread {
            try {
                val dir = File(folderPath)
                if (!dir.exists() || !dir.isDirectory) {
                    runOnUiThread { result.error("INVALID_PATH", "Folder does not exist", null) }
                    return@thread
                }

                val noMediaFile = File(dir, ".nomedia")
                var created = true
                if (!noMediaFile.exists()) {
                    created = noMediaFile.createNewFile()
                }

                if (created) {
                    val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    val projection = arrayOf(MediaStore.Video.Media.DATA)
                    val selection = "${MediaStore.Video.Media.DATA} LIKE ?"
                    val selectionArgs = arrayOf("$folderPath/%")
                    val pathsToScan = ArrayList<String>()
                    
                    pathsToScan.add(dir.absolutePath)
                    pathsToScan.add(noMediaFile.absolutePath)

                    val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
                    cursor?.use {
                        val dataCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                        while (it.moveToNext()) {
                            val path = it.getString(dataCol) ?: ""
                            if (path.isNotEmpty()) {
                                pathsToScan.add(path)
                            }
                        }
                    }

                    android.media.MediaScannerConnection.scanFile(
                        this,
                        pathsToScan.toTypedArray(),
                        null
                    ) { path, scanUri -> }

                    runOnUiThread { result.success(true) }
                } else {
                    runOnUiThread { result.success(false) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("HIDE_FOLDER_FAILED", e.message, null) }
            }
        }
    }

    private fun refreshFolder(folderPath: String, result: MethodChannel.Result) {
        thread {
            try {
                val dir = File(folderPath)
                if (!dir.exists() || !dir.isDirectory) {
                    runOnUiThread { result.error("INVALID_PATH", "Folder does not exist", null) }
                    return@thread
                }

                val pathsToScan = ArrayList<String>()
                pathsToScan.add(dir.absolutePath)
                val files = dir.listFiles()
                if (files != null) {
                    for (f in files) {
                        if (f.isFile) {
                            pathsToScan.add(f.absolutePath)
                        }
                    }
                }

                android.media.MediaScannerConnection.scanFile(
                    this,
                    pathsToScan.toTypedArray(),
                    null
                ) { path, uri -> }

                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("REFRESH_FOLDER_FAILED", e.message, null) }
            }
        }
    }

    private fun shareVideo(path: String, result: MethodChannel.Result) {
        thread {
            try {
                val file = File(path)
                if (!file.exists()) {
                    runOnUiThread { result.error("FILE_NOT_FOUND", "File does not exist", null) }
                    return@thread
                }

                var contentUri: Uri? = null
                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                val projection = arrayOf(MediaStore.Video.Media._ID)
                val selection = "${MediaStore.Video.Media.DATA} = ?"
                val selectionArgs = arrayOf(path)

                val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val id = it.getLong(it.getColumnIndexOrThrow(MediaStore.Video.Media._ID))
                        contentUri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                    }
                }

                if (contentUri == null) {
                    contentUri = Uri.fromFile(file)
                }

                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "video/*"
                    putExtra(Intent.EXTRA_STREAM, contentUri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                
                runOnUiThread {
                    try {
                        startActivity(Intent.createChooser(shareIntent, "Share Video"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message, null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("SHARE_FAILED", e.message, null) }
            }
        }
    }


    private fun updateActiveMediaSession(title: String, isPlaying: Boolean, position: Long, duration: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(NOTIFICATION_ID)

                val session = mediaSession ?: MediaSession(this, "VeilPlayerMediaSession").apply {
                    setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
                    setCallback(mediaSessionCallback)
                    mediaSession = this
                }
                
                if (title.isEmpty() || !isPlaying) {
                    if (session.isActive) {
                        session.isActive = false
                    }
                    val stateBuilder = PlaybackState.Builder()
                        .setActions(
                            PlaybackState.ACTION_PLAY or
                            PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_PLAY_PAUSE or
                            PlaybackState.ACTION_SKIP_TO_NEXT or
                            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                            PlaybackState.ACTION_SEEK_TO
                        )
                        .setState(PlaybackState.STATE_STOPPED, position, 0.0f)
                    session.setPlaybackState(stateBuilder.build())
                } else {
                    if (session.isActive) {
                        session.isActive = false
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun trimThumbnailCache() {
        try {
            val prefs = getSharedPreferences("veil_player_settings", Context.MODE_PRIVATE)
            val maxSizeMb = prefs.getInt("thumbnail_cache_size", 200)
            val maxSizeBytes = maxSizeMb.toLong() * 1024 * 1024

            val thumbDir = File(cacheDir, "veil_thumbnails")
            if (!thumbDir.exists() || !thumbDir.isDirectory) return

            val files = thumbDir.listFiles() ?: return
            var currentSize: Long = 0
            for (f in files) {
                currentSize += f.length()
            }

            if (currentSize > maxSizeBytes) {
                val sortedFiles = files.sortedBy { it.lastModified() }
                var sizeToFree = currentSize - maxSizeBytes
                for (f in sortedFiles) {
                    if (sizeToFree <= 0) break
                    val len = f.length()
                    if (f.delete()) {
                        sizeToFree -= len
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun clearThumbnailCache(result: MethodChannel.Result) {
        thread {
            try {
                val thumbDir = File(cacheDir, "veil_thumbnails")
                if (thumbDir.exists() && thumbDir.isDirectory) {
                    val files = thumbDir.listFiles()
                    if (files != null) {
                        for (f in files) {
                            f.delete()
                        }
                    }
                }
                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("CLEAR_CACHE_FAILED", e.message, null)
                }
            }
        }
    }

    private val mediaSessionCallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        object : MediaSession.Callback() {
            override fun onPlay() {
                super.onPlay()
                runOnUiThread { channel?.invokeMethod("onMediaButtonPlay", null) }
            }

            override fun onPause() {
                super.onPause()
                runOnUiThread { channel?.invokeMethod("onMediaButtonPause", null) }
            }

            override fun onSkipToNext() {
                super.onSkipToNext()
                runOnUiThread { channel?.invokeMethod("onMediaButtonNext", null) }
            }

            override fun onSkipToPrevious() {
                super.onSkipToPrevious()
                runOnUiThread { channel?.invokeMethod("onMediaButtonPrevious", null) }
            }

            override fun onSeekTo(pos: Long) {
                super.onSeekTo(pos)
                runOnUiThread { channel?.invokeMethod("onMediaButtonSeekTo", pos) }
            }
        }
    } else {
        null
    }

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        runOnUiThread {
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS -> {
                    channel?.invokeMethod("onAudioFocusLoss", false)
                }
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                    channel?.invokeMethod("onAudioFocusLoss", true)
                }
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    channel?.invokeMethod("onAudioFocusDuck", null)
                }
                AudioManager.AUDIOFOCUS_GAIN -> {
                    channel?.invokeMethod("onAudioFocusGain", null)
                }
            }
        }
    }

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                "action_prev" -> {
                    runOnUiThread { channel?.invokeMethod("onMediaButtonPrevious", null) }
                }
                "action_play_pause" -> {
                    runOnUiThread { channel?.invokeMethod("onMediaButtonToggle", null) }
                }
                "action_next" -> {
                    runOnUiThread { channel?.invokeMethod("onMediaButtonNext", null) }
                }
                AudioManager.ACTION_AUDIO_BECOMING_NOISY -> {
                    runOnUiThread { channel?.invokeMethod("onMediaButtonPause", null) }
                }
            }
        }
    }

    private fun requestAudioFocus(): Boolean {
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(playbackAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(audioFocusChangeListener)
                .build()
            audioFocusRequest = request
            audioManager?.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager?.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager?.abandonAudioFocus(audioFocusChangeListener)
        }
    }

    private fun showMediaNotification(title: String, isPlaying: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Veil Player Media Controls"
            val descriptionText = "Show media controls for active video"
            val importance = NotificationManager.IMPORTANCE_LOW
            val notificationChannel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(notificationChannel)
        }

        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // Previous intent
        val prevIntent = Intent("action_prev")
        val prevPending = PendingIntent.getBroadcast(this, 1, prevIntent, PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0))

        // Play/Pause intent
        val playPauseIntent = Intent("action_play_pause")
        val playPausePending = PendingIntent.getBroadcast(this, 2, playPauseIntent, PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0))

        // Next intent
        val nextIntent = Intent("action_next")
        val nextPending = PendingIntent.getBroadcast(this, 3, nextIntent, PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0))

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText("Veil Player active playback")
            .setContentIntent(pendingIntent)
            .setOngoing(isPlaying)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setStyle(Notification.MediaStyle()
                .setMediaSession(mediaSession?.sessionToken)
                .setShowActionsInCompactView(0, 1, 2)
            )
            // Add actions
            builder.addAction(Notification.Action.Builder(
                android.R.drawable.ic_media_previous, "Previous", prevPending
            ).build())

            val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
            builder.addAction(Notification.Action.Builder(
                playPauseIcon, if (isPlaying) "Pause" else "Play", playPausePending
            ).build())

            builder.addAction(Notification.Action.Builder(
                android.R.drawable.ic_media_next, "Next", nextPending
            ).build())
        }

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_BACKGROUND || level == TRIM_MEMORY_RUNNING_CRITICAL) {
            thread {
                trimThumbnailCache()
            }
            runOnUiThread {
                channel?.invokeMethod("onLowMemory", null)
            }
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        thread {
            trimThumbnailCache()
        }
        runOnUiThread {
            channel?.invokeMethod("onLowMemory", null)
        }
    }

    private fun saveCrashLog(log: String, result: MethodChannel.Result) {
        thread {
            try {
                val context = this
                val logDir = File(filesDir, "crash_reports")
                if (!logDir.exists()) {
                    logDir.mkdirs()
                }
                val logFile = File(logDir, "crash_${System.currentTimeMillis()}.log")
                val versionName = try {
                    context.packageManager.getPackageInfo(context.packageName, 0).versionName
                } catch (e: Exception) {
                    "Unknown"
                }

                val finalLog = StringBuilder().apply {
                    append("Timestamp: ${java.util.Date()}\n")
                    append("App Version: $versionName\n")
                    append("Android Version: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\n")
                    append("Device Model: ${Build.MANUFACTURER} ${Build.MODEL}\n")
                    append(log)
                }.toString()

                logFile.writeText(finalLog)
                runOnUiThread {
                    result.success(logFile.absolutePath)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SAVE_CRASH_FAILED", e.message, null)
                }
            }
        }
    }

    override fun onDestroy() {
        setSessionActive(false)
        try {
            unregisterReceiver(notificationReceiver)
        } catch (e: Exception) {}
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (notificationManager.isNotificationPolicyAccessGranted && originalInterruptionFilter != null) {
                    notificationManager.setInterruptionFilter(originalInterruptionFilter!!)
                }
            } catch (e: Exception) {}
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mediaSession?.release()
        }
        thread {
            trimThumbnailCache()
        }
        if (activeChannel == channel) {
            activeChannel = null
        }
        super.onDestroy()
    }

    private fun setFocusModeEnabled(enable: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (notificationManager.isNotificationPolicyAccessGranted) {
                try {
                    if (enable) {
                        if (originalInterruptionFilter == null) {
                            originalInterruptionFilter = notificationManager.currentInterruptionFilter
                        }
                        notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
                    } else {
                        originalInterruptionFilter?.let { filter ->
                            notificationManager.setInterruptionFilter(filter)
                        }
                        originalInterruptionFilter = null
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private fun getDeviceInfo(result: MethodChannel.Result) {
        try {
            val context = this
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            val versionName = packageInfo.versionName ?: "1.0.0"
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode.toString()
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toString()
            }
            val map = HashMap<String, String>()
            map["manufacturer"] = Build.MANUFACTURER ?: "Unknown"
            map["model"] = Build.MODEL ?: "Unknown"
            map["android_version"] = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
            map["sdk_int"] = Build.VERSION.SDK_INT.toString()
            map["arch"] = if (Build.SUPPORTED_ABIS.isNotEmpty()) Build.SUPPORTED_ABIS[0] else "arm64-v8a"
            map["app_version"] = versionName
            map["build_number"] = versionCode
            result.success(map)
        } catch (e: Exception) {
            result.error("DEVICE_INFO_FAILED", e.message, null)
        }
    }

    private fun shareReportFile(path: String, title: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "Report file does not exist", null)
                return
            }

            val contentUri: Uri = try {
                androidx.core.content.FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",
                    file
                )
            } catch (e: Exception) {
                Uri.fromFile(file)
            }

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, contentUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            val chooser = Intent.createChooser(shareIntent, title)
            startActivity(chooser)
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_REPORT_FAILED", e.message, null)
        }
    }

    private fun setSessionActive(active: Boolean) {
        try {
            val prefs = getSharedPreferences("veil_player_settings", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("session_active", active).commit()
        } catch (e: Exception) {
            // ignore
        }
    }

    override fun onPause() {
        super.onPause()
        setSessionActive(false)
    }

    override fun onStop() {
        super.onStop()
        setSessionActive(false)
    }
}
