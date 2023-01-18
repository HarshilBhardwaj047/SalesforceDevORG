trigger ClosedOpportunityTrigger on Opportunity (after insert, after update) {
    List<Task> tasksToInsert = new List<Task>();
    for (Opportunity opp : Trigger.new) {
        if (opp.StageName == 'Closed Won') {
            Task followUp = new Task();
            followUp.Subject = 'Follow-up with ' + opp.Account.Name;
            followUp.WhatId = opp.Id;
            followUp.ActivityDate = Date.today().addDays(7);
            followUp.Status = 'Not Started';
            tasksToInsert.add(followUp);
        }
    }
    insert tasksToInsert;
}