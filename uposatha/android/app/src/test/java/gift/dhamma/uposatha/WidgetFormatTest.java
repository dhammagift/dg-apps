package gift.dhamma.uposatha;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** The widget's pure text helpers: the strings of the design (design/README.md section 3) from numbers. */
public class WidgetFormatTest {
    private static final long H = WidgetFormat.HOUR, M = WidgetFormat.MIN, D = WidgetFormat.DAY;

    @Test
    public void counterShowsDaysAndHoursNoMinutes() {
        assertEquals("1 d 7 h", WidgetFormat.counter(D + 7 * H + 59 * M, "d", "h"));
        assertEquals("1 д 7 ч", WidgetFormat.counter(D + 7 * H, "д", "ч"));
        assertEquals("20 h", WidgetFormat.counter(20 * H + 5 * M, "d", "h"));
        assertEquals("2 d 0 h", WidgetFormat.counter(2 * D + 30 * M, "d", "h"));
        assertEquals("0 h", WidgetFormat.counter(-5, "d", "h"));
    }

    @Test
    public void timeLeft() {
        assertEquals("1 h 34 min", WidgetFormat.left(H + 33 * M + 20000, "h", "min"));   // rounded up, like the design's "1 h 34 min"
        assertEquals("3 ч 02 мин", WidgetFormat.left(3 * H + 2 * M, "ч", "мин"));
        assertEquals("34 min", WidgetFormat.left(34 * M, "h", "min"));
        assertEquals("1 min", WidgetFormat.left(5000, "h", "min"));
    }

    @Test
    public void kalaLineOfTheDesign() {
        assertEquals("Kala until 12:41 · 1 h 34 min left",
                WidgetFormat.kalaLine("Kala until {time}", "{left} left", "12:41", H + 34 * M, "h", "min"));
        assertEquals("Kala до 12:41 · ещё 1 ч 34 мин",
                WidgetFormat.kalaLine("Kala до {time}", "ещё {left}", "12:41", H + 34 * M, "ч", "мин"));
        assertEquals("Kala until 12:41", WidgetFormat.kalaLine("Kala until {time}", "{left} left", "12:41", -1, "h", "min"));
    }

    @Test
    public void counterFlipsOnTheHourOfTheRemainingTime() {
        // 1 d 7 h 20 min left: the text changes after the 20 minutes (and a millisecond)
        assertEquals(20 * M + 1, WidgetFormat.untilCounterChanges(D + 7 * H + 20 * M));
    }

    @Test
    public void calendar() {
        assertEquals(6, WidgetFormat.dow(2026, 10, 11));   // Sunday
        assertEquals(0, WidgetFormat.dow(2026, 10, 12));   // Monday
        assertEquals(31, WidgetFormat.daysInMonth(2026, 10));
        assertEquals(29, WidgetFormat.daysInMonth(2028, 2));
        assertEquals("2026-11-02", WidgetFormat.ymdFromDays(WidgetFormat.daysFromCivil(2026, 10, 31) + 2));
        assertEquals(8, WidgetFormat.daysBetween("2026-10-09", "2026-10-17"));
        assertEquals(15 * 60 + 30, WidgetFormat.minutes("15:30"));
    }

    @Test
    public void uposathaPlurals() {
        assertEquals("4 упосатхи", WidgetFormat.uposathas("ru", 4));
        assertEquals("1 упосатха", WidgetFormat.uposathas("ru", 1));
        assertEquals("5 упосатх", WidgetFormat.uposathas("ru", 5));
        assertEquals("11 упосатх", WidgetFormat.uposathas("ru", 11));
        assertEquals("4 Uposathas", WidgetFormat.uposathas("en", 4));
        assertEquals("1 Uposatha", WidgetFormat.uposathas("en", 1));
    }
}
