package com.veil.player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder

class VeilAudioService : Service() {

    companion object {
        const val CHANNEL_ID = "veil_audio_playback_channel"
        const val NOTIFICATION_ID = 2002

        const val ACTION_START = "com.veil.player.action.START"
        const val ACTION_UPDATE = "com.veil.player.action.UPDATE"
        const val ACTION_STOP = "com.veil.player.action.STOP"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_ARTIST = "extra_artist"
        const val EXTRA_IS_PLAYING = "extra_is_playing"
        const val EXTRA_POSITION = "extra_position"
        const val EXTRA_DURATION = "extra_duration"

        const val INTENT_ACTION_PREV = "com.veil.player.audio.PREV"
        const val INTENT_ACTION_PLAY_PAUSE = "com.veil.player.audio.PLAY_PAUSE"
        const val INTENT_ACTION_NEXT = "com.veil.player.audio.NEXT"
        const val INTENT_ACTION_STOP = "com.veil.player.audio.STOP"

        var isRunning: Boolean = false
            private set
        var isPlaying: Boolean = false
            private set
        var currentTitle: String = ""
            private set
        var currentArtist: String = ""
            private set
        var currentPosition: Long = 0L
            private set
        var currentDuration: Long = 0L
            private set
    }

    private var mediaSession: MediaSession? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var isReceiverRegistered: Boolean = false

    private val mediaReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                INTENT_ACTION_PREV -> {
                    MainActivity.sendMediaCommand("onMediaButtonPrevious", null)
                }
                INTENT_ACTION_PLAY_PAUSE -> {
                    MainActivity.sendMediaCommand("onMediaButtonToggle", null)
                }
                INTENT_ACTION_NEXT -> {
                    MainActivity.sendMediaCommand("onMediaButtonNext", null)
                }
                INTENT_ACTION_STOP -> {
                    MainActivity.sendMediaCommand("onMediaButtonPause", null)
                    stopAudioService()
                }
                AudioManager.ACTION_AUDIO_BECOMING_NOISY -> {
                    // Headset unplugged / bluetooth disconnected
                    MainActivity.sendMediaCommand("onMediaButtonPause", null)
                }
            }
        }
    }

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                MainActivity.sendMediaCommand("onAudioFocusLoss", false)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                MainActivity.sendMediaCommand("onAudioFocusLoss", true)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                MainActivity.sendMediaCommand("onAudioFocusDuck", null)
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                MainActivity.sendMediaCommand("onAudioFocusGain", null)
            }
        }
    }

    private val mediaSessionCallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        object : MediaSession.Callback() {
            override fun onPlay() {
                super.onPlay()
                MainActivity.sendMediaCommand("onMediaButtonPlay", null)
            }

            override fun onPause() {
                super.onPause()
                MainActivity.sendMediaCommand("onMediaButtonPause", null)
            }

            override fun onSkipToNext() {
                super.onSkipToNext()
                MainActivity.sendMediaCommand("onMediaButtonNext", null)
            }

            override fun onSkipToPrevious() {
                super.onSkipToPrevious()
                MainActivity.sendMediaCommand("onMediaButtonPrevious", null)
            }

            override fun onSeekTo(pos: Long) {
                super.onSeekTo(pos)
                MainActivity.sendMediaCommand("onMediaButtonSeekTo", pos)
            }

            override fun onStop() {
                super.onStop()
                MainActivity.sendMediaCommand("onMediaButtonPause", null)
                stopAudioService()
            }
        }
    } else null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        initMediaSession()
        registerReceivers()
        requestAudioFocus()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        when (intent.action) {
            ACTION_START, ACTION_UPDATE -> {
                currentTitle = intent.getStringExtra(EXTRA_TITLE) ?: currentTitle
                currentArtist = intent.getStringExtra(EXTRA_ARTIST) ?: currentArtist
                isPlaying = intent.getBooleanExtra(EXTRA_IS_PLAYING, isPlaying)
                currentPosition = intent.getLongExtra(EXTRA_POSITION, currentPosition)
                currentDuration = intent.getLongExtra(EXTRA_DURATION, currentDuration)

                updatePlaybackState()
                updateNotification()
            }
            ACTION_STOP -> {
                stopAudioService()
            }
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Veil Music Playback"
            val descriptionText = "Persistent offline background audio playback controls"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun initMediaSession() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mediaSession = MediaSession(this, "VeilAudioPlaybackSession").apply {
                setFlags(
                    MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
                )
                setCallback(mediaSessionCallback)
                isActive = true
            }
        }
    }

    private fun registerReceivers() {
        if (!isReceiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(INTENT_ACTION_PREV)
                addAction(INTENT_ACTION_PLAY_PAUSE)
                addAction(INTENT_ACTION_NEXT)
                addAction(INTENT_ACTION_STOP)
                addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(mediaReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(mediaReceiver, filter)
            }
            isReceiverRegistered = true
        }
    }

    private fun requestAudioFocus(): Boolean {
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
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

    private fun updatePlaybackState() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val session = mediaSession ?: return
            val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
            val speed = if (isPlaying) 1.0f else 0.0f

            val playbackState = PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                    PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE or
                    PlaybackState.ACTION_SKIP_TO_NEXT or
                    PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackState.ACTION_SEEK_TO or
                    PlaybackState.ACTION_STOP
                )
                .setState(state, currentPosition, speed)
                .build()

            session.setPlaybackState(playbackState)

            val metadata = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, currentTitle)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, currentArtist)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, currentDuration)
                .build()

            session.setMetadata(metadata)
            session.isActive = true
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val contentPending = PendingIntent.getActivity(this, 10, launchIntent, flags)

        val prevIntent = Intent(INTENT_ACTION_PREV)
        val prevPending = PendingIntent.getBroadcast(this, 11, prevIntent, flags)

        val playPauseIntent = Intent(INTENT_ACTION_PLAY_PAUSE)
        val playPausePending = PendingIntent.getBroadcast(this, 12, playPauseIntent, flags)

        val nextIntent = Intent(INTENT_ACTION_NEXT)
        val nextPending = PendingIntent.getBroadcast(this, 13, nextIntent, flags)

        val stopIntent = Intent(INTENT_ACTION_STOP)
        val stopPending = PendingIntent.getBroadcast(this, 14, stopIntent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val playPauseIcon = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val playPauseTitle = if (isPlaying) "Pause" else "Play"

        builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(if (currentTitle.isNotEmpty()) currentTitle else "Veil Player")
            .setContentText(if (currentArtist.isNotEmpty()) currentArtist else "Offline Music")
            .setContentIntent(contentPending)
            .setOngoing(isPlaying)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession?.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    prevPending
                ).build()
            )

            builder.addAction(
                Notification.Action.Builder(
                    playPauseIcon,
                    playPauseTitle,
                    playPausePending
                ).build()
            )

            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_next,
                    "Next",
                    nextPending
                ).build()
            )

            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPending
                ).build()
            )
        }

        return builder.build()
    }

    private fun updateNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopAudioService() {
        isRunning = false
        isPlaying = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Task removal policy:
        // If audio is actively playing, continue background playback.
        // If paused or stopped, cleanly shut down the foreground service.
        if (!isPlaying) {
            stopAudioService()
        }
    }

    override fun onDestroy() {
        isRunning = false
        isPlaying = false
        if (isReceiverRegistered) {
            try {
                unregisterReceiver(mediaReceiver)
            } catch (e: Exception) {}
            isReceiverRegistered = false
        }
        abandonAudioFocus()
        mediaSession?.let {
            it.isActive = false
            it.release()
        }
        mediaSession = null
        super.onDestroy()
    }
}
