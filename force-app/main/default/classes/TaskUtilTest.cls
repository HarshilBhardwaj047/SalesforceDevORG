@isTest
private class TaskUtilTest {
    @isTest
    static void testTaskPriority(){
        String pr = TaskUtil.getTaskPriority('NY');
        System.assertEquals('Normal', pr);
    }
}