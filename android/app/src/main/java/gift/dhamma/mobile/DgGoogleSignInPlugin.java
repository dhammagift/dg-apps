package gift.dhamma.mobile;

import androidx.core.content.ContextCompat;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

/**
 * Native Google sign-in: the system's own account sheet (Credential Manager), then the Google ID token back
 * to the page, which signs in to the same Firebase account with it (native-bridge.js, wireBrowserSignIn).
 *
 * Replaces the browser detour for Google on Android (dg-apps#43): Google refuses sign-in inside an app's
 * WebView, so the app used to open login/app-google.html in a Custom Tab — a second "Sign in with Google"
 * page before the account chooser, which the owner rightly called an extra step. This is tap -> account ->
 * done, as on the site.
 *
 * serverClientId is the Firebase project's WEB OAuth client ID: the ID token is issued for it, which is what
 * Firebase's GoogleAuthProvider accepts. Google only answers when an ANDROID OAuth client for this package
 * and the signing key's SHA-1 exists in the same project (the upload key for sideloaded builds, the Play
 * signing key for installs from the store).
 */
@CapacitorPlugin(name = "DgGoogleSignIn")
public class DgGoogleSignInPlugin extends Plugin {

    @PluginMethod
    public void signIn(PluginCall call) {
        String clientId = call.getString("serverClientId", "");
        if (clientId == null || clientId.isEmpty()) {
            call.reject("serverClientId is missing", "config");
            return;
        }
        GetSignInWithGoogleOption option = new GetSignInWithGoogleOption.Builder(clientId).build();
        GetCredentialRequest request = new GetCredentialRequest.Builder().addCredentialOption(option).build();
        CredentialManager manager = CredentialManager.create(getContext());
        manager.getCredentialAsync(getActivity(), request, null, ContextCompat.getMainExecutor(getContext()),
                new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                    @Override
                    public void onResult(GetCredentialResponse response) {
                        Credential credential = response.getCredential();
                        if (credential instanceof CustomCredential
                                && GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(credential.getType())) {
                            try {
                                GoogleIdTokenCredential google = GoogleIdTokenCredential.createFrom(((CustomCredential) credential).getData());
                                JSObject result = new JSObject();
                                result.put("idToken", google.getIdToken());
                                call.resolve(result);
                            } catch (Exception e) {
                                call.reject("unreadable Google credential: " + e.getMessage(), "credential");
                            }
                        } else {
                            call.reject("unexpected credential type " + credential.getType(), "credential");
                        }
                    }

                    @Override
                    public void onError(GetCredentialException e) {
                        // "cancelled" is the reader closing the sheet: the page stays quiet about it.
                        String code = e instanceof GetCredentialCancellationException ? "cancelled" : e.getType();
                        call.reject(String.valueOf(e.getMessage()), code);
                    }
                });
    }
}
