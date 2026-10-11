package gift.dhamma.uposatha;

/**
 * The pure decisions behind the widgets (no Android classes, so the JVM unit test runs them): how much a design is scaled for a cell,
 * which arrangement of the 2x2 fits, what the calendar shows for its height, the day bar's numbers, the name of the moon's phase.
 *
 * Seven widgets, each ONE design (owner, 2026-10-10: "a widget stays itself when stretched, only bigger"). A design is written in
 * "base dp" for the smallest cell it is meant for; WidgetViews measures its lines with the real font and asks scale() how many times
 * bigger it can be drawn in the cell the launcher gave. Nothing is cut and nothing is left small in a big cell.
 */
final class WidgetPlan {
    /** The widgets of the picker. */
    static final int MOON = 0, MOONUPO = 1, UPO = 2, STRIP = 3, UPO_M = 4, DAY = 5, CAL = 6;
    static final int KINDS = 7;

    private WidgetPlan() {}

    /** How many times the design (needW x needH base dp) fits into the cell (w x h dp), within min..max. */
    /** The phase (0..1) a share `f` of the way from one midday's phase to the next one's; the next one may be past the new moon (0.98 -> 0.01). */
    static double phaseBetween(double a, double b, double f) {
        if (b < a) b += 1;
        return (a + (b - a) * f) % 1;
    }

    /** A route the app opens: a path of its own page ("/uposatha-calendar?tab=cal"), never an address ("https://...", "//host/x", "\\host"). */
    static boolean ownPath(String route) {
        return route != null && route.startsWith("/") && !route.startsWith("//") && route.indexOf('\\') < 0;
    }

    /**
     * How much taller than the launcher says a widget may really be: it is also drawn for these heights, and the launcher takes the
     * tallest that fits the view it really has (a RemoteViews of several sizes, Android 12+). A Motorola razr reports the cells of
     * its other screen: a 1 x 1 widget "82 x 68 dp" was 82 x 115 on the screen, so every design was scaled for a cell 1.7 times
     * lower than the real one and sat small in the middle of it (owner's phone and a razr plus 2024 in Test Lab, 2026-10-11).
     * A Pixel's launcher is a little off too: it leaves the gaps between the rows out (a 4 x 4 "440" was 464 dp high).
     * Steps of 5 to 10 %: what is left unused is less than that.
     */
    static final float[] TALLER = { 1.05f, 1.12f, 1.2f, 1.3f, 1.42f, 1.56f, 1.72f, 1.9f };

    static float scale(float w, float h, float needW, float needH, float min, float max) {
        float k = Math.min(w / Math.max(1, needW), h / Math.max(1, needH));
        return Math.max(min, Math.min(max, k));
    }

    /**
     * The gap between the lines of a design: gmin when the cell is exactly as high as the design, more when the cell is higher than
     * the scaled design (the spare height is shared between the gaps, up to gmax each; the rest stays above and below).
     * needH is the design's height with gaps of gmin.
     */
    static float gap(float h, float k, float needH, int gaps, float gmin, float gmax) {
        if (gaps <= 0) return gmin;
        float spare = h / k - needH;
        return Math.max(gmin, Math.min(gmax, gmin + spare / gaps));
    }

    /**
     * The 2x2: 0 = the agreed wide arrangement (1A / 1B), 1 = stacked with the date and time in one line, 2 = stacked, in two lines.
     * The arrangement that can be drawn BIGGEST in the cell wins (a tall cell: stacked; a low one: wide); the agreed wide one is kept
     * whenever it is within a tenth of the biggest.
     */
    static int upoArrangement(float kWide, float kStackA, float kStackB) {
        float best = Math.max(kWide, Math.max(kStackA, kStackB));
        if (kWide >= 0.9f * best) return 0;
        return kStackA >= 0.98f * kStackB ? 1 : 2;
    }

    /** The phase as one of eight names: 0 new, 1 waxing crescent, 2 first quarter, 3 waxing gibbous, 4 full, 5 waning gibbous, 6 last quarter, 7 waning crescent. */
    static int phaseIndex(double f) {
        f = ((f % 1) + 1) % 1;
        if (f < 0.02 || f > 0.98) return 0;
        if (f < 0.23) return 1;
        if (f < 0.27) return 2;
        if (f < 0.48) return 3;
        if (f < 0.52) return 4;
        if (f < 0.73) return 5;
        if (f < 0.77) return 6;
        return 7;
    }

