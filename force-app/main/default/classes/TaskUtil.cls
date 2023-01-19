public class TaskUtil {
    public static String getTaskPriority(String LeadState){
        //validate input
        if (String.isBlank(LeadState)||LeadState.length()>2){
            return null;
        }
        String taskPriority;
        if (LeadState == 'CA'){
            taskPriority == 'High';
        } else {
            taskPriority == 'Normal';
        }
        return taskPriority;
    }
}