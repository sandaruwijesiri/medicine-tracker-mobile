package com.example.medicine_tracker;

import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "medicine_tracker/device_settings")
            .setMethodCallHandler((call, result) -> {
                try {
                    Intent intent;
                    if (call.method.equals("notificationSettings")) {
                        String channel = call.argument("channel");
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            intent = new Intent(channel == null ? Settings.ACTION_APP_NOTIFICATION_SETTINGS : Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS);
                            intent.putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
                            if (channel != null) intent.putExtra(Settings.EXTRA_CHANNEL_ID, channel);
                        } else {
                            intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName()));
                        }
                    } else if (call.method.equals("appSettings")) {
                        intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName()));
                    } else { result.notImplemented(); return; }
                    startActivity(intent);
                    result.success(null);
                } catch (Exception error) {
                    result.error("settings_unavailable", "Open Medicine Tracker in your phone settings.", null);
                }
            });
    }
}
