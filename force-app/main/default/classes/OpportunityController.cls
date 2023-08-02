public with sharing class OpportunityController {
    @AuraEnabled
    public static Id createOpportunity(String name, Date closeDate, String stage) {
        Opportunity opp = new Opportunity(
            Name = name,
            CloseDate = closeDate,
            StageName = stage
        );
        insert opp;
        return opp.Id;
    }
}