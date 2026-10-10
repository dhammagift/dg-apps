package gift.dhamma.uposatha;

import android.content.Context;
import android.graphics.Bitmap;
import android.util.Log;
import android.view.View;
import android.widget.RemoteViews;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;

/**
 * The REAL widget (WidgetViews -> RemoteViews.apply, as a launcher does it) at several dp sizes and aspects, light and dark, every
 * layer, a few scenarios: PNGs into getExternalFilesDir(null)/shots (sheet-*.png). Any stretching, clipping or overflow of the layouts shows.
 * Needs no launcher: runs in a second, next to WidgetFlowTest in the same Test Lab run.
 */
@RunWith(AndroidJUnit4.class)
public class WidgetSheetTest {
    private static final String TAG = "UpoSheet";

    @Test
    public void sheet() throws Exception {
        final Context ctx = InstrumentationRegistry.getInstrumentation().getTargetContext();
        final File shots = new File(ctx.getExternalFilesDir(null), "shots");
        shots.mkdirs();
        final int[] done = { 0 };
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            for (int si = 0; si < WidgetSheet.SCENARIOS.length; si++) {
                WidgetSheet.Scenario sc = WidgetSheet.SCENARIOS[si];
                for (int[] sz : WidgetSheet.SIZES) {
                    for (int dark = 0; dark < 2; dark++) {
                        for (int ly = 0; ly < 3; ly++) {
                            if (sc.file == null && ly > 0) continue;
                            for (int variant = 0; variant < (sc.file == null ? 2 : 1); variant++) {
                                try {
                                    RemoteViews rv = WidgetSheet.views(ctx, sc, variant, ly, sz[0], sz[1]);
                                    View v = WidgetSheet.inflate(ctx, rv, sz[0], sz[1], dark == 1);
                                    Bitmap b = WidgetSheet.draw(v, "#" + si + " L" + ly + " " + sz[0] + "x" + sz[1] + " dp " + (dark == 1 ? "dark" : "light"));
                                    WidgetSheet.save(b, new File(shots, WidgetSheet.name(si, ly, sz[0], sz[1], dark == 1, variant) + ".png"));
                                    done[0]++;
                                } catch (Throwable t) {
                                    Log.e(TAG, "FAILED #" + si + " L" + ly + " " + sz[0] + "x" + sz[1] + ": " + t, t);
                                }
                            }
                        }
                    }
                }
            }
        });
        Log.i(TAG, "sheets written: " + done[0]);
    }
}
