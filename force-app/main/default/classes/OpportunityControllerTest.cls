@isTest
private class OpportunityControllerTest {
    @TestSetup
    static void setup() {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
    }

    @isTest
    static void createOpportunity_succeeds() {
        Test.startTest();
        Id newId = OpportunityController.createOpportunity(
            'New From Test', Date.today().addDays(15), 'Qualification');
        Test.stopTest();
        System.assertNotEquals(null, newId, 'Created Opportunity should have an Id');
    }

    @isTest
    static void getOpportunity_returnsRecord() {
        Opportunity existing = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        Opportunity result = OpportunityController.getOpportunity(existing.Id);
        Test.stopTest();
        System.assertEquals(existing.Id, result.Id);
    }

    @isTest
    static void getOpportunity_throwsWhenIdMissing() {
        Boolean threw = false;
        try {
            OpportunityController.getOpportunity(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should throw when Id is null');
    }

    @isTest
    static void getOpportunitiesByKeyword_filters() {
        Test.startTest();
        List<Opportunity> all = OpportunityController.getOpportunitiesByKeyword(null);
        List<Opportunity> matched = OpportunityController.getOpportunitiesByKeyword('Test');
        Test.stopTest();
        System.assert(all.size() >= 1);
        System.assert(matched.size() >= 1);
    }
}
