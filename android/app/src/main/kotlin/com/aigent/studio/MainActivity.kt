package com.aigent.studio

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.util.Locale
import java.util.TimeZone
import kotlin.math.max
import kotlin.math.sqrt

/**
 * 语音功能的原生实现：录音、系统朗读、URL/文件播放、系统语音识别。
 *
 * 为什么不用第三方插件：flutter_tts / speech_to_text / record 这几个包各自
 * 在 build.gradle 里锁定了 AGP 8.12+ 或 8.13 的 classpath，与本工程的
 * Gradle 8.3 不兼容，只要装进来 release 构建就直接失败。这些能力本身都是
 * Android 系统 API（TextToSpeech / MediaPlayer / SpeechRecognizer /
 * MediaRecorder），自己接一遍约 300 行，换来的是构建链彻底可控。
 */
class MainActivity : FlutterActivity() {
    private val methodChannelName = "aigent/voice"
    private val eventChannelName = "aigent/voice_events"
    private val deviceChannelName = "aigent/device"

    private var events: EventChannel.EventSink? = null

    // 录音
    private var recorder: MediaRecorder? = null
    private var recordPath: String? = null

    // 系统朗读
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsUtteranceId = "aigent"

    // 播放（云端合成的音频）
    private var player: MediaPlayer? = null

    // 系统识别
    private var recognizer: SpeechRecognizer? = null
    private var sttOffline = false

    // 端侧离线识别（Vosk）：模型按需加载，识别在独立线程跑，不阻塞 UI。
    private var voskModel: Model? = null
    private var voskModelPath: String = ""
    private var voskRecord: AudioRecord? = null
    private var voskThread: Thread? = null
    @Volatile private var voskRunning = false

