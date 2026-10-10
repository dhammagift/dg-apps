package gift.dhamma.uposatha;

/**
 * The pure decisions behind the widget's views (no Android classes, so the JVM unit test runs them): the size class, how many rows of a
 * list fit, the shape of a month-grid cell, the day bar's numbers. The geometry itself is never decided here: it is weights in the
 * layouts. These only choose what is shown (which rows exist, which lines are dropped) for the height the launcher reports.
 */
final class WidgetPlan {
    static final int SMALL = 0, MEDIUM = 1, LARGE = 2;
    static final int LAYERS = 3;

    private WidgetPlan() {}

    /** Size class from the widget's size in dp: a column or two wide (2x2, 2x4) is small, otherwise tall is large, the rest medium. */
    static int sizeClass(int widthDp, int heightDp) {
        if (widthDp < 200) return SMALL;
        return heightDp >= 240 ? LARGE : MEDIUM;
    }

    /**
     * The sizes (width x height, dp) a widget gets its own RemoteViews for (Android 12+: the launcher picks the entry that is the largest
     * to fit the REAL size of the widget, whatever sizes it reports in its options - some launchers report them inconsistently, and a widget
     * resized wider got the list of a short one). Each entry is the smallest size its decisions are made for, so a widget never gets more
     * than fits; the steps are about two list rows, rows share the height, so the gap between steps is never visible as a hole.
     * wide: also the 350 dp width (texts that appear only on a wide card).
     */
    static int[][] grid(boolean wide) {
        int[] small = { 100, 125, 165, 205, 250, 330, 430, 540 };   // one or two columns wide (the sizeClass): the counter grows with the height
        int[] medium = { 100, 125, 150, 185, 215 };                // wide and low (the short ones drop lines)
        int[] large = { 240, 300, 370, 440, 510, 580 };            // wide and tall: more rows of the list
        java.util.ArrayList<int[]> out = new java.util.ArrayList<>();
        for (int h : small) out.add(new int[] { 110, h });
        for (int w : wide ? new int[] { 230, 350 } : new int[] { 230 }) {
            for (int h : medium) out.add(new int[] { w, h });
            for (int h : large) out.add(new int[] { w, h });
        }
        return out.toArray(new int[0][]);
    }

    /** How many rows of at least rowMin dp fit into availDp, at most max (rows then share the height, so none is smaller than rowMin). */
    static int rowsThatFit(float availDp, float rowMin, int max) {
        return (int) Math.max(0, Math.min(max, Math.floor(availDp / rowMin)));
    }

    /** Whole days and whole hours of a time left, as {days, hours}; never negative. */
    static long[] counter(long remMs) {
        if (remMs < 0) remMs = 0;
        return new long[] { remMs / WidgetFormat.DAY, (remMs % WidgetFormat.DAY) / WidgetFormat.HOUR };
    }

    /**
     * The shape of a month cell that is part of an Uposatha strip: "r" round, "sr" square on the right (it joins the next cell),
     * "sl" square on the left (it joins the one before), "s" square on both sides. A day that has no fill has no shape.
     */
    static String cellShape(boolean joinLeft, boolean joinRight) {
        return joinLeft ? (joinRight ? "s" : "sl") : (joinRight ? "sr" : "r");
    }

    /** The drawable name of a cell: fill "solid" (evening start), "band" (the day), or null; today adds the ring. null = no background. */
    static String cellDrawable(String fill, boolean joinLeft, boolean joinRight, boolean today) {
        if (fill == null) return today ? "w_cell_t" : null;
        String shape = cellShape(joinLeft, joinRight);
        if ("band".equals(fill)) shape = joinLeft ? "sl" : "r";   // a band is joined on its left only (its right is the end of the strip)
        return "w_cell_" + fill + "_" + shape + (today ? "_t" : "");
    }

    /**
     * The day bar: each of the six parts is a bar drawn from the left edge to the END of the part, as a share (1..1000) of the whole
     * day; the next part's bar lies over it, so the parts show with their own widths.
     */
    static int[] barEnds(long[] partStart, long[] partEnd) {
        long t0 = partStart[0], t1 = partEnd[partEnd.length - 1], span = Math.max(1, t1 - t0);
        int[] out = new int[partEnd.length];
        for (int k = 0; k < out.length; k++) out[k] = (int) Math.max(1, Math.min(1000, Math.round(1000.0 * (partEnd[k] - t0) / span)));
        out[out.length - 1] = 1000;
        return out;
    }

    /** The "now" mark's position on that bar, 1..1000. */
    static int nowMark(long now, long t0, long t1) {
        double f = (now - t0) / (double) Math.max(1, t1 - t0);
        return (int) Math.max(1, Math.min(1000, Math.round(1000 * f)));
    }
}
