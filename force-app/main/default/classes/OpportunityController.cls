public with sharing class OpportunityController {
    /**
     * Creates a new Opportunity. Called from the createOpportunity LWC.
     * Enforces field-level security via Schema describes and wraps DML
     * in try/catch with AuraHandledException so the LWC gets a friendly error.
     */
    @AuraEnabled
    public static Id createOpportunity(String name, Date closeDate, String stage) {
        try {
            // CRUD check
            if (!Schema.sObjectType.Opportunity.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create Opportunities.');
            }
            // FLS check on the fields we are about to write
            Map<String, Schema.SObjectField> fields = Schema.SObjectType.Opportunity.fields.getMap();
            for (String f : new List<String>{'Name', 'CloseDate', 'StageName'}) {
                if (!fields.get(f).getDescribe().isCreateable()) {
                    throw new AuraHandledException('You do not have permission to set ' + f + '.');
                }
            }

            Opportunity opp = new Opportunity(
                Name = name,
                CloseDate = closeDate,
                StageName = stage
            );
            insert opp;
            return opp.Id;
        } catch (DmlException e) {
            // Surface a clean message to the LWC; full detail still in System.debug
            System.debug(LoggingLevel.ERROR, 'createOpportunity DML failure: ' + e.getMessage());
            throw new AuraHandledException('Failed to create opportunity: ' + e.getDmlMessage(0));
        }
    }

    /**
     * Returns a single Opportunity by Id.
     * Used by the opportunityDetail LWC.
     */
    @AuraEnabled(cacheable=true)
    public static Opportunity getOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }
        List<Opportunity> opps = [
            SELECT Id, Name, StageName, CloseDate, Amount
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (opps.isEmpty()) {
            throw new AuraHandledException('Opportunity not found or you do not have access.');
        }
        return opps[0];
    }

    /**
     * Returns Opportunities matching a keyword in Name (case-insensitive).
     * Used by the opportunityList LWC. Empty keyword returns all accessible opps.
     */
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunitiesByKeyword(String keyword) {
        String key = String.isBlank(keyword) ? '%' : '%' + String.escapeSingleQuotes(keyword) + '%';
        return [
            SELECT Id, Name, StageName, CloseDate
            FROM Opportunity
            WHERE Name LIKE :key
            WITH USER_MODE
            ORDER BY CloseDate DESC NULLS LAST
            LIMIT 200
        ];
    }
}
