package com.bligo.app;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Module calendrier maison (voir CalendarPlugin.java).
        registerPlugin(CalendarPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
