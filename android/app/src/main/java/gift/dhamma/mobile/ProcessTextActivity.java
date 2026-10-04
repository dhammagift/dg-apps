package gift.dhamma.mobile;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * Text-selection menu entry (PROCESS_TEXT, see AndroidManifest.xml). The caller starts it for a
 * result, which pins it to the caller's task; this hands the selected text to MainActivity in the
 * app's own task and finishes, so the app opens as itself and Back returns to the caller.
 * Nothing is returned: the selection is a query, not text to replace.
 */
public class ProcessTextActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        CharSequence text = getIntent().getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT);
        if (text != null && text.length() > 0) {
            startActivity(new Intent(this, MainActivity.class)
                .setAction(Intent.ACTION_PROCESS_TEXT)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_PROCESS_TEXT, text.toString())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
        setResult(RESULT_CANCELED);
        finish();
    }
}
