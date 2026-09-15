package com.handypick.mimasu

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.handypick.mimasu.host.ExtensionHostApi
import com.handypick.mimasu.host.ExtensionHostImpl
import com.handypick.mimasu.downloads.DownloadHostImpl
import com.handypick.mimasu.host.DownloadHostApi
import com.handypick.mimasu.host.SourceApi
import com.handypick.mimasu.host.SourceApiImpl

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExtensionHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            ExtensionHostImpl(applicationContext),
        )
        SourceApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            SourceApiImpl(applicationContext),
        )
        DownloadHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            DownloadHostImpl(applicationContext),
        )
    }
}
