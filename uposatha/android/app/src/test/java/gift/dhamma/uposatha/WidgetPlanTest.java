package gift.dhamma.uposatha;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** The pure decisions of the widgets (WidgetPlan): the scale of a design in a cell, the 2x2's arrangement, the calendar's rows, the moon's names. */
public class WidgetPlanTest {

    @Test
    public void aDesignIsScaledToTheCellAndNeverPastItsLimits() {
        assertEquals(1f, WidgetPlan.scale(145, 215, 145, 215, 0.8f, 2.2f), 1e-4);
        assertEquals("a wider and higher cell: the same design, bigger", 1.5f, WidgetPlan.scale(300, 400, 200, 200, 0.8f, 2.2f), 1e-4);
        assertEquals("the tighter side decides", 1.2f, WidgetPlan.scale(240, 900, 200, 200, 0.8f, 2.2f), 1e-4);
        assertEquals("not bigger than the limit", 2.2f, WidgetPlan.scale(900, 900, 100, 100, 0.8f, 2.2f), 1e-4);
        assertEquals("not smaller than the floor", 0.8f, WidgetPlan.scale(50, 50, 200, 200, 0.8f, 2.2f), 1e-4);
    }

    @Test
    public void spareHeightGoesIntoTheGapsUpToALimit() {
        assertEquals("an exact fit keeps the smallest gap", 3f, WidgetPlan.gap(150, 1f, 150, 3, 3, 12), 1e-4);
        assertEquals("15 dp spare over 3 gaps", 8f, WidgetPlan.gap(165, 1f, 150, 3, 3, 12), 1e-4);
        assertEquals("never more than the limit", 12f, WidgetPlan.gap(400, 1f, 150, 3, 3, 12), 1e-4);
        assertEquals("the spare is counted in the design's own units", 8f, WidgetPlan.gap(330, 2f, 150, 3, 3, 12), 1e-4);
    }

    @Test
    public void theArrangementThatCanBeDrawnBiggestWins() {
        assertEquals("a low wide cell: 1A / 1B", 0, WidgetPlan.upoArrangement(1.13f, 1.04f, 0.9f));
        assertEquals("the agreed one stays when it is nearly as big", 0, WidgetPlan.upoArrangement(1.2f, 1.3f, 1.1f));
        assertEquals("a tall cell: stacked is drawn much bigger", 1, WidgetPlan.upoArrangement(1.02f, 1.3f, 1.2f));
        assertEquals("a narrow tall cell: stacked, two lines for the date and time", 2, WidgetPlan.upoArrangement(0.7f, 0.95f, 1.1f));
    }

    @Test
    public void theMoonHasEightNames() {
        int[] expect = { 0, 1, 2, 3, 4, 5, 6, 7, 0 };
        double[] f = { 0.0, 0.12, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 0.99 };
        for (int i = 0; i < f.length; i++) assertEquals("phase " + f[i], expect[i], WidgetPlan.phaseIndex(f[i]));
        assertEquals("the day after the new moon is already a crescent", 1, WidgetPlan.phaseIndex(0.03));
        assertEquals(0, WidgetPlan.litPercent(0));
        assertEquals(50, WidgetPlan.litPercent(0.25));
        assertEquals(100, WidgetPlan.litPercent(0.5));
        assertEquals("the page's rule: floor(phase * 30) + 1", 1, WidgetPlan.tithi(0.0));
        assertEquals(15, WidgetPlan.tithi(0.49));
        assertEquals(30, WidgetPlan.tithi(0.999));
    }

    @Test
    public void theCalendarShowsWhatItsHeightHasRoomFor() {
        // {next rows, card, the card's detail line, mini-moons}
        assertArrayEquals("4x3 (the smallest): the month and the card, no list", new int[] { 0, 1, 0, 1 }, WidgetPlan.cal(328, 5, false, true));
        int[] p44 = WidgetPlan.cal(441, 5, false, true);
        assertTrue("4x4: the card and a couple of next rows", p44[1] == 1 && p44[0] >= 1 && p44[0] <= 3 && p44[3] == 1);
        int[] p55 = WidgetPlan.cal(556, 5, true, true);
        assertTrue("taller: more rows of the list, never more than six", p55[0] > p44[0] && p55[0] <= 6 && p55[2] == 1);
        assertEquals("the list can be switched off", 0, WidgetPlan.cal(556, 5, true, false)[0]);
        assertArrayEquals("too low for the card: the month alone", new int[] { 0, 0, 0, 0 }, WidgetPlan.cal(WidgetPlan.calMinH(6) + 10, 6, true, true));
        assertEquals("a six-week month has less room for the list than a five-week one", true, WidgetPlan.cal(441, 6, false, true)[0] <= p44[0]);
    }

    @Test
    public void theDayBarKeepsTheProportionsOfTheDay() {
        long h = 3600000L;
        long[] start = { 0, 4 * h, 8 * h, 12 * h, 16 * h, 20 * h }, end = { 4 * h, 8 * h, 12 * h, 16 * h, 20 * h, 24 * h };
        float[] p = WidgetPlan.barParts(start, end);
        assertEquals(12, p.length);
        assertEquals(0f, p[0], 1e-6);
        assertEquals(1f / 6, p[1], 1e-6);
        assertEquals(1f, p[11], 1e-6);
        assertEquals(0.5f, WidgetPlan.nowMark(12 * h, 0, 24 * h), 1e-6);
        assertEquals("before the first dawn: the left edge", 0f, WidgetPlan.nowMark(-h, 0, 24 * h), 1e-6);
    }

