trigger ClosedOpportunityTrigger on Opportunity (after insert, after update) {
    List<Task> tasksToInsert = new List<Task>();
    for (Opportunity opp : [SELECT Id, StageName FROM Opportunity WHERE StageName = 'Closed Won' AND Id IN : Trigger.new]) {
        tasksToInsert.add(new Task(Subject='Follow Up Test Task',WhatId = opp.Id));
    }
    if (tasksToInsert.size()>0) {
        insert tasksToInsert;
    }
    
}