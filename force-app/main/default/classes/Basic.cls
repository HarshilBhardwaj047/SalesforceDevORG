public with sharing class Basic {
    public static void method() {
        List<Integer> intList = new List<Integer>{1, 2, 3};
        System.debug(LoggingLevel.DEBUG, 'intList ==> ' + intList);
    }
}
