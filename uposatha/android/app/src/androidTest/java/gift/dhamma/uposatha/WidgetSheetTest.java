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
 * The REAL widgets (WidgetViews -> RemoteViews.apply, as a launcher does it): every case of WidgetSheet.cases() (widget x size x
 * scenario x settings), light and dark: PNGs into getExternalFilesDir(null)/shots (sheet-*.png). Any stretching, clipping or overflow of the layouts shows.
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
            for (WidgetSheet.Case c : WidgetSheet.cases()) {
                for (int dark = 0; dark < 2; dark++) {
                    try {
                        RemoteViews rv = WidgetSheet.views(ctx, c);
                        View v = WidgetSheet.inflate(ctx, rv, c.w, c.h, dark == 1);
                        Bitmap b = WidgetSheet.draw(v, c.name + (dark == 1 ? " dark" : " light"));
                        WidgetSheet.save(b, new File(shots, "sheet-" + c.name + (dark == 1 ? "-dark" : "-light") + ".png"));
                        done[0]++;
                    } catch (Throwable t) {
                        Log.e(TAG, "FAILED " + c.name + ": " + t, t);
                    }
                }
            }
        });
        Log.i(TAG, "sheets written: " + done[0]);
    }
}
