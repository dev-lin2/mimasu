package sg.heysara.mimasu

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import sg.heysara.mimasu.host.ExtensionHostApi
import sg.heysara.mimasu.host.ExtensionHostImpl

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExtensionHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            ExtensionHostImpl(applicationContext),
        )
    }
}
