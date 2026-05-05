@isTest
private class TestVerifyDate {
    @isTest static void testCheckDates() {
        Date date1 = Date.newInstance(2020, 1, 1);
        Date date2 = Date.newInstance(2020, 1, 15);
        System.assertEquals(date2, VerifyDate.CheckDates(date1, date2));

        date1 = Date.newInstance(2020, 1, 1);
        date2 = Date.newInstance(2020, 2, 1);
        Date result = VerifyDate.CheckDates(date1, date2);
        Integer totalDays = Date.daysInMonth(date1.year(), date1.month());
        System.assertEquals(Date.newInstance(2020, 1, totalDays), result);
    }
}
