package com.bligo.app;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;

import androidx.core.content.FileProvider;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileOutputStream;

// Partage vers les autres applis (30/10/2026). La WebView Android n'a pas
// navigator.share : sans ce module, « Partager en story », « Envoyer à un
// ami » et « Partager l'appli » ne faisaient rien sur Android. Ouvre la
// feuille de partage du téléphone (Instagram, TikTok, Snapchat, WhatsApp...)
// avec un texte et/ou une image PNG reçue en base64.
@CapacitorPlugin(name = "BligoPartage")
public class PartagePlugin extends Plugin {

    @PluginMethod
    public void share(PluginCall call) {
        String text = call.getString("text", "");
        String image = call.getString("image", "");
        String fileName = call.getString("fileName", "bligo.png").replaceAll("[^A-Za-z0-9._-]", "_");

        Intent intent = new Intent(Intent.ACTION_SEND);
        if (!text.isEmpty()) intent.putExtra(Intent.EXTRA_TEXT, text);
        if (!image.isEmpty()) {
            try {
                File dir = new File(getContext().getCacheDir(), "partage");
                dir.mkdirs();
                File file = new File(dir, fileName);
                try (FileOutputStream out = new FileOutputStream(file)) {
                    out.write(Base64.decode(image.replaceFirst("^data:image/\\w+;base64,", ""), Base64.DEFAULT));
                }
                Uri uri = FileProvider.getUriForFile(getContext(), getContext().getPackageName() + ".fileprovider", file);
                intent.putExtra(Intent.EXTRA_STREAM, uri);
                intent.setType("image/png");
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } catch (Exception e) {
                call.reject("L'image n'a pas pu être préparée");
                return;
            }
        } else {
            intent.setType("text/plain");
        }
        try {
            getActivity().startActivity(Intent.createChooser(intent, call.getString("title", "Partager")));
            call.resolve();
        } catch (ActivityNotFoundException e) {
            call.reject("Aucune appli de partage");
        }
    }
}
