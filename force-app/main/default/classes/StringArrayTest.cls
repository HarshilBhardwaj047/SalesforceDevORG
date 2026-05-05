public with sharing class StringArrayTest {
    public static List<String> generateStringArray(Integer n) {
        List<String> testList = new List<String>();
        Integer count = (n == null || n < 0) ? 0 : n;
        for (Integer i = 0; i < count; i++) {
            testList.add('Test ' + i);
        }
        return testList;
    }
}
