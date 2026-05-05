@isTest
private class TaskUtilTest {
    @isTest static void testTaskPriority() {
        System.assertEquals('Normal', TaskUtil.getTaskPriority('NY'));
    }
    @isTest static void testTaskHighPriority() {
        System.assertEquals('High', TaskUtil.getTaskPriority('CA'));
    }
    @isTest static void testTaskInvalidPriority() {
        System.assertEquals(null, TaskUtil.getTaskPriority('Delhi'));
    }
}
