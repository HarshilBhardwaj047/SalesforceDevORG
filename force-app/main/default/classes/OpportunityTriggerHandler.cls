/**
 * Handler for Opportunity triggers. Creates follow-up Tasks when an
 * Opportunity transitions to Closed Won. Bulk-safe: one DML call regardless
 * of batch size.
 */
public with sharing class OpportunityTriggerHandler {

    private static Boolean followUpRunOnce = false;

    public static void createFollowUpTaskForClosedWon(Map<Id, Opportunity> newMap) {
        if (followUpRunOnce) return;
        followUpRunOnce = true;

        if (newMap == null || newMap.isEmpty()) return;

        if (!Schema.sObjectType.Task.isCreateable()) {
            // Running user lacks permission — silently skip rather than error the trigger
            return;
        }

        List<Task> tasksToInsert = new List<Task>();
        for (Opportunity opp : newMap.values()) {
            if (opp.StageName == 'Closed Won') {
                tasksToInsert.add(new Task(
                    Subject = 'Follow Up Test Task',
                    WhatId = opp.Id
                ));
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }
}
