package com.zebwqfox.sign

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 内容延伸到状态栏/导航栏（手势小白条区域），避免底部「实色方块」。
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        // Activity 就绪后再请求最高可用刷新率（90/120Hz 等），与 Choreographer 对齐。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = display ?: @Suppress("DEPRECATION") windowManager.defaultDisplay
            display?.supportedModes?.maxByOrNull { it.refreshRate }?.let { mode ->
                val attrs = window.attributes
                attrs.preferredDisplayModeId = mode.modeId
                window.attributes = attrs
            }
        }
    }
}
