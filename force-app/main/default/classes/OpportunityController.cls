// Apex Controller
public with sharing class OpportunityController {
    @AuraEnabled(cacheable=true)
    public static List<String> getStageNames() {
        List<String> stageNames = new List<String>();
        Schema.DescribeFieldResult fieldResult = Opportunity.StageName.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();

        for(Schema.PicklistEntry pickListVal : ple){
            stageNames.add(pickListVal.getLabel());
        }       
        return stageNames;
    }
}
