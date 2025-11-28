package com.sentry.test.minimal;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;

/**
 * Minimal test activity that accepts intent parameters and auto-closes after a few seconds.
 * Used for automated testing of Android device management.
 */
public class MainActivity extends Activity {
    private static final String TAG = "SentryTestApp";
    private static final int AUTO_CLOSE_DELAY_MS = 3000; // 3 seconds

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        Log.i(TAG, "MainActivity started");
        
        // Log all intent extras
        Intent intent = getIntent();
        if (intent != null && intent.getExtras() != null) {
            Bundle extras = intent.getExtras();
            Log.i(TAG, "Received " + extras.size() + " intent parameter(s):");
            for (String key : extras.keySet()) {
                Object value = extras.get(key);
                Log.i(TAG, "  " + key + " = " + value);
            }
        } else {
            Log.i(TAG, "No intent parameters received");
        }
        
        // Auto-close after delay
        new Handler().postDelayed(new Runnable() {
            @Override
            public void run() {
                Log.i(TAG, "Auto-closing activity");
                finish();
                System.exit(0);
            }
        }, AUTO_CLOSE_DELAY_MS);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        Log.i(TAG, "MainActivity destroyed");
    }
}
