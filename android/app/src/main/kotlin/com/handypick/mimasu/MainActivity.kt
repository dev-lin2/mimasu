package com.handypick.mimasu

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.handypick.mimasu.host.ExtensionHostApi
import com.handypick.mimasu.host.ExtensionHostImpl

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExtensionHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            ExtensionHostImpl(applicationContext),
        )
    }
}
