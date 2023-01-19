@isTest
private class TaskUtilTest {
    @isTest static void testTaskPriority() {
        String pr = TaskUtil.getTaskPriority('NY');
        System.assertEquals('Normal', pr);
    }
    @isTest static void testTaskHighPriority(){
        String pr = TaskUtil.getTaskPriority('CA');
        System.assertEquals('High', pr);
    }
    @isTest static void testTaskInvalidPriority(){
        String pr = TaskUtil.getTaskPriority('Delhi');
        System.assertEquals(null, pr);
    }
}