package com.bligo.app;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.view.View;
import android.webkit.WebView;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

// Thème clair / foncé de l'appli (30/10/2026), équivalent Android de
// ApparencePlugin.swift. Entre deux pages, le téléphone montre un instant le
// fond natif de l'écran (blanc par défaut), d'où un flash blanc en thème
// foncé. Le choix fait dans le profil est donc aussi appliqué au fond natif,
// et gardé pour l'ouverture suivante de l'appli.
@CapacitorPlugin(name = "BligoApparence")
public class ApparencePlugin extends Plugin {

    static final String PREFS = "bligo";
    static final String KEY = "bligo_apparence_fonce";

    // Même vert très foncé que le fond des pages (--sombre-fond dans
    // css/theme-sombre.css), pour qu'aucun noir ne clignote entre deux pages.
    static final int FOND_FONCE = Color.rgb(0x1E, 0x28, 0x26);

    static boolean isDark(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, false);
    }

    static void apply(boolean dark, Activity activity, WebView webView) {
        int fond = dark ? FOND_FONCE : Color.WHITE;
        if (activity != null) {
            activity.getWindow().getDecorView().setBackgroundColor(fond);
            View content = activity.findViewById(android.R.id.content);
            if (content != null) content.setBackgroundColor(fond);
        }
        if (webView != null) webView.setBackgroundColor(fond);
    }

    @PluginMethod
    public void setTheme(PluginCall call) {
        boolean dark = call.getBoolean("dark", false);
        getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY, dark).apply();
        getActivity().runOnUiThread(() -> {
            apply(dark, getActivity(), getBridge().getWebView());
            call.resolve();
        });
    }
}
