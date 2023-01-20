@isTest
private class TestVerifyDate {
    @isTest static void datetest() {
        // Arrange
        Date date1 = Date.newInstance(2022, 1, 1);
        Date date2 = Date.newInstance(2022, 1, 15);
        Date date3 = Date.newInstance(2022, 2, 1);
        Date date4 = Date.newInstance(2021, 12, 31);
        
        // Act
        Date result1 = VerifyDate.CheckDates(date1, date2);
        Date result2 = VerifyDate.CheckDates(date1, date3);
        Date result3 = VerifyDate.CheckDates(date1, date4);
        
        // Assert
        // Check that date2 is returned when it is within 30 days of date1
        System.assertEquals(date2, result1);
        // Check that the end of the month is returned when date2 is not within 30 days of date1
        System.assertEquals(Date.newInstance(2022, 1, 31), result2);
        // Check that the end of the month is returned when date2 is in the past
        System.assertEquals(Date.newInstance(2021, 12, 31), result3);
    }
}