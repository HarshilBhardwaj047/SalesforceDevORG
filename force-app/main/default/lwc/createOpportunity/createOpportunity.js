import { LightningElement, track } from 'lwc';
import createOpportunityRecord from '@salesforce/apex/OpportunityController.createOpportunity';

export default class CreateOpportunity extends LightningElement {
    @track oppName = '';
    @track oppCloseDate = '';
    @track oppStage = '';

    // Stages for the Opportunity
    stageOptions = [
        { label: 'Prospecting', value: 'Prospecting' },
        { label: 'Qualification', value: 'Qualification' },
        // other stages as per your business requirements
    ];

    handleNameChange(event) {
        this.oppName = event.target.value;
    }

    handleCloseDateChange(event) {
        this.oppCloseDate = event.target.value;
    }

    handleStageChange(event) {
        this.oppStage = event.target.value;
    }

    createOpportunity() {
        createOpportunityRecord({
            name: this.oppName,
            closeDate: this.oppCloseDate,
            stage: this.oppStage
        })
            .then(result => {
                // Opportunity created successfully
                // Reset the form
                this.oppName = '';
                this.oppCloseDate = '';
                this.oppStage = '';
            })
            .catch(error => {
                // Handle the error
            });
    }
}