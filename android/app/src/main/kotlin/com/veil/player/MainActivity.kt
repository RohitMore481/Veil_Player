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
import java.io.File
import java.io.FileOutputStream
import java.util.LinkedHashSet
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "veil_player/media"
    private val PERMISSION_REQUEST_CODE = 4567
    private var mediaSession: MediaSession? = null
    private var channel: MethodChannel? = null
    private val NOTIFICATION_ID = 101
    private val CHANNEL_ID = "veil_player_channel"
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private val PICK_SUBTITLE_REQUEST_CODE = 4568
    private var permissionResult: MethodChannel.Result? = null
    private var subtitleResult: MethodChannel.Result? = null
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
        var containsMovies: Boolean
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
                        .setState(PlaybackState.STATE_PLAYING, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                        .build()
                    setPlaybackState(state)
                    isActive = true
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
                    openSettings()
                    result.success(true)
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
                    showMediaNotification(title, isPlaying)
                    result.success(true)
                }
                "saveCrashLog" -> {
                    val log = call.argument<String>("log") ?: ""
                    saveCrashLog(log, result)
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
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                Manifest.permission.POST_NOTIFICATIONS
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
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
            sharedPrefs.edit().putBoolean("has_requested_permissions", true).apply()

            val status = getPermissionStatus()
            permissionResult?.success(status)
            permissionResult = null
        }
    }

    private fun openSettings() {
        val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        }
        startActivity(intent)
    }

    private fun getVideos(limit: Int, offset: Int, folderName: String?, folderPath: String?, result: MethodChannel.Result) {
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
                val foldersMap = LinkedHashMap<String, FolderInfo>()
                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                val projection = arrayOf(
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
                    val pathCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                    val durationCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                    val bucketCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        it.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                    } else {
                        it.getColumnIndex("bucket_display_name")
                    }

                    while (it.moveToNext()) {
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
                        val isMovieName = nameLower.contains("movie") || nameLower.contains("film") || nameLower.contains("cinema")
                        val isLongVideo = duration > 60 * 60 * 1000 // > 60 minutes

                        val existing = foldersMap[folderPath]
                        if (existing == null) {
                            foldersMap[folderPath] = FolderInfo(
                                name = folderName,
                                path = folderPath,
                                count = 1,
                                containsMovies = isMovieName || isLongVideo
                            )
                        } else {
                            existing.count += 1
                            if (isMovieName || isLongVideo) {
                                existing.containsMovies = true
                            }
                        }
                    }
                }

                val folderList = ArrayList<Map<String, Any>>()
                for (info in foldersMap.values) {
                    val item = HashMap<String, Any>()
                    item["name"] = info.name
                    item["path"] = info.path
                    item["count"] = info.count
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

                editor.apply()
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
                        if (progress < 0.95 && pos > 1000) {
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

                val selection = "${MediaStore.Video.Media.DISPLAY_NAME} LIKE ? OR $bucketColName LIKE ?"
                val selectionArgs = arrayOf("%$query%", "%$query%")

                val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val queryArgs = Bundle().apply {
                        putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
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
                    val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC LIMIT $limit"
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
                val session = mediaSession ?: MediaSession(this, "VeilPlayerMediaSession").apply {
                    setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
                    mediaSession = this
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

                val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
                stateBuilder.setState(state, position, if (isPlaying) 1.0f else 0.0f)
                session.setPlaybackState(stateBuilder.build())

                val metadata = android.media.MediaMetadata.Builder()
                    .putString(android.media.MediaMetadata.METADATA_KEY_TITLE, title)
                    .putLong(android.media.MediaMetadata.METADATA_KEY_DURATION, duration)
                    .build()
                session.setMetadata(metadata)
                
                if (!session.isActive) {
                    session.isActive = true
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
        try {
            unregisterReceiver(notificationReceiver)
        } catch (e: Exception) {}
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mediaSession?.release()
        }
        thread {
            trimThumbnailCache()
        }
        super.onDestroy()
    }
}
