@isTest
private class TemperatureConverterTest {
    @isTest static void testWarmTemp() {
        System.assertEquals(21.11, TemperatureConverter.FahrenheitToCelsius(70));
    }
    @isTest static void testFreezingPoint() {
        System.assertEquals(0, TemperatureConverter.FahrenheitToCelsius(32));
    }
    @isTest static void testBoilingPoint() {
        System.assertEquals(100, TemperatureConverter.FahrenheitToCelsius(212),
            'Boiling point temperature is not expected.');
    }
    @isTest static void testNegativeTemp() {
        System.assertEquals(-23.33, TemperatureConverter.FahrenheitToCelsius(-10));
    }
    @isTest static void testNullInput() {
        System.assertEquals(null, TemperatureConverter.FahrenheitToCelsius(null));
    }
}
