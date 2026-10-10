package gift.dhamma.uposatha;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class WidgetPlanTest {
    @Test public void sizeClasses() {
        assertEquals(WidgetPlan.SMALL, WidgetPlan.sizeClass(160, 160));
        assertEquals(WidgetPlan.MEDIUM, WidgetPlan.sizeClass(360, 130));
        assertEquals(WidgetPlan.LARGE, WidgetPlan.sizeClass(360, 300));
        assertEquals(WidgetPlan.LARGE, WidgetPlan.sizeClass(250, 520));
        assertEquals(WidgetPlan.MEDIUM, WidgetPlan.sizeClass(250, 110));
        assertEquals(WidgetPlan.SMALL, WidgetPlan.sizeClass(170, 520));
    }

    @Test public void rowsThatFit() {
        assertEquals(0, WidgetPlan.rowsThatFit(20, 33, 6));
        assertEquals(3, WidgetPlan.rowsThatFit(110, 33, 6));
        assertEquals(6, WidgetPlan.rowsThatFit(900, 33, 6));
    }

    @Test public void counter() {
        assertArrayEquals(new long[] { 1, 7 }, WidgetPlan.counter(WidgetFormat.DAY + 7 * WidgetFormat.HOUR + 59 * WidgetFormat.MIN));
        assertArrayEquals(new long[] { 0, 0 }, WidgetPlan.counter(-5));
    }

    @Test public void cellShapes() {
        assertEquals("r", WidgetPlan.cellShape(false, false));
        assertEquals("sr", WidgetPlan.cellShape(false, true));
        assertEquals("sl", WidgetPlan.cellShape(true, false));
        assertEquals("s", WidgetPlan.cellShape(true, true));
        assertEquals("w_cell_solid_sr", WidgetPlan.cellDrawable("solid", false, true, false));
        assertEquals("w_cell_band_sl_t", WidgetPlan.cellDrawable("band", true, false, true));
        assertEquals("w_cell_band_r", WidgetPlan.cellDrawable("band", false, true, false));   // a band never joins on its right
        assertEquals("w_cell_t", WidgetPlan.cellDrawable(null, false, false, true));
        assertNull(WidgetPlan.cellDrawable(null, false, false, false));
    }

    @Test public void dayBar() {
        long h = WidgetFormat.HOUR;
        long[] s = { 0, 4 * h, 8 * h, 12 * h, 16 * h, 20 * h }, e = { 4 * h, 8 * h, 12 * h, 16 * h, 20 * h, 24 * h };
        assertArrayEquals(new int[] { 167, 333, 500, 667, 833, 1000 }, WidgetPlan.barEnds(s, e));
        assertEquals(500, WidgetPlan.nowMark(12 * h, 0, 24 * h));
        assertEquals(1, WidgetPlan.nowMark(-h, 0, 24 * h));
        assertEquals(1000, WidgetPlan.nowMark(30 * h, 0, 24 * h));
    }
}
