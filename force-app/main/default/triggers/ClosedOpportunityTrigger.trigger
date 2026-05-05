trigger ClosedOpportunityTrigger on Opportunity (after insert, after update) {
    OpportunityTriggerHandler.createFollowUpTaskForClosedWon(Trigger.newMap);
}
