package com.bligo.app;

import android.os.CancellationSignal;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.credentials.exceptions.NoCredentialException;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

// « Continuer avec Google » (02/11/2026), équivalent Android de
// ConnexionPlugin.swift : le sélecteur de comptes Google du téléphone
// (Credential Manager), puis le jeton d'identité est donné à Supabase par la
// page (signInWithIdToken, voir js/connexionSociale.js).
@CapacitorPlugin(name = "BligoConnexion")
public class ConnexionPlugin extends Plugin {

    // Client « BliGO Web (Supabase) » du projet Google Cloud bligo-513513 :
    // c'est lui que Google met dans le jeton, et que Supabase vérifie.
    static final String GOOGLE_WEB_CLIENT_ID = "370561304576-qd8k87nqo3bdp7ngahgmrmt63qk138hn.apps.googleusercontent.com";

    @PluginMethod
    public void google(PluginCall call) {
        GetSignInWithGoogleOption.Builder option = new GetSignInWithGoogleOption.Builder(GOOGLE_WEB_CLIENT_ID);
        String nonce = call.getString("nonce");
        if (nonce != null) option.setNonce(nonce);
        GetCredentialRequest request = new GetCredentialRequest.Builder()
            .addCredentialOption(option.build())
            .build();
        CredentialManager.create(getContext()).getCredentialAsync(
            getActivity(),
            request,
            new CancellationSignal(),
            ContextCompat.getMainExecutor(getContext()),
            new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                @Override
                public void onResult(GetCredentialResponse response) {
                    Credential credential = response.getCredential();
                    if (credential instanceof CustomCredential
                        && GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(credential.getType())) {
                        GoogleIdTokenCredential google = GoogleIdTokenCredential.createFrom(credential.getData());
                        JSObject ret = new JSObject();
                        ret.put("idToken", google.getIdToken());
                        call.resolve(ret);
                    } else {
                        call.reject("Connexion Google impossible");
                    }
                }

                @Override
                public void onError(@NonNull GetCredentialException e) {
                    if (e instanceof GetCredentialCancellationException) {
                        JSObject ret = new JSObject();
                        ret.put("cancelled", true);
                        call.resolve(ret);
                    } else if (e instanceof NoCredentialException) {
                        call.reject("Aucun compte Google sur ce téléphone", "NO_ACCOUNT");
                    } else {
                        call.reject(e.getMessage() != null ? e.getMessage() : "Connexion Google impossible");
                    }
                }
            }
        );
    }
}