    // 录音/识别音量（驱动 Dart 侧波形）
    private val uiHandler = Handler(Looper.getMainLooper())
    private var amplitudeTask: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            },
        )

        MethodChannel(messenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                // ---------------- 录音
                "rec.hasPermission" -> result.success(hasMicPermission())
                "rec.requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !hasMicPermission()
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7701)
                    }
                    result.success(true)
                }
                "rec.start" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_path", "缺少输出路径", null)
                    } else {
                        try {
                            startRecording(path)
                            result.success(path)
                        } catch (e: Exception) {
                            releaseRecorder()
                            result.error("start_failed", e.message, null)
                        }
                    }
                }
                "rec.stop" -> {
                    val path = try {
                        stopRecording()
                    } catch (e: Exception) {
                        releaseRecorder()
                        null
                    }
                    result.success(path)
                }
                "rec.cancel" -> {
                    releaseRecorder()
                    deleteQuietly(recordPath)
                    recordPath = null
                    result.success(true)
                }

                // ---------------- 系统朗读
                "tts.speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    val lang = call.argument<String>("lang") ?: "zh-CN"
                    val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    if (text.isBlank()) {
                        result.success(false)
                    } else {
                        speak(text, lang, rate)
                        result.success(true)
                    }
                }
                "tts.stop" -> {
                    try {
                        tts?.stop()
                    } catch (_: Exception) {
                    }
                    emit(mapOf("type" to "tts_done"))
                    result.success(true)
                }
                "tts.available" -> result.success(ttsReady || tts != null)

                // ---------------- 播放合成的音频
                "player.url" -> {
                    val url = call.argument<String>("url") ?: ""
                    val ok = playSource(url, isFile = false)
                    result.success(ok)
                }
                "player.file" -> {
                    val path = call.argument<String>("path") ?: ""
                    val ok = playSource(path, isFile = true)
                    result.success(ok)
                }
                "player.stop" -> {
                    try {
                        player?.stop()
                    } catch (_: Exception) {
                    }
                    try {
                        player?.release()
                    } catch (_: Exception) {
                    }
                    player = null
                    result.success(true)
                }

                // ---------------- 系统语音识别
                "stt.available" -> result.success(SpeechRecognizer.isRecognitionAvailable(this))
                // v4.4：把「有没有端侧离线引擎」告诉 Dart，用于标注引擎与自动回落。
                "stt.capabilities" -> result.success(sttCapabilities())
                "stt.start" -> {
                    val lang = call.argument<String>("lang") ?: "zh-CN"
                    val preferOffline = call.argument<Boolean>("preferOffline") ?: true
                    val silenceMs = call.argument<Int>("silenceMs") ?: 700
                    result.success(startListening(lang, preferOffline, silenceMs))
                }
                "stt.stop" -> {
                    try {
                        recognizer?.stopListening()
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                "stt.cancel" -> {
                    destroyRecognizer()
                    result.success(true)
                }

                // ---------------- 端侧离线识别（Vosk）
                "vosk.status" -> result.success(
                    mapOf(
                        "loaded" to (voskModel != null),
                        "path" to voskModelPath,
                    ),
                )
                "vosk.prepare" -> {
                    val path = call.argument<String>("path") ?: ""
                    prepareVosk(path, result)
                }
                "vosk.start" -> {
                    val silenceMs = call.argument<Int>("silenceMs") ?: 700
                    result.success(startVosk(silenceMs))
                }
                "vosk.stop" -> {
                    voskRunning = false
                    result.success(true)
                }
                "vosk.cancel" -> {
                    voskRunning = false
                    voskThread?.interrupt()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // 设备智能体：只读设备信息 + 系统级动作（打开 App / 浏览器 / 日历 / 闹钟）。
        // 所有会跳出本应用的动作都走系统 Intent 的确认界面，不暗改任何数据。
        MethodChannel(messenger, deviceChannelName).setMethodCallHandler { call, result ->
            handleDeviceCall(call, result)
        }

        // 提前把 TTS 引擎准备好，首次点击朗读就不用等初始化。
        initTts()
    }

    // ------------------------------------------------------------ 设备智能体
    //
    // 设计边界：这里只做「读」和「调起系统界面」，不做静默写入。
    // 日历 / 闹钟 / 分享都会打开对应系统 App 的确认页，用户不点保存就不会
    // 产生任何变更；文件类操作一律交给 Dart 侧的隔离工作区，绝不接触外部路径。

    private fun handleDeviceCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "device.info" -> result.success(deviceInfo())
                "device.apps" -> result.success(installedApps())
                "app.open" -> result.success(openApp(call.argument<String>("package")))
                "web.open" -> result.success(openUrl(call.argument<String>("url")))
                "calendar.add" -> result.success(addCalendarEvent(call))
                "alarm.set" -> result.success(setAlarm(call))
                "share.text" -> result.success(
                    shareText(call.argument<String>("text"), call.argument<String>("title"))
                )
                "clipboard.set" -> result.success(setClipboard(call.argument<String>("text")))
                "toast" -> {
                    val msg = call.argument<String>("text") ?: ""
                    runOnUiThread { Toast.makeText(this, msg, Toast.LENGTH_SHORT).show() }
                    result.success(true)
                }
                "workspace.root" -> result.success(workspaceRoot())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("device_error", e.message ?: "设备能力调用失败", null)
        }
    }

    @SuppressLint("HardwareIds")
    private fun deviceInfo(): Map<String, Any?> {
        val am = getSystemService(ACTIVITY_SERVICE) as? ActivityManager
        val mem = ActivityManager.MemoryInfo()
        try {
            am?.getMemoryInfo(mem)
        } catch (_: Exception) {
        }
        val dm = resources.displayMetrics
        val battery = try {
            (getSystemService(BATTERY_SERVICE) as? BatteryManager)
                ?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        } catch (_: Exception) {
            -1
        }
        val stat = try {
            StatFs(filesDir.absolutePath)
        } catch (_: Exception) {
            null
        }
        val version = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "?"
        } catch (_: Exception) {
            "?"
        }
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "product" to Build.PRODUCT,
            "device" to Build.DEVICE,
            "board" to Build.BOARD,
            "hardware" to Build.HARDWARE,
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "buildId" to Build.DISPLAY,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "totalMemMb" to mem.totalMem / 1048576L,
            "availMemMb" to mem.availMem / 1048576L,
            "width" to dm.widthPixels,
            "height" to dm.heightPixels,
            "density" to dm.densityDpi,
            "battery" to battery,
            "storageTotalMb" to (stat?.totalBytes ?: -1L) / 1048576L,
            "storageFreeMb" to (stat?.availableBytes ?: -1L) / 1048576L,
            "locale" to Locale.getDefault().toString(),
            "timezone" to TimeZone.getDefault().id,
            "appVersion" to version,
            "packageName" to packageName,
        )
    }

    /** 只列「可从桌面启动」的应用，避免把系统服务组件也暴露给模型。 */
    private fun installedApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val list = try {
            pm.queryIntentActivities(main, 0)
        } catch (_: Exception) {
            emptyList()
        }
        return list.map { ri ->
            val info = ri.activityInfo
            mapOf(
                "package" to info.packageName,
                "label" to try {
                    ri.loadLabel(pm).toString()
                } catch (_: Exception) {
                    info.packageName
                },
                "system" to ((info.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
            )
        }.sortedBy { it["label"].toString().lowercase(Locale.ROOT) }
    }

    private fun openApp(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        // 只接受纯包名，杜绝把别的东西塞进 Intent。
        if (!Regex("^[A-Za-z0-9_.]+$").matches(pkg)) return false
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openUrl(raw: String?): Boolean {
        if (raw.isNullOrBlank()) return false
        var url = raw.trim()
        if (!url.contains("://")) url = "https://$url"
        // 只放行 http/https，避免模型拼出 file://、content:// 之类的私有 URI。
        if (!url.startsWith("http://") && !url.startsWith("https://")) return false
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 调起系统日历「新建事件」界面，由用户确认后保存；本应用不持有日历权限。 */
    private fun addCalendarEvent(call: MethodCall): Boolean {
        val title = call.argument<String>("title")?.trim()
        if (title.isNullOrEmpty()) return false
        val start = call.argument<Number>("start")?.toLong()
            ?: (System.currentTimeMillis() + 3600000L)
        val end = call.argument<Number>("end")?.toLong() ?: (start + 3600000L)
        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
            .putExtra(Intent.EXTRA_TITLE, title)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        call.argument<String>("description")?.let {
            intent.putExtra(CalendarContract.Events.DESCRIPTION, it)
        }
        call.argument<String>("location")?.let {
            intent.putExtra(CalendarContract.Events.EVENT_LOCATION, it)
        }
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 调起系统时钟「设置闹钟」界面，不跳过确认页。 */
    private fun setAlarm(call: MethodCall): Boolean {
        val hour = call.argument<Number>("hour")?.toInt() ?: return false
        val minute = call.argument<Number>("minute")?.toInt() ?: 0
        if (hour !in 0..23 || minute !in 0..59) return false
        val intent = Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour)
            .putExtra(AlarmClock.EXTRA_MINUTES, minute)
            .putExtra(AlarmClock.EXTRA_MESSAGE, call.argument<String>("label") ?: "Aigent")
            .putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun shareText(text: String?, title: String?): Boolean {
        if (text.isNullOrEmpty()) return false
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, text)
        val chooser = Intent.createChooser(send, title ?: "分享")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(chooser)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun setClipboard(text: String?): Boolean {
        if (text.isNullOrEmpty()) return false
        val cm = getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager ?: return false
        cm.setPrimaryClip(ClipData.newPlainText("Aigent", text))
        return true
    }

    /** 智能体的独立工作目录：应用专属外部目录，卸载即清理，不碰用户文件。 */
    private fun workspaceRoot(): String {
        val base = getExternalFilesDir(null) ?: filesDir
        return File(base, "aigent_workspace").absolutePath
    }

    private fun emit(data: Map<String, Any?>) {
        runOnUiThread { events?.success(data) }
    }

    private fun hasMicPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    // ------------------------------------------------------------ 录音

    private fun startRecording(path: String) {
        if (!hasMicPermission()) throw IllegalStateException("没有麦克风权限")
        releaseRecorder()

        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        r.setAudioSource(MediaRecorder.AudioSource.MIC)
        // MPEG_4 + AAC，16k 单声道：体积小，转写接口都认。
        r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioEncodingBitRate(64000)
        r.setAudioSamplingRate(16000)
        r.setAudioChannels(1)
        r.setOutputFile(path)
        r.prepare()
        r.start()

        recorder = r
        recordPath = path
        startAmplitudePolling()
    }

    /** 每 90ms 读一次峰值，归一化成 0~1 回传给输入栏的波形。 */
    private fun startAmplitudePolling() {
        stopAmplitudePolling()
        val task = object : Runnable {
            override fun run() {
                val r = recorder ?: return
                val level = try {
                    (r.maxAmplitude / 12000f).coerceIn(0f, 1f)
                } catch (_: Exception) {
                    0f
                }
                emit(mapOf("type" to "rec_rms", "level" to level))
                uiHandler.postDelayed(this, 90)
            }
        }
        amplitudeTask = task
        uiHandler.postDelayed(task, 120)
    }

    private fun stopAmplitudePolling() {
        amplitudeTask?.let { uiHandler.removeCallbacks(it) }
        amplitudeTask = null
    }

    /** 停止并返回路径；录得太短（< 1KB）视为无效，返回 null 让 Dart 侧提示重录。 */
    private fun stopRecording(): String? {
        stopAmplitudePolling()
        val r = recorder ?: return null
        var ok = true
        try {
            r.stop()
        } catch (e: Exception) {
            ok = false
        }
        try {
            r.release()
        } catch (_: Exception) {
        }
        recorder = null

        val path = recordPath
        recordPath = null
        if (!ok || path == null) {
            deleteQuietly(path)
            return null
        }
        val f = File(path)
        if (!f.exists() || f.length() < 1024) {
            deleteQuietly(path)
            return null
        }
        return path
    }

    private fun releaseRecorder() {
        stopAmplitudePolling()
        try {
            recorder?.release()
        } catch (_: Exception) {
        }
        recorder = null
    }

    // ------------------------------------------------------------ 系统朗读

    private fun initTts() {
        if (tts != null) return
        tts = TextToSpeech(this) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.setOnUtteranceProgressListener(
                    object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) {
                            emit(mapOf("type" to "tts_done"))
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            emit(mapOf("type" to "tts_error", "message" to "朗读失败"))
                        }
                    },
                )
            }
        }
    }

    private fun speak(text: String, lang: String, rate: Float) {
        initTts()
        val engine = tts ?: run {
            emit(mapOf("type" to "tts_error", "message" to "系统没有可用的语音引擎"))
            return
        }
        // 初始化是异步的：引擎还没就绪时，直接在 onInit 里补一次。
        if (!ttsReady) {
            engine.setOnUtteranceProgressListener(
                object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) {
                        emit(mapOf("type" to "tts_done"))
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        emit(mapOf("type" to "tts_error", "message" to "朗读失败"))
                    }
                },
            )
        }
        try {
            val locale = Locale.forLanguageTag(lang)
            if (engine.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE) {
                engine.language = locale
            }
            // TextToSpeech 的 1.0 是常速；调用方给的是倍率，直接对齐。
            engine.setSpeechRate(rate.coerceIn(0.3f, 2.0f))
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, ttsUtteranceId)
            emit(mapOf("type" to "tts_start"))
        } catch (e: Exception) {
            emit(mapOf("type" to "tts_error", "message" to (e.message ?: "朗读失败")))
        }
    }

    // ------------------------------------------------------------ 播放合成音频

    private fun playSource(source: String, isFile: Boolean): Boolean {
        if (source.isBlank()) return false
        try {
            player?.release()
        } catch (_: Exception) {
        }
        val p = MediaPlayer()
        p.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        return try {
            if (isFile) p.setDataSource(source) else p.setDataSource(source)
            p.setOnPreparedListener {
                it.start()
                emit(mapOf("type" to "player_start"))
            }
            p.setOnCompletionListener {
                emit(mapOf("type" to "player_done"))
                try {
                    it.release()
                } catch (_: Exception) {
                }
            }
            p.setOnErrorListener { mp, _, _ ->
                emit(mapOf("type" to "player_error", "message" to "音频无法播放"))
                try {
                    mp.release()
                } catch (_: Exception) {
                }
                true
            }
            p.prepareAsync()
            player = p
            true
        } catch (e: Exception) {
            emit(mapOf("type" to "player_error", "message" to (e.message ?: "播放失败")))
            try {
                p.release()
            } catch (_: Exception) {
            }
            false
        }
    }

    // ------------------------------------------------------------ 系统识别

    /** 端侧离线能力探测：设置页据此标注「本地可用 / 需下载语音包」。 */
    @SuppressLint("NewApi")
    private fun sttCapabilities(): Map<String, Any?> {
        val available = try {
            SpeechRecognizer.isRecognitionAvailable(this)
        } catch (_: Exception) {
            false
        }
        val onDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            } catch (_: Exception) {
                false
            }
        } else {
            false
        }
        return mapOf(
            "available" to available,
            "onDevice" to onDevice,
            "preferOffline" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M),
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    @SuppressLint("NewApi")
    @Suppress("DEPRECATION")
    private fun startListening(lang: String, preferOffline: Boolean, silenceMs: Int): Boolean {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            emit(mapOf("type" to "stt_error", "message" to "系统没有语音识别服务", "code" to -1))
            return false
        }
        destroyRecognizer()

        // Android 12+ 且系统装了离线语音包时，直接用端侧识别器：
        // 不联网、首字延迟最低。其余情况退回普通识别器 + EXTRA_PREFER_OFFLINE。
        val useOnDevice = preferOffline &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            try {
                SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            } catch (_: Exception) {
                false
            }
        sttOffline = useOnDevice
        val r = if (useOnDevice) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        } else {
            SpeechRecognizer.createSpeechRecognizer(this)
        }
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                emit(mapOf("type" to "stt_start", "offline" to sttOffline))
            }

            override fun onBeginningOfSpeech() {
                emit(mapOf("type" to "stt_speech_begin"))
            }

            override fun onRmsChanged(rmsdB: Float) {
                // 系统回传的是 dB，常见范围 -2~10；映射到 0~1 给波形用。
                emit(
                    mapOf(
                        "type" to "stt_rms",
                        "level" to ((rmsdB + 2f) / 12f).coerceIn(0f, 1f),
                    ),
                )
            }

            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {
                emit(mapOf("type" to "stt_speech_end"))
            }

            override fun onError(error: Int) {
                // 6/7 是「没听到声音」「没识别出结果」，属于正常结束，不算错误。
                if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                ) {
                    emit(mapOf("type" to "stt_no_result", "offline" to sttOffline))
                } else {
                    emit(
                        mapOf(
                            "type" to "stt_error",
                            "message" to sttErrorText(error),
                            "code" to error,
                            "offline" to sttOffline,
                        ),
                    )
                }
            }

            override fun onResults(results: Bundle?) {
                val text = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                    ?: ""
                emit(mapOf("type" to "stt_final", "text" to text, "offline" to sttOffline))
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                    ?: ""
                if (text.isNotEmpty()) {
                    emit(mapOf("type" to "stt_partial", "text" to text))
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            // 端侧识别器不认这个 extra；普通识别器用它优先走离线语音包。
            if (!useOnDevice && preferOffline) {
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            // 说完立即收尾，别让用户等系统默认的 2 秒静音判断。
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                silenceMs,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                (silenceMs * 0.7).toInt(),
            )
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 800)
        }
        return try {
            r.startListening(intent)
            true
        } catch (e: Exception) {
            emit(
                mapOf(
                    "type" to "stt_error",
                    "message" to (e.message ?: "无法启动识别"),
                    "code" to -2,
                    "offline" to sttOffline,
                ),
            )
            destroyRecognizer()
            false
        }
    }

    private fun sttErrorText(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "录音出错"
        SpeechRecognizer.ERROR_CLIENT -> "识别客户端错误"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "没有麦克风权限"
        SpeechRecognizer.ERROR_NETWORK -> "识别需要网络，当前不可用"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "识别网络超时"
        SpeechRecognizer.ERROR_SERVER -> "识别服务异常"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "没有听到声音"
        SpeechRecognizer.ERROR_NO_MATCH -> "没识别出内容"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "识别器忙，稍后再试"
        // 9 = ERROR_LANGUAGE_UNAVAILABLE：端侧离线包没下载，交给 Dart 侧回落在线识别。
        9 -> "没有这个语言的离线语音包"
        else -> "识别失败（$code）"
    }

    private fun destroyRecognizer() {
        try {
            recognizer?.cancel()
        } catch (_: Exception) {
        }
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
    }

    private fun deleteQuietly(path: String?) {
        if (path.isNullOrEmpty()) return
        try {
            val f = File(path)
            if (f.exists()) f.delete()
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------ 端侧离线识别

    /// 加载模型可能花 1~3 秒，放到后台线程，加载完再回主线程 resolve。
    private fun prepareVosk(path: String, result: MethodChannel.Result) {
        if (path.isEmpty() || !File(path).exists()) {
            result.success(false)
            return
        }
        if (voskModel != null && voskModelPath == path) {
            result.success(true)
            return
        }
        Thread {
            var ok = false
            var message = ""
            try {
                voskModel?.close()
                voskModel = Model(path)
                voskModelPath = path
                ok = true
            } catch (e: Throwable) {
                message = e.message ?: "模型加载失败"
                voskModel = null
                voskModelPath = ""
            }
            runOnUiThread {
                if (!ok) {
                    result.error("vosk_model", message.ifEmpty { "模型加载失败" }, null)
                } else {
                    result.success(true)
                }
            }
        }.start()
    }

    private fun startVosk(silenceMs: Int): Boolean {
        val model = voskModel
        if (model == null) {
            emitAsync(
                mapOf(
                    "type" to "stt_error",
                    "message" to "离线语音包还未加载",
                    "code" to -11,
                    "offline" to true,
                ),
            )
            return false
        }
        if (!hasMicPermission()) {
            emitAsync(
                mapOf(
                    "type" to "stt_error",
                    "message" to "没有麦克风权限",
                    "code" to -3,
                    "offline" to true,
                ),
            )
            return false
        }
        voskRunning = false
        voskThread?.interrupt()
        voskThread = null
        try {
            voskRecord?.release()
        } catch (_: Exception) {
        }

        val minBuf = AudioRecord.getMinBufferSize(
            16000,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufSize = max(minBuf, 4096) * 2
        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                16000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufSize,
            )
        } catch (e: Exception) {
            emitAsync(
                mapOf(
                    "type" to "stt_error",
                    "message" to (e.message ?: "无法打开麦克风"),
                    "code" to -4,
                    "offline" to true,
                ),
            )
            return false
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            try {
                record.release()
            } catch (_: Exception) {
            }
            emitAsync(
                mapOf(
                    "type" to "stt_error",
                    "message" to "麦克风被其他应用占用",
                    "code" to -4,
                    "offline" to true,
                ),
            )
            return false
        }
        voskRecord = record
        voskRunning = true

        Thread {
            var rec: Recognizer? = null
            var heard = false
            val startedAt = System.currentTimeMillis()
            val quietLimit = silenceMs.coerceIn(300, 3000)
            var lastVoiceAt = startedAt
            try {
                rec = Recognizer(model, 16000.0f)
                rec.setWords(false)
                record.startRecording()
                emitAsync(
                    mapOf("type" to "stt_start", "offline" to true, "engine" to "vosk"),
                )
                val buffer = ByteArray(4096)
                while (voskRunning) {
                    val n = record.read(buffer, 0, buffer.size)
                    if (n <= 0) {
                        if (n == AudioRecord.ERROR_INVALID_OPERATION ||
                            n == AudioRecord.ERROR_BAD_VALUE
                        ) break
                        continue
                    }
                    // RMS 驱动波形；顺带做「说完就停」的判断，比等系统超时快。
                    var sum = 0.0
                    var i = 0
                    while (i + 1 < n) {
                        val s = ((buffer[i + 1].toInt() shl 8) or (buffer[i].toInt() and 0xFF)).toShort()
                        sum += (s.toDouble() / 32768.0) * (s.toDouble() / 32768.0)
                        i += 2
                    }
                    val rms = sqrt(sum / max(1, n / 2).toDouble()).coerceIn(0.0, 1.0)
                    emitAsync(mapOf("type" to "stt_rms", "level" to rms))
                    val now = System.currentTimeMillis()
                    if (rms > 0.035) {
                        heard = true
                        lastVoiceAt = now
                    }

                    val complete = rec.acceptWaveForm(buffer, n)
                    if (complete) {
                        val text = JSONObject(rec.result).optString("text", "").trim()
                        if (text.isNotEmpty()) {
                            emitAsync(
                                mapOf(
                                    "type" to "stt_final",
                                    "text" to text,
                                    "offline" to true,
                                    "engine" to "vosk",
                                ),
                            )
                            heard = true
                            break
                        }
                    } else {
                        val partial =
                            JSONObject(rec.partialResult).optString("partial", "").trim()
                        if (partial.isNotEmpty()) {
                            emitAsync(mapOf("type" to "stt_partial", "text" to partial))
                        }
                    }

                    // 一直没听到声音：8 秒收尾，别让面板无限转。
                    if (!heard && now - startedAt > 8000) break
                    // 说过话之后长时间静音：直接结束，省得用户再点一次。
                    if (heard && now - lastVoiceAt > quietLimit + 300) break
                }
                if (voskRunning) {
                    val text = JSONObject(rec.finalResult).optString("text", "").trim()
                    if (text.isNotEmpty()) {
                        emitAsync(
                            mapOf(
                                "type" to "stt_final",
                                "text" to text,
                                "offline" to true,
                                "engine" to "vosk",
                            ),
                        )
                    } else {
                        emitAsync(
                            mapOf("type" to "stt_no_result", "offline" to true),
                        )
                    }
                }
            } catch (e: Throwable) {
                emitAsync(
                    mapOf(
                        "type" to "stt_error",
                        "message" to (e.message ?: "离线识别失败"),
                        "code" to -12,
                        "offline" to true,
                    ),
                )
            } finally {
                try {
                    record.stop()
                } catch (_: Exception) {
                }
                try {
                    record.release()
                } catch (_: Exception) {
                }
                if (voskRecord === record) voskRecord = null
                try {
                    rec?.close()
                } catch (_: Exception) {
                }
                voskRunning = false
            }
        }.start()
        return true
    }

    private fun emitAsync(data: Map<String, Any?>) {
        runOnUiThread {
            try {
                emit(data)
            } catch (_: Exception) {
            }
        }
    }

    override fun onDestroy() {
        stopAmplitudePolling()
        voskRunning = false
        voskThread?.interrupt()
        try {
            voskRecord?.release()
        } catch (_: Exception) {
        }
        try {
            voskModel?.close()
        } catch (_: Exception) {
        }
        releaseRecorder()
        destroyRecognizer()
        try {
            player?.release()
        } catch (_: Exception) {
        }
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
