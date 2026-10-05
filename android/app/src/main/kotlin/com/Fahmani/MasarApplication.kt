package com.Fahmani

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

/**
 * Initializes the native Android Firebase default app before Flutter and any
 * FlutterFire plugin can access FirebaseAuth/Firestore/Messaging.
 *
 * This avoids the FlutterFire Core platform-channel initialization path on
 * Android, which was failing with "No Firebase App '[DEFAULT]' has been
 * created" / channel-error on this project.
 */
class MasarApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        if (FirebaseApp.getApps(this).none { it.name == FirebaseApp.DEFAULT_APP_NAME }) {
            val options = FirebaseOptions.Builder()
                .setApiKey("AIzaSyBVzHAgc-gLC8uVIylT7gpV1HWgaCvINrs")
                .setApplicationId("1:60922959373:android:b28cad44b8b2dded0fa744")
                .setProjectId("studio-7708799057-99672")
                .setGcmSenderId("60922959373")
                .setStorageBucket("studio-7708799057-99672.firebasestorage.app")
                .build()

            FirebaseApp.initializeApp(this, options)
        }
    }
}
