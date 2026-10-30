package com.bligo.app;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Module calendrier maison (voir CalendarPlugin.java).
        registerPlugin(CalendarPlugin.class);
        // Thème foncé sans flash blanc (voir ApparencePlugin.java) et partage
        // vers les autres applis (voir PartagePlugin.java).
        registerPlugin(ApparencePlugin.class);
        registerPlugin(PartagePlugin.class);
        super.onCreate(savedInstanceState);
        ApparencePlugin.apply(ApparencePlugin.isDark(this), this, getBridge().getWebView());
    }
}
