public with sharing class VerifyDate {
    /**
     * If date2 is within the next 30 days of date1, returns date2.
     * Otherwise returns the last day of date1's month.
     */
    public static Date CheckDates(Date date1, Date date2) {
        if (DateWithin30Days(date1, date2)) {
            return date2;
        }
        return SetEndOfMonthDate(date1);
    }

    private static Boolean DateWithin30Days(Date date1, Date date2) {
        if (date2 < date1) return false;
        Date date30Days = date1.addDays(30);
        return date2 < date30Days;
    }

    private static Date SetEndOfMonthDate(Date date1) {
        Integer totalDays = Date.daysInMonth(date1.year(), date1.month());
        return Date.newInstance(date1.year(), date1.month(), totalDays);
    }
}
