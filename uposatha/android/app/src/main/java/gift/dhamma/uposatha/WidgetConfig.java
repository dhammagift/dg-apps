package gift.dhamma.uposatha;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * The settings of ONE widget on the screen (the gear of the launcher opens WidgetConfigActivity): how it looks on this wallpaper
 * and how much it says. They belong to the widget, not to the app; "as in the app" is the default of every choice, so a widget that
 * was never set up follows the app. Kept in the widget's own SharedPreferences under the widget's id.
 */
final class WidgetConfig {
    static final int SYSTEM = 0, LIGHT = 1, DARK = 2;      // theme
    static final int APP = 0, ON = 1, OFF = 2;             // a choice that can follow the app

    int theme = SYSTEM;
    int opacity = 100;       // of the card, 0 (text only) .. 100
    int details = APP;
    int kala = APP;
    int moons = APP;         // the calendar: the moon of every day
    boolean next = true;     // the calendar: the list of the next Uposathas
    boolean pct = false;     // the Moon 1x1: the lit percent under the moon (owner, 2026-10-10: just the moon by default)
    boolean slides = true;   // the big widgets (4x2, 4x4): three slides (Uposatha, Day & night, Calendar) with a switch at the bottom

    static WidgetConfig load(Context ctx, int id) {
        SharedPreferences p = WidgetProvider.prefs(ctx);
        WidgetConfig c = new WidgetConfig();
        c.theme = clamp(p.getInt("cfg_theme_" + id, SYSTEM), 0, 2);
        c.opacity = clamp(p.getInt("cfg_opacity_" + id, 100), 0, 100);
        c.details = clamp(p.getInt("cfg_details_" + id, APP), 0, 2);
        c.kala = clamp(p.getInt("cfg_kala_" + id, APP), 0, 2);
        c.moons = clamp(p.getInt("cfg_moons_" + id, APP), 0, 2);
        c.next = p.getBoolean("cfg_next_" + id, true);
        c.slides = p.getBoolean("cfg_slides_" + id, true);
        c.pct = p.getBoolean("cfg_pct_" + id, false);
        return c;
    }

    void save(Context ctx, int id) {
        WidgetProvider.prefs(ctx).edit()
                .putInt("cfg_theme_" + id, theme).putInt("cfg_opacity_" + id, opacity).putInt("cfg_details_" + id, details)
                .putInt("cfg_kala_" + id, kala).putInt("cfg_moons_" + id, moons).putBoolean("cfg_next_" + id, next).putBoolean("cfg_slides_" + id, slides)
                .putBoolean("cfg_pct_" + id, pct).apply();
    }

    static void forget(Context ctx, int[] ids) {
        SharedPreferences.Editor e = WidgetProvider.prefs(ctx).edit();
        for (int id : ids)
            for (String k : new String[] { "cfg_theme_", "cfg_opacity_", "cfg_details_", "cfg_kala_", "cfg_moons_", "cfg_next_", "cfg_slides_", "cfg_pct_", "layer_", "mon_", "mon_day_" }) e.remove(k + id);
        e.apply();
    }

    /** A choice that can follow the app: the widget's own answer, else the app's. */
    static boolean pick(int choice, boolean app) { return choice == ON || (choice == APP && app); }

    private static int clamp(int v, int a, int b) { return Math.max(a, Math.min(b, v)); }

    // ------------------------------------------------------------------ colours
    /** The roles a text or a shape can have; the index into the tables below. */
    static final int TEXT = 0, TEXT2 = 1, MUTED = 2, INK = 3, VIK = 4, ON_ACCENT = 5, SURFACE = 6, ACCENT = 7, PART_DAY = 8, PART_NIGHT = 9, EDGE = 10;
    /** The same colours as res/values(-night)/widget_colors.xml (widget/tools/gen_android_res.py writes both from one table). */
    static final int[] LIGHT_C = { 0xFF1B1D19, 0xFF5C6058, 0xFF6E716A, 0xFF0F7C63, 0xFF9B1C31, 0xFFFFFFFF, 0xFFEEF4F2, 0xFF149C7C, 0xFFBDE3DA, 0xFFC1C9D0, 0xFFC3CFCB };
    static final int[] DARK_C = { 0xFFE2E2E2, 0xFFB0B0B0, 0xFF8E8E8E, 0xFF1FB394, 0xFFE0607A, 0xFFFFFFFF, 0xFF1A211F, 0xFF149C7C, 0xFF1D3A34, 0xFF444C54, 0xFF414B49 };
    static final int[] RES_C = { R.color.w_text, R.color.w_text2, R.color.w_muted, R.color.w_accent_ink, R.color.w_vik, R.color.w_on_accent, R.color.w_surface, R.color.w_accent, R.color.w_part_day, R.color.w_part_night, R.color.w_border_strong };
}