    /** The lunar day (tithi) of a phase, 1..30: the page's own rule (uposatha-core.js: floor(MoonPhase / 12) + 1). */
    static int tithi(double f) {
        f = ((f % 1) + 1) % 1;
        return Math.min(30, (int) Math.floor(f * 30) + 1);
    }

    /** Percent of the disc that is lit, 0..100. */
    static int litPercent(double f) {
        return (int) Math.round((1 - Math.cos(2 * Math.PI * f)) / 2 * 100);
    }

    /** Whole days and whole hours of a time left, as {days, hours}; never negative. */
    static long[] counter(long remMs) {
        if (remMs < 0) remMs = 0;
        return new long[] { remMs / WidgetFormat.DAY, (remMs % WidgetFormat.DAY) / WidgetFormat.HOUR };
    }

    // ------------------------------------------------------------------ the calendar
    /** The calendar's fixed parts in base dp: the paddings, the month's name, the weekdays. */
    static final float CAL_FIXED = 28 + 27 + 16;
    static final float CAL_ROW = 37, CAL_ROW_MIN = 28, CAL_ROW_MOONS = 33, CAL_NEXT_HEAD = 22, CAL_NEXT_ROW = 26;

    static float calCardH(boolean details) { return 8 + 18 + 17 + 16 + 16 + (details ? 16 : 0); }

    /**
     * What a calendar of the given height (base dp) shows under the month's name: {next rows 0..6, card 0/1, the card's detail line 0/1,
     * mini-moons 0/1}. The grid comes first (a week is never lower than CAL_ROW_MIN), then the card of today, then the list of the next
     * Uposathas: as many rows as the height has left. Whatever is still spare goes to the grid (taller weeks).
     */
    static int[] cal(float hBase, int weeks, boolean details, boolean nextOn) {
        float avail = hBase - CAL_FIXED;
        boolean card = true, det = details;
        if (avail - weeks * CAL_ROW - calCardH(det) < 0) det = false;
        if (avail - weeks * CAL_ROW_MIN - calCardH(det) < 0) card = false;
        float cardH = card ? calCardH(det) : 0;
        int rows = 0;
        float free = avail - weeks * CAL_ROW - cardH;
        if (nextOn && card && free >= CAL_NEXT_HEAD + CAL_NEXT_ROW) rows = (int) Math.min(6, Math.floor((free - CAL_NEXT_HEAD) / CAL_NEXT_ROW));
        float rowH = (avail - cardH - (rows > 0 ? CAL_NEXT_HEAD + rows * CAL_NEXT_ROW : 0)) / weeks;
        return new int[] { rows, card ? 1 : 0, det ? 1 : 0, rowH >= CAL_ROW_MOONS ? 1 : 0 };
    }

    /** The lowest calendar that still shows the month (base dp): below it the design is scaled down instead. */
    static float calMinH(int weeks) { return CAL_FIXED + weeks * CAL_ROW_MIN; }

    // ------------------------------------------------------------------ the day bar
    /** The six parts of the day as shares 0..1 of the bar: {start0, end0, start1, end1, ...}. */
    static float[] barParts(long[] partStart, long[] partEnd) {
        long t0 = partStart[0], t1 = partEnd[partEnd.length - 1];
        double span = Math.max(1, t1 - t0);
        float[] out = new float[partEnd.length * 2];
        for (int k = 0; k < partEnd.length; k++) {
            out[2 * k] = (float) Math.max(0, Math.min(1, (partStart[k] - t0) / span));
            out[2 * k + 1] = (float) Math.max(0, Math.min(1, (partEnd[k] - t0) / span));
        }
        return out;
    }

    /** Where "now" is on the bar, 0..1. */
    static float nowMark(long now, long t0, long t1) {
        return (float) Math.max(0, Math.min(1, (now - t0) / (double) Math.max(1, t1 - t0)));
    }
}
