@isTest
private class TestVerifyDate {
    @isTest static void testCheckDates() {
        // Test case where date2 is within 30 days of date1
        Date date1 = Date.newInstance(2020, 1, 1);
        Date date2 = Date.newInstance(2020, 1, 15);
        Date result = VerifyDate.CheckDates(date1, date2);
        System.assertEquals(date2, result);

        // Test case where date2 is not within 30 days of date1
        date1 = Date.newInstance(2020, 1, 1);
        date2 = Date.newInstance(2020, 2, 1);
        result = VerifyDate.CheckDates(date1, date2);
        Integer totalDays = Date.daysInMonth(date1.year(), date1.month());
        Date expected = Date.newInstance(2020, 1, totalDays);
        System.assertEquals(expected, result);
    }
}