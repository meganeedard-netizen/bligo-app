package com.bligo.app;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.provider.CalendarContract;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

// Ajout d'un événement de l'agenda culturel au calendrier du téléphone
// (23/10/2026), équivalent Android de CalendarPlugin.swift. Ouvre l'appli
// d'agenda (Google Agenda, Outlook, Samsung...) avec l'événement déjà rempli :
// l'usager choisit son agenda, enregistre et revient dans BliGO. Aucune
// autorisation d'accès au calendrier n'est nécessaire.
@CapacitorPlugin(name = "BligoCalendar")
public class CalendarPlugin extends Plugin {

    @PluginMethod
    public void addEvent(PluginCall call) {
        // Les dates arrivent en millisecondes, parfois lues comme entiers :
        // optDouble accepte les deux.
        double start = call.getData().optDouble("start", Double.NaN);
        double end = call.getData().optDouble("end", Double.NaN);
        if (Double.isNaN(start) || Double.isNaN(end)) {
            call.reject("Date de l'événement manquante");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, call.getString("title", "Événement"))
            .putExtra(CalendarContract.Events.EVENT_LOCATION, call.getString("location", ""))
            .putExtra(CalendarContract.Events.DESCRIPTION, call.getString("notes", ""))
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, (long) start)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, (long) end);
        try {
            getActivity().startActivity(intent);
            JSObject result = new JSObject();
            result.put("opened", true);
            call.resolve(result);
        } catch (ActivityNotFoundException e) {
            call.reject("Aucune appli d'agenda sur ce téléphone");
        }
    }
}