    @Test
    public void theCounterIsWholeDaysAndHours() {
        assertArrayEquals(new long[] { 1, 7 }, WidgetPlan.counter(WidgetFormat.DAY + 7 * WidgetFormat.HOUR + 59 * WidgetFormat.MIN));
        assertArrayEquals(new long[] { 0, 0 }, WidgetPlan.counter(-5));
    }

    @Test
    public void theMoonBetweenTwoMiddaysAlsoOverTheNewMoon() {
        assertEquals(0.515, WidgetPlan.phaseBetween(0.50, 0.53, 0.5), 1e-9);
        assertEquals(0.995, WidgetPlan.phaseBetween(0.98, 0.01, 0.5), 1e-9);   // not 0.495, the full moon's side
        assertEquals(0.004, WidgetPlan.phaseBetween(0.98, 0.01, 0.8), 1e-9);
    }

    @Test
    public void onlyAPathOfThePageIsARoute() {
        assertTrue(WidgetPlan.ownPath("/uposatha-calendar?app=1&tab=cal&day=2026-11-05"));
        for (String bad : new String[] { null, "", "https://example.com/", "http://x", "//example.com/x", "/\\example.com", "javascript:alert(1)", "uposatha-calendar" })
            assertFalse(String.valueOf(bad), WidgetPlan.ownPath(bad));
    }

    /** The size a launcher takes of those the widget is drawn for: {draw w, draw h}. */
    private static int[] taken(int reportedW, int reportedH, float realW, float realH) {
        int[][] all = WidgetPlan.sizes(reportedW, reportedH);
        return all[WidgetPlan.chosen(all, realW, realH)];
    }

    @Test
    public void theLauncherFindsASizeNearTheRealOneWhateverItReported() {
        // a launcher that tells the truth takes the reported size itself
        assertArrayEquals(new int[] { 80, 104 }, java.util.Arrays.copyOf(taken(80, 104, 80, 104), 2));
        // a Pixel 4x4: "368 x 442", really 368 x 464
        int[] pixel = taken(368, 442, 368, 464);
        assertTrue("pixel " + pixel[0] + "x" + pixel[1], pixel[0] == 368 && pixel[1] >= 442 * 1.04 && pixel[1] <= 465);
        // a razr plus 2024: the cells of its other screen, "82 x 68" is 83 x 115 and "378 x 323" is 379 x 507
        int[] cell = taken(82, 68, 83, 115);
        assertTrue("razr 1x1 " + cell[0] + "x" + cell[1], cell[0] == 82 && cell[1] >= 115 / 1.12f && cell[1] <= 116);
        int[] big = taken(378, 323, 379, 507);
        assertTrue("razr 4x4 " + big[0] + "x" + big[1], big[0] == 378 && big[1] >= 507 / 1.12f && big[1] <= 508);
        // the owner's razr: too WIDE as well, "391 x 302" is 375 x 441 and "391 x 151" is 375 x 213. With only the reported width
        // nothing fitted and the launcher fell back to the smallest view.
        int[] own = taken(391, 302, 375, 441);
        assertTrue("owner 4x4 " + own[0] + "x" + own[1], own[0] <= 376 && own[0] >= 375 * 0.94f && own[1] >= 441 / 1.12f && own[1] <= 442);
        int[] own2 = taken(391, 151, 375, 213);
        assertTrue("owner 4x2 " + own2[0] + "x" + own2[1], own2[0] <= 376 && own2[1] >= 213 / 1.12f && own2[1] <= 214);
        // nothing fits (a view much smaller than reported): the smallest, which is about the reported size - as before
        int[] none = taken(391, 302, 300, 250);
        assertTrue("nothing fits " + none[0] + "x" + none[1], none[1] == 302);
    }

    @Test
    public void theMoonsOfTheCalendarComeBeforeTheCardOfToday() {
        // {next rows, card, the card's detail line, mini-moons}: a height with room for the card OR the moons shows the moons
        float h = WidgetPlan.CAL_FIXED + 5 * WidgetPlan.CAL_ROW_MOONS + 40;
        assertArrayEquals(new int[] { 0, 0, 0, 1 }, WidgetPlan.cal(h, 5, true, true));
        // room for both: both, and the moons stay when the list comes
        int[] both = WidgetPlan.cal(WidgetPlan.CAL_FIXED + 5 * WidgetPlan.CAL_ROW_MOONS + WidgetPlan.calCardH(false) + 2, 5, false, true);
        assertArrayEquals(new int[] { 0, 1, 0, 1 }, both);
        for (int hh = 250; hh < 700; hh += 7) {
            int[] p = WidgetPlan.cal(hh, 5, true, true);
            if (p[1] == 1) assertEquals("a card without the moons at " + hh, 1, p[3]);
        }
    }
}
