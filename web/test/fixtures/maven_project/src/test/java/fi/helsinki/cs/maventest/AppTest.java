package fi.helsinki.cs.maventest;

import fi.helsinki.cs.tmc.edutestutils.Points;
import org.junit.Test;
import static org.junit.Assert.*;

public class AppTest {
    @Test
    @Points("trol")
    public void trol() {
        assertTrue(true);
    }
}
