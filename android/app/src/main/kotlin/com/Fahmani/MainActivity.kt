package com.Fahmani

import android.os.Bundle
import android.view.WindowManager
import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Build
import android.app.Application
import com.google.firebase.FirebaseApp
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "masar_app/screen_protection"
    private val firebaseChannelName = "masar_app/firebase"
    private val audioProtectionChannelName = "masar_app/audio_protection"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableScreenProtection()
        blockAudioCapture()
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, state: Bundle?) { activity.window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE) }
            override fun onActivityStarted(activity: Activity) { activity.window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE) }
            override fun onActivityResumed(activity: Activity) { activity.window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE) }
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensurePlugins(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            firebaseChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureInitialized" -> {
                    try {
                        result.success(ensureNativeFirebase())
                    } catch (e: Exception) {
                        result.error("FIREBASE_NATIVE_INIT", e.message, null)
                    }
                }
                "diagnostics" -> result.success(pluginReport)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioProtectionChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "disableMicrophoneCapture", "blockAudioCapture" -> result.success(blockAudioCapture())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    enableScreenProtection()
                    result.success(true)
                }

                "disable" -> {
                    disableScreenProtection()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }


    @Volatile
    private var pluginReport: String = "not-run"

    /**
     * Guarantees that the FlutterFire plugins are attached to this engine.
     * The automatic registration can silently fail (it only logs), which makes
     * every plugin channel fail with "channel-error". Registration is
     * idempotent (already-registered plugins are skipped), so it is safe to
     * repeat here. Reflection is used so this can never break compilation, and
     * the outcome is reported to Dart to make any remaining failure visible.
     */
    @Suppress("UNCHECKED_CAST")
    private fun ensurePlugins(engine: FlutterEngine) {
        val notes = StringBuilder()

        try {
            Class.forName("io.flutter.plugins.GeneratedPluginRegistrant")
                .getMethod("registerWith", FlutterEngine::class.java)
                .invoke(null, engine)
            notes.append("registrant=ok; ")
        } catch (t: Throwable) {
            val cause = t.cause ?: t
            notes.append("registrant=${cause.javaClass.simpleName}:${cause.message}; ")
        }

        try {
            val cls = Class.forName("io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin")
                as Class<out io.flutter.embedding.engine.plugins.FlutterPlugin>
            notes.append(
                if (engine.plugins.has(cls)) "firebase_core=registered; "
                else "firebase_core=missing; "
            )
            repairFirebaseCore(engine, cls, notes)
        } catch (t: Throwable) {
            notes.append("firebase_core=${describe(t)}; ")
        }

        pluginReport = notes.toString()
    }

    private fun describe(t: Throwable): String {
        val c = t.cause ?: t
        return "${c.javaClass.simpleName}:${c.message}@${c.stackTrace.firstOrNull()}"
    }

    /**
     * A plugin is stored in the engine's registry BEFORE its onAttachedToEngine
     * runs, so "registered" does not prove that its Pigeon channel handlers were
     * installed (an exception during attach is only logged). Re-attach the
     * plugin, capture any exception, and install the Pigeon handlers directly.
     */
    @Suppress("UNCHECKED_CAST")
    private fun repairFirebaseCore(
        engine: FlutterEngine,
        cls: Class<out io.flutter.embedding.engine.plugins.FlutterPlugin>,
        notes: StringBuilder,
    ) {
        try {
            engine.plugins.remove(cls)
            notes.append("core-detached; ")
        } catch (t: Throwable) {
            notes.append("core-detach=${describe(t)}; ")
        }
        try {
            engine.plugins.add(cls.getDeclaredConstructor().newInstance())
            notes.append("core-attached; ")
        } catch (t: Throwable) {
            notes.append("core-attach=${describe(t)}; ")
        }

        val plugin = engine.plugins.get(cls)
        for (api in listOf("FirebaseCoreHostApi", "FirebaseAppHostApi")) {
            try {
                val apiCls = Class.forName(
                    "io.flutter.plugins.firebase.core.GeneratedAndroidFirebaseCore\$$api"
                )
                val setUp = apiCls.declaredMethods.first {
                    it.name == "setUp" && it.parameterTypes.size == 2
                }
                setUp.invoke(null, engine.dartExecutor.binaryMessenger, plugin)
                notes.append("$api.setUp=ok; ")
            } catch (t: Throwable) {
                notes.append("$api.setUp=${describe(t)}; ")
            }
        }
    }

    /**
     * Ensure the Android Firebase default app exists.
     * google-services.json + FirebaseInitProvider normally initialize it before
     * the Flutter engine; the explicit check also makes startup deterministic.
     */
    private fun ensureNativeFirebase(): Boolean {
        return FirebaseApp.getApps(this).any {
            it.name == FirebaseApp.DEFAULT_APP_NAME
        }
    }

    /**
     * Blocks recording of the app's own audio by other apps / system screen
     * recorders (Android 10+). Combined with allowAudioPlaybackCapture="false"
     * in the manifest. It cannot stop a physical microphone recording speakers.
     */
    private fun blockAudioCapture(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                am.setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_NONE)
            }
            true
        } catch (_: Throwable) { false }
    }

    private fun enableScreenProtection() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    private fun disableScreenProtection() {
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
}
